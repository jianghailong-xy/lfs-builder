#!/usr/bin/env bash
# LFS 13.0-systemd §8.17 Tcl-8.6.17
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.17.1 Installation of Tcl 的命令序列（全部，一条不多一条不少）：
#   SRCDIR=$(pwd)
#   cd unix
#   ./configure --prefix=/usr           \
#               --mandir=/usr/share/man \
#               --disable-rpath
#   make
#   sed -e "s|$SRCDIR/unix|/usr/lib|" -e "s|$SRCDIR|/usr/include|" -i tclConfig.sh
#   sed ... -i pkgs/tdbc1.1.12/tdbcConfig.sh
#   sed ... -i pkgs/itcl4.3.4/itclConfig.sh
#   unset SRCDIR
#   LC_ALL=C.UTF-8 make test
#   make install
#   chmod 644 /usr/lib/libtclstub8.6.a
#   chmod -v u+w /usr/lib/libtcl8.6.so
#   make install-private-headers
#   ln -sfv tclsh8.6 /usr/bin/tclsh
#   mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3
#   （Optionally）cd .. ; tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1 ;
#                 mkdir -v -p /usr/share/doc/tcl-8.6.17 ; cp -v -r ./html/* /usr/share/doc/tcl-8.6.17
# 本节没有补丁；手册全节没有任何关于允许测试失败的 Note / Caution。
set -euo pipefail

PKG=tcl
VER=8.6.17
TARBALL=tcl8.6.17-src.tar.gz
HTMLBALL=tcl8.6.17-html.tar.gz
SRCTOP=tcl8.6.17
CONFLOG=/sources/.tcl-configure.log
MAKELOG=/sources/.tcl-make.log
TESTLOG=/sources/.tcl-make-test.log
INSTLOG=/sources/.tcl-make-install.log

echo "===== LFS 13.0-systemd §8.17 Tcl-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Tcl package contains the Tool Command Language, a robust"
echo "  general-purpose scripting language. The Expect package is written in Tcl"
echo "  (pronounced \"tickle\")."
echo "手册数据：Approximate build time 2.9 SBU，Required disk space 91 MB"
echo "手册说明（§8.17.1 开头）：This package and the next two (Expect and DejaGNU) are"
echo "  installed to support running the test suites for Binutils, GCC and other packages."
echo "  Installing three packages for testing purposes may seem excessive, but it is very"
echo "  reassuring, if not essential, to know that the most important tools are working"
echo "  properly."
echo "手册存档：/workspace/docs/book/chapter08-tcl.html（宿主机 \$LFS_ROOT/docs/book/）"
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
echo "1) 上一任务 §8.16 Flex-2.6.4 的产物（确认其已完成、产物可用）："
for f in /usr/bin/flex /usr/bin/flex++ /usr/bin/lex /usr/lib/libfl.so \
         /usr/include/FlexLexer.h /usr/share/man/man1/flex.1 /usr/share/man/man1/lex.1; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.16 未完成？）\n' "$f"; rc=1; fi
done
echo "   flex 自述版本：$(flex --version 2>&1 | sed -n 1p)"
flexd=$(mktemp -d /tmp/flexsmoke-XXXXXX)
cat > "$flexd/s.l" <<'LEX'
%option noyywrap
%%
[0-9]+   { printf("N(%s)", yytext); }
.|\n     { }
%%
int main(void){ yylex(); printf("\n"); return 0; }
LEX
if flex -o "$flexd/s.c" "$flexd/s.l" && gcc -o "$flexd/s" "$flexd/s.c" \
   && [ "$(printf 'a 12 b 7\n' | "$flexd/s")" = "N(12)N(7)" ]; then
  echo "   OK   flex 冒烟：由规则文件生成扫描器并正确识别数字"
else echo "   FAIL 上一任务的 flex 冒烟测试失败"; rc=1; fi
rm -rf "$flexd"
echo "   说明：Tcl 不依赖 Flex，此处只用于确认「上一任务产物可用」。"
echo
echo "2) 编译 Tcl 所需的工具链与 C 库（§8.5 Glibc-2.43 等）："
for f in /usr/lib/libc.so.6 /usr/lib/libm.so.6 /lib64/ld-linux-x86-64.so.2 \
         /usr/include/stdio.h /usr/include/pthread.h /usr/include/dlfcn.h \
         /usr/include/zlib.h /usr/lib/libz.so; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   说明：Tcl 的 configure 会探测系统 zlib（generic/tclZlib.c），§8.6 Zlib 已装。"
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("glibc sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
tmpz=$(mktemp /tmp/zsanity-XXXXXX.c)
cat > "$tmpz" <<'EOF'
#include <zlib.h>
#include <stdio.h>
int main(void){ printf("zlib %s\n", zlibVersion()); return 0; }
EOF
if gcc -o "${tmpz%.c}" "$tmpz" -lz >/dev/null 2>&1; then
  echo "   OK   可链接系统 zlib：$("${tmpz%.c}")"
else echo "   FAIL 无法链接 -lz"; rc=1; fi
rm -f "$tmpz" "${tmpz%.c}"
echo
echo "3) 本节直接用到的工具："
for t in tar gzip make gcc ld ar ranlib sed grep awk install ln mv cp mkdir chmod \
         find file readelf ldd stat sort head tail tr wc md5sum timeout; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %-10s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo
echo "4) 测试套件运行所需的运行时环境（tcltest 会用到 /tmp、/dev、/proc、exec 子进程）："
for f in /dev/null /dev/zero /dev/urandom /dev/tty /dev/pts /proc/self /tmp /var/tmp \
         /etc/passwd /etc/group /bin/sh /usr/bin/cat /usr/bin/echo; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   TZ 相关：/usr/share/zoneinfo $( [ -d /usr/share/zoneinfo ] && echo 存在 || echo '不存在（clock 测试会跳过相关用例）')"
echo "   locale C.UTF-8 是否可用（手册测试命令用 LC_ALL=C.UTF-8）："
if LC_ALL=C.UTF-8 locale >/dev/null 2>&1; then echo "     OK   LC_ALL=C.UTF-8 可用"
else echo "     INFO LC_ALL=C.UTF-8 未被 locale 命令接受（C.UTF-8 由 glibc 内建，通常仍可用）"; fi
echo
echo "5) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "6) 安装目标目录（手册 §8.17.2 Contents）："
for d in /usr/bin /usr/lib /usr/include /usr/share/man /usr/share/man/man3 /usr/share/doc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo
echo "7) 源码包（/sources 是宿主机 bind mount）："
for t in "$TARBALL" "$HTMLBALL"; do
  if [ -f "/sources/$t" ]; then echo "   OK   /sources/$t 存在（$(stat -c %s "/sources/$t") 字节）"
  else echo "   FAIL /sources/$t 缺失"; rc=1; fi
done
echo "   （$HTMLBALL 用于手册标注 Optionally 的文档安装步骤）"
echo
echo "8) 安装前系统中的 Tcl 痕迹（Tcl 在第 5–7 章从未构建过，预期全部不存在）："
for f in /usr/bin/tclsh /usr/bin/tclsh8.6 /usr/lib/libtcl8.6.so /usr/lib/libtclstub8.6.a \
         /usr/lib/tcl8.6 /usr/lib/tclConfig.sh /usr/include/tcl.h \
         /usr/share/man/man3/Thread.3 /usr/share/man/man3/Tcl_Thread.3 \
         /usr/share/doc/tcl-$VER; do
  if [ -e "$f" ] || [ -L "$f" ]; then printf '   INFO %-38s 已存在\n' "$f"
  else printf '   INFO %-38s 不存在（符合预期：本节是首次安装）\n' "$f"; fi
