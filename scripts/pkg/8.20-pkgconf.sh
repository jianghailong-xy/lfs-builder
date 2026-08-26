#!/usr/bin/env bash
# LFS 13.0-systemd §8.20 Pkgconf-2.5.1
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.20.1 Installation of Pkgconf 的命令序列（全部，一条不多一条不少）：
#   ./configure --prefix=/usr    \
#               --disable-static \
#               --docdir=/usr/share/doc/pkgconf-2.5.1
#   make
#   make install
#   ln -sv pkgconf   /usr/bin/pkg-config
#   ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
# 本节没有 sed、没有 patch、没有可选命令，**也没有任何测试命令**（手册全节不含
# "To test the results" 一句），同样没有任何关于允许失败的 Note / Caution。
set -euo pipefail

PKG=pkgconf
VER=2.5.1
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
CONFLOG=/sources/.pkgconf-configure.log
MAKELOG=/sources/.pkgconf-make.log
INSTLOG=/sources/.pkgconf-make-install.log

echo "===== LFS 13.0-systemd §8.20 Pkgconf-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The pkgconf package is a successor to pkg-config and contains a tool for"
echo "  passing the include path and/or library paths to build tools during the configure"
echo "  and make phases of package installations."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 5.0 MB"
echo "手册存档：/workspace/docs/book/chapter08-pkgconf.html（宿主机 /root/lfs/docs/book/）"
echo

echo "----- 环境（手册 §7.4 进入 chroot 后的环境） -----"
echo "id        : $(id)"
echo "whoami    : $(whoami)"
echo "PATH      : $PATH"
echo "HOME      : $HOME"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "TESTSUITEFLAGS: ${TESTSUITEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
esac
echo "  OK   PATH 中不含 /tools/bin（交叉工具链已不再使用）"
echo

echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0
echo "1) 上一任务 §8.19 DejaGNU-1.6.3 的产物（确认其已完成、产物可用）："
for f in /usr/bin/runtest /usr/bin/dejagnu /usr/share/dejagnu/runtest.exp \
         /usr/share/dejagnu/dejagnu.exp /usr/share/man/man1/runtest.1; do
  if [ -e "$f" ]; then printf '   OK   %-38s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.19 未完成？）\n' "$f"; rc=1; fi
done
rt_ver=$(runtest --version 2>&1 | sed -n 's/^DejaGnu version[[:space:]]*//p' | sed -n 1p)
echo "   runtest 自述版本：${rt_ver:-（取不到）}"
echo "   说明：Pkgconf 不依赖 DejaGNU，此处只用于确认「上一任务产物可用」。"
echo
echo "2) §8.5 Glibc-2.43 的 C 库与工具链（本节要 configure + 编译 C 代码 + 建共享库）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2 /usr/include/stdio.h; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("glibc sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && \
   [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo
echo "3) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "4) 本节直接依赖的工具（解包 + configure + libtool 建共享库 + make install）："
for t in tar xz make gcc ld ar ranlib sed grep awk install ln rm mkdir cmp \
         md5sum readelf objdump ldd file find stat bash sort; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   sed  版本：$(sed --version | sed -n 1p)"
echo "   说明：configure 由发行包自带（无需 autoconf/automake/libtool 重生成）；"
echo "     共享库由源码树内自带的 ltmain.sh 生成的 ./libtool 脚本构建。"
echo
echo "5) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo
echo "6) 安装目标目录（手册 §8.20.2 Contents 的落点）："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/share/man/man5 \
         /usr/share/man/man7 /usr/share/doc /usr/share/aclocal; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo
echo "7) 安装前系统中的 pkgconf / pkg-config 痕迹（第 5-7 章从未构建过本包，应全部不存在）："
for f in /usr/bin/pkgconf /usr/bin/pkg-config /usr/bin/bomtool /usr/lib/libpkgconf.so \
         /usr/share/man/man1/pkg-config.1 /usr/share/doc/pkgconf-$VER; do
  if [ -e "$f" ] || [ -L "$f" ]; then printf '   INFO %-40s 已存在（重复运行？）\n' "$f"
  else printf '   OK   %-40s 不存在（首次安装）\n' "$f"; fi
