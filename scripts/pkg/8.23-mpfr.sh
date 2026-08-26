#!/usr/bin/env bash
# LFS 13.0-systemd §8.23 MPFR-4.2.2
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.23.1 Installation of MPFR 的命令序列（全部 6 条，一条不多一条不少）：
#   ./configure --prefix=/usr        \
#               --disable-static     \
#               --enable-thread-safe \
#               --docdir=/usr/share/doc/mpfr-4.2.2
#   make
#   make html
#   make check
#   make install
#   make install-html
#
# 本节没有 sed、没有补丁、没有 mkdir build（in-tree build）。
# 本节的提示框只有 1 个：
#   Important（The test suite for MPFR in this section is considered critical.
#     Do not skip it under any circumstances.）—— make check 必跑。
# 手册对结果的量化判据：「Test the results and ensure that all 198 tests passed」。
set -euo pipefail

PKG=mpfr
VER=4.2.2
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
DOCDIR=/usr/share/doc/mpfr-$VER
CONFLOG=/sources/.mpfr-configure.log
MAKELOG=/sources/.mpfr-make.log
HTMLLOG=/sources/.mpfr-make-html.log
CHECKLOG=/sources/.mpfr-make-check.log
INSTLOG=/sources/.mpfr-make-install.log
INSTHTMLLOG=/sources/.mpfr-make-install-html.log
SUMLOG=/sources/.mpfr-test-summary.log

echo "===== LFS 13.0-systemd §8.23 MPFR-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The MPFR package contains functions for multiple precision math."
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 43 MB"
echo
echo "----- chroot 环境自述（手册 §7.4） -----"
echo "PATH      : $PATH"
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
echo "1) 上一任务 §8.22 GMP-6.3.0 的产物 —— MPFR 是 GMP 的直接使用者，"
echo "   configure 会做 'checking for GMP library vs header correctness'，装不全必然失败："
for f in /usr/include/gmp.h /usr/include/gmpxx.h /usr/lib/libgmp.so /usr/lib/libgmpxx.so \
         /usr/lib/pkgconfig/gmp.pc /usr/lib/pkgconfig/gmpxx.pc; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.22 未完成？）\n' "$f"; rc=1; fi
done
echo "   libgmp 实体与 SONAME："
for so in $({ ls /usr/lib/libgmp.so.*.*.* 2>/dev/null || true; }); do
  printf '     %-24s SONAME=%s\n' "$(basename "$so")" \
    "$(readelf -d "$so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')"
done
echo "   已装 gmp.h 自述版本："
{ grep -E '^#define __GNU_MP_VERSION' /usr/include/gmp.h || true; } | sed 's/^/     /'
g_major=$(sed -n 's/^#define __GNU_MP_VERSION  *//p' /usr/include/gmp.h | sed -n 1p)
g_minor=$(sed -n 's/^#define __GNU_MP_VERSION_MINOR  *//p' /usr/include/gmp.h | sed -n 1p)
g_patch=$(sed -n 's/^#define __GNU_MP_VERSION_PATCHLEVEL  *//p' /usr/include/gmp.h | sed -n 1p)
if [ "$g_major.$g_minor.$g_patch" = "6.3.0" ]; then
  echo "     OK   GMP 头文件版本 $g_major.$g_minor.$g_patch = §8.22 的 6.3.0"
else
  echo "     FAIL GMP 头文件版本 $g_major.$g_minor.$g_patch 与 §8.22 的 6.3.0 不符"; rc=1
fi
echo "   用已装 GMP 编译并运行一个最小程序（MPFR configure 的等价前置探测）："
tmpg=$(mktemp /tmp/gmp-pre-XXXXXX.c)
cat > "$tmpg" <<'EOF'
#include <stdio.h>
#include <gmp.h>
int main(void){ mpz_t t; mpz_init_set_ui(t,7); gmp_printf("gmp ok %Zd %s\n", t, gmp_version); mpz_clear(t); return 0; }
EOF
if gcc -o "${tmpg%.c}" "$tmpg" -lgmp >/dev/null 2>&1; then
  echo "     $("${tmpg%.c}")"
  echo "     OK   默认搜索路径下可 #include <gmp.h> 并 -lgmp 链接运行"
else
  echo "     FAIL 无法用已装 GMP 编译/链接（MPFR 的 configure 必然失败）"; rc=1
fi
rm -f "$tmpg" "${tmpg%.c}"
echo
echo "2) C 库与编译器（本节只编 C，不需要 C++）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2 /usr/include/stdio.h; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("c sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && [ "$("${tmpc%.c}")" = "c sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo
echo "3) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "4) 本节直接依赖的外部命令（开工前一次性 command -v 过一遍 —— 第 8 章的 chroot"
echo "   是半成品系统，宿主机上顺手就有的命令不一定存在）："
for t in tar xz make gcc ld as ar ranlib sed grep awk tee install ln rm mkdir \
         cmp diff md5sum readelf objdump ldd find stat bash sort head tail \
         makeinfo texi2any perl file du df pkg-config env tr wc cat cp mktemp date; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-11s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   makeinfo 版本：$(makeinfo --version 2>&1 | sed -n 1p)"
echo "   说明：手册命令 3/6 的 make html 由 doc/Makefile 调用 makeinfo --html 生成，"
echo "     命令 6/6 的 make install-html 再把它装进 --docdir 指定的目录，"
echo "     故 §7.11 Texinfo 的 makeinfo 是本节的硬依赖。"
echo "   make 版本：$(make --version | sed -n 1p)"
echo
echo "5) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then
  echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "   本节无补丁（手册 §8.23 未引用任何 patch）；/sources 中匹配 mpfr*patch 的文件："
mpfr_patches=$({ ls /sources 2>/dev/null | grep -E '^mpfr.*patch' || true; })
echo "     ${mpfr_patches:-无}"
echo
echo "6) §7.3 虚拟内核文件系统与 §7.6 基础文件（198 个测试程序要读写 /dev、/proc、/tmp）："
for f in /dev/null /dev/zero /dev/full /dev/urandom /dev/tty /proc/self /sys \
         /etc/passwd /etc/group /tmp /var/tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "7) 安装目标目录与安装前的 MPFR 痕迹（MPFR 是第一次装进本系统）："
for d in /usr/lib /usr/include /usr/lib/pkgconfig /usr/share/info /usr/share/doc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
pre=$({ ls -d /usr/lib/libmpfr* /usr/include/mpfr.h /usr/include/mpf2mpfr.h \
        /usr/lib/pkgconfig/mpfr.pc "$DOCDIR" 2>/dev/null || true; })
