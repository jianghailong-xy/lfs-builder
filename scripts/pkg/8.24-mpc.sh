#!/usr/bin/env bash
# LFS 13.0-systemd §8.24 MPC-1.3.1
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.24.1 Installation of MPC 的命令序列（全部 6 条，一条不多一条不少）：
#   ./configure --prefix=/usr    \
#               --disable-static \
#               --docdir=/usr/share/doc/mpc-1.3.1
#   make
#   make html
#   make check
#   make install
#   make install-html
#
# 本节没有 sed、没有补丁、没有 mkdir build（in-tree build）。
# 本节**一个提示框都没有**（无 Note / Important / Caution / Warning）。
# 手册对测试只说了一句「To test the results, issue: make check」——
#   与 §8.23 MPFR 不同，这里既没有 critical 的 Important，也没有给出任何数字判据。
set -euo pipefail

PKG=mpc
VER=1.3.1
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
DOCDIR=/usr/share/doc/mpc-$VER
CONFLOG=/sources/.mpc-configure.log
MAKELOG=/sources/.mpc-make.log
HTMLLOG=/sources/.mpc-make-html.log
CHECKLOG=/sources/.mpc-make-check.log
INSTLOG=/sources/.mpc-make-install.log
INSTHTMLLOG=/sources/.mpc-make-install-html.log
SUMLOG=/sources/.mpc-test-summary.log

echo "===== LFS 13.0-systemd §8.24 MPC-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The MPC package contains a library for the arithmetic of complex numbers"
echo "  with arbitrarily high precision and correct rounding of the result."
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 22 MB"
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
echo "1) 上一任务 §8.23 MPFR-4.2.2 的产物 —— MPC 建在 MPFR 之上，configure 会做"
echo "   'checking for MPFR' 与 'checking for recent MPFR'，装不全必然失败："
for f in /usr/include/mpfr.h /usr/include/mpf2mpfr.h /usr/lib/libmpfr.so \
         /usr/lib/libmpfr.so.6 /usr/lib/pkgconfig/mpfr.pc; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.23 未完成？）\n' "$f"; rc=1; fi
done
echo "   libmpfr 实体与 SONAME："
for so in $({ ls /usr/lib/libmpfr.so.*.*.* 2>/dev/null || true; }); do
  printf '     %-24s SONAME=%s\n' "$(basename "$so")" \
    "$(readelf -d "$so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')"
done
echo "   已装 mpfr.h 自述版本："
{ grep -E '^#define MPFR_VERSION_(MAJOR|MINOR|PATCHLEVEL|STRING)' /usr/include/mpfr.h || true; } | sed 's/^/     /'
m_str=$(sed -n 's/^#define MPFR_VERSION_STRING *"\(.*\)"$/\1/p' /usr/include/mpfr.h | sed -n 1p)
if [ "$m_str" = "4.2.2" ]; then
  echo "     OK   MPFR 头文件版本 $m_str = §8.23 的 4.2.2"
else
  echo "     FAIL MPFR 头文件版本 '$m_str' 与 §8.23 的 4.2.2 不符"; rc=1
fi
echo
echo "2) 再上一步 §8.22 GMP-6.3.0 的产物 —— MPC 的 configure 先查 GMP 再查 MPFR："
for f in /usr/include/gmp.h /usr/lib/libgmp.so /usr/lib/libgmp.so.10; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.22 未完成？）\n' "$f"; rc=1; fi
done
g_major=$(sed -n 's/^#define __GNU_MP_VERSION  *//p' /usr/include/gmp.h | sed -n 1p)
g_minor=$(sed -n 's/^#define __GNU_MP_VERSION_MINOR  *//p' /usr/include/gmp.h | sed -n 1p)
g_patch=$(sed -n 's/^#define __GNU_MP_VERSION_PATCHLEVEL  *//p' /usr/include/gmp.h | sed -n 1p)
if [ "$g_major.$g_minor.$g_patch" = "6.3.0" ]; then
  echo "   OK   GMP 头文件版本 $g_major.$g_minor.$g_patch = §8.22 的 6.3.0"
else
  echo "   FAIL GMP 头文件版本 $g_major.$g_minor.$g_patch 与 §8.22 的 6.3.0 不符"; rc=1
fi
echo "   用已装 GMP+MPFR 编译并运行一个最小程序（= MPC configure 的等价前置探测，"
echo "   含 MPC 的 configure.ac 对 MPFR 版本下限的等价要求）："
tmpg=$(mktemp /tmp/mpfr-pre-XXXXXX.c)
cat > "$tmpg" <<'EOF'
#include <stdio.h>
#include <gmp.h>
#include <mpfr.h>
int main(void){
  mpfr_t t; mpfr_init2(t, 128); mpfr_const_pi(t, MPFR_RNDN);
  mpfr_printf("gmp=%s mpfr=%s pi=%.10Rf\n", gmp_version, mpfr_get_version(), t);
  mpfr_clear(t); mpfr_free_cache(); return 0;
}
EOF
if gcc -o "${tmpg%.c}" "$tmpg" -lmpfr -lgmp >/dev/null 2>&1; then
  echo "     $("${tmpg%.c}")"
  echo "     OK   默认搜索路径下可同时 #include <gmp.h>/<mpfr.h> 并 -lmpfr -lgmp 链接运行"
else
  echo "     FAIL 无法用已装 GMP+MPFR 编译/链接（MPC 的 configure 必然失败）"; rc=1
fi
rm -f "$tmpg" "${tmpg%.c}"
echo
echo "3) C 库与编译器（本节只编 C，不需要 C++）："
for f in /usr/lib/libc.so.6 /usr/lib/libm.so.6 /lib64/ld-linux-x86-64.so.2 \
         /usr/include/stdio.h /usr/include/complex.h; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   （/usr/include/complex.h 单列：MPC 的 configure 会探测它，探到后 config.h 里"