done
echo "   /usr/lib/pkgconfig 下现有的 .pc 文件（本节之前应为空或很少）："
{ ls /usr/lib/pkgconfig 2>/dev/null || echo '（目录不存在）'; } | sed 's/^/     /'
echo
echo "8) 磁盘空间（手册要求 5.0 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 102400 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 5.0 MB"
else echo "   FAIL 可用空间不足：$((avail_k/1024)) MB"; rc=1; fi
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
echo "上游版本自述："
echo "  configure.ac：$(grep -n 'AC_INIT' configure.ac | sed -n 1p)"
conf_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'\$/\1/p" configure | sed -n 1p)
conf_str=$(sed -n "s/^PACKAGE_STRING='\(.*\)'\$/\1/p" configure | sed -n 1p)
echo "  configure   ：PACKAGE_VERSION=$conf_ver  PACKAGE_STRING='$conf_str'"
if [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $conf_ver 与手册 §8.20 的 Pkgconf-$VER 一致"
else echo "  FAIL 源码自述版本为 '$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁、无 sed：手册 §8.20 的命令序列只有 configure/make/make install + 2 条 ln"
pc_patches=$({ ls /sources | grep -E '^pkgconf.*patch' || true; } | tr '\n' ' ')
echo "  （/sources 中匹配 pkgconf*patch 的文件：${pc_patches:-无}）"
echo
echo "----- 上游构建系统预读（据此确定安装清单与自检判据） -----"
echo "Makefile.am 的安装目标声明："
{ grep -nE '^(bin_PROGRAMS|lib_LTLIBRARIES|nobase_pkginclude_HEADERS|dist_man_MANS|dist_doc_DATA|m4data_DATA|nodist_pkgconfig_DATA|pkgconfigdir|m4datadir|libpkgconf_la_LDFLAGS) *=' Makefile.am || true; } | sed 's/^/  /'
echo "  → 由此推出本节写入系统的内容："
echo "    程序：/usr/bin/pkgconf、/usr/bin/bomtool"
echo "    共享库：/usr/lib/libpkgconf.so*（-version-info 7:0:0 ⇒ SONAME libpkgconf.so.7）"
echo "    头文件：nobase_pkginclude_HEADERS ⇒ 保留 libpkgconf/ 前缀，装到"
echo "            /usr/include/pkgconf/libpkgconf/（pkgincludedir = includedir/pkgconf）"
echo "    man：man/{pkgconf.1,bomtool.1,pc.5,pkgconf-personality.5,pkg.m4.7}"
echo "    doc：dist_doc_DATA = README.md AUTHORS ⇒ 落到 --docdir 指定的目录"
echo "    其它：/usr/share/aclocal/pkg.m4、/usr/lib/pkgconfig/libpkgconf.pc"
echo "Makefile.am 的 check 目标（说明手册为何不给测试命令）："
{ grep -nA2 '^check: pkgconf' Makefile.am || true; } | sed 's/^/  /'
if command -v kyua >/dev/null 2>&1; then
  echo "  INFO 本系统存在 kyua：$(command -v kyua)"
else
  echo "  OK   本系统无 kyua —— 上游 check 目标依赖 kyua 测试框架（LFS 不含该包），"
  echo "       这正是手册 §8.20 全节没有 \"To test the results\" 一句的原因。"
fi
echo "  手册 §8.20 全文中出现的命令（从存档 HTML 的 <kbd class=\"command\"> 提取，见宿主机"
echo "  docs/book/chapter08-pkgconf.html）：configure / make / make install / 2 条 ln，无测试命令。"
echo

echo "================= 8.20.1. Installation of Pkgconf ================="
echo
echo "----- 手册命令 1/5：configure -----"
echo "手册原文：Prepare Pkgconf for compilation:"
echo "手册命令：./configure --prefix=/usr    \\"
echo "                     --disable-static \\"
echo "                     --docdir=/usr/share/doc/pkgconf-$VER"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/pkgconf-2.5.1 > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "config.status 生成的文件（据此确定 config.h 的真实位置）："
{ grep -E '^config\.status: creating ' "$CONFLOG" || true; } | sed 's/^/  /'
echo "configure 关键探测结果摘要："
{ grep -E '^checking (for gcc|whether the C compiler works|for a sed|whether ln -s works|for shared library run path|if gcc supports)' "$CONFLOG" || true; } | sed -n '1,15p' | sed 's/^/  /'
echo "configure 末尾 10 行："
tail -n 10 "$CONFLOG" | sed 's/^/  /'
echo
echo "----- 核对三个手册选项确实生效 -----"
crc=0
{ grep -E '^(prefix|exec_prefix|bindir|libdir|includedir|mandir|docdir|datarootdir) = ' Makefile || true; } | sed 's/^/  /'
got_prefix=$(sed -n 's/^prefix = //p' Makefile | sed -n 1p)
got_docdir=$(sed -n 's/^docdir = //p' Makefile | sed -n 1p)
if [ "$got_prefix" = /usr ]; then echo "  OK   --prefix=/usr 生效（prefix = /usr）"
else echo "  FAIL prefix 为 '$got_prefix'，不是 /usr"; crc=1; fi
if [ "$got_docdir" = "/usr/share/doc/pkgconf-$VER" ]; then
  echo "  OK   --docdir 生效（docdir = $got_docdir）"
else echo "  FAIL docdir 为 '$got_docdir'，不是 /usr/share/doc/pkgconf-$VER"; crc=1; fi
echo "  --disable-static 的核对点是生成的 ./libtool 里的 build_old_libs（§8.16 Flex 同法）："
bol=$({ grep -E '^build_old_libs=' libtool || true; } | sed -n 1p)
echo "    libtool 首个 build_old_libs 赋值：$bol"
if [ "$bol" = "build_old_libs=no" ]; then
  echo "    OK   build_old_libs=no ⇒ 不会构建/安装 libpkgconf.a"
else echo "    FAIL build_old_libs 不是 no"; crc=1; fi
echo "    （libtool 中另外两处 build_old_libs= 出现在条件重算逻辑里，属正常）"
echo "  生成的配置头（configure.ac 的 AC_CONFIG_HEADERS 指定为 libpkgconf/config.h）："
if [ -f libpkgconf/config.h ]; then
  echo "    OK   libpkgconf/config.h 存在（$(wc -l < libpkgconf/config.h) 行）"
  { grep -E '^#define PACKAGE_(VERSION|STRING) ' libpkgconf/config.h || true; } | sed 's/^/      /'
  h_ver=$(sed -n 's/^#define PACKAGE_VERSION "\(.*\)"$/\1/p' libpkgconf/config.h | sed -n 1p)
  if [ "$h_ver" = "$VER" ]; then echo "      OK   config.h 自述版本 $h_ver"
  else echo "      FAIL config.h 版本 '$h_ver' 与 $VER 不符"; crc=1; fi
else echo "    FAIL libpkgconf/config.h 未生成"; crc=1; fi
echo "  内置默认搜索路径（AM_CFLAGS 的 -DPKG_DEFAULT_PATH / -DSYSTEM_LIBDIR / -DSYSTEM_INCLUDEDIR，"
echo "  由 configure 从 libdir/datadir/includedir 推出，安装后可用 pkgconf 自身回读验证）："
for v in PKG_DEFAULT_PATH SYSTEM_LIBDIR SYSTEM_INCLUDEDIR PERSONALITY_PATH; do
  printf '    %-18s = %s\n' "$v" "$(sed -n "s/^$v = //p" Makefile | sed -n 1p)"
done
for f in Makefile libpkgconf.pc Kyuafile tests/Kyuafile tests/test_env.sh; do
  if [ -f "$f" ]; then printf '    OK   %s 已生成\n' "$f"
  else printf '    FAIL %s 未生成\n' "$f"; crc=1; fi
done
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册的三个选项"
echo

echo "----- 手册命令 2/5：make -----"
echo "手册原文：Compile the package:"
echo "手册命令：make"
echo "完整输出写入 $MAKELOG，下面只摘要。"
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "make 退出码：$make_rc（输出 $(wc -l < "$MAKELOG") 行）"
if [ $make_rc -ne 0 ]; then
  echo "make 失败，末尾 40 行："; tail -n 40 "$MAKELOG" | sed 's/^/  /'
  exit $make_rc
fi
echo "make 输出末尾 10 行："
tail -n 10 "$MAKELOG" | sed 's/^/  /'
echo "编译告警统计（仅记录，不作判据）：warning 行 $({ grep -c 'warning:' "$MAKELOG" || true; }) 条，"
echo "  error 行 $({ grep -c 'error:' "$MAKELOG" || true; }) 条"
echo
echo "----- 编译结果确认 -----"
mrc=0
echo "  注意：libtool 在构建目录里把 pkgconf / bomtool 生成为**包装 shell 脚本**，"
echo "  真正的 ELF 可执行文件在 .libs/ 下（试建时确认过，故断言按 .libs/ 写）。"
for p in pkgconf bomtool; do
  printf '    %-8s 顶层：%s\n' "$p" "$(file -b $p | cut -d, -f1)"
  if [ -x ".libs/$p" ]; then
    printf '    OK   .libs/%-8s %s 字节，%s\n' "$p" "$(stat -Lc %s .libs/$p)" "$(file -b .libs/$p | cut -d, -f1-2)"
  else printf '    FAIL .libs/%s 未生成\n' "$p"; mrc=1; fi
done
echo "  共享库（-version-info 7:0:0）："
for l in .libs/libpkgconf.so.7.0.0 .libs/libpkgconf.so.7 .libs/libpkgconf.so; do
  if [ -e "$l" ]; then printf '    OK   %-28s -> %s\n' "$l" "$(readlink -f $l | sed 's|.*/||')"
  else printf '    FAIL %s 未生成\n' "$l"; mrc=1; fi
done
if [ -e .libs/libpkgconf.a ]; then
  echo "    FAIL .libs/libpkgconf.a 存在（--disable-static 未生效）"; mrc=1
else echo "    OK   .libs/libpkgconf.a 不存在（--disable-static 生效）"; fi
echo "  构建产物冒烟测试（用 libtool 包装脚本运行，它会指向构建目录里的库）："
build_ver=$(./pkgconf --version 2>&1 | sed -n 1p)
echo "    ./pkgconf --version  -> $build_ver"
[ "$build_ver" = "$VER" ] || { echo "    FAIL 构建产物自述版本不是 $VER"; mrc=1; }
build_bom=$(./bomtool --version 2>&1 | sed -n 1p)
echo "    ./bomtool --version  -> $build_bom"
case "$build_bom" in *"$VER"*) : ;; *) echo "    FAIL bomtool 自述版本不含 $VER"; mrc=1 ;; esac
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 本节的「手册规定测试」 -----"
echo "手册 §8.20 全节没有测试命令：8.20.1 只有 configure / make / make install 和两条 ln，"
echo "  不存在其它小节里那句 \"To test the results, issue: make check\"。"
echo "原因（上游 Makefile.am 已在前面打印）：check 目标写死调用 kyua 测试框架"
echo "  （kyua --config=none test --kyuafile=...），而 LFS 13.0-systemd 不安装 kyua，"
echo "  本系统中 kyua 不存在（前面已确认），故该测试套件在此无法运行，手册也未要求运行。"
echo "结论：本节按手册「无测试」处理；正确性改由下面的安装后功能验证覆盖"
echo "  （对照 §8.20.2 Contents 对 pkgconf / bomtool / libpkgconf 的描述逐条验证）。"
echo