if [ -z "$pre" ]; then
  echo "   INFO 系统中当前没有任何 MPFR 文件 —— 符合预期：第 5/6 章的 GCC 是把 gmp/mpfr/mpc"
  echo "     解包进 gcc 源码树内联构建的，从未把 MPFR 装进 \$LFS，本节是首次安装。"
else
  echo "   INFO 安装前已存在的 MPFR 相关文件（本节会覆盖）："; echo "$pre" | sed 's/^/     /'
fi
echo
echo "8) 磁盘空间（手册要求 43 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 204800 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 43 MB"
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
echo "手册 §8.23 全节没有 mkdir build —— MPFR 在源码目录内直接 configure（in-tree build）。"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
echo "上游版本自述："
conf_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'\$/\1/p" configure | sed -n 1p)
conf_str=$(sed -n "s/^PACKAGE_STRING='\(.*\)'\$/\1/p" configure | sed -n 1p)
echo "  configure ：PACKAGE_VERSION=$conf_ver  PACKAGE_STRING='$conf_str'"
echo "  VERSION 文件：$(cat VERSION 2>/dev/null)"
echo "  src/mpfr.h 中的版本宏："
{ grep -nE '^#define MPFR_VERSION_(MAJOR|MINOR|PATCHLEVEL|STRING)' src/mpfr.h || true; } | sed 's/^/    /'
if [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $conf_ver 与手册 §8.23 的 MPFR-$VER 一致"
else echo "  FAIL 源码自述版本为 '$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo
echo "----- 本包的两个结构性事实（开工前已在 chroot /tmp 的完整试建中确认，写在这里"
echo "      是为了让下面的核对方式有据可依） -----"
echo "  a) MPFR 不使用 config.h —— configure.ac 第 93 行的 AC_CONFIG_HEADERS 被 dnl 注释掉了："
{ grep -nE 'AC_CONFIG_HEADERS' configure.ac || true; } | sed 's/^/       /'
echo "     所以 --enable-thread-safe 之类选项的结果不在任何 config.h 里，而是以 -D 形式"
echo "     进入生成的 Makefile 的 DEFS 变量。核对点必须落在 DEFS 上，不能去找 config.h。"
echo "  b) 共享库版本号来自 src/Makefile.am 的 libtool -version-info，而非包版本号："
{ grep -nE 'version-info' src/Makefile.am || true; } | sed 's/^/       /'
echo "     -version-info 8:2:2 → SONAME 主版本 = CURRENT-AGE = 8-2 = 6，"
echo "     实体文件名 libmpfr.so.6.2.2。别按 4.2.2 猜。"
echo
echo "----- 测试结构预读（决定 make check 的判定标准） -----"
echo "tests/Makefile.am 的测试声明（automake parallel-tests 框架）："
{ grep -nE '^(TESTS|check_PROGRAMS|TESTS_ENVIRONMENT) = ' tests/Makefile.am || true; } | sed 's/^/  /'
echo "tests 目录下的 .c 文件数：$(ls tests/*.c 2>/dev/null | wc -l)"
echo "手册给出的量化判据："
echo "  「Test the results and ensure that all 198 tests passed:  make check」"
echo "判定标准（本脚本采用，先手册后自加，全部要满足）："
echo "  硬判据 1（手册 Important：测试 critical，不得跳过）：make check 必须真的跑完，"
echo "    且退出码为 0 —— 手册 §8.23 没有给出任何允许失败的例外说明；"
echo "  硬判据 2（手册）：automake 汇总块 # TOTAL: 198；"
echo "  硬判据 3（手册「all 198 tests passed」）：# PASS: 198；"
echo "  硬判据 4（自加，与 2/3 一致性互校）：FAIL=0、XPASS=0、ERROR=0，且"
echo "    PASS+SKIP+XFAIL+FAIL+XPASS+ERROR = TOTAL。"
echo

echo "================= 8.23.1. Installation of MPFR ================="
echo
echo "----- 手册命令 1/6：configure -----"
echo "手册原文：Prepare MPFR for compilation:"
echo "手册命令：./configure --prefix=/usr        \\"
echo "                     --disable-static     \\"
echo "                     --enable-thread-safe \\"
echo "                     --docdir=/usr/share/doc/mpfr-$VER"
echo "手册对本节未单独解释选项（--disable-static 与 --docdir 的含义见 §8.22 GMP 一节，"
echo "  --enable-thread-safe 见 MPFR 自己的 INSTALL：build MPFR as thread safe, i.e."
echo "  with TLS support）。"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-$VER > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 60 行："; tail -n 60 "$CONFLOG" | sed 's/^/  /'
  [ -f config.log ] && { echo "config.log 末尾 60 行："; tail -n 60 config.log | sed 's/^/  /'; }
  exit $conf_rc
fi
echo "configure 对 GMP 的探测（MPFR 的核心前置）："
{ grep -inE 'gmp' "$CONFLOG" || true; } | sed -n '1,20p' | sed 's/^/  /'
echo "configure 对 TLS / thread 的探测（--enable-thread-safe 的直接结论）："
{ grep -inE 'thread|tls' "$CONFLOG" || true; } | sed 's/^/  /'
echo "configure 生成的文件（config.status: creating 行，用于确认落点）："
{ grep -n 'config.status: creating' "$CONFLOG" || true; } | sed 's/^/  /'
echo "configure 末尾 20 行："
tail -n 20 "$CONFLOG" | sed 's/^/  /'
echo
echo "----- 核对手册给的 4 个选项确实生效（三重核对：configure 结论 + 生成 Makefile + 后面的 ldd/运行期） -----"
crc=0
echo "0) 选项一个不多一个不少：config.status 里的 ac_cs_config"
cs=$(sed -n "s/^ac_cs_config='\(.*\)'\$/\1/p" config.status | sed -n 1p)
echo "     ac_cs_config = $cs"
exp_cs="--prefix=/usr --disable-static --enable-thread-safe --docdir=$DOCDIR"
if [ "$cs" = "$exp_cs" ]; then echo "     OK   与手册命令逐字一致（4 个选项，无多余、无遗漏）"
else echo "     FAIL 期望 '$exp_cs'"; crc=1; fi
echo "a) --prefix=/usr"
{ grep -E '^(prefix|exec_prefix|libdir|includedir|infodir|docdir|datarootdir) = ' Makefile || true; } | sed 's/^/     /'
got_prefix=$(sed -n 's/^prefix = //p' Makefile | sed -n 1p)
if [ "$got_prefix" = /usr ]; then echo "     OK   prefix = /usr"
else echo "     FAIL prefix 为 '$got_prefix'，不是 /usr"; crc=1; fi
echo "b) --docdir=$DOCDIR"
got_docdir=$(sed -n 's/^docdir = //p' Makefile | sed -n 1p)
if [ "$got_docdir" = "$DOCDIR" ]; then echo "     OK   docdir = $got_docdir"
else echo "     FAIL docdir 为 '$got_docdir'，不是 $DOCDIR"; crc=1; fi
echo "c) --disable-static"
echo "     生成的 libtool 里 build_old_libs / build_libtool_libs 的全部出现位置："
{ grep -nE '^(build_old_libs|build_libtool_libs)=' libtool || true; } | sed 's/^/       /'
echo "     （该文件里这两个变量各出现多次：靠后的是另一段的默认值与 case 重算，"
echo "       本次配置的结论是**第一处**，与 §8.20/§8.22 的判据一致。）"
old_libs=$(sed -n 's/^build_old_libs=//p' libtool | sed -n 1p)
new_libs=$(sed -n 's/^build_libtool_libs=//p' libtool | sed -n 1p)
if [ "$old_libs" = "no" ]; then echo "     OK   build_old_libs=no（不构建 .a 静态库）"
else echo "     FAIL build_old_libs='$old_libs'，--disable-static 未生效"; crc=1; fi
if [ "$new_libs" = "yes" ]; then echo "     OK   build_libtool_libs=yes（构建共享库）"
else echo "     FAIL build_libtool_libs='$new_libs'"; crc=1; fi
echo "d) --enable-thread-safe"
echo "     核对点 1：configure 的探测结论"
tls_line=$({ grep -iE 'checking for TLS support' "$CONFLOG" || true; })
echo "       ${tls_line:-（未找到 TLS 探测行）}"
case "$tls_line" in
  *yes) echo "       OK   configure 探到 TLS 支持" ;;
  *) echo "       FAIL configure 未探到 TLS 支持"; crc=1 ;;