echo "     会有 HAVE_COMPLEX_H 1，_Complex 相关的 mpc_set_dc/mpc_get_dc 接口才可用。）"
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
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "5) 本节直接依赖的外部命令（开工前一次性 command -v 过一遍 —— 第 8 章的 chroot"
echo "   是半成品系统，宿主机上顺手就有的命令不一定存在）："
for t in tar gzip make gcc ld as ar ranlib sed grep awk tee install ln rm mkdir \
         cmp diff md5sum readelf objdump ldd find stat bash sort head tail \
         makeinfo texi2any install-info perl file du df env tr wc cat cp mktemp date; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-12s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   makeinfo 版本：$(makeinfo --version 2>&1 | sed -n 1p)"
echo "   说明：手册命令 3/6 的 make html 由 doc/Makefile 调用 makeinfo --html 生成，"
echo "     命令 6/6 的 make install-html 再把它装进 --docdir 指定的目录，"
echo "     故 §7.11 Texinfo 的 makeinfo 是本节的硬依赖；install-info 则用于更新"
echo "     /usr/share/info/dir（make install 装 mpc.info 时会调用）。"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   注意：本包的 tarball 是 .tar.gz（不是 .tar.xz），解包靠 gzip 而非 xz。"
echo
echo "6) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then
  echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "   本节无补丁（手册 §8.24 未引用任何 patch）；/sources 中匹配 mpc*patch 的文件："
mpc_patches=$({ ls /sources 2>/dev/null | grep -E '^mpc.*patch' || true; })
echo "     ${mpc_patches:-无}"
echo
echo "7) §7.3 虚拟内核文件系统与 §7.6 基础文件（测试程序要读写 /dev、/proc、/tmp）："
for f in /dev/null /dev/zero /dev/full /dev/urandom /dev/tty /proc/self /sys \
         /etc/passwd /etc/group /tmp /var/tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "8) 安装目标目录与安装前的 MPC 痕迹（MPC 是第一次装进本系统）："
for d in /usr/lib /usr/include /usr/share/info /usr/share/doc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
pre=$({ ls -d /usr/lib/libmpc* /usr/include/mpc.h "$DOCDIR" 2>/dev/null || true; })
if [ -z "$pre" ]; then
  echo "   INFO 系统中当前没有任何 MPC 文件 —— 符合预期：第 5/6 章的 GCC 是把 gmp/mpfr/mpc"
  echo "     解包进 gcc 源码树内联构建的，从未把 MPC 装进 \$LFS，本节是首次安装。"
else
  echo "   INFO 安装前已存在的 MPC 相关文件（本节会覆盖）："; echo "$pre" | sed 's/^/     /'
fi
echo "   /usr/share/info/dir 当前状态（make install 会用 install-info 往里加 MPC 条目）："
if [ -f /usr/share/info/dir ]; then
  echo "     存在（$(stat -c %s /usr/share/info/dir) 字节，$(wc -l < /usr/share/info/dir) 行）"
else
  echo "     不存在，make install 会创建"