echo "----- 手册命令 3/5：make install -----"
echo "手册原文：Install the package:"
echo "手册命令：make install"
echo "完整输出写入 $INSTLOG，下面只摘要。"
set +e
make install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "make install 退出码：$inst_rc（输出 $(wc -l < "$INSTLOG") 行）"
if [ $inst_rc -ne 0 ]; then
  echo "make install 失败，末尾 40 行："; tail -n 40 "$INSTLOG" | sed 's/^/  /'
  exit $inst_rc
fi
echo "安装到 /usr 下的条目（摘自 install 日志）："
{ grep -oE '/usr/(bin|lib|include|share)[^ "'"'"']*' "$INSTLOG" || true; } | sort -u | sed 's/^/  /'
echo

echo "----- 手册命令 4/5 与 5/5：兼容 Pkg-config 的两条符号链接 -----"
echo "手册原文：To maintain compatibility with the original Pkg-config create two symlinks:"
echo "手册命令：ln -sv pkgconf   /usr/bin/pkg-config"
echo "          ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1"
echo "（说明：ln -sv 在目标已存在时会失败。本脚本可重复运行，故先判断——目标已是正确的"
echo "  相对符号链接时跳过并说明，否则原样执行手册命令。）"
if [ "$(readlink /usr/bin/pkg-config 2>/dev/null)" = pkgconf ]; then
  echo "  已存在且正确，跳过：/usr/bin/pkg-config -> pkgconf"