esac
echo "     核对点 2：生成的 src/Makefile 的 DEFS 中的 MPFR_USE_THREAD_SAFE"
defs=$(sed -n 's/^DEFS = //p' src/Makefile | sed -n 1p)
echo "       DEFS 中与 THREAD 相关的项："
echo "$defs" | tr ' ' '\n' | { grep -E 'THREAD' || true; } | sed 's/^/         /'
case " $defs " in
  *" -DMPFR_USE_THREAD_SAFE=1 "*) echo "       OK   -DMPFR_USE_THREAD_SAFE=1 已在 DEFS 中" ;;
  *) echo "       FAIL DEFS 中没有 -DMPFR_USE_THREAD_SAFE=1"; crc=1 ;;
esac
case " $defs " in
  *" -DMPFR_USE_C11_THREAD_SAFE=1 "*) echo "       OK   -DMPFR_USE_C11_THREAD_SAFE=1 已在 DEFS 中（用 C11 的 _Thread_local 实现）" ;;
  *) echo "       INFO DEFS 中无 -DMPFR_USE_C11_THREAD_SAFE=1（可能改用 __thread 实现，不算失败）" ;;
esac
echo "     核对点 3：运行期 mpfr_buildopt_tls_p() —— 放在安装后的功能验证里做。"
echo "e) 生成的 mpfr.pc 与各子目录 Makefile"
if [ -f mpfr.pc ]; then echo "     OK   mpfr.pc 已生成"; sed 's/^/       /' mpfr.pc
else echo "     FAIL mpfr.pc 未生成"; crc=1; fi
for d in src tests doc tune; do
  if [ -f "$d/Makefile" ]; then printf '     OK   %s/Makefile\n' "$d"
  else printf '     FAIL %s/Makefile 未生成\n' "$d"; crc=1; fi
done
echo "     （本包无 config.h —— 见上面的结构性事实 a，故此处不查 config.h。）"
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册 §8.23 的 4 个选项"
echo

echo "----- 手册命令 2/6：make -----"
echo "手册原文：Compile the package and generate the HTML documentation:"
echo "手册命令：make"
echo "完整输出写入 $MAKELOG，下面只摘要。"
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "make 退出码：$make_rc（输出 $(wc -l < "$MAKELOG") 行）"
if [ $make_rc -ne 0 ]; then
  echo "make 失败，末尾 60 行："; tail -n 60 "$MAKELOG" | sed 's/^/  /'
  exit $make_rc