fi
echo
echo "9) 磁盘空间（手册要求 22 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 204800 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 22 MB"
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
echo "手册 §8.24 全节没有 mkdir build —— MPC 在源码目录内直接 configure（in-tree build）。"
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
echo "  （本包没有顶层 VERSION 文件，与 §8.23 MPFR 不同。）"
echo "  src/mpc.h 中的版本宏："
{ grep -nE '^#define MPC_VERSION_(MAJOR|MINOR|PATCHLEVEL|STRING)' src/mpc.h || true; } | sed 's/^/    /'
if [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $conf_ver 与手册 §8.24 的 MPC-$VER 一致"
else echo "  FAIL 源码自述版本为 '$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo
echo "----- 本包的三个结构性事实（开工前已在 chroot /tmp 的完整试建中确认，写在这里"
echo "      是为了让下面的核对方式有据可依；这三条都与紧邻的 §8.23 MPFR **相反**，"
echo "      照抄上一节的判据必然扑空） -----"
echo "  a) MPC **使用** config.h —— configure.ac 第 26 行有 AC_CONFIG_HEADERS（MPFR 那一节"
echo "     是被 dnl 注释掉的）。因此 src/Makefile 的 DEFS 只有 -DHAVE_CONFIG_H，"
echo "     各项探测结论要去 config.h 里看，不在 DEFS 里："
{ grep -nE 'AC_CONFIG_HEADERS' configure.ac || true; } | sed 's/^/       /'
echo "  b) 共享库版本号来自 src/Makefile.am 的 libtool -version-info，而非包版本号："
{ grep -nE 'version-info' src/Makefile.am || true; } | sed 's/^/       /'
echo "     -version-info 6:1:3 → SONAME 主版本 = CURRENT-AGE = 6-3 = 3，"
echo "     实体文件名 libmpc.so.3.3.1。别按包版本 1.3.1 猜 SONAME。"
echo "  c) MPC **不安装 pkg-config 文件** —— 源码树里没有 mpc.pc(.in)，"
echo "     §8.22 GMP / §8.23 MPFR 都装了 .pc，本节不装，去查 /usr/lib/pkgconfig/mpc.pc"
echo "     必然扑空。源码树中匹配 *.pc* 的文件："
pc_in_tree=$({ find . -maxdepth 2 \( -name '*.pc' -o -name '*.pc.in' \) || true; })
echo "       ${pc_in_tree:-（无 —— 确实没有 .pc/.pc.in）}"
echo
echo "----- 测试结构预读（决定 make check 的判定标准） -----"
echo "tests/Makefile.am 的测试声明（automake parallel-tests 框架）："
{ grep -nE '^(TESTS|check_PROGRAMS|XFAIL_TESTS) *=' tests/Makefile.am || true; } | sed 's/^/  /'
echo "tests 目录下的 .c 文件数：$(ls tests/*.c 2>/dev/null | wc -l)"
echo "  （.c 文件数 ≠ 测试数：tests/ 里还有 tgeneric.c 等被 #include 的公共代码，"
echo "    真正的测试程序数以 automake 汇总块的 # TOTAL: 为准。）"
echo "手册对测试的全部原文只有一句：「To test the results, issue: make check」"
echo "  —— 本节**没有**任何提示框，手册也**没有**给出期望的测试数量或允许失败的例外。"
echo "判定标准（本脚本采用；因手册无数字判据，下面除第 1 条外均为自加，"
echo "  其中 TOTAL=74 来自开工前同源码、同选项的 chroot /tmp 完整试建实测，不是猜的）："
echo "  硬判据 1（手册「To test the results, issue: make check」）：make check 必须真的"
echo "    跑完，且退出码为 0 —— 手册没有给出任何允许失败的例外说明；"
echo "  硬判据 2（自加，试建校准）：automake 汇总块 # TOTAL: 74、# PASS: 74；"
echo "  硬判据 3（自加）：FAIL=0、XPASS=0、ERROR=0；"
echo "  硬判据 4（自加，一致性互校）：PASS+SKIP+XFAIL+FAIL+XPASS+ERROR = TOTAL。"
echo

echo "================= 8.24.1. Installation of MPC ================="
echo

echo "----- 手册命令 1/6：configure -----"
echo "手册原文：Prepare MPC for compilation:"
echo "手册命令：./configure --prefix=/usr    \\"
echo "                     --disable-static \\"
echo "                     --docdir=/usr/share/doc/mpc-$VER"
echo "手册对本节未单独解释选项（--disable-static 与 --docdir 的含义见 §8.22 GMP 一节："
echo "  前者不构建/不安装静态库，后者把本包文档装到带版本号的目录里）。"
echo "本节比 §8.23 MPFR 少一个 --enable-thread-safe —— 手册没给，就不加。"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/mpc-$VER > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 60 行："; tail -n 60 "$CONFLOG" | sed 's/^/  /'
  [ -f config.log ] && { echo "config.log 末尾 60 行："; tail -n 60 config.log | sed 's/^/  /'; }
  exit $conf_rc
fi
echo "configure 对 GMP / MPFR 的探测（MPC 的两个核心前置）："
{ grep -inE 'gmp|mpfr' "$CONFLOG" || true; } | sed 's/^/  /'
echo "configure 对 complex.h / _Complex 的探测（决定 config.h 里的 HAVE_COMPLEX_H）："
{ grep -inE 'complex' "$CONFLOG" || true; } | sed 's/^/  /'
echo "configure 生成的文件（config.status: creating 行，用于确认落点）："
{ grep -n 'config.status: creating' "$CONFLOG" || true; } | sed 's/^/  /'
echo "configure 末尾 20 行："
tail -n 20 "$CONFLOG" | sed 's/^/  /'
echo
echo "----- 核对手册给的 3 个选项确实生效（多重核对：configure 结论 + 生成 Makefile/libtool + 后面的 ldd/运行期） -----"
crc=0
echo "0) 选项一个不多一个不少：config.status 里的 ac_cs_config"
echo "   （本包的 config.status 用双引号包住、各选项再各自单引号，与 §8.23 MPFR 的"
echo "     单引号整串格式不同，取值方式据此调整。）"
cs=$(sed -n 's/^ac_cs_config="\(.*\)"$/\1/p' config.status | sed -n 1p)
echo "     ac_cs_config = $cs"
exp_cs="'--prefix=/usr' '--disable-static' '--docdir=$DOCDIR'"
if [ "$cs" = "$exp_cs" ]; then echo "     OK   与手册命令逐字一致（3 个选项，无多余、无遗漏）"
else echo "     FAIL 期望 $exp_cs"; crc=1; fi
echo "   config.log 里记录的原始命令行（第二重核对）："
{ grep -n '^  \$ \./configure' config.log || true; } | sed -n '1,3p' | sed 's/^/     /'
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
echo "       本次配置的结论是**第一处**，与 §8.20/§8.22/§8.23 的判据一致。）"
old_libs=$(sed -n 's/^build_old_libs=//p' libtool | sed -n 1p)
new_libs=$(sed -n 's/^build_libtool_libs=//p' libtool | sed -n 1p)
if [ "$old_libs" = "no" ]; then echo "     OK   build_old_libs=no（不构建 .a 静态库）"
else echo "     FAIL build_old_libs='$old_libs'，--disable-static 未生效"; crc=1; fi
if [ "$new_libs" = "yes" ]; then echo "     OK   build_libtool_libs=yes（构建共享库）"
else echo "     FAIL build_libtool_libs='$new_libs'"; crc=1; fi
echo "d) config.h（结构性事实 a：本包的探测结论落在这里，不在 DEFS 里）"
if [ -f config.h ]; then
  echo "     OK   config.h 已生成（$(stat -Lc %s config.h) 字节）"
  echo "     关键宏："
  { grep -E '^#define (PACKAGE_NAME|PACKAGE_VERSION|HAVE_COMPLEX_H|HAVE_LOCALE_H|HAVE_LIMITS_H)' config.h || true; } | sed 's/^/       /'
  ch_ver=$(sed -n 's/^#define PACKAGE_VERSION *"\(.*\)"$/\1/p' config.h | sed -n 1p)
  if [ "$ch_ver" = "$VER" ]; then echo "       OK   config.h 的 PACKAGE_VERSION = $VER"
  else echo "       FAIL config.h 的 PACKAGE_VERSION 为 '$ch_ver'"; crc=1; fi
  if { grep -qE '^#define HAVE_COMPLEX_H 1$' config.h; }; then
    echo "       OK   HAVE_COMPLEX_H 1（探到 glibc 的 complex.h，_Complex 接口可用）"
  else
    echo "       INFO config.h 中无 HAVE_COMPLEX_H 1（手册未要求，不算失败）"
  fi
  echo "     src/Makefile 的 DEFS（应只有 -DHAVE_CONFIG_H）："
  defs=$(sed -n 's/^DEFS = //p' src/Makefile | sed -n 1p)
  echo "       DEFS = $defs"
  case " $defs " in
    *" -DHAVE_CONFIG_H "*) echo "       OK   DEFS 含 -DHAVE_CONFIG_H，与 AC_CONFIG_HEADERS 一致" ;;
    *) echo "       FAIL DEFS 中没有 -DHAVE_CONFIG_H"; crc=1 ;;
  esac
else
  echo "     FAIL config.h 未生成"; crc=1