done
echo "   注意：手册命令 mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3 依赖 make install"
echo "     刚装出来的 Thread.3；上面的清单用于确认它不是此前遗留的文件。"
echo
echo "9) 磁盘空间（手册要求 91 MB；本节还要跑完整测试套件）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 1048576 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 91 MB"
else echo "   FAIL 可用空间不足：$((avail_k/1024)) MB"; rc=1; fi
echo
echo "10) 内存与并行度（make test 会并发跑 test-tcl 与 test-packages）："
free -m 2>/dev/null | sed 's/^/   /' || echo "   （无 free 命令）"
echo "   MAKEFLAGS=${MAKEFLAGS:-} —— 手册 §7.4 规定的 -j\$(nproc)"
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " ($TARBALL|$HTMLBALL)\$" md5sums
grep -E " ($TARBALL|$HTMLBALL)\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCTOP"
tar -xf "$TARBALL"
cd "$SRCTOP"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
echo "上游版本自述（unix/configure.in 的 TCL_VERSION / TCL_PATCH_LEVEL）："
{ grep -nE '^(TCL_VERSION|TCL_PATCH_LEVEL)=' unix/configure.in || true; } | sed 's/^/  /'
# 注意：unix/configure.in 里 TCL_VERSION=8.6 不带引号，而 TCL_PATCH_LEVEL=".17" 带引号，
# 直接拼接会得到 8.6".17"，故两者都要去掉字面量引号。
src_ver=$(sed -n 's/^TCL_VERSION=//p' unix/configure.in | tr -d '\r"' | awk 'NR==1')
src_patch=$(sed -n 's/^TCL_PATCH_LEVEL=//p' unix/configure.in | tr -d '\r"' | awk 'NR==1')
echo "  拼出的完整版本：$src_ver$src_patch"
if [ "$src_ver$src_patch" = "$VER" ]; then
  echo "  OK   源码自述版本 $src_ver$src_patch 与手册 §8.17 的 Tcl-$VER 一致"
else echo "  FAIL 源码自述版本为 '$src_ver$src_patch'，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁：/sources 中匹配 tcl*patch 的文件：$({ ls /sources | grep -E '^tcl.*patch' || true; } | tr '\n' ' ')"
echo

echo "----- 上游结构预读（先读上游再写自检） -----"
echo "a) unix/Makefile.in：make 的默认目标与安装目标的构成"
{ grep -nE '^(all:|install:|INSTALL_BASE_TARGETS|INSTALL_DEV_TARGETS|INSTALL_DOC_TARGETS|INSTALL_PACKAGE_TARGETS|INSTALL_TARGETS) ?=?' unix/Makefile.in || true; } | sed 's/^/    /'
echo "    → make install 会依次跑 install-binaries / install-libraries / install-msgs /"
echo "      install-headers / install-doc / install-packages（install-tzdata 视 configure 而定）。"
echo "b) unix/Makefile.in：install-binaries 里对已装共享库执行 chmod 555 —— 这正是手册随后"
echo "   要 chmod -v u+w /usr/lib/libtcl8.6.so 的原因"
{ grep -nB1 -A1 'chmod 555' unix/Makefile.in || true; } | sed 's/^/    /'
echo "c) unix/Makefile.in：test 目标 = test-tcl + test-packages"
{ sed -n '/^test:/,/^$/p;/^test-tcl:/,/^$/p' unix/Makefile.in || true; } | sed 's/^/    /'
echo "    → MAKEFLAGS=-j 时两者并发执行，两套测试的输出会交错，因此判据取"
echo "      「所有 all.tcl 汇总行的 Failed 之和」与 make 退出码，而不是按出现顺序取某一行。"
echo "d) unix/Makefile.in：packages 目标把 pkgs/* 逐个 configure 到 unix/pkgs/<pkg>"
{ grep -nA6 '^configure-packages:' unix/Makefile.in || true; } | sed 's/^/    /'
echo "    → 手册两条针对 pkgs 的 sed 的目标文件 unix/pkgs/{tdbc1.1.12,itcl4.3.4}/*Config.sh"
echo "      由此产生；源码树中的版本号必须与手册写死的一致，核对："
for p in tdbc1.1.12 itcl4.3.4; do
  if [ -d "pkgs/$p" ]; then echo "      OK   pkgs/$p 存在（手册 sed 中写死的版本号与源码一致）"
  else echo "      FAIL pkgs/$p 不存在，手册的 sed 目标将落空" >&2; exit 1; fi
done
echo "    源码树 pkgs/ 全部子目录：$(ls pkgs | tr '\n' ' ')"
echo "e) unix/configure：--disable-rpath 的作用（Linux 分支下把 CC_SEARCH_FLAGS 置空，"
echo "   LD_SEARCH_FLAGS 取自 CC_SEARCH_FLAGS，于是链接时不再写入 -Wl,-rpath）"
{ grep -nA3 'checking if rpath support is requested' unix/configure || true; } | sed -n '1,8p' | sed 's/^/    /'
echo

echo "================= 8.17.1. Installation of Tcl ================="
echo
echo "----- 手册命令 1/3（Prepare Tcl for compilation）：SRCDIR / cd unix / configure -----"
echo "手册命令：SRCDIR=\$(pwd)"
SRCDIR=$(pwd)
echo "  SRCDIR = $SRCDIR"
echo "手册命令：cd unix"
cd unix
echo "  当前目录 = $PWD"
echo "手册命令：./configure --prefix=/usr           \\"
echo "                     --mandir=/usr/share/man \\"
echo "                     --disable-rpath"
echo "手册对新选项的解释：--disable-rpath —— This parameter prevents hard coding library"
echo "  search paths (rpath) into the binary executable files and shared libraries. This"
echo "  package does not need rpath for an installation into the standard location, and"
echo "  rpath may sometimes cause unwanted effects or even security issues."
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --disable-rpath > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "configure 关键探测行："
{ grep -nE 'checking (if rpath support is requested|for gcc|for build with symbols|whether to use dll unloading|for required early compiler flags|if compiler supports visibility|for the existence of zlib|whether to use zlib)|^Configuring package|config\.status: creating' "$CONFLOG" || true; } | sed -n '1,40p' | sed 's/^/  /'
echo