fi
echo "make 输出末尾 10 行："
tail -n 10 "$MAKELOG" | sed 's/^/  /'
echo
echo "----- 编译结果确认 -----"
mrc=0
echo "  libtool 归档与 .libs 下的共享库实体："
{ ls -l src/libmpfr.la 2>/dev/null || true; } | sed 's/^/    /'
{ ls -l src/.libs/libmpfr.so src/.libs/libmpfr.so.6 src/.libs/libmpfr.so.6.* 2>/dev/null || true; } | sed 's/^/    /'
if [ -f src/libmpfr.la ]; then echo "    OK   src/libmpfr.la"
else echo "    FAIL src/libmpfr.la 未生成"; mrc=1; fi
mpfr_so=$({ ls src/.libs/libmpfr.so.*.*.* 2>/dev/null || true; } | sed -n 1p)
if [ -n "$mpfr_so" ]; then
  printf '    OK   %s（%s 字节，%s）\n' "$mpfr_so" "$(stat -Lc %s "$mpfr_so")" "$(file -b "$mpfr_so" | cut -d, -f1-2)"
  soname=$(readelf -d "$mpfr_so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')
  echo "    SONAME=$soname"
  if [ "$soname" = "libmpfr.so.6" ]; then
    echo "    OK   SONAME 为 libmpfr.so.6（= -version-info 8:2:2 的 CURRENT-AGE = 6）"
  else echo "    FAIL SONAME 为 '$soname'，期望 libmpfr.so.6"; mrc=1; fi
  if [ "$(basename "$mpfr_so")" = "libmpfr.so.6.2.2" ]; then
    echo "    OK   实体文件名 libmpfr.so.6.2.2"
  else echo "    FAIL 实体文件名为 $(basename "$mpfr_so")，期望 libmpfr.so.6.2.2"; mrc=1; fi
else echo "    FAIL 未生成 src/.libs/libmpfr.so.*"; mrc=1; fi
echo "  --disable-static 的验证：构建目录内不应有 libmpfr.a"
stat_a=$({ ls src/.libs/*.a 2>/dev/null || true; })
if [ -z "$stat_a" ]; then echo "    OK   构建目录内无静态库"
else echo "    FAIL 生成了静态库：$stat_a"; mrc=1; fi
echo "  构建产物的动态依赖（应含 libgmp.so.10，且不含任何 /tools 路径）："
dep=$({ ldd "$mpfr_so" || true; })
echo "$dep" | sed 's/^/    /'
case "$dep" in
  *libgmp.so.10*) echo "    OK   链接到 §8.22 装的 libgmp.so.10" ;;
  *) echo "    FAIL 未链接 libgmp.so.10"; mrc=1 ;;
esac
case "$dep" in
  */tools/*) echo "    FAIL 仍链接 /tools 下的库"; mrc=1 ;;
  *) echo "    OK   未链接任何 /tools 路径" ;;
esac
echo "  未安装产物的冒烟测试（直接链接构建目录里的 libmpfr）："
tmpd=$(mktemp -d /tmp/mpfr-build-smoke-XXXXXX)
cat > "$tmpd/s.c" <<'EOF'
#include <stdio.h>
#include <mpfr.h>
int main(void){
  mpfr_t x; mpfr_init2(x, 200);
  mpfr_const_pi(x, MPFR_RNDN);
  mpfr_printf("pi=%.20Rf\n", x);
  printf("version=%s\n", mpfr_get_version());
  mpfr_clear(x); mpfr_free_cache();
  return 0;
}
EOF
if gcc -o "$tmpd/s" "$tmpd/s.c" -Isrc -Lsrc/.libs -lmpfr -lgmp > "$tmpd/cc.log" 2>&1; then
  smoke=$(LD_LIBRARY_PATH=$PWD/src/.libs "$tmpd/s" 2>&1)
  echo "$smoke" | sed 's/^/    /'
  case "$smoke" in
    *"pi=3.14159265358979323846"*) echo "    OK   pi 前 20 位小数正确" ;;
    *) echo "    FAIL pi 前 20 位小数不正确"; mrc=1 ;;
  esac
  case "$smoke" in
    *"version=$VER"*) echo "    OK   构建产物自述版本 $VER" ;;
    *) echo "    FAIL 构建产物自述版本不是 $VER"; mrc=1 ;;
  esac
else
  echo "    FAIL 无法链接构建目录里的 libmpfr："; sed 's/^/      /' "$tmpd/cc.log"; mrc=1
fi
rm -rf "$tmpd"
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 3/6：make html -----"
echo "手册原文（与上一条同一句）：Compile the package and generate the HTML documentation:"
echo "手册命令：make html"
echo "完整输出写入 $HTMLLOG，下面只摘要。"
set +e
make html > "$HTMLLOG" 2>&1
html_rc=$?
set -e
echo "make html 退出码：$html_rc（输出 $(wc -l < "$HTMLLOG") 行）"
if [ $html_rc -ne 0 ]; then
  echo "make html 失败，末尾 60 行："; tail -n 60 "$HTMLLOG" | sed 's/^/  /'
  exit $html_rc
fi
echo "make html 输出："
sed -n '1,40p' "$HTMLLOG" | sed 's/^/  /'
echo "生成的 HTML 文档（doc/ 下）："
{ ls -ld doc/mpfr.html 2>/dev/null || true; } | sed 's/^/  /'
hrc=0
if [ -d doc/mpfr.html ]; then
  echo "  OK   doc/mpfr.html/ 是按节点拆分的目录，共 $(ls doc/mpfr.html | wc -l) 个文件"
  echo "  前 10 个文件："; { ls doc/mpfr.html || true; } | sed -n '1,10p' | sed 's/^/    /'
  if [ -f doc/mpfr.html/index.html ]; then echo "  OK   doc/mpfr.html/index.html 存在"
  else echo "  FAIL doc/mpfr.html/index.html 缺失"; hrc=1; fi
elif [ -f doc/mpfr.html ]; then
  echo "  OK   doc/mpfr.html 是单文件（$(stat -Lc %s doc/mpfr.html) 字节）"
else
  echo "  FAIL 未生成 doc/mpfr.html"; hrc=1
fi
echo "  info 文档（doc/mpfr.info —— 本包的 tarball 里自带预生成版本，make install 会安装它）："
if [ -f doc/mpfr.info ]; then echo "    OK   doc/mpfr.info（$(stat -Lc %s doc/mpfr.info) 字节）"
else echo "    INFO doc/mpfr.info 不在 doc/ 下，查找："; { find . -name 'mpfr.info*' || true; } | sed -n '1,5p' | sed 's/^/      /'; fi
[ $hrc -eq 0 ] || { echo "错误：make html 未产出预期文档" >&2; exit 1; }
echo

echo "----- 手册命令 4/6：make check（本节的测试） -----"
echo "手册 Important 原文：The test suite for MPFR in this section is considered critical."
echo "  Do not skip it under any circumstances."
echo "手册原文：Test the results and ensure that all 198 tests passed:"
echo "手册命令：make check"
echo "（手册这条**不带** tee —— 与 §8.22 GMP 不同，本节按原样直接执行；"
echo "  完整输出另存到 $CHECKLOG 供留档。）"
set +e
make check > "$CHECKLOG" 2>&1
check_rc=$?
set -e
echo "make check 退出码：$check_rc（输出 $(wc -l < "$CHECKLOG") 行）"
echo
echo "----- make check 结论 -----"
echo "automake 汇总块（Testsuite summary）原文："
{ grep -nE '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary|=====)' "$CHECKLOG" || true; } \
  | sed 's/^/  /'
echo
sum_of() { awk -v k="$1" '$0 ~ "^# "k": " {s += $3} END {print s+0}' "$CHECKLOG"; }
t_total=$(sum_of TOTAL); t_pass=$(sum_of PASS);   t_fail=$(sum_of FAIL)
t_skip=$(sum_of SKIP);   t_xfail=$(sum_of XFAIL); t_xpass=$(sum_of XPASS)
t_err=$(sum_of ERROR)
echo "汇总合计："
printf '  TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
  "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
echo "非 PASS 的逐项结果（FAIL/XFAIL/XPASS/ERROR/SKIP）："
nonpass=$({ grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; })
if [ -n "$nonpass" ]; then echo "$nonpass" | sed 's/^/  /'; else echo "  （无）"; fi
echo "PASS 行条数（逐项，供与 '# PASS:' 互校）：$({ grep -cE '^PASS: ' "$CHECKLOG" || true; })"
echo
echo "测试套件自报的构建选项（tests/tversion，198 个测试中的第 1 个）："
{ grep -E '^\[tversion\]' "$CHECKLOG" || true; } | sed -n '1,30p' | sed 's/^/  /'
tvers_tls=$({ grep -E '^\[tversion\] TLS = ' "$CHECKLOG" || true; } | sed -n 1p)
if [ -n "$tvers_tls" ]; then
  echo "  --enable-thread-safe 的第三重核对（测试套件自己的报告）：$tvers_tls"
fi
echo
{
  echo "===== §8.23 MPFR-$VER 测试汇总 ====="
  echo "手册命令：make check"
  echo "手册判据：Test the results and ensure that all 198 tests passed."
  echo "make check 退出码：$check_rc"
  printf 'TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
    "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
  echo "----- 非 PASS 项 -----"
  { grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; }
  echo "----- 汇总块 -----"
  { grep -E '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary)' "$CHECKLOG" || true; }
  echo "----- tversion 报告的构建选项 -----"
  { grep -E '^\[tversion\]' "$CHECKLOG" || true; }
} > "$SUMLOG"
trc=0
echo "判据核对："
if [ "$check_rc" -eq 0 ]; then
  echo "  OK   硬判据 1（手册 Important）：make check 完整跑完且退出码 0"
else
  echo "  FAIL 硬判据 1：make check 退出码 $check_rc"; trc=1
fi
if [ "$t_total" = 198 ]; then
  echo "  OK   硬判据 2（手册）：TOTAL = 198"
else
  echo "  FAIL 硬判据 2（手册）：TOTAL = $t_total，手册说本节共 198 个测试"; trc=1
fi
if [ "$t_pass" = 198 ]; then
  echo "  OK   硬判据 3（手册「all 198 tests passed」）：PASS = 198"
else
  echo "  FAIL 硬判据 3（手册）：PASS = $t_pass，手册要求 198 个全过"; trc=1
fi
if [ "$t_fail" = 0 ] && [ "$t_err" = 0 ] && [ "$t_xpass" = 0 ]; then
  echo "  OK   硬判据 4（自加）：FAIL=0、XPASS=0、ERROR=0"
else
  echo "  FAIL 硬判据 4（自加）：FAIL=$t_fail XPASS=$t_xpass ERROR=$t_err"; trc=1
fi
if [ "$t_total" -gt 0 ] && [ "$((t_pass + t_skip + t_xfail + t_fail + t_xpass + t_err))" = "$t_total" ]; then
  echo "  OK   汇总自洽：PASS+SKIP+XFAIL+FAIL+XPASS+ERROR = TOTAL($t_total)"
else
  echo "  FAIL 汇总不自洽：各项之和 != TOTAL($t_total)"; trc=1
fi
if [ $trc -ne 0 ]; then
  echo "错误：测试结果不符合手册要求；完整输出见 $CHECKLOG" >&2
  echo "  make check 末尾 80 行：" >&2
  tail -n 80 "$CHECKLOG" | sed 's/^/  /' >&2
  exit 1
fi
echo
echo "测试结论：手册 §8.23 的 Important 要求本节测试必跑，本次已完整跑完 make check。"
echo "  手册量化判据「all 198 tests passed」：TOTAL=$t_total、PASS=$t_pass —— 全过；"
echo "  FAIL=0、XPASS=0、ERROR=0、SKIP=$t_skip、XFAIL=$t_xfail。"
echo

echo "----- 手册命令 5/6：make install -----"
echo "手册原文：Install the package and its documentation:"
echo "手册命令：make install"
echo "完整输出写入 $INSTLOG，下面只摘要。"
set +e
make install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "make install 退出码：$inst_rc（输出 $(wc -l < "$INSTLOG") 行）"
if [ $inst_rc -ne 0 ]; then
  echo "make install 失败，末尾 60 行："; tail -n 60 "$INSTLOG" | sed 's/^/  /'
  exit $inst_rc
fi
echo "安装到系统的条目（摘自 install 日志）："
{ grep -oE '/usr/(bin|share|lib|include)[^ "'"'"']*' "$INSTLOG" || true; } | sort -u | sed 's/^/  /'
echo

echo "----- 手册命令 6/6：make install-html -----"
echo "手册原文（与上一条同一句）：Install the package and its documentation:"
echo "手册命令：make install-html"
echo "完整输出写入 $INSTHTMLLOG，下面只摘要。"
set +e
make install-html > "$INSTHTMLLOG" 2>&1
insth_rc=$?
set -e
echo "make install-html 退出码：$insth_rc（输出 $(wc -l < "$INSTHTMLLOG") 行）"
if [ $insth_rc -ne 0 ]; then
  echo "make install-html 失败，末尾 60 行："; tail -n 60 "$INSTHTMLLOG" | sed 's/^/  /'
  exit $insth_rc
fi
echo "make install-html 输出（前 40 行）："
sed -n '1,40p' "$INSTHTMLLOG" | sed 's/^/  /'
echo

echo "----- 安装后检查（手册 §8.23.2 Contents of MPFR） -----"
echo "手册列出的内容："
echo "  Installed library : libmpfr.so"
echo "  Installed directory: /usr/share/doc/mpfr-$VER"
echo "  libmpfr —— Contains multiple-precision math functions"
rc=0
echo
echo "1) Installed library（手册明确列出的唯一一个）："
if [ -L /usr/lib/libmpfr.so ]; then
  echo "   OK   /usr/lib/libmpfr.so -> $(readlink /usr/lib/libmpfr.so)"
elif [ -e /usr/lib/libmpfr.so ]; then
  echo "   OK   /usr/lib/libmpfr.so（普通文件，$(stat -Lc %s /usr/lib/libmpfr.so) 字节）"
else
  echo "   FAIL /usr/lib/libmpfr.so 缺失"; rc=1
fi
echo "   /usr/lib 下全部 MPFR 库文件（通配符写成不重叠的，避免同一批文件列两遍）："
{ ls -l /usr/lib/libmpfr.la /usr/lib/libmpfr.so /usr/lib/libmpfr.so.6 /usr/lib/libmpfr.so.6.* 2>/dev/null || true; } | sed 's/^/     /'
inst_so=/usr/lib/libmpfr.so.6.2.2
if [ -f "$inst_so" ]; then
  printf '   OK   %s（%s 字节，%s）\n' "$inst_so" "$(stat -Lc %s "$inst_so")" "$(file -b "$inst_so" | cut -d, -f1-2)"
  isoname=$(readelf -d "$inst_so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')
  if [ "$isoname" = "libmpfr.so.6" ]; then echo "   OK   SONAME=libmpfr.so.6"
  else echo "   FAIL SONAME='$isoname'，期望 libmpfr.so.6"; rc=1; fi
else
  echo "   FAIL $inst_so 缺失"; rc=1
fi
if [ -L /usr/lib/libmpfr.so.6 ]; then
  echo "   OK   /usr/lib/libmpfr.so.6 -> $(readlink /usr/lib/libmpfr.so.6)（SONAME 链接）"
else echo "   FAIL /usr/lib/libmpfr.so.6 不是符号链接"; rc=1; fi
echo
echo "2) --disable-static 的验证：/usr/lib 下不应出现 libmpfr.a"
stale=$({ ls /usr/lib/libmpfr.a 2>/dev/null || true; })
if [ -z "$stale" ]; then echo "   OK   未安装 MPFR 静态库"
else echo "   FAIL 存在静态库：$stale"; rc=1; fi
echo "   libtool 归档（.la，LFS 未要求删除，仅记录）："
if [ -f /usr/lib/libmpfr.la ]; then
  { grep -E '^(dlname|library_names|old_library)=' /usr/lib/libmpfr.la || true; } | sed 's/^/     /'
  la_old=$(sed -n "s/^old_library='\(.*\)'\$/\1/p" /usr/lib/libmpfr.la | sed -n 1p)
  if [ -z "$la_old" ]; then echo "     OK   .la 里 old_library='' （与 --disable-static 一致）"
  else echo "     FAIL .la 里 old_library='$la_old'"; rc=1; fi
else
  echo "     （无 .la）"
fi
echo
echo "3) 头文件（手册 Contents 未单列，但 make install 会装，后续 §8.24 MPC 依赖 mpfr.h）："
for f in /usr/include/mpfr.h /usr/include/mpf2mpfr.h; do
  if [ -f "$f" ]; then printf '   OK   %-28s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   已安装 mpfr.h 的版本宏："
{ grep -E '^#define MPFR_VERSION_(MAJOR|MINOR|PATCHLEVEL|STRING)' /usr/include/mpfr.h || true; } | sed 's/^/     /'
i_str=$(sed -n 's/^#define MPFR_VERSION_STRING *"\(.*\)"$/\1/p' /usr/include/mpfr.h | sed -n 1p)
if [ "$i_str" = "$VER" ]; then echo "     OK   已安装 mpfr.h 自述版本 $i_str = $VER"
else echo "     FAIL 已安装 mpfr.h 自述版本 '$i_str' 与 $VER 不符"; rc=1; fi
echo
echo "4) pkg-config 文件（mpfr.pc.in → mpfr.pc，由 make install 安装）："
if [ -f /usr/lib/pkgconfig/mpfr.pc ]; then
  echo "   OK   /usr/lib/pkgconfig/mpfr.pc"; sed 's/^/     /' /usr/lib/pkgconfig/mpfr.pc
else echo "   FAIL /usr/lib/pkgconfig/mpfr.pc 缺失"; rc=1; fi
echo "   用 §8.20 的 pkgconf 查询（验证 .pc 可被解析）："
if command -v pkg-config >/dev/null 2>&1 || command -v pkgconf >/dev/null 2>&1; then
  pc=$(command -v pkg-config 2>/dev/null || command -v pkgconf)
  echo "     $pc --modversion mpfr : $("$pc" --modversion mpfr 2>&1)"
  echo "     $pc --libs mpfr       : $("$pc" --libs mpfr 2>&1)"
  echo "     $pc --cflags mpfr     : $("$pc" --cflags mpfr 2>&1)"
  pcver=$("$pc" --modversion mpfr 2>/dev/null || true)
  if [ "$pcver" = "$VER" ]; then echo "     OK   pkg-config 报告的 mpfr 版本 = $VER"
  else echo "     FAIL pkg-config 报告的 mpfr 版本 '$pcver' 与 $VER 不符"; rc=1; fi
else
  echo "     INFO 系统中无 pkg-config/pkgconf，跳过"
fi
echo
echo "5) Installed directory：$DOCDIR（手册 Contents 明确列出）"
if [ -d "$DOCDIR" ]; then
  echo "   OK   $DOCDIR 存在"
  echo "   目录内容（顶层）："; { ls -l "$DOCDIR" || true; } | sed 's/^/     /'
  nfile=$(find "$DOCDIR" -type f | wc -l)
  echo "   目录内文件总数：$nfile；占用：$(du -sh "$DOCDIR" | cut -f1)"
  if [ "$nfile" -gt 0 ]; then echo "   OK   文档目录非空"
  else echo "   FAIL 文档目录为空"; rc=1; fi
  if [ -f "$DOCDIR/mpfr.html/index.html" ]; then
    echo "   OK   $DOCDIR/mpfr.html/index.html 存在（make install-html 的产物，"
    echo "        共 $(find "$DOCDIR/mpfr.html" -type f | wc -l) 个 HTML 文件）"
    echo "   入口文件首行：$(sed -n 1p "$DOCDIR/mpfr.html/index.html")"
    echo "   入口文件中出现的 MPFR 版本串："
    { grep -oE 'MPFR [0-9]+\.[0-9]+\.[0-9]+' "$DOCDIR/mpfr.html/index.html" || true; } | sed -n '1,3p' | sed 's/^/     /'
  else
    echo "   FAIL $DOCDIR/mpfr.html/index.html 缺失（make install-html 未生效）"; rc=1
  fi
  echo "   随包文档（make install 装入，非 install-html 产物）："
  for f in AUTHORS BUGS COPYING COPYING.LESSER NEWS TODO FAQ.html; do
    if [ -f "$DOCDIR/$f" ]; then printf '     OK   %s\n' "$f"
    else printf '     INFO %s 不在文档目录\n' "$f"; fi
  done
  echo "   examples 子目录：$(find "$DOCDIR/examples" -type f 2>/dev/null | wc -l) 个文件"
else
  echo "   FAIL $DOCDIR 不存在"; rc=1
fi
echo
echo "6) info 文档（doc/Makefile.am 的 info_TEXINFOS = mpfr.texi）："
if [ -e /usr/share/info/mpfr.info ]; then
  printf '   OK   %-30s（%s 字节）\n' /usr/share/info/mpfr.info "$(stat -Lc %s /usr/share/info/mpfr.info)"
else
  echo "   INFO /usr/share/info/mpfr.info 不存在，查找实际落点："
  { find /usr/share/info -name 'mpfr.info*' || true; } | sed 's/^/     /'
fi
echo "   /usr/share/info 中的 mpfr 条目："
{ ls /usr/share/info | grep -i mpfr || echo "（无）"; } | sed 's/^/     /'
echo
echo "7) 动态链接与库可见性（后续 §8.24 MPC 的 configure 要同时找到 libgmp 与 libmpfr）："
echo "   libmpfr.so 的动态依赖（应含 libgmp.so.10 与 libc）："
xdep=$({ ldd /usr/lib/libmpfr.so || true; })
echo "$xdep" | sed 's/^/     /'
case "$xdep" in
  *libgmp.so.10*) echo "     OK   libmpfr.so 链接到 libgmp.so.10" ;;
  *) echo "     FAIL libmpfr.so 未链接 libgmp.so.10"; rc=1 ;;
esac
case "$xdep" in
  *"not found"*) echo "     FAIL 存在未解析的依赖"; rc=1 ;;
  *) echo "     OK   所有依赖均已解析" ;;
esac
case "$xdep" in
  */tools/*) echo "     FAIL 仍链接 /tools 下的库"; rc=1 ;;
  *) echo "     OK   未链接任何 /tools 路径" ;;
esac
echo
echo "----- 功能验证（对照手册 §8.23.2 的 libmpfr 说明，用已安装的库逐项验证） -----"
echo "手册：libmpfr —— Contains multiple-precision math functions"
tmpd=$(mktemp -d /tmp/mpfr-verify-XXXXXX)
echo "a) 多精度浮点数与超越函数（pi / sqrt(2) / e，200 位二进制精度，取 40 位小数）"
echo "   —— 期望值取自开工前在 chroot /tmp 里同源码、同选项试建产物的实测输出，"
echo "      不是从十进制展开表抄的，因此不存在末位进位歧义："
cat > "$tmpd/a.c" <<'EOF'
#include <stdio.h>
#include <mpfr.h>
int main(void){
  mpfr_t x, y;
  mpfr_init2(x, 200); mpfr_init2(y, 200);
  mpfr_const_pi(x, MPFR_RNDN);
  mpfr_printf("pi=%.40Rf\n", x);
  mpfr_set_ui(y, 2, MPFR_RNDN); mpfr_sqrt(y, y, MPFR_RNDN);
  mpfr_printf("sqrt2=%.40Rf\n", y);
  mpfr_set_ui(y, 1, MPFR_RNDN); mpfr_exp(y, y, MPFR_RNDN);
  mpfr_printf("e=%.40Rf\n", y);
  printf("version=%s\n", mpfr_get_version());
  mpfr_clear(x); mpfr_clear(y); mpfr_free_cache();
  return 0;
}
EOF
if gcc -o "$tmpd/a" "$tmpd/a.c" -lmpfr -lgmp > "$tmpd/a.cc.log" 2>&1; then
  out_a=$("$tmpd/a" 2>&1)
  echo "$out_a" | sed 's/^/     /'
  case "$out_a" in
    *"pi=3.1415926535897932384626433832795028841972"*) echo "     OK   pi 的 40 位小数与试建实测值逐字一致" ;;
    *) echo "     FAIL pi 的 40 位小数与试建实测值不一致"; rc=1 ;;
  esac
  case "$out_a" in
    *"sqrt2=1.4142135623730950488016887242096980785697"*) echo "     OK   sqrt(2) 的 40 位小数与试建实测值逐字一致" ;;
    *) echo "     FAIL sqrt(2) 的 40 位小数与试建实测值不一致"; rc=1 ;;
  esac
  case "$out_a" in
    *"e=2.7182818284590452353602874713526624977572"*) echo "     OK   e 的 40 位小数与试建实测值逐字一致" ;;
    *) echo "     FAIL e 的 40 位小数与试建实测值不一致"; rc=1 ;;
  esac
  case "$out_a" in
    *"version=$VER"*) echo "     OK   已安装库自述版本 $VER" ;;
    *) echo "     FAIL 已安装库自述版本不是 $VER"; rc=1 ;;
  esac
else
  echo "     FAIL 无法用已安装的 mpfr.h + -lmpfr 编译 C 程序："; sed 's/^/       /' "$tmpd/a.cc.log"; rc=1
fi
echo "b) 四种舍入模式与 IEEE 语义（MPFR 与 GMP 的 mpf 的关键区别：正确舍入）："
cat > "$tmpd/b.c" <<'EOF'
#include <stdio.h>
#include <mpfr.h>
int main(void){
  mpfr_t a, b, r;
  /* 1/3 在 8 位精度下，向上/向下舍入必然给出不同结果 */
  mpfr_init2(a, 8); mpfr_init2(b, 8); mpfr_init2(r, 8);
  mpfr_set_ui(a, 1, MPFR_RNDN); mpfr_set_ui(b, 3, MPFR_RNDN);
  mpfr_div(r, a, b, MPFR_RNDD); mpfr_printf("down=%.10Rf\n", r);
  mpfr_div(r, a, b, MPFR_RNDU); mpfr_printf("up=%.10Rf\n", r);
  mpfr_set_ui(r, 0, MPFR_RNDN);
  mpfr_log(r, r, MPFR_RNDN);            /* log(0) = -inf */
  printf("log0_inf=%d sign=%d\n", mpfr_inf_p(r), mpfr_sgn(r) < 0);
  mpfr_set_si(r, -1, MPFR_RNDN);
  mpfr_sqrt(r, r, MPFR_RNDN);           /* sqrt(-1) = NaN */
  printf("sqrtneg_nan=%d\n", mpfr_nan_p(r));
  mpfr_clear(a); mpfr_clear(b); mpfr_clear(r); mpfr_free_cache();
  return 0;
}
EOF
if gcc -o "$tmpd/b" "$tmpd/b.c" -lmpfr -lgmp > "$tmpd/b.cc.log" 2>&1; then
  out_b=$("$tmpd/b" 2>&1)
  echo "$out_b" | sed 's/^/     /'
  d_val=$(printf '%s\n' "$out_b" | sed -n 's/^down=//p')
  u_val=$(printf '%s\n' "$out_b" | sed -n 's/^up=//p')
  if [ -n "$d_val" ] && [ -n "$u_val" ] && [ "$d_val" != "$u_val" ]; then
    echo "     OK   RNDD($d_val) 与 RNDU($u_val) 结果不同 —— 定向舍入按 IEEE 语义生效"
  else
    echo "     FAIL 定向舍入未生效（down='$d_val' up='$u_val'）"; rc=1
  fi
  case "$out_b" in
    *"log0_inf=1 sign=1"*) echo "     OK   log(0) = -Inf（特殊值处理正确）" ;;
    *) echo "     FAIL log(0) 未得到 -Inf"; rc=1 ;;
  esac
  case "$out_b" in
    *"sqrtneg_nan=1"*) echo "     OK   sqrt(-1) = NaN（特殊值处理正确）" ;;
    *) echo "     FAIL sqrt(-1) 未得到 NaN"; rc=1 ;;
  esac