fi
echo "e) 生成的各子目录 Makefile"
for d in src tests doc tools; do
  if [ -f "$d/Makefile" ]; then printf '     OK   %s/Makefile\n' "$d"
  else printf '     FAIL %s/Makefile 未生成\n' "$d"; crc=1; fi
done
echo "     （本包无 mpc.pc —— 见上面的结构性事实 c，故此处不查 pkgconfig 文件。）"
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册 §8.24 的 3 个选项"
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
{ ls -l src/libmpc.la 2>/dev/null || true; } | sed 's/^/    /'
{ ls -l src/.libs/libmpc.so src/.libs/libmpc.so.3 src/.libs/libmpc.so.3.* 2>/dev/null || true; } | sed 's/^/    /'
if [ -f src/libmpc.la ]; then echo "    OK   src/libmpc.la"
else echo "    FAIL src/libmpc.la 未生成"; mrc=1; fi
mpc_so=$({ ls src/.libs/libmpc.so.*.*.* 2>/dev/null || true; } | sed -n 1p)
if [ -n "$mpc_so" ]; then
  printf '    OK   %s（%s 字节，%s）\n' "$mpc_so" "$(stat -Lc %s "$mpc_so")" "$(file -b "$mpc_so" | cut -d, -f1-2)"
  soname=$(readelf -d "$mpc_so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')
  echo "    SONAME=$soname"
  if [ "$soname" = "libmpc.so.3" ]; then
    echo "    OK   SONAME 为 libmpc.so.3（= -version-info 6:1:3 的 CURRENT-AGE = 3）"
  else echo "    FAIL SONAME 为 '$soname'，期望 libmpc.so.3"; mrc=1; fi
  if [ "$(basename "$mpc_so")" = "libmpc.so.3.3.1" ]; then
    echo "    OK   实体文件名 libmpc.so.3.3.1"
  else echo "    FAIL 实体文件名为 $(basename "$mpc_so")，期望 libmpc.so.3.3.1"; mrc=1; fi
else echo "    FAIL 未生成 src/.libs/libmpc.so.*"; mrc=1; fi
echo "  --disable-static 的验证：构建目录内不应有 libmpc.a"
stat_a=$({ ls src/.libs/*.a 2>/dev/null || true; })
if [ -z "$stat_a" ]; then echo "    OK   构建目录内无静态库"
else echo "    FAIL 生成了静态库：$stat_a"; mrc=1; fi
echo "  构建产物的动态依赖（应同时含 libmpfr.so.6 与 libgmp.so.10，且不含任何 /tools 路径）："
dep=$({ ldd "$mpc_so" || true; })
echo "$dep" | sed 's/^/    /'
case "$dep" in
  *libmpfr.so.6*) echo "    OK   链接到 §8.23 装的 libmpfr.so.6" ;;
  *) echo "    FAIL 未链接 libmpfr.so.6"; mrc=1 ;;
esac
case "$dep" in
  *libgmp.so.10*) echo "    OK   链接到 §8.22 装的 libgmp.so.10" ;;
  *) echo "    FAIL 未链接 libgmp.so.10"; mrc=1 ;;
esac
case "$dep" in
  */tools/*) echo "    FAIL 仍链接 /tools 下的库"; mrc=1 ;;
  *) echo "    OK   未链接任何 /tools 路径" ;;
esac
echo "  未安装产物的冒烟测试（直接链接构建目录里的 libmpc）："
tmpd=$(mktemp -d /tmp/mpc-build-smoke-XXXXXX)
cat > "$tmpd/s.c" <<'EOF'
#include <stdio.h>
#include <mpc.h>
int main(void){
  mpc_t z, w;
  mpc_init2(z, 200); mpc_init2(w, 200);
  mpc_set_ui_ui(z, 0, 1, MPC_RNDNN);   /* z = i */
  mpc_mul(w, z, z, MPC_RNDNN);         /* i*i = -1 */
  mpfr_printf("i2=%.10Rf %.10Rf\n", mpc_realref(w), mpc_imagref(w));
  printf("version=%s\n", mpc_get_version());
  mpc_clear(z); mpc_clear(w); mpfr_free_cache();
  return 0;
}
EOF
if gcc -o "$tmpd/s" "$tmpd/s.c" -Isrc -Lsrc/.libs -lmpc -lmpfr -lgmp > "$tmpd/cc.log" 2>&1; then
  smoke=$(LD_LIBRARY_PATH=$PWD/src/.libs "$tmpd/s" 2>&1)
  echo "$smoke" | sed 's/^/    /'
  case "$smoke" in
    *"i2=-1.0000000000 0.0000000000"*) echo "    OK   i×i = -1 + 0i（复数乘法正确）" ;;
    *) echo "    FAIL i×i 结果不正确"; mrc=1 ;;
  esac
  case "$smoke" in
    *"version=$VER"*) echo "    OK   构建产物自述版本 $VER" ;;
    *) echo "    FAIL 构建产物自述版本不是 $VER"; mrc=1 ;;
  esac
else
  echo "    FAIL 无法链接构建目录里的 libmpc："; sed 's/^/      /' "$tmpd/cc.log"; mrc=1
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
echo "make html 输出（全部，共 $(wc -l < "$HTMLLOG") 行；只有 doc/ 一个子目录真正干活，"
echo "  src/tests/tools 都是 Nothing to be done）："
sed -n '1,60p' "$HTMLLOG" | sed 's/^/  /'
echo "生成的 HTML 文档（doc/ 下）："
{ ls -ld doc/mpc.html 2>/dev/null || true; } | sed 's/^/  /'
hrc=0
if [ -d doc/mpc.html ]; then
  nh=$(ls doc/mpc.html | wc -l)
  echo "  OK   doc/mpc.html/ 是按节点拆分的目录，共 $nh 个文件（试建实测 27 个）"
  echo "  全部文件："; { ls doc/mpc.html || true; } | sed 's/^/    /'
  if [ -f doc/mpc.html/index.html ]; then echo "  OK   doc/mpc.html/index.html 存在（入口）"
  else echo "  FAIL doc/mpc.html/index.html 缺失"; hrc=1; fi