echo "----- 核对手册的 3 个 configure 选项确实生效（configure 结论 + 生成的 Makefile） -----"
crc=0
[ -f Makefile ] || { echo "  FAIL configure 未生成 unix/Makefile"; exit 1; }
echo "a) --prefix=/usr 与 --mandir=/usr/share/man —— 生成的 Makefile 中的安装路径变量："
{ grep -nE '^(prefix|exec_prefix|bindir|libdir|includedir|mandir|PACKAGE_DIR|MAN_INSTALL_DIR|SCRIPT_INSTALL_DIR)[[:space:]]*=' Makefile || true; } | sed 's/^/    /'
got_prefix=$(sed -n 's/^prefix[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
got_mandir=$(sed -n 's/^mandir[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
got_libdir=$(sed -n 's/^libdir[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
if [ "$got_prefix" = /usr ]; then echo "    OK   prefix = /usr"
else echo "    FAIL prefix 为 '$got_prefix'"; crc=1; fi
if [ "$got_mandir" = /usr/share/man ]; then
  echo "    OK   mandir = /usr/share/man（不给此选项时 autoconf 默认是 \${prefix}/man，"
  echo "         即 /usr/man —— 不符合 FHS，这正是手册显式给 --mandir 的原因）"
else echo "    FAIL mandir 为 '$got_mandir'"; crc=1; fi
if [ "$got_libdir" = /usr/lib ]; then echo "    OK   libdir = /usr/lib（PACKAGE_DIR 亦取自此，pkgs 装到 /usr/lib/<pkg>）"
else echo "    FAIL libdir 为 '$got_libdir'"; crc=1; fi
echo "b) --disable-rpath —— 三重核对之一：configure 自己的探测结论"
{ grep -n 'checking if rpath support is requested' "$CONFLOG" || true; } | sed 's/^/    /'
rpath_ans=$(sed -n 's/.*checking if rpath support is requested\.\.\. //p' "$CONFLOG" | awk 'NR==1')
if [ "$rpath_ans" = no ]; then echo "    OK   configure 结论：rpath support is requested = no"
else echo "    FAIL configure 结论为 '$rpath_ans'"; crc=1; fi
echo "   三重核对之二：生成的 Makefile 中的搜索路径变量必须为空"
{ grep -nE '^(CC_SEARCH_FLAGS|LD_SEARCH_FLAGS)[[:space:]]*=' Makefile || true; } | cat -A | sed 's/^/    /'
cc_sf=$(sed -n 's/^CC_SEARCH_FLAGS[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
ld_sf=$(sed -n 's/^LD_SEARCH_FLAGS[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
if [ -z "$cc_sf" ] && [ -z "$ld_sf" ]; then
  echo "    OK   CC_SEARCH_FLAGS 与 LD_SEARCH_FLAGS 均为空（未给该选项时是 -Wl,-rpath,\${LIB_RUNTIME_DIR}）"
else echo "    FAIL CC_SEARCH_FLAGS='$cc_sf' LD_SEARCH_FLAGS='$ld_sf'"; crc=1; fi
echo "   （三重核对之三 —— 安装后用 readelf -d 确认二进制里没有 RPATH/RUNPATH —— 见后文）"
echo "c) 其它由 configure 决定、影响本节结果的变量："
{ grep -nE '^(VERSION|TCL_LIB_FILE|STUB_LIB_FILE|TCL_STUB_LIB_FILE|SHARED_BUILD|TCL_THREADS|CC|CFLAGS_OPTIMIZE|INSTALL_TZDATA|DL_LIBS|TCL_LIBS)[[:space:]]*=' Makefile || true; } | sed 's/^/    /'
got_ver=$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
got_libfile=$(sed -n 's/^TCL_LIB_FILE[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
if [ "$got_ver" = 8.6 ]; then echo "    OK   VERSION = 8.6（决定 tclsh8.6 / libtcl8.6.so / /usr/lib/tcl8.6 等名字）"
else echo "    FAIL VERSION = '$got_ver'"; crc=1; fi
if [ "$got_libfile" = libtcl8.6.so ]; then echo "    OK   TCL_LIB_FILE = libtcl8.6.so（共享库构建）"
else echo "    FAIL TCL_LIB_FILE = '$got_libfile'"; crc=1; fi
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册的选项要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册的 --prefix=/usr + --mandir=/usr/share/man + --disable-rpath"
echo

echo "----- 手册命令 2/3（Build the package）：make + 3 条 sed + unset SRCDIR -----"
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
echo "make 中构建的 pkgs（Configuring/Building package 行）："
{ grep -nE "^(Configuring|Building) package" "$MAKELOG" || true; } | sed 's/^/  /'
echo "make 输出末尾 5 行："
tail -n 5 "$MAKELOG" | sed 's/^/  /'
echo
echo "----- 编译结果确认 -----"
mrc=0
for f in tclsh libtcl8.6.so libtclstub8.6.a; do
  if [ -e "$f" ]; then printf '  OK   %-18s（%s 字节，%s）\n' "$f" "$(stat -Lc %s "$f")" "$(file -b "$f" | cut -d, -f1-2)"
  else printf '  FAIL %s 未生成\n' "$f"; mrc=1; fi
done
echo "  说明：构建树里的解释器名为 tclsh（安装时才改名为 tclsh8.6）；tcltest 由 make test"
echo "    在需要时才构建，此刻不存在属正常。"
echo "  构建产物自述版本（用构建树里的 tclsh，需指向未安装的脚本库）："
build_pl=$(echo 'puts $tcl_patchLevel' | TCL_LIBRARY="$SRCDIR/library" LD_LIBRARY_PATH="$PWD" ./tclsh)
echo "    tcl_patchLevel = $build_pl"
if [ "$build_pl" = "$VER" ]; then echo "    OK   自述为 $VER"
else echo "    FAIL 自述为 '$build_pl'"; mrc=1; fi
echo "  tclsh 的动态依赖（不得含 /tools）："
LD_LIBRARY_PATH="$PWD" ldd ./tclsh | sed 's/^/    /'
ldd_build=$(LD_LIBRARY_PATH="$PWD" ldd ./tclsh)
case "$ldd_build" in *"/tools/"*) echo "    FAIL 仍链接 /tools 下的库"; mrc=1 ;; *) echo "    OK   未链接任何 /tools 路径" ;; esac
case "$ldd_build" in *libz.so*) echo "    OK   链接系统 zlib（§8.6 的产物）" ;; *) echo "    INFO 未直接链接 libz（可能由 libtcl8.6.so 间接引入）" ;; esac
echo "  --disable-rpath 的即时效果（构建树里的二进制不应有 RPATH/RUNPATH）："
for f in ./tclsh ./libtcl8.6.so; do
  dyn=$({ readelf -d "$f" || true; })
  case "$dyn" in
    *RUNPATH*|*RPATH*) echo "    FAIL $f 含 RPATH/RUNPATH："; printf '%s\n' "$dyn" | sed -n '/PATH/p' | sed 's/^/      /'; mrc=1 ;;
    *) echo "    OK   $f 无 RPATH/RUNPATH" ;;
  esac
done
echo "  已构建的 pkgs 目录（unix/pkgs/）："
{ ls pkgs || true; } | sed 's/^/    /'
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 3 条 sed：把配置文件里的构建目录换成安装目录 -----"
echo "手册原文：The various \"sed\" instructions after the \"make\" command remove references"
echo "  to the build directory from the configuration files and replace them with the"
echo "  install directory. This is not mandatory for the remainder of LFS, but may be"
echo "  needed if a package built later uses Tcl."
echo "替换前，三个文件中出现 \$SRCDIR（$SRCDIR）的行："
for f in tclConfig.sh pkgs/tdbc1.1.12/tdbcConfig.sh pkgs/itcl4.3.4/itclConfig.sh; do
  if [ -f "$f" ]; then
    n=$({ grep -c "$SRCDIR" "$f" || true; })
    echo "  $f：$n 行"
    { grep -n "$SRCDIR" "$f" || true; } | sed 's/^/    /'
  else echo "  FAIL $f 不存在（make 未生成？）" >&2; exit 1; fi