else
  echo "     FAIL 无法编译舍入模式测试程序："; sed 's/^/       /' "$tmpd/b.cc.log"; rc=1
fi
echo "c) --enable-thread-safe 的第三重核对：运行期 mpfr_buildopt_tls_p()"
cat > "$tmpd/c.c" <<'EOF'
#include <stdio.h>
#include <mpfr.h>
int main(void){
  printf("tls=%d\n", mpfr_buildopt_tls_p());
  printf("gmpinternals=%d\n", mpfr_buildopt_gmpinternals_p());
  printf("sharedcache=%d\n", mpfr_buildopt_sharedcache_p());
  printf("tune=%s\n", mpfr_buildopt_tune_case());
  return 0;
}
EOF
if gcc -o "$tmpd/c" "$tmpd/c.c" -lmpfr -lgmp > "$tmpd/c.cc.log" 2>&1; then
  out_c=$("$tmpd/c" 2>&1)
  echo "$out_c" | sed 's/^/     /'
  case "$out_c" in
    *"tls=1"*) echo "     OK   mpfr_buildopt_tls_p() = 1 —— --enable-thread-safe 在运行期确实生效" ;;
    *) echo "     FAIL mpfr_buildopt_tls_p() != 1，--enable-thread-safe 未真正生效"; rc=1 ;;
  esac
  case "$out_c" in
    *"sharedcache=0"*) echo "     OK   sharedcache=0（手册未要求 --enable-shared-cache，符合预期）" ;;
    *) echo "     INFO sharedcache 非 0" ;;
  esac