else
  ln -sv pkgconf   /usr/bin/pkg-config
fi
if [ "$(readlink /usr/share/man/man1/pkg-config.1 2>/dev/null)" = pkgconf.1 ]; then
  echo "  已存在且正确，跳过：/usr/share/man/man1/pkg-config.1 -> pkgconf.1"
else
  ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
fi
echo

echo "----- 安装后检查（手册 §8.20.2 Contents of Pkgconf） -----"
echo "手册列出的内容："
echo "  Installed programs: pkgconf, pkg-config (link to pkgconf), and bomtool"
echo "  Installed library : libpkgconf.so"
echo "  Installed directory: /usr/share/doc/pkgconf-$VER"
echo "  pkgconf   ：Returns meta information for the specified library or package"
echo "  bomtool   ：Generates a Software Bill Of Materials from pkg-config .pc files"
echo "  libpkgconf：Contains most of pkgconf's functionality, while allowing other tools"
echo "              like IDEs and compilers to use its frameworks"
rc=0
echo
echo "1) Installed programs："
for p in /usr/bin/pkgconf /usr/bin/bomtool; do
  if [ -x "$p" ]; then printf '   OK   %-18s（%s 字节，%s）\n' "$p" "$(stat -Lc %s "$p")" "$(file -b "$p" | cut -d, -f1-2)"
  else printf '   FAIL %s 缺失或不可执行\n' "$p"; rc=1; fi
done
inst_ver=$(pkgconf --version 2>&1 | sed -n 1p)
echo "   pkgconf --version -> $inst_ver"
if [ "$inst_ver" = "$VER" ]; then echo "   OK   已安装 pkgconf 自述版本为 $VER"
else echo "   FAIL 已安装 pkgconf 自述版本 '$inst_ver' 不是 $VER"; rc=1; fi
inst_bom=$(bomtool --version 2>&1 | sed -n 1p)
echo "   bomtool --version -> $inst_bom"
case "$inst_bom" in *"$VER"*) echo "   OK   已安装 bomtool 自述版本含 $VER" ;;
  *) echo "   FAIL bomtool 自述版本不含 $VER"; rc=1 ;; esac