else
  echo "  FAIL 未生成 doc/mpc.html/ 目录"; hrc=1
fi
echo "  info 文档（doc/mpc.info —— 本包的 tarball 里自带预生成版本，由 make install"
echo "    装进 /usr/share/info，不由 make html 产出）："
if [ -f doc/mpc.info ]; then echo "    OK   doc/mpc.info（$(stat -Lc %s doc/mpc.info) 字节）"
else echo "    INFO doc/mpc.info 不在 doc/ 下，查找："; { find . -name 'mpc.info*' || true; } | sed -n '1,5p' | sed 's/^/      /'; fi
[ $hrc -eq 0 ] || { echo "错误：make html 未产出预期文档" >&2; exit 1; }
echo

echo "----- 手册命令 4/6：make check（本节的测试） -----"
echo "手册原文（本节关于测试的全部文字，一句话，没有任何提示框）："
echo "  To test the results, issue:"
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
echo "逐项 PASS 清单："
{ grep -E '^PASS: ' "$CHECKLOG" || true; } | sed 's/^/  /'
echo
{
  echo "===== §8.24 MPC-$VER 测试汇总 ====="
  echo "手册命令：make check"
  echo "手册判据：本节手册只说「To test the results, issue: make check」，"
  echo "  没有给出期望的测试数量，也没有任何提示框/允许失败的例外。"
  echo "  故除「退出码 0」外的数字判据均为本项目自加，其中 TOTAL=74 来自开工前"
  echo "  同源码、同选项在 chroot /tmp 内的完整试建实测。"
  echo "make check 退出码：$check_rc"
  printf 'TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
    "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
  echo "----- 非 PASS 项 -----"
  { grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; }
  echo "----- 汇总块 -----"
  { grep -E '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary)' "$CHECKLOG" || true; }
  echo "----- 逐项 PASS -----"
  { grep -E '^PASS: ' "$CHECKLOG" || true; }
} > "$SUMLOG"
trc=0
echo "判据核对："
if [ "$check_rc" -eq 0 ]; then
  echo "  OK   硬判据 1（手册「To test the results, issue: make check」）：make check 完整跑完且退出码 0"
else
  echo "  FAIL 硬判据 1：make check 退出码 $check_rc"; trc=1
fi
if [ "$t_total" = 74 ]; then
  echo "  OK   硬判据 2（自加，试建校准）：TOTAL = 74"
else
  echo "  FAIL 硬判据 2（自加）：TOTAL = $t_total，试建实测应为 74"; trc=1
fi
if [ "$t_pass" = 74 ]; then
  echo "  OK   硬判据 2（自加，试建校准）：PASS = 74（全过）"
else
  echo "  FAIL 硬判据 2（自加）：PASS = $t_pass，试建实测应为 74"; trc=1
fi
if [ "$t_fail" = 0 ] && [ "$t_err" = 0 ] && [ "$t_xpass" = 0 ]; then
  echo "  OK   硬判据 3（自加）：FAIL=0、XPASS=0、ERROR=0"
else
  echo "  FAIL 硬判据 3（自加）：FAIL=$t_fail XPASS=$t_xpass ERROR=$t_err"; trc=1
fi
if [ "$t_total" -gt 0 ] && [ "$((t_pass + t_skip + t_xfail + t_fail + t_xpass + t_err))" = "$t_total" ]; then
  echo "  OK   硬判据 4（自加）：PASS+SKIP+XFAIL+FAIL+XPASS+ERROR = TOTAL($t_total)"
else
  echo "  FAIL 硬判据 4（自加）：各项之和 != TOTAL($t_total)"; trc=1
fi
if [ $trc -ne 0 ]; then
  echo "错误：测试结果不符合要求；完整输出见 $CHECKLOG" >&2
  echo "  make check 末尾 80 行：" >&2
  tail -n 80 "$CHECKLOG" | sed 's/^/  /' >&2
  exit 1
fi
echo
echo "测试结论：手册 §8.24 要求 make check，本次已完整跑完，退出码 $check_rc。"
echo "  TOTAL=$t_total、PASS=$t_pass —— 全过；FAIL=0、XPASS=0、ERROR=0、"
echo "  SKIP=$t_skip、XFAIL=$t_xfail。无未解释的意外失败。"
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

echo "----- 安装后检查（手册 §8.24.2 Contents of MPC） -----"
echo "手册列出的内容："
echo "  Installed libraries : libmpc.so"
echo "  Installed directory : /usr/share/doc/mpc-$VER"
echo "  libmpc —— Contains complex math functions"
rc=0
echo
echo "1) Installed libraries（手册明确列出的唯一一个）："
if [ -L /usr/lib/libmpc.so ]; then
  echo "   OK   /usr/lib/libmpc.so -> $(readlink /usr/lib/libmpc.so)"
elif [ -e /usr/lib/libmpc.so ]; then
  echo "   OK   /usr/lib/libmpc.so（普通文件，$(stat -Lc %s /usr/lib/libmpc.so) 字节）"
else
  echo "   FAIL /usr/lib/libmpc.so 缺失"; rc=1