else
  echo "     FAIL 无法编译 buildopt 测试程序："; sed 's/^/       /' "$tmpd/c.cc.log"; rc=1
fi
echo "d) 后续包的可用性预演（§8.24 MPC 的 configure 会做的事：同时找到 gmp.h + mpfr.h"
echo "   并链接 -lmpfr -lgmp，且要求 MPFR >= 4.1.0）："
cat > "$tmpd/d.c" <<'EOF'
#include <gmp.h>
#include <mpfr.h>
#if MPFR_VERSION < MPFR_VERSION_NUM(4,1,0)
#error "mpfr too old for MPC"
#endif
int main(void){
  mpfr_t t; mpfr_init2(t, 64); mpfr_set_ui(t, 1, MPFR_RNDN);
  mpfr_clear(t); mpfr_free_cache(); return 0;
}
EOF
if gcc -o "$tmpd/d" "$tmpd/d.c" -lmpfr -lgmp > "$tmpd/d.cc.log" 2>&1 && "$tmpd/d"; then
  echo "     OK   默认搜索路径下即可同时 #include <gmp.h>/<mpfr.h> 并 -lmpfr -lgmp（无需额外 -I/-L），"
  echo "          且 MPFR_VERSION >= 4.1.0"
else
  echo "     FAIL 默认搜索路径下无法使用 mpfr："; sed 's/^/       /' "$tmpd/d.cc.log"; rc=1