echo "   pkgconf 的动态依赖（应链接自家 libpkgconf.so.7 + glibc，不含 /tools）："
ldd_out=$(ldd /usr/bin/pkgconf)
echo "$ldd_out" | sed 's/^/     /'
case "$ldd_out" in *"/tools/"*) echo "     FAIL 仍链接 /tools 下的库"; rc=1 ;;
  *) echo "     OK   未链接任何 /tools 路径" ;; esac
case "$ldd_out" in *"libpkgconf.so.7 => /usr/lib/libpkgconf.so.7"*) echo "     OK   链接到 /usr/lib/libpkgconf.so.7" ;;
  *) echo "     FAIL 未链接到 /usr/lib/libpkgconf.so.7"; rc=1 ;; esac
case "$ldd_out" in *"libc.so.6"*) echo "     OK   链接到 libc.so.6" ;;
  *) echo "     FAIL 未链接 libc.so.6"; rc=1 ;; esac
echo
echo "2) pkg-config（link to pkgconf）："
if [ -L /usr/bin/pkg-config ]; then
  tgt=$(readlink /usr/bin/pkg-config)
  echo "   OK   /usr/bin/pkg-config 是符号链接 -> $tgt"
  [ "$tgt" = pkgconf ] || { echo "   FAIL 链接目标不是 pkgconf"; rc=1; }
  echo "   解析后的真实路径：$(readlink -f /usr/bin/pkg-config)"
else echo "   FAIL /usr/bin/pkg-config 不是符号链接"; rc=1; fi
pc_ver=$(pkg-config --version 2>&1 | sed -n 1p)
echo "   pkg-config --version -> $pc_ver"
if [ "$pc_ver" = "$VER" ]; then echo "   OK   经符号链接调用的行为与 pkgconf 一致"
else echo "   FAIL pkg-config --version 输出 '$pc_ver'"; rc=1; fi
if [ -L /usr/share/man/man1/pkg-config.1 ]; then
  tgt1=$(readlink /usr/share/man/man1/pkg-config.1)
  echo "   OK   /usr/share/man/man1/pkg-config.1 -> $tgt1"
  [ "$tgt1" = pkgconf.1 ] || { echo "   FAIL man 链接目标不是 pkgconf.1"; rc=1; }
  if [ -e /usr/share/man/man1/pkg-config.1 ]; then echo "   OK   该 man 链接可解析到真实文件"
  else echo "   FAIL man 链接悬空"; rc=1; fi
else echo "   FAIL /usr/share/man/man1/pkg-config.1 不是符号链接"; rc=1; fi
echo
echo "3) Installed library：libpkgconf.so（-version-info 7:0:0 ⇒ SONAME libpkgconf.so.7）"
for l in /usr/lib/libpkgconf.so.7.0.0 /usr/lib/libpkgconf.so.7 /usr/lib/libpkgconf.so; do
  if [ -e "$l" ]; then
    if [ -L "$l" ]; then printf '   OK   %-32s -> %s\n' "$l" "$(readlink "$l")"
    else printf '   OK   %-32s（%s 字节，%s）\n' "$l" "$(stat -Lc %s "$l")" "$(file -b "$l" | cut -d, -f1-2)"; fi
  else printf '   FAIL %s 缺失\n' "$l"; rc=1; fi
done
readelf -d /usr/lib/libpkgconf.so.7.0.0 > /tmp/pkgconf-dyn.txt 2>&1
soname=$(sed -n 's/.*SONAME.*Library soname: \[\(.*\)\]/\1/p' /tmp/pkgconf-dyn.txt | sed -n 1p)
echo "   SONAME：$soname"
if [ "$soname" = libpkgconf.so.7 ]; then echo "   OK   SONAME 与 -version-info 7:0:0 相符"
else echo "   FAIL SONAME 为 '$soname'"; rc=1; fi
if [ -e /usr/lib/libpkgconf.a ]; then echo "   FAIL /usr/lib/libpkgconf.a 存在（--disable-static 应阻止其安装）"; rc=1
else echo "   OK   /usr/lib/libpkgconf.a 不存在（--disable-static）"; fi
readelf --dyn-syms -W /usr/lib/libpkgconf.so.7.0.0 > /tmp/pkgconf-syms.txt 2>&1
n_pkgconf=$({ grep -c ' pkgconf_' /tmp/pkgconf-syms.txt || true; })
n_leak=$(awk '$4=="FUNC" && $5=="GLOBAL" && $7!="UND" && $8 !~ /^pkgconf_/' /tmp/pkgconf-syms.txt | wc -l)
echo "   导出符号：pkgconf_* 共 $n_pkgconf 个；非 pkgconf_ 前缀的 GLOBAL FUNC 共 $n_leak 个"
echo "     （Makefile.am 的 libpkgconf_la_LDFLAGS 含 -export-symbols-regex '^pkgconf_'）"
if [ "$n_pkgconf" -gt 50 ] && [ "$n_leak" -eq 0 ]; then
  echo "   OK   符号导出符合 -export-symbols-regex 的约定"