done
echo
echo "手册命令：sed -e \"s|\$SRCDIR/unix|/usr/lib|\" -e \"s|\$SRCDIR|/usr/include|\" -i tclConfig.sh"
sed -e "s|$SRCDIR/unix|/usr/lib|" \
    -e "s|$SRCDIR|/usr/include|"  \
    -i tclConfig.sh
echo "手册命令：sed ... -i pkgs/tdbc1.1.12/tdbcConfig.sh"
sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.12|/usr/lib/tdbc1.1.12|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/generic|/usr/include|"     \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/library|/usr/lib/tcl8.6|"  \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12|/usr/include|"             \
    -i pkgs/tdbc1.1.12/tdbcConfig.sh
echo "手册命令：sed ... -i pkgs/itcl4.3.4/itclConfig.sh"
sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.4|/usr/lib/itcl4.3.4|" \
    -e "s|$SRCDIR/pkgs/itcl4.3.4/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/itcl4.3.4|/usr/include|"            \
    -i pkgs/itcl4.3.4/itclConfig.sh
echo
echo "替换后核对：三个文件中不得再出现构建目录，且替换成了预期的安装路径"
src_rc=0
for f in tclConfig.sh pkgs/tdbc1.1.12/tdbcConfig.sh pkgs/itcl4.3.4/itclConfig.sh; do
  n=$({ grep -c "$SRCDIR" "$f" || true; })
  if [ "$n" -eq 0 ]; then echo "  OK   $f 中已无 $SRCDIR"
  else echo "  FAIL $f 中仍有 $n 行含构建目录："; { grep -n "$SRCDIR" "$f" || true; } | sed 's/^/    /'; src_rc=1; fi
done
echo "  替换后的关键行："
{ grep -nE "^TCL_(SRC_DIR|BUILD_LIB_SPEC|LIB_SPEC|INCLUDE_SPEC|BUILD_STUB_LIB_SPEC|BUILD_STUB_LIB_PATH|STUB_LIB_PATH)=" tclConfig.sh || true; } | sed 's/^/    /'
{ grep -nE "^(tdbc_SRC_DIR|tdbc_BUILD_LIB_SPEC|tdbc_BUILD_INCLUDE_SPEC|tdbc_BUILD_LIBRARY_PATH)=" pkgs/tdbc1.1.12/tdbcConfig.sh || true; } | sed 's/^/    /'
{ grep -nE "^(itcl_SRC_DIR|itcl_BUILD_LIB_SPEC|itcl_INCLUDE_SPEC)=" pkgs/itcl4.3.4/itclConfig.sh || true; } | sed 's/^/    /'
[ $src_rc -eq 0 ] || { echo "错误：sed 未能清除全部构建目录引用" >&2; exit 1; }
echo "手册命令：unset SRCDIR"
unset SRCDIR
echo "  SRCDIR 已 unset（是否仍有该变量：$( [ -z "${SRCDIR+x}" ] && echo 否 || echo 是 )）"
echo

echo "----- 手册命令 3/3 之测试：LC_ALL=C.UTF-8 make test -----"
echo "手册原文：To test the results, issue:  LC_ALL=C.UTF-8 make test"
echo "（手册 §8.17 全节没有任何关于测试结果的 Note / Caution，即要求测试无失败。"
echo "  本包用 tcltest：test = test-tcl + test-packages，各自在结束时打印一行"
echo "  'all.tcl:<TAB>Total N Passed N Skipped N Failed N'。MAKEFLAGS=-j 时两者并发，"
echo "  输出交错，故判据是：make 退出码 0，且所有 all.tcl 汇总行的 Failed 之和为 0，"
echo "  且日志中没有 'Files with failing tests' 与 'Test file error'。）"
echo "完整输出写入 $TESTLOG。"
test_start=$(date -Is)
set +e
LC_ALL=C.UTF-8 make test > "$TESTLOG" 2>&1
test_rc=$?
set -e
test_end=$(date -Is)
echo "make test 退出码：$test_rc（$test_start -> $test_end，输出 $(wc -l < "$TESTLOG") 行）"
echo
echo "----- 各测试套件的 tcltest 汇总行 -----"
{ grep -nE '^all\.tcl:' "$TESTLOG" || true; } | sed 's/^/  /'
echo
echo "----- 被测试的 pkgs -----"
{ grep -nE "^Testing package '" "$TESTLOG" || true; } | sed 's/^/  /'
echo
echo "----- 汇总统计 -----"
awk -F'\t' '/^all\.tcl:/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "Total")   tot += $(i+1);
      if ($i == "Passed")  pas += $(i+1);
      if ($i == "Skipped") skp += $(i+1);
      if ($i == "Failed")  fal += $(i+1);
    }
    n++;
  }
  END { printf "  汇总行数=%d  Total=%d  Passed=%d  Skipped=%d  Failed=%d\n", n, tot, pas, skp, fal }' "$TESTLOG"
sum_n=$(awk -F'\t' '/^all\.tcl:/{n++} END{print n+0}' "$TESTLOG")
sum_total=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Total") s+=$(i+1)} END{print s+0}' "$TESTLOG")
sum_pass=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Passed") s+=$(i+1)} END{print s+0}' "$TESTLOG")
sum_skip=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Skipped") s+=$(i+1)} END{print s+0}' "$TESTLOG")
sum_fail=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Failed") s+=$(i+1)} END{print s+0}' "$TESTLOG")
echo "  失败线索行（Files with failing tests / Test file error / ==== ... FAILED）："
{ grep -nE 'Files with failing tests|Test file error|^==== .*FAILED' "$TESTLOG" || true; } | sed -n '1,60p' | sed 's/^/    /'
n_failfiles=$({ grep -cE 'Files with failing tests' "$TESTLOG" || true; })
n_fileerr=$({ grep -cE 'Test file error' "$TESTLOG" || true; })
n_failed_marker=$({ grep -cE '^==== .*FAILED' "$TESTLOG" || true; })
echo "    Files with failing tests 行数：$n_failfiles"
echo "    Test file error 行数：$n_fileerr"
echo "    '==== ... FAILED' 行数：$n_failed_marker"
echo
echo "  「Test file error」的归类 —— 手册第 8 章此时尚未安装（且 LFS 基础系统根本不含）"
echo "    MySQL / iODBC / PostgreSQL 的客户端库，因此 pkgs 里的 tdbcmysql、tdbcodbc、"
echo "    tdbcpostgres 三个驱动的测试文件在 load 阶段就报 'couldn'\''t load file'，其"
echo "    tcltest 汇总相应为 Total 0 / Failed 0 —— 这不是 Tcl 本身的测试失败。"
echo "    判据：只有「不是这三类缺库」的 Test file error 才算真失败。"
n_fileerr_dblib=$({ grep -cE "Test file error: couldn't load file \"(libmysql\\.so\\.[0-9]+|libiodbc\\.so|libpq\\.so\\.[0-9]+)\"" "$TESTLOG" || true; })
echo "    其中属于缺 MySQL/iODBC/PostgreSQL 客户端库的：$n_fileerr_dblib 行"
n_fileerr_other=$(( n_fileerr - n_fileerr_dblib ))
echo "    其它（视为真失败）：$n_fileerr_other 行"
if [ "$n_fileerr_other" -gt 0 ]; then
  echo "    未归类的 Test file error 行："
  { grep -nE 'Test file error' "$TESTLOG" || true; } \
    | { grep -vE "couldn't load file \"(libmysql\\.so\\.[0-9]+|libiodbc\\.so|libpq\\.so\\.[0-9]+)\"" || true; } | sed 's/^/      /'