fi
rm -rf "$tmpd"
echo
echo "8) 本节写入系统的文件清单（实际落点）："
{ ls -l /usr/lib/libmpfr.la /usr/lib/libmpfr.so /usr/lib/libmpfr.so.6 /usr/lib/libmpfr.so.6.* \
       /usr/include/mpfr.h /usr/include/mpf2mpfr.h /usr/lib/pkgconfig/mpfr.pc 2>/dev/null || true; } | sed 's/^/     /'
echo "   $DOCDIR：$(find "$DOCDIR" -type f 2>/dev/null | wc -l) 个文件"
echo "   /usr/share/info 下的 mpfr*：$({ ls /usr/share/info/mpfr* 2>/dev/null || true; } | tr '\n' ' ')"
[ $rc -eq 0 ] || { echo "错误：MPFR 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.23.sh"
echo "  移入 \$LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure         完整输出：$CONFLOG"
echo "  make              完整输出：$MAKELOG"
echo "  make html         完整输出：$HTMLLOG"
echo "  make check        完整输出：$CHECKLOG"
echo "  make install      完整输出：$INSTLOG"
echo "  make install-html 完整输出：$INSTHTMLLOG"
echo "  测试汇总          ：$SUMLOG"
echo "清理前 /sources 下的 mpfr 相关条目："
{ ls -d /sources/mpfr* 2>/dev/null || true; } | sed 's/^/  /'
echo "  待删除：$(du -sh "/sources/$SRCDIR" 2>/dev/null | cut -f1)	/sources/$SRCDIR"
cd /sources
rm -rf "$SRCDIR"
if [ -d "/sources/$SRCDIR" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCDIR"
echo "清理后 /sources 下的 mpfr 相关条目（应只剩 tarball）："
{ ls -d /sources/mpfr* 2>/dev/null || true; } | sed 's/^/  /'
echo "  OK   源码构建目录已删除"
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -mindepth 1 -type d || true; } | sed 's/^/  /'
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo

echo "================= 本节结论 ================="
echo "手册 §8.23 的 6 条命令全部按原样执行完毕："
echo "  1. ./configure --prefix=/usr --disable-static --enable-thread-safe \\"
echo "                 --docdir=$DOCDIR       —— 完成，4 个选项逐条核对生效"
echo "  2. make                                             —— 完成"
echo "  3. make html                                        —— 完成"
echo "  4. make check                                       —— 完成，退出码 $check_rc"
echo "  5. make install                                     —— 完成"
echo "  6. make install-html                                —— 完成"
echo "本节无 sed、无补丁、无 build 目录（in-tree build），提示框只有 1 个 Important（已遵守）。"
echo
echo "测试结论（手册 Important：本节测试 critical，不得跳过；手册判据：all 198 tests passed）："
echo "  TOTAL : $t_total（手册说 198）"
echo "  PASS  : $t_pass（手册要求 198 全过）"
echo "  FAIL  : $t_fail（要求 0）"
echo "  SKIP  : $t_skip"
echo "  XFAIL : $t_xfail"
echo "  XPASS : $t_xpass（要求 0）"
echo "  ERROR : $t_err（要求 0）"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.23 MPFR-$VER 完成 ====="