else echo "   FAIL 导出符号不符合预期（pkgconf_=$n_pkgconf，越界=$n_leak）"; rc=1; fi
echo "   libtool .la 文件（本节手册未要求删除，故保留）："
if [ -f /usr/lib/libpkgconf.la ]; then
  { grep -E '^(dlname|library_names|old_library|installed)=' /usr/lib/libpkgconf.la || true; } | sed 's/^/     /'
  old_lib=$(sed -n "s/^old_library='\(.*\)'\$/\1/p" /usr/lib/libpkgconf.la | sed -n 1p)
  if [ -z "$old_lib" ]; then echo "     OK   old_library 为空 ⇒ 确无静态库"
  else echo "     FAIL old_library='$old_lib'"; rc=1; fi
else echo "     INFO /usr/lib/libpkgconf.la 不存在"; fi
echo
echo "4) Installed directory：/usr/share/doc/pkgconf-$VER（--docdir 的落点）"
if [ -d "/usr/share/doc/pkgconf-$VER" ]; then
  echo "   OK   目录存在，内容："
  ls -l "/usr/share/doc/pkgconf-$VER" | sed 's/^/     /'
  for f in README.md AUTHORS; do
    if [ -f "/usr/share/doc/pkgconf-$VER/$f" ]; then printf '     OK   %s（%s 字节）\n' "$f" "$(stat -Lc %s "/usr/share/doc/pkgconf-$VER/$f")"
    else printf '     FAIL %s 缺失（dist_doc_DATA 应安装它）\n' "$f"; rc=1; fi
  done
else echo "   FAIL /usr/share/doc/pkgconf-$VER 不存在"; rc=1; fi
echo
echo "5) 手册 Contents 未逐条列出、但由 make install 一并安装的文件（清单取自试建时的"
echo "   DESTDIR 安装结果，非凭源码猜测）："
for f in /usr/include/pkgconf/libpkgconf/libpkgconf.h \
         /usr/include/pkgconf/libpkgconf/libpkgconf-api.h \
         /usr/include/pkgconf/libpkgconf/bsdstubs.h \
         /usr/include/pkgconf/libpkgconf/iter.h \
         /usr/include/pkgconf/libpkgconf/stdinc.h \
         /usr/lib/pkgconfig/libpkgconf.pc \
         /usr/share/aclocal/pkg.m4 \
         /usr/share/man/man1/pkgconf.1 \
         /usr/share/man/man1/bomtool.1 \
         /usr/share/man/man5/pc.5 \
         /usr/share/man/man5/pkgconf-personality.5 \
         /usr/share/man/man7/pkg.m4.7; do
  if [ -e "$f" ]; then printf '   OK   %-50s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "----- 功能验证（对照 §8.20.2 的 Short Descriptions，用已安装的程序逐条验证） -----"
tmpd=$(mktemp -d /tmp/pkgconf-verify-XXXXXX)
mkdir -p "$tmpd/pc"
cat > "$tmpd/pc/demo.pc" <<'EOF'
prefix=/opt/demo
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: demo
Description: A demo package for the §8.20 self-check
Version: 3.2.1
License: MIT
Requires: demodep >= 1.0
Libs: -L${libdir} -ldemo
Cflags: -I${includedir}/demo
EOF
cat > "$tmpd/pc/demodep.pc" <<'EOF'
prefix=/opt/demodep
libdir=${prefix}/lib
includedir=${prefix}/include

Name: demodep
Description: dependency of demo
Version: 1.4.0
Libs: -L${libdir} -ldemodep
Cflags: -I${includedir}
EOF
export PKG_CONFIG_PATH="$tmpd/pc"
echo "a) pkgconf —— Returns meta information for the specified library or package"
echo "   （自建的 demo.pc / demodep.pc 在 $tmpd/pc，通过 PKG_CONFIG_PATH 提供）"
out=$(pkgconf --modversion demo)
echo "   --modversion demo        -> $out"
[ "$out" = "3.2.1" ] || { echo "   FAIL 期望 3.2.1"; rc=1; }
out=$(pkgconf --cflags demo)
echo "   --cflags demo            -> $out"
[ "$out" = "-I/opt/demo/include/demo -I/opt/demodep/include" ] || \
  { echo "   FAIL cflags 不符（应含 Requires 传递来的 demodep 头路径）"; rc=1; }