fi
echo "  各 constraint 跳过统计（tcltest 的 Number of tests skipped for each constraint）："
{ awk '/Number of tests skipped for each constraint/{f=1;print;next} f&&/^\t/{print;next} f{f=0}' "$TESTLOG" || true; } | sed 's/^/    /'
echo
echo "----- make test 结论 -----"
trc=0
if [ "$test_rc" -ne 0 ]; then echo "  FAIL make test 退出码 $test_rc"; trc=1
else echo "  OK   make test 退出码 0"; fi
if [ "$sum_n" -ge 2 ]; then echo "  OK   共 $sum_n 个 tcltest 汇总行（test-tcl 1 个 + 各 pkg 各 1 个）"
else echo "  FAIL 只找到 $sum_n 个汇总行，测试疑似未真正运行"; trc=1; fi
if [ "$sum_total" -ge 20000 ]; then echo "  OK   用例总数 $sum_total（Tcl 主测试套件量级正常）"
else echo "  FAIL 用例总数只有 $sum_total，测试疑似未跑全"; trc=1; fi
if [ "$sum_fail" -eq 0 ]; then echo "  OK   Failed 合计 = 0"
else echo "  FAIL Failed 合计 = $sum_fail（手册 §8.17 未允许任何失败）"; trc=1; fi
if [ "$n_failfiles" -eq 0 ]; then echo "  OK   日志中没有 'Files with failing tests'"
else echo "  FAIL 日志中出现 'Files with failing tests'"; trc=1; fi
if [ "$n_failed_marker" -eq 0 ]; then echo "  OK   日志中没有 '==== ... FAILED' 用例标记"
else echo "  FAIL 日志中出现 $n_failed_marker 个 '==== ... FAILED' 用例标记"; trc=1; fi
if [ "$n_fileerr_other" -eq 0 ]; then
  echo "  OK   Test file error 共 $n_fileerr 行，全部是 tdbcmysql/tdbcodbc/tdbcpostgres 缺"
  echo "       数据库客户端库所致（LFS 基础系统不含 MySQL/iODBC/PostgreSQL），无其它类型"
else echo "  FAIL 存在 $n_fileerr_other 行无法用「缺数据库客户端库」解释的 Test file error"; trc=1; fi
if [ $trc -ne 0 ]; then
  echo "错误：测试结果不符合手册要求；make test 末尾 80 行：" >&2
  tail -n 80 "$TESTLOG" | sed 's/^/  /' >&2
  exit 1
fi
echo "结论：§8.17 的 LC_ALL=C.UTF-8 make test 退出码 0，$sum_n 个测试套件合计"
echo "  Total=$sum_total Passed=$sum_pass Skipped=$sum_skip Failed=$sum_fail，无失败项。"
echo "  唯一的非 PASS 现象是 $n_fileerr_dblib 行 Test file error，来自 tdbcmysql / tdbcodbc /"
echo "  tdbcpostgres 三个数据库驱动在 load 阶段找不到 libmysql / libiodbc / libpq —— LFS"
echo "  基础系统不包含这些第三方客户端库，属环境使然而非 Tcl 缺陷，对应套件 Total 均为 0。"
echo

echo "----- 手册命令：make install + chmod 644 /usr/lib/libtclstub8.6.a -----"
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
echo "make install 中的 Installing 行（摘要）："
{ grep -nE '^(Installing|Making directory)' "$INSTLOG" || true; } | sed -n '1,40p' | sed 's/^/  /'
echo "安装前 libtclstub8.6.a 的权限（install-binaries 用 INSTALL_LIBRARY 装入）："
ls -l /usr/lib/libtclstub8.6.a | sed 's/^/  /'
echo "手册命令：chmod 644 /usr/lib/libtclstub8.6.a"
chmod 644 /usr/lib/libtclstub8.6.a
ls -l /usr/lib/libtclstub8.6.a | sed 's/^/  /'
stub_mode=$(stat -c %a /usr/lib/libtclstub8.6.a)
if [ "$stub_mode" = 644 ]; then echo "  OK   /usr/lib/libtclstub8.6.a 权限为 644"
else echo "  FAIL 权限为 $stub_mode" >&2; exit 1; fi
echo

echo "----- 手册命令：chmod -v u+w /usr/lib/libtcl8.6.so -----"
echo "手册原文：Make the installed library writable so debugging symbols can be removed later:"
echo "  （unix/Makefile.in 的 install-binaries 里有 chmod 555，故装好后属主不可写；"
echo "   §8.83 Stripping 要对它执行 strip，因此这里先加上写权限。）"
echo "执行前："; ls -l /usr/lib/libtcl8.6.so | sed 's/^/  /'
chmod -v u+w /usr/lib/libtcl8.6.so
echo "执行后："; ls -l /usr/lib/libtcl8.6.so | sed 's/^/  /'
if [ -w /usr/lib/libtcl8.6.so ]; then echo "  OK   /usr/lib/libtcl8.6.so 现在可写"
else echo "  FAIL /usr/lib/libtcl8.6.so 仍不可写" >&2; exit 1; fi
echo

echo "----- 手册命令：make install-private-headers -----"
echo "手册原文：Install Tcl's headers. The next package, Expect, requires them."
set +e
make install-private-headers >> "$INSTLOG" 2>&1
iph_rc=$?
set -e
echo "make install-private-headers 退出码：$iph_rc"
if [ $iph_rc -ne 0 ]; then
  echo "失败，末尾 40 行："; tail -n 40 "$INSTLOG" | sed 's/^/  /'
  exit $iph_rc
fi
{ grep -nE 'private header' "$INSTLOG" || true; } | sed 's/^/  /'
echo "  §8.18 Expect 需要的私有头文件（unix/Makefile.in 的 install-private-headers 清单）："
iph_rc2=0
for h in tclInt.h tclIntDecls.h tclIntPlatDecls.h tclPort.h tclOOInt.h tclOOIntDecls.h \
         tclUnixPort.h; do
  if [ -f "/usr/include/$h" ]; then printf '    OK   /usr/include/%-20s（%s 字节）\n' "$h" "$(stat -Lc %s "/usr/include/$h")"
  else printf '    FAIL /usr/include/%s 缺失\n' "$h"; iph_rc2=1; fi
done
echo "    （规则里第 8 个文件 tclConfig.h 带 'if test -f tclConfig.h' 条件：unix 构建目录"
echo "      生成的配置头名为 tclConfig.h 但不在 unix/ 顶层，故实际不会被安装 ——"
echo "      本次 /usr/include/tclConfig.h：$( [ -f /usr/include/tclConfig.h ] && echo 存在 || echo 不存在 )，两种情况都不影响 §8.18 Expect）"
[ $iph_rc2 -eq 0 ] || { echo "错误：私有头文件未装全，§8.18 Expect 会失败" >&2; exit 1; }
echo

echo "----- 手册命令：ln -sfv tclsh8.6 /usr/bin/tclsh -----"
echo "手册原文：Now make a necessary symbolic link:"
ln -sfv tclsh8.6 /usr/bin/tclsh
echo