fi
echo "   /usr/lib 下全部 MPC 库文件（通配符写成不重叠的，避免同一批文件列两遍）："
{ ls -l /usr/lib/libmpc.la /usr/lib/libmpc.so /usr/lib/libmpc.so.3 /usr/lib/libmpc.so.3.* 2>/dev/null || true; } | sed 's/^/     /'
inst_so=/usr/lib/libmpc.so.3.3.1
if [ -f "$inst_so" ]; then
  printf '   OK   %s（%s 字节，%s）\n' "$inst_so" "$(stat -Lc %s "$inst_so")" "$(file -b "$inst_so" | cut -d, -f1-2)"
  isoname=$(readelf -d "$inst_so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')
  if [ "$isoname" = "libmpc.so.3" ]; then echo "   OK   SONAME=libmpc.so.3"
  else echo "   FAIL SONAME='$isoname'，期望 libmpc.so.3"; rc=1; fi
else
  echo "   FAIL $inst_so 缺失"; rc=1
fi
if [ -L /usr/lib/libmpc.so.3 ]; then
  echo "   OK   /usr/lib/libmpc.so.3 -> $(readlink /usr/lib/libmpc.so.3)（SONAME 链接）"
else echo "   FAIL /usr/lib/libmpc.so.3 不是符号链接"; rc=1; fi
echo
echo "2) --disable-static 的验证：/usr/lib 下不应出现 libmpc.a"
stale=$({ ls /usr/lib/libmpc.a 2>/dev/null || true; })
if [ -z "$stale" ]; then echo "   OK   未安装 MPC 静态库"
else echo "   FAIL 存在静态库：$stale"; rc=1; fi
echo "   libtool 归档（.la，LFS 未要求删除，仅记录）："
if [ -f /usr/lib/libmpc.la ]; then
  { grep -E '^(dlname|library_names|old_library)=' /usr/lib/libmpc.la || true; } | sed 's/^/     /'
  la_old=$(sed -n "s/^old_library='\(.*\)'\$/\1/p" /usr/lib/libmpc.la | sed -n 1p)
  if [ -z "$la_old" ]; then echo "     OK   .la 里 old_library='' （与 --disable-static 一致）"
  else echo "     FAIL .la 里 old_library='$la_old'"; rc=1; fi
else
  echo "     （无 .la）"
fi
echo
echo "3) 头文件（手册 Contents 未单列，但 make install 会装；§8.31 GCC 重建时要用）："
if [ -f /usr/include/mpc.h ]; then
  printf '   OK   %-28s（%s 字节）\n' /usr/include/mpc.h "$(stat -Lc %s /usr/include/mpc.h)"
else printf '   FAIL /usr/include/mpc.h 缺失\n'; rc=1; fi
echo "   已安装 mpc.h 的版本宏："
{ grep -E '^#define MPC_VERSION_(MAJOR|MINOR|PATCHLEVEL|STRING)' /usr/include/mpc.h || true; } | sed 's/^/     /'
i_str=$(sed -n 's/^#define MPC_VERSION_STRING *"\(.*\)"$/\1/p' /usr/include/mpc.h | sed -n 1p)
if [ "$i_str" = "$VER" ]; then echo "     OK   已安装 mpc.h 自述版本 $i_str = $VER"
else echo "     FAIL 已安装 mpc.h 自述版本 '$i_str' 与 $VER 不符"; rc=1; fi
echo
echo "4) pkg-config 文件：按结构性事实 c，本包不安装 .pc，此处只确认「确实没有」"
if [ -e /usr/lib/pkgconfig/mpc.pc ]; then
  echo "   INFO 意外地存在 /usr/lib/pkgconfig/mpc.pc（不影响手册要求，仅记录）"
else
  echo "   OK   /usr/lib/pkgconfig/mpc.pc 不存在 —— 与源码树中没有 mpc.pc.in 一致，"
  echo "        不是安装遗漏（§8.22 GMP、§8.23 MPFR 装 .pc，本节不装）"
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
  if [ -f "$DOCDIR/mpc.html/index.html" ]; then
    nih=$(find "$DOCDIR/mpc.html" -type f | wc -l)
    echo "   OK   $DOCDIR/mpc.html/index.html 存在（make install-html 的产物，"
    echo "        共 $nih 个 HTML 文件，试建实测 27 个）"
    echo "   入口文件首行：$(sed -n 1p "$DOCDIR/mpc.html/index.html")"
    echo "   入口文件中出现的 MPC 版本串："
    { grep -oE 'GNU MPC [0-9]+\.[0-9]+\.[0-9]+' "$DOCDIR/mpc.html/index.html" || true; } | sed -n '1,3p' | sed 's/^/     /'
  else
    echo "   FAIL $DOCDIR/mpc.html/index.html 缺失（make install-html 未生效）"; rc=1
  fi
  echo "   说明：本包的 docdir 里**只有** mpc.html/ 一个子目录 —— 与 §8.23 MPFR 不同，"
  echo "     MPC 的 Makefile.am 没有 doc_DATA，AUTHORS/NEWS/COPYING.LESSER 等随包文本"
  echo "     不会被装进 docdir。下面逐一确认这一点（不算失败）："
  for f in AUTHORS NEWS COPYING.LESSER README TODO; do
    if [ -f "$DOCDIR/$f" ]; then printf '     INFO %s 存在于文档目录\n' "$f"
    else printf '     INFO %s 不在文档目录（符合 MPC 的 Makefile.am）\n' "$f"; fi
  done
else
  echo "   FAIL $DOCDIR 不存在"; rc=1
fi
echo
echo "6) info 文档（doc/Makefile.am 的 info_TEXINFOS = mpc.texi）："
if [ -e /usr/share/info/mpc.info ]; then
  printf '   OK   %-30s（%s 字节）\n' /usr/share/info/mpc.info "$(stat -Lc %s /usr/share/info/mpc.info)"
else
  echo "   FAIL /usr/share/info/mpc.info 不存在，查找实际落点："
  { find /usr/share/info -name 'mpc.info*' || true; } | sed 's/^/     /'
  rc=1
fi
echo "   /usr/share/info/dir 中的 MPC 条目（make install 调用 install-info 写入）："
{ grep -n -i 'mpc' /usr/share/info/dir 2>/dev/null || echo "（dir 中暂无 mpc 条目）"; } | sed 's/^/     /'
echo
echo "7) 动态链接与库可见性（§8.31 GCC 重建时要同时找到 libgmp/libmpfr/libmpc）："
echo "   libmpc.so 的动态依赖（应含 libmpfr.so.6、libgmp.so.10 与 libc）："
xdep=$({ ldd /usr/lib/libmpc.so || true; })
echo "$xdep" | sed 's/^/     /'
case "$xdep" in
  *libmpfr.so.6*) echo "     OK   libmpc.so 链接到 libmpfr.so.6" ;;
  *) echo "     FAIL libmpc.so 未链接 libmpfr.so.6"; rc=1 ;;