out=$(pkgconf --libs demo)
echo "   --libs demo              -> $out"
[ "$out" = "-L/opt/demo/lib -ldemo -L/opt/demodep/lib -ldemodep" ] || \
  { echo "   FAIL libs 不符（应含 Requires 传递来的 demodep 库）"; rc=1; }
out=$(pkgconf --variable=libdir demo)
echo "   --variable=libdir demo   -> $out"
[ "$out" = "/opt/demo/lib" ] || { echo "   FAIL 变量展开不符"; rc=1; }
out=$(pkgconf --print-requires demo | tr '\n' ' ')
echo "   --print-requires demo    -> $out"
case "$out" in *demodep*) : ;; *) echo "   FAIL 未报告 Requires"; rc=1 ;; esac
set +e
pkgconf --exists demo; e1=$?
pkgconf --exists no-such-package-xyz; e2=$?
pkgconf --atleast-version=3.0 demo; e3=$?
pkgconf --atleast-version=99.0 demo; e4=$?
pkgconf --cflags no-such-package-xyz > "$tmpd/err.txt" 2>&1; e5=$?
set -e
echo "   退出码：--exists demo=$e1  --exists 缺失包=$e2  --atleast-version=3.0=$e3"
echo "           --atleast-version=99.0=$e4  --cflags 缺失包=$e5"
echo "   缺失包的诊断首行：$(sed -n 1p "$tmpd/err.txt")"
if [ $e1 -eq 0 ] && [ $e2 -ne 0 ] && [ $e3 -eq 0 ] && [ $e4 -ne 0 ] && [ $e5 -ne 0 ]; then
  echo "   OK   存在性/版本比较/错误路径的退出码全部正确"
else echo "   FAIL 退出码不符合预期"; rc=1; fi
echo "   内置默认搜索路径（不设 PKG_CONFIG_PATH 时生效，应为 configure 推出的 /usr 路径）："
pcpath=$(pkgconf --variable=pc_path pkg-config)
echo "     pkgconf --variable=pc_path pkg-config -> $pcpath"
if [ "$pcpath" = "/usr/lib/pkgconfig:/usr/share/pkgconfig" ]; then
  echo "     OK   与 --prefix=/usr 推出的 PKG_DEFAULT_PATH 一致"
else echo "     FAIL 内置搜索路径为 '$pcpath'"; rc=1; fi
echo "   用内置路径直接查询本包自己安装的 libpkgconf.pc（不设 PKG_CONFIG_PATH）："
lp_ver=$(env -u PKG_CONFIG_PATH pkgconf --modversion libpkgconf)
echo "     pkgconf --modversion libpkgconf -> $lp_ver"
if [ "$lp_ver" = "$VER" ]; then echo "     OK   系统级 .pc 搜索链路打通（后续各包 configure 依赖它）"
else echo "     FAIL 期望 $VER"; rc=1; fi
echo "b) pkg-config 符号链接的行为与 pkgconf 一致（同一查询两边比对）："
o1=$(pkgconf --cflags --libs demo); o2=$(pkg-config --cflags --libs demo)
echo "   pkgconf   --cflags --libs demo -> $o1"
echo "   pkg-config --cflags --libs demo -> $o2"
if [ "$o1" = "$o2" ]; then echo "   OK   两者输出逐字一致"
else echo "   FAIL 两者输出不一致"; rc=1; fi
echo "c) bomtool —— Generates a Software Bill Of Materials from pkg-config .pc files"
bomtool demo > "$tmpd/bom.txt" 2>&1; bom_rc=$?
echo "   bomtool demo 退出码：$bom_rc，输出 $(wc -l < "$tmpd/bom.txt") 行，前 8 行："
sed -n '1,8p' "$tmpd/bom.txt" | sed 's/^/     /'
brc=0
for key in "SPDXVersion: SPDX-2.2" "PackageName: demo@3.2.1" "PackageLicenseDeclared: MIT" "Creator: Tool: bomtool $VER"; do
  if { grep -F "$key" "$tmpd/bom.txt" >/dev/null; }; then printf '     OK   SBOM 含 %s\n' "$key"
  else printf '     FAIL SBOM 缺 %s\n' "$key"; brc=1; fi
done
[ $bom_rc -eq 0 ] || { echo "     FAIL bomtool 退出码非 0"; brc=1; }
[ $brc -eq 0 ] || rc=1
echo "d) libpkgconf —— 供其它工具（IDE / 编译器）使用其框架：用已安装的头文件 + 共享库"
echo "   编译一个最小 C 程序，调用 libpkgconf 的 client API 查询同一个 demo 包："
cat > "$tmpd/uselib.c" <<'EOF'
#include <stdio.h>
#include <libpkgconf/libpkgconf.h>