echo "----- 手册命令：mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3 -----"
echo "手册原文：Rename a man page that conflicts with a Perl man page:"
echo "  （§8.？ Perl 会安装 /usr/share/man/man3/Thread.3，两者同名冲突。）"
echo "执行前 man3 中的 Thread* ："
{ ls -l /usr/share/man/man3/Thread.3 /usr/share/man/man3/Tcl_Thread.3 2>&1 || true; } | sed 's/^/  /'
mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3
echo "执行后："
{ ls -l /usr/share/man/man3/Thread.3 /usr/share/man/man3/Tcl_Thread.3 2>&1 || true; } | sed 's/^/  /'
if [ -f /usr/share/man/man3/Tcl_Thread.3 ] && [ ! -e /usr/share/man/man3/Thread.3 ]; then
  echo "  OK   Thread.3 已改名为 Tcl_Thread.3，不再与 Perl 的 Thread.3 冲突"
else echo "  FAIL 改名结果不符" >&2; exit 1; fi
echo

echo "----- 手册命令（Optionally, install the documentation）-----"
echo "手册原文：Optionally, install the documentation by issuing the following commands:"
echo "手册命令：cd .."
cd ..
echo "  当前目录 = $PWD"
echo "手册命令：tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1"
tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1
echo "  解包后本目录多出：$( [ -d ./html ] && echo './html（'"$(find ./html -type f | wc -l)"' 个文件）' || echo '（无 html 目录）')"
echo "手册命令：mkdir -v -p /usr/share/doc/tcl-$VER"
mkdir -v -p /usr/share/doc/tcl-$VER
echo "手册命令：cp -v -r  ./html/* /usr/share/doc/tcl-$VER"
cp -v -r  ./html/* /usr/share/doc/tcl-$VER > /tmp/.tcl-doc-cp.log 2>&1
echo "  cp 复制了 $(wc -l < /tmp/.tcl-doc-cp.log) 项，前 5 行："
sed -n '1,5p' /tmp/.tcl-doc-cp.log | sed 's/^/    /'
rm -f /tmp/.tcl-doc-cp.log
echo "  /usr/share/doc/tcl-$VER 内容："
ls /usr/share/doc/tcl-$VER | sed 's/^/    /'
doc_n=$(find /usr/share/doc/tcl-$VER -type f | wc -l)
echo "  文件总数：$doc_n"
if [ "$doc_n" -gt 400 ]; then echo "  OK   文档已安装（html 手册页数量级正常）"
else echo "  FAIL 文档文件数异常：$doc_n" >&2; exit 1; fi
echo

echo "================= 安装后检查（手册 §8.17.2 Contents of Tcl） ================="
echo "手册列出的内容："
echo "  Installed programs: tclsh (link to tclsh8.6) and tclsh8.6"
echo "  Installed library : libtcl8.6.so and libtclstub8.6.a"
rc=0
echo
echo "1) Installed program：/usr/bin/tclsh8.6 —— The Tcl command shell"
if [ -x /usr/bin/tclsh8.6 ] && [ ! -L /usr/bin/tclsh8.6 ]; then
  printf '   OK   /usr/bin/tclsh8.6（%s 字节，%s）\n' "$(stat -Lc %s /usr/bin/tclsh8.6)" "$(file -b /usr/bin/tclsh8.6 | cut -d, -f1-2)"
else echo "   FAIL /usr/bin/tclsh8.6 缺失或不是普通可执行文件"; rc=1; fi
echo
echo "2) Installed program：/usr/bin/tclsh —— A link to tclsh8.6"
if [ -L /usr/bin/tclsh ]; then
  echo "   OK   /usr/bin/tclsh 是符号链接 -> $(readlink /usr/bin/tclsh)"
  if [ "$(readlink /usr/bin/tclsh)" = tclsh8.6 ]; then echo "   OK   指向 tclsh8.6（与手册 'link to tclsh8.6' 一致）"
  else echo "   FAIL 指向的不是 tclsh8.6"; rc=1; fi
else echo "   FAIL /usr/bin/tclsh 不是符号链接"; rc=1; fi
i_a=$(stat -Lc %i /usr/bin/tclsh8.6); i_b=$(stat -Lc %i /usr/bin/tclsh)
echo "   inode：tclsh8.6=$i_a  tclsh=$i_b"
if [ "$i_a" = "$i_b" ]; then echo "   OK   两者解析到同一个可执行文件"
else echo "   FAIL 两者不是同一个文件"; rc=1; fi
echo "   命令来源（PATH 解析）：$(command -v tclsh)"
inst_pl=$(echo 'puts $tcl_patchLevel' | tclsh || true)
echo "   已安装 tclsh 自述版本：tcl_patchLevel = $inst_pl"
if [ "$inst_pl" = "$VER" ]; then echo "   OK   自述为 $VER"
else echo "   FAIL 自述为 '$inst_pl'"; rc=1; fi
echo "   动态依赖（不得含 /tools）："
ldd /usr/bin/tclsh8.6 | sed 's/^/     /'
ldd_out=$(ldd /usr/bin/tclsh8.6)
case "$ldd_out" in *"/tools/"*) echo "     FAIL 仍链接 /tools 下的库"; rc=1 ;; *) echo "     OK   未链接任何 /tools 路径" ;; esac
case "$ldd_out" in *libtcl8.6.so*) echo "     OK   动态链接到 libtcl8.6.so" ;; *) echo "     FAIL 未链接 libtcl8.6.so"; rc=1 ;; esac
echo
echo "3) Installed library：/usr/lib/libtcl8.6.so —— The Tcl library"
if [ -f /usr/lib/libtcl8.6.so ]; then
  printf '   OK   /usr/lib/libtcl8.6.so（%s 字节，%s，权限 %s）\n' \
    "$(stat -Lc %s /usr/lib/libtcl8.6.so)" "$(file -b /usr/lib/libtcl8.6.so | cut -d, -f1-2)" "$(stat -c %a /usr/lib/libtcl8.6.so)"
else echo "   FAIL /usr/lib/libtcl8.6.so 缺失"; rc=1; fi
echo "   导出符号抽样（Tcl_Main / Tcl_CreateInterp / Tcl_Eval）："
nm_out=$({ nm -D --defined-only /usr/lib/libtcl8.6.so || true; })
for s in Tcl_Main Tcl_CreateInterp Tcl_Eval Tcl_GetVersion; do
  case "$nm_out" in *" T $s"*) echo "     OK   导出 $s" ;; *) echo "     FAIL 未导出 $s"; rc=1 ;; esac
done
echo
echo "4) Installed library：/usr/lib/libtclstub8.6.a —— The Tcl Stub library"
if [ -f /usr/lib/libtclstub8.6.a ]; then
  printf '   OK   /usr/lib/libtclstub8.6.a（%s 字节，%s，权限 %s）\n' \
    "$(stat -Lc %s /usr/lib/libtclstub8.6.a)" "$(file -b /usr/lib/libtclstub8.6.a | cut -d, -f1)" "$(stat -c %a /usr/lib/libtclstub8.6.a)"
  echo "   归档成员：$({ ar t /usr/lib/libtclstub8.6.a || true; } | tr '\n' ' ')"
else echo "   FAIL /usr/lib/libtclstub8.6.a 缺失"; rc=1; fi
echo
echo "5) --disable-rpath 的三重核对之三：已安装的二进制与库中不得有 RPATH/RUNPATH"
for f in /usr/bin/tclsh8.6 /usr/lib/libtcl8.6.so; do
  dyn=$({ readelf -d "$f" || true; })
  echo "   --- $f"
  { printf '%s\n' "$dyn" | grep -E '\((NEEDED|SONAME|RPATH|RUNPATH)\)' || true; } | sed -n '1,12p' | sed 's/^/     /' 
  case "$dyn" in
    *RUNPATH*|*RPATH*) echo "     FAIL 含 RPATH/RUNPATH（--disable-rpath 未生效）"; rc=1 ;;
    *) echo "     OK   无 RPATH/RUNPATH" ;;
  esac
done
echo "   /usr/lib 下 pkgs 共享库的 rpath 抽样："
pkg_sos=$({ find /usr/lib/itcl4.3.4 /usr/lib/tdbc1.1.12 -name '*.so' 2>/dev/null || true; } | sed -n '1,4p')
for f in $pkg_sos; do
  dyn=$({ readelf -d "$f" || true; })
  case "$dyn" in
    *RUNPATH*|*RPATH*) echo "     INFO $f 含 RPATH/RUNPATH（pkgs 由各自的 TEA configure 构建，手册的 --disable-rpath 只作用于 Tcl 本体）" ;;
    *) echo "     OK   $f 无 RPATH/RUNPATH" ;;
  esac
done
echo
echo "6) 手册 Contents 未逐条列出、但由 make install 一并安装的内容："
for f in /usr/lib/tclConfig.sh /usr/lib/tclooConfig.sh /usr/lib/pkgconfig/tcl.pc \
         /usr/include/tcl.h /usr/include/tclDecls.h /usr/include/tclPlatDecls.h \
         /usr/include/tclTomMath.h /usr/include/tclTomMathDecls.h \
         /usr/lib/tcl8.6/init.tcl /usr/share/man/man1/tclsh.1 \
         /usr/share/man/man3/Tcl_Thread.3 /usr/share/man/mann/Tcl.n; do
  if [ -e "$f" ]; then printf '   OK   %-40s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   本节还会装出手册 Contents 未列出的 /usr/bin/sqlite3_analyzer（来自 pkgs/sqlite3.50.4）："
{ ls -l /usr/bin/sqlite3_analyzer 2>&1 || true; } | sed 's/^/     /'
echo "   /usr/lib 下本节安装的目录："
{ ls -d /usr/lib/tcl8.6 /usr/lib/tcl8 /usr/lib/itcl4.3.4 /usr/lib/tdbc1.1.12 \
        /usr/lib/sqlite3.50.4 /usr/lib/thread2.8.12 /usr/lib/tdbcsqlite3-1.1.12 2>/dev/null || true; } | sed 's/^/     /'
echo "   man 页数量：man1=$({ ls /usr/share/man/man1 2>/dev/null | wc -l; })  man3=$({ ls /usr/share/man/man3 2>/dev/null | wc -l; })  mann=$({ ls /usr/share/man/mann 2>/dev/null | wc -l; })"
echo "   （手册给 --mandir=/usr/share/man 的效果：man 页在 /usr/share/man 而非 /usr/man）"
if [ -d /usr/man ]; then echo "   FAIL 出现了 /usr/man（--mandir 未生效）"; rc=1
else echo "   OK   不存在 /usr/man"; fi
echo
echo "7) tclConfig.sh 中不得再有构建目录引用（手册 3 条 sed 的最终效果，装到系统里的那一份）"
leftover=$({ grep -n "/sources/$SRCTOP" /usr/lib/tclConfig.sh || true; })
if [ -z "$leftover" ]; then echo "   OK   /usr/lib/tclConfig.sh 中没有 /sources/$SRCTOP 的引用"
else echo "   FAIL 仍有构建目录引用："; printf '%s\n' "$leftover" | sed 's/^/     /'; rc=1; fi
echo "   关键行："
{ grep -nE '^TCL_(SRC_DIR|LIB_SPEC|INCLUDE_SPEC|STUB_LIB_PATH|PREFIX|EXEC_PREFIX)=' /usr/lib/tclConfig.sh || true; } | sed 's/^/     /'
for f in /usr/lib/tdbc1.1.12/tdbcConfig.sh /usr/lib/itcl4.3.4/itclConfig.sh; do
  if [ -f "$f" ]; then
    lo=$({ grep -c "/sources/$SRCTOP" "$f" || true; })
    if [ "$lo" -eq 0 ]; then echo "   OK   $f 中没有构建目录引用"
    else echo "   FAIL $f 中有 $lo 行构建目录引用"; rc=1; fi
  else echo "   INFO $f 不存在"; fi
done
echo

echo "----- 功能验证（对照手册 §8.17.2 的 Short Descriptions，用已安装的 /usr/bin 程序） -----"
tmpd=$(mktemp -d /tmp/tcl-verify-XXXXXX)
cd "$tmpd"
echo "A. tclsh8.6 —— The Tcl command shell"
cat > a.tcl <<'EOF'
puts "version=$tcl_version patch=$tcl_patchLevel"
puts "expr=[expr {2**64 + 1}]"
puts "string=[string toupper {hello tcl}]"
puts "list=[lsort -integer {10 9 100 1}]"
puts "regexp=[regexp -inline {(\w+)@(\w+)} {mail: user@host end}]"
puts "clock=[clock format 0 -gmt 1 -format {%Y-%m-%d %H:%M:%S}]"
puts "dict=[dict get [dict create a 1 b 2] b]"
set f [open out.txt w]; puts $f "file io works"; close $f
set g [open out.txt r]; puts "fileio=[string trim [read $g]]"; close $g
puts "exec=[exec echo hi from exec]"
puts "encoding=[encoding system]"
puts "zlib=[binary encode hex [zlib compress abc]]"
EOF
set +e
a_out=$(tclsh a.tcl 2>&1)
a_rc=$?
set -e
echo "     tclsh a.tcl 退出码：$a_rc"
printf '%s\n' "$a_out" | sed 's/^/     /'
[ $a_rc -eq 0 ] || { echo "     FAIL tclsh 执行功能脚本失败"; rc=1; }
for kv in "version=8.6 patch=8.6.17" "expr=18446744073709551617" "string=HELLO TCL" \
          "list=1 9 10 100" "regexp=user@host user host" "clock=1970-01-01 00:00:00" \
          "dict=2" "fileio=file io works" "exec=hi from exec"; do
  if printf '%s\n' "$a_out" | grep -Fx "$kv" >/dev/null; then echo "     OK   $kv"
  else echo "     FAIL 期望输出行 '$kv' 未出现"; rc=1; fi
done
case "$a_out" in *"zlib="*) echo "     OK   zlib 子命令可用（Tcl 内建的 zlib 绑定，依赖 §8.6 Zlib）" ;; *) echo "     FAIL zlib 子命令不可用"; rc=1 ;; esac
echo
echo "B. tclsh —— A link to tclsh8.6（用链接名调用行为一致）"
set +e; b1=$(tclsh a.tcl 2>&1); b2=$(tclsh8.6 a.tcl 2>&1); set -e
if [ "$b1" = "$b2" ]; then echo "     OK   tclsh 与 tclsh8.6 对同一脚本输出逐字节一致"
else echo "     FAIL 两者输出不一致"; rc=1; fi
echo "     info nameofexecutable（经 tclsh 调用）：$(echo 'puts [info nameofexecutable]' | tclsh)"
echo
echo "C. libtcl8.6.so —— The Tcl library（脚本库与已安装包能被找到）"
cat > c.tcl <<'EOF'
puts "tcl_library=$tcl_library"
puts "auto_path=$auto_path"
foreach p {Itcl tdbc tdbc::sqlite3 sqlite3 Thread} {
  if {[catch {package require $p} v]} { puts "PKGFAIL $p -> $v" } else { puts "PKGOK $p $v" }
}
EOF
set +e
c_out=$(tclsh c.tcl 2>&1)
c_rc=$?
set -e
echo "     tclsh c.tcl 退出码：$c_rc"
printf '%s\n' "$c_out" | sed 's/^/     /'
[ $c_rc -eq 0 ] || { echo "     FAIL tclsh 执行包加载脚本失败"; rc=1; }
if printf '%s\n' "$c_out" | grep -E '^tcl_library=/usr/lib/tcl8\.6$' >/dev/null; then
  echo "     OK   tcl_library = /usr/lib/tcl8.6（安装到手册指定位置，非构建目录）"
else echo "     FAIL tcl_library 不是 /usr/lib/tcl8.6"; rc=1; fi
n_pkgok=$({ printf '%s\n' "$c_out" | grep -c '^PKGOK ' || true; })
n_pkgfail=$({ printf '%s\n' "$c_out" | grep -c '^PKGFAIL ' || true; })
echo "     可加载的扩展包：$n_pkgok 个；加载失败：$n_pkgfail 个"
if [ "$n_pkgok" -ge 4 ]; then echo "     OK   随 Tcl 一并安装的扩展包可从 /usr/lib 正常加载"
else echo "     FAIL 扩展包加载数量异常"; rc=1; fi
echo
echo "D. libtclstub8.6.a —— The Tcl Stub library（用 C 写一个 stub 扩展并加载）"
cat > ext.c <<'EOF'
#include <tcl.h>
static int AddCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    long a, b;
    if (objc != 3) { Tcl_WrongNumArgs(interp, 1, objv, "a b"); return TCL_ERROR; }
    if (Tcl_GetLongFromObj(interp, objv[1], &a) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetLongFromObj(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
    Tcl_SetObjResult(interp, Tcl_NewLongObj(a + b));
    return TCL_OK;
}
int Demo_Init(Tcl_Interp *interp) {
    if (Tcl_InitStubs(interp, "8.6", 0) == NULL) return TCL_ERROR;
    Tcl_CreateObjCommand(interp, "demo::add", AddCmd, NULL, NULL);
    Tcl_PkgProvide(interp, "demo", "1.0");
    return TCL_OK;
}
EOF
set +e
gcc -fPIC -shared -DUSE_TCL_STUBS -o libdemo.so ext.c -I/usr/include -ltclstub8.6 > ext.err 2>&1
ext_cc=$?
set -e
if [ $ext_cc -eq 0 ]; then
  echo "     OK   用 -ltclstub8.6 编译出扩展 libdemo.so（stub 库可用，且 tcl.h 已正确安装）"
else echo "     FAIL 无法用 stub 库编译扩展："; sed -n '1,10p' ext.err | sed 's/^/       /'; rc=1; fi
echo 'load ./libdemo.so Demo; namespace eval demo {}; puts "demo::add=[demo::add 40 2]"' > d.tcl
set +e
d_out=$(tclsh d.tcl 2>&1)
set -e
echo "     $d_out"
if [ "$d_out" = "demo::add=42" ]; then echo "     OK   stub 扩展被 tclsh 动态加载并正确执行"
else echo "     FAIL stub 扩展执行结果不符"; rc=1; fi
echo
echo "E. 私有头文件（§8.18 Expect 需要 tclInt.h）"
echo "   注意（试建时实测得到、写死在此以免误判）：tclInt.h -> tclPort.h -> tclUnixPort.h"
echo "     里有 #ifdef HAVE_UNISTD_H ... #else #include \"../compat/unistd.h\"，而生成的"
echo "     tclConfig.h 并不随 install-private-headers 安装，所以裸编译 tclInt.h 会去找"
echo "     不存在的 ../compat/unistd.h。使用方（Expect 的 configure）自己会定义"
echo "     HAVE_UNISTD_H，故这里也带上该宏 —— 这是使用方的正常用法，不是缺陷。"
cat > priv.c <<'EOF'
#include <tclInt.h>
#include <stdio.h>
int main(void){ printf("tclInt.h ok, TCL_VERSION=%s\n", TCL_VERSION); return 0; }
EOF
set +e
gcc -o priv priv.c -DHAVE_UNISTD_H=1 -I/usr/include -ltcl8.6 > priv.err 2>&1
priv_cc=$?
set -e
if [ $priv_cc -eq 0 ]; then
  echo "     OK   gcc -DHAVE_UNISTD_H=1 ... -ltcl8.6 编译链接成功：$(./priv)"
else
  echo "     FAIL 私有头文件不可用（§8.18 Expect 将失败）："; sed -n '1,10p' priv.err | sed 's/^/       /'; rc=1
fi
echo
echo "F. 错误路径（诊断信息与非 0 退出码）"
set +e
tclsh /nonexistent-script.tcl > e1.out 2>&1; e1=$?
echo 'error "boom"' > e2.tcl; tclsh e2.tcl > e2.out 2>&1; e2=$?
echo 'exit 3' > e3.tcl; tclsh e3.tcl > e3.out 2>&1; e3=$?
set -e
echo "     脚本不存在   -> 退出码 $e1，诊断：$(sed -n '1p' e1.out)"
echo "     脚本内 error -> 退出码 $e2，诊断：$(sed -n '1p' e2.out)"
echo "     脚本内 exit 3 -> 退出码 $e3"
if [ $e1 -ne 0 ] && [ $e2 -ne 0 ] && [ $e3 -eq 3 ]; then
  echo "     OK   错误返回非 0 并给出诊断；exit N 的退出码被正确传递"
else echo "     FAIL 错误路径行为不符"; rc=1; fi
echo
cd /sources
rm -rf "$tmpd"
echo "8) 本节写入系统的主要文件清单："
{ ls -ld /usr/bin/tclsh /usr/bin/tclsh8.6 \
        /usr/lib/libtcl8.6.so /usr/lib/libtclstub8.6.a /usr/lib/tclConfig.sh \
        /usr/lib/tclooConfig.sh /usr/lib/pkgconfig/tcl.pc /usr/lib/tcl8.6 /usr/lib/tcl8 \
        /usr/include/tcl.h /usr/include/tclInt.h \
        /usr/share/man/man1/tclsh.1 /usr/share/man/man3/Tcl_Thread.3 \
        "/usr/share/doc/tcl-$VER" 2>/dev/null || true; } | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Tcl 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.17.sh"
echo "  移入 \$LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure                完整输出：$CONFLOG"
echo "  make                     完整输出：$MAKELOG"
echo "  LC_ALL=C.UTF-8 make test 完整输出：$TESTLOG"
echo "  make install(+private-headers) 完整输出：$INSTLOG"
cd /sources
rm -rf "$SRCTOP"
if [ -d "/sources/$SRCTOP" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCTOP（其中也包含解包出来的 ./html 文档源）"
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -mindepth 1 -type d || true; } | sed 's/^/  /'
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.17 完成，结束时间：$(date -Is) ====="