esac
case "$xdep" in
  *libgmp.so.10*) echo "     OK   libmpc.so 链接到 libgmp.so.10" ;;
  *) echo "     FAIL libmpc.so 未链接 libgmp.so.10"; rc=1 ;;
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
echo "----- 功能验证（对照手册 §8.24.2 的 libmpc 说明，用已安装的库逐项验证） -----"
echo "手册：libmpc —— Contains complex math functions"
tmpd=$(mktemp -d /tmp/mpc-verify-XXXXXX)
echo "a) 任意精度复数运算与正确舍入（手册简介：arithmetic of complex numbers with"
echo "   arbitrarily high precision and correct rounding of the result），200 位二进制"
echo "   精度、取 40 位小数 —— 期望值取自开工前在 chroot /tmp 里同源码、同选项试建"
echo "   产物的实测输出，不是从数学表抄的，因此不存在末位进位歧义："
cat > "$tmpd/a.c" <<'EOF'
#include <stdio.h>
#include <mpc.h>
int main(void){
  mpc_t z, w;
  mpc_init2(z, 200); mpc_init2(w, 200);
  mpc_set_ui_ui(z, 0, 1, MPC_RNDNN);          /* i */
  mpc_sqrt(w, z, MPC_RNDNN);
  mpfr_printf("sqrt_i=%.40Rf %.40Rf\n", mpc_realref(w), mpc_imagref(w));
  mpc_set_ui_ui(z, 1, 0, MPC_RNDNN);          /* 1 */
  mpc_log(w, z, MPC_RNDNN);
  mpfr_printf("log1=%.40Rf %.40Rf\n", mpc_realref(w), mpc_imagref(w));
  mpc_set_ui_ui(z, 0, 1, MPC_RNDNN);          /* i */
  mpc_mul(w, z, z, MPC_RNDNN);                /* i*i = -1 */
  mpfr_printf("i2=%.10Rf %.10Rf\n", mpc_realref(w), mpc_imagref(w));
  mpc_set_ui_ui(z, 0, 1, MPC_RNDNN);          /* i */
  mpc_exp(w, z, MPC_RNDNN);                   /* exp(i) = cos1 + i*sin1 */
  mpfr_printf("expi=%.40Rf %.40Rf\n", mpc_realref(w), mpc_imagref(w));
  printf("version=%s\n", mpc_get_version());
  mpc_clear(z); mpc_clear(w); mpfr_free_cache();
  return 0;
}
EOF
if gcc -o "$tmpd/a" "$tmpd/a.c" -lmpc -lmpfr -lgmp > "$tmpd/a.cc.log" 2>&1; then
  out_a=$("$tmpd/a" 2>&1)
  echo "$out_a" | sed 's/^/     /'
  case "$out_a" in
    *"sqrt_i=0.7071067811865475244008443621048490392848 0.7071067811865475244008443621048490392848"*)
      echo "     OK   sqrt(i) = (√2/2)(1+i) 的 40 位小数与试建实测值逐字一致" ;;
    *) echo "     FAIL sqrt(i) 的 40 位小数与试建实测值不一致"; rc=1 ;;
  esac
  case "$out_a" in
    *"log1=0.0000000000000000000000000000000000000000 0.0000000000000000000000000000000000000000"*)
      echo "     OK   log(1) = 0 + 0i" ;;
    *) echo "     FAIL log(1) 不是 0 + 0i"; rc=1 ;;
  esac
  case "$out_a" in
    *"i2=-1.0000000000 0.0000000000"*) echo "     OK   i×i = -1 + 0i" ;;
    *) echo "     FAIL i×i 结果不正确"; rc=1 ;;
  esac
  case "$out_a" in
    *"expi=0.5403023058681397174009366074429766037323 0.8414709848078965066525023216302989996226"*)
      echo "     OK   exp(i) = cos(1) + i·sin(1) 的 40 位小数与试建实测值逐字一致" ;;
    *) echo "     FAIL exp(i) 的 40 位小数与试建实测值不一致"; rc=1 ;;
  esac
  case "$out_a" in
    *"version=$VER"*) echo "     OK   已安装库自述版本 $VER" ;;
    *) echo "     FAIL 已安装库自述版本不是 $VER"; rc=1 ;;
  esac
else
  echo "     FAIL 无法用已安装的 mpc.h + -lmpc 编译 C 程序："; sed 's/^/       /' "$tmpd/a.cc.log"; rc=1
fi
echo "b) 正确舍入（MPC 与朴素复数库的关键区别）与特殊值处理："
cat > "$tmpd/b.c" <<'EOF'
#include <stdio.h>
#include <mpc.h>
int main(void){
  mpc_t a, b, r;
  /* (1+0i)/(3+0i) 在 8 位精度下，向上/向下舍入必然给出不同实部 */
  mpc_init2(a, 8); mpc_init2(b, 8); mpc_init2(r, 8);
  mpc_set_ui_ui(a, 1, 0, MPC_RNDNN);
  mpc_set_ui_ui(b, 3, 0, MPC_RNDNN);
  mpc_div(r, a, b, MPC_RNDDN); mpfr_printf("down=%.10Rf\n", mpc_realref(r));
  mpc_div(r, a, b, MPC_RNDUN); mpfr_printf("up=%.10Rf\n", mpc_realref(r));
  /* |3+4i| = 5 精确 */
  mpc_set_ui_ui(a, 3, 4, MPC_RNDNN);
  { mpfr_t n; mpfr_init2(n, 64); mpc_abs(n, a, MPFR_RNDN);
    mpfr_printf("abs34=%.10Rf\n", n); mpfr_clear(n); }
  /* arg(i) = pi/2 */
  mpc_set_ui_ui(a, 0, 1, MPC_RNDNN);
  { mpfr_t g; mpfr_init2(g, 200); mpc_arg(g, a, MPFR_RNDN);
    mpfr_printf("argi=%.20Rf\n", g); mpfr_clear(g); }
  mpc_clear(a); mpc_clear(b); mpc_clear(r); mpfr_free_cache();
  return 0;
}
EOF
if gcc -o "$tmpd/b" "$tmpd/b.c" -lmpc -lmpfr -lgmp > "$tmpd/b.cc.log" 2>&1; then
  out_b=$("$tmpd/b" 2>&1)
  echo "$out_b" | sed 's/^/     /'
  d_val=$(printf '%s\n' "$out_b" | sed -n 's/^down=//p')
  u_val=$(printf '%s\n' "$out_b" | sed -n 's/^up=//p')
  if [ -n "$d_val" ] && [ -n "$u_val" ] && [ "$d_val" != "$u_val" ]; then
    echo "     OK   实部 RNDD($d_val) 与 RNDU($u_val) 结果不同 —— 定向舍入按 IEEE 语义生效"
  else
    echo "     FAIL 定向舍入未生效（down='$d_val' up='$u_val'）"; rc=1
  fi
  case "$out_b" in
    *"abs34=5.0000000000"*) echo "     OK   |3+4i| = 5" ;;
    *) echo "     FAIL |3+4i| != 5"; rc=1 ;;
  esac
  case "$out_b" in
    *"argi=1.57079632679489661923"*) echo "     OK   arg(i) = π/2 = 1.57079632679489661923…" ;;
    *) echo "     FAIL arg(i) != π/2"; rc=1 ;;
  esac