static bool err_handler(const char *msg, const pkgconf_client_t *c, void *d)
{ (void)c; (void)d; fputs(msg, stderr); return true; }

int main(void)
{
	pkgconf_cross_personality_t *personality = pkgconf_cross_personality_default();
	pkgconf_client_t *client = pkgconf_client_new(err_handler, NULL, personality);
	pkgconf_pkg_t *pkg;

	if (client == NULL) { printf("no-client\n"); return 1; }
	pkgconf_client_dir_list_build(client, personality);
	pkg = pkgconf_pkg_find(client, "demo");
	if (pkg == NULL) { printf("not-found\n"); pkgconf_client_free(client); return 1; }
	printf("id=%s version=%s\n", pkg->id, pkg->version);
	pkgconf_pkg_unref(client, pkg);
	pkgconf_client_free(client);
	return 0;
}
EOF
if gcc -I/usr/include/pkgconf -o "$tmpd/uselib" "$tmpd/uselib.c" -lpkgconf > "$tmpd/cc.log" 2>&1; then
  echo "   OK   gcc -I/usr/include/pkgconf ... -lpkgconf 编译成功"
  uo=$(PKG_CONFIG_PATH="$tmpd/pc" "$tmpd/uselib" 2>&1)
  echo "   运行输出：$uo"
  if [ "$uo" = "id=demo version=3.2.1" ]; then
    echo "   OK   libpkgconf 的公共 API 可被第三方程序链接并正确工作"
  else echo "   FAIL libpkgconf API 返回不符合预期"; rc=1; fi
  echo "   该程序的动态依赖："
  ldd "$tmpd/uselib" | sed 's/^/     /'
else
  echo "   FAIL 无法用已安装的头/库编译第三方程序，编译日志："
  sed -n '1,20p' "$tmpd/cc.log" | sed 's/^/     /'
  rc=1
fi
echo "e) pkg.m4（供 autoconf 的 PKG_CHECK_MODULES 使用，装在 /usr/share/aclocal）："
{ grep -nE '^AC_DEFUN\(\[PKG_(PROG_PKG_CONFIG|CHECK_MODULES)\]' /usr/share/aclocal/pkg.m4 || true; } | sed 's/^/     /'
if { grep -E '^AC_DEFUN\(\[PKG_CHECK_MODULES\]' /usr/share/aclocal/pkg.m4 >/dev/null; }; then
  echo "     OK   pkg.m4 提供 PKG_CHECK_MODULES 宏"
else echo "     FAIL pkg.m4 内容异常"; rc=1; fi
echo "f) man 页可被 man 命令找到（若 man 已安装）："
if command -v man >/dev/null 2>&1; then
  for m in pkgconf pkg-config bomtool; do
    p=$(man -w "$m" 2>/dev/null || true)
    printf '     %-12s man -w -> %s\n' "$m" "${p:-（未找到）}"
  done
else
  echo "     INFO man 命令尚未安装（§8.x Man-DB 在后续小节），仅确认文件存在："
  ls -l /usr/share/man/man1/pkgconf.1 /usr/share/man/man1/pkg-config.1 \
        /usr/share/man/man1/bomtool.1 | sed 's/^/       /'
fi
unset PKG_CONFIG_PATH
rm -rf "$tmpd"
echo
echo "6) 本节写入系统的文件清单（含两条手册符号链接）："
{ ls -l /usr/bin/pkgconf /usr/bin/bomtool /usr/bin/pkg-config \
        /usr/lib/libpkgconf.so /usr/lib/libpkgconf.so.7 /usr/lib/libpkgconf.so.7.0.0 \
        /usr/lib/libpkgconf.la /usr/lib/pkgconfig/libpkgconf.pc /usr/share/aclocal/pkg.m4 \
        /usr/share/man/man1/pkgconf.1 /usr/share/man/man1/pkg-config.1 \
        /usr/share/man/man1/bomtool.1 /usr/share/man/man5/pc.5 \
        /usr/share/man/man5/pkgconf-personality.5 /usr/share/man/man7/pkg.m4.7 \
        2>/dev/null || true; } | sed 's/^/     /'
echo "   /usr/include/pkgconf/libpkgconf/："
{ ls -l /usr/include/pkgconf/libpkgconf/ || true; } | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Pkgconf 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.20.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make install 完整输出：$INSTLOG"
rm -f /tmp/pkgconf-dyn.txt /tmp/pkgconf-syms.txt
cd /sources
rm -rf "$SRCDIR"
if [ -d "/sources/$SRCDIR" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCDIR"
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -mindepth 1 -type d || true; } | sed 's/^/  /'
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.20 完成，结束时间：$(date -Is) ====="