else
  echo "     FAIL 无法编译舍入/特殊值测试程序："; sed 's/^/       /' "$tmpd/b.cc.log"; rc=1
fi
echo "c) 后续包的可用性预演（§8.31 GCC 重建时 configure 会做的事：同时找到"
echo "   gmp.h + mpfr.h + mpc.h 并链接 -lmpc -lmpfr -lgmp，且要求 MPC >= 1.0.1）："
cat > "$tmpd/c.c" <<'EOF'
#include <gmp.h>
#include <mpfr.h>
#include <mpc.h>
#if MPC_VERSION < MPC_VERSION_NUM(1,0,1)
#error "mpc too old for gcc"
#endif
int main(void){
  mpc_t z; mpc_init2(z, 64); mpc_set_ui_ui(z, 1, 1, MPC_RNDNN);
  mpc_clear(z); mpfr_free_cache(); return 0;
}
EOF
if gcc -o "$tmpd/c" "$tmpd/c.c" -lmpc -lmpfr -lgmp > "$tmpd/c.cc.log" 2>&1 && "$tmpd/c"; then
  echo "     OK   默认搜索路径下即可同时 #include <gmp.h>/<mpfr.h>/<mpc.h> 并"
  echo "          -lmpc -lmpfr -lgmp（无需额外 -I/-L），且 MPC_VERSION >= 1.0.1"
else
  echo "     FAIL 默认搜索路径下无法使用 mpc："; sed 's/^/       /' "$tmpd/c.cc.log"; rc=1
fi
rm -rf "$tmpd"
echo
echo "8) 本节写入系统的文件清单（实际落点，与试建的 DESTDIR 清单逐项对应）："
{ ls -l /usr/lib/libmpc.la /usr/lib/libmpc.so /usr/lib/libmpc.so.3 /usr/lib/libmpc.so.3.* \
       /usr/include/mpc.h /usr/share/info/mpc.info 2>/dev/null || true; } | sed 's/^/     /'
echo "   $DOCDIR：$(find "$DOCDIR" -type f 2>/dev/null | wc -l) 个文件"
[ $rc -eq 0 ] || { echo "错误：MPC 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.24.sh"
echo "  移入 \$LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure         完整输出：$CONFLOG"
echo "  make              完整输出：$MAKELOG"
echo "  make html         完整输出：$HTMLLOG"
echo "  make check        完整输出：$CHECKLOG"
echo "  make install      完整输出：$INSTLOG"
echo "  make install-html 完整输出：$INSTHTMLLOG"
echo "  测试汇总          ：$SUMLOG"
echo "清理前 /sources 下的 mpc 相关条目："
{ ls -d /sources/mpc* 2>/dev/null || true; } | sed 's/^/  /'
echo "  待删除：$(du -sh "/sources/$SRCDIR" 2>/dev/null | cut -f1)	/sources/$SRCDIR"
cd /sources
rm -rf "$SRCDIR"
if [ -d "/sources/$SRCDIR" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCDIR"
echo "清理后 /sources 下的 mpc 相关条目（应只剩 tarball）："
{ ls -d /sources/mpc* 2>/dev/null || true; } | sed 's/^/  /'
echo "  OK   源码构建目录已删除"
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -mindepth 1 -type d || true; } | sed 's/^/  /'
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "/tmp 下本节留下的临时目录（应为空）："
{ ls -d /tmp/mpc-* 2>/dev/null || true; } | sed 's/^/  /'
echo "根文件系统占用："
df -h / | tail -n1
echo

echo "================= 本节结论 ================="
echo "手册 §8.24 的 6 条命令全部按原样执行完毕："
echo "  1. ./configure --prefix=/usr --disable-static --docdir=$DOCDIR"
echo "                                                      —— 完成，3 个选项逐条核对生效"
echo "  2. make                                             —— 完成"
echo "  3. make html                                        —— 完成"
echo "  4. make check                                       —— 完成，退出码 $check_rc"
echo "  5. make install                                     —— 完成"
echo "  6. make install-html                                —— 完成"
echo "本节无 sed、无补丁、无 build 目录（in-tree build），全节一个提示框都没有。"
echo
echo "测试结论（手册对本节测试的全部要求就是「To test the results, issue: make check」，"
echo "  未给数量判据；下列数字与试建实测一致）："
echo "  TOTAL : $t_total"
echo "  PASS  : $t_pass"
echo "  FAIL  : $t_fail（要求 0）"
echo "  SKIP  : $t_skip"
echo "  XFAIL : $t_xfail"
echo "  XPASS : $t_xpass（要求 0）"
echo "  ERROR : $t_err（要求 0）"
echo
echo "手册 §8.24.2 Contents 逐项确认："
echo "  Installed libraries : libmpc.so   —— 已装（-> $(readlink /usr/lib/libmpc.so 2>/dev/null)）"
echo "  Installed directory : $DOCDIR     —— 已装（$(find "$DOCDIR" -type f 2>/dev/null | wc -l) 个文件）"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.24 MPC-$VER 完成 ====="
