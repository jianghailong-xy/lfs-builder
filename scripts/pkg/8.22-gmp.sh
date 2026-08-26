#!/usr/bin/env bash
# LFS 13.0-systemd §8.22 GMP-6.3.0
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.22.1 Installation of GMP 的命令序列（全部 8 条，一条不多一条不少）：
#   sed -i '/long long t1;/,+1s/()/(...)/' configure
#   ./configure --prefix=/usr    \
#               --enable-cxx     \
#               --disable-static \
#               --docdir=/usr/share/doc/gmp-6.3.0
#   make
#   make html
#   make check 2>&1 | tee gmp-check-log
#   awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log
#   make install
#   make install-html
#
# 本节的提示框共 4 个，逐个处置：
#   Note①（32 位 x86 + CFLAGS 时要加 ABI=32）—— 本机 uname -m = x86_64，且 §7.4 的
#     env -i 环境里没有 CFLAGS，两个前提都不成立，不适用；脚本会把这两点打印出来。
#   Note②（想要通用库可加 --host=none-linux-gnu）—— 是「if ... are desired」的可选项，
#     手册正文命令未加，本节按手册正文原样执行，不加。
#   Important（The test suite for GMP in this section is considered critical.
#     Do not skip it under any circumstances.）—— make check 必跑。
#   Caution（处理器探测偶尔误判会导致 Illegal instruction，此时应加 --host=none-linux-gnu
#     重新配置重建）—— 脚本在 make/make check 的输出里显式搜索 "Illegal instruction"，
#     命中就报出来，不静默放过。
# 手册对结果的唯一量化判据：「Ensure that at least 199 tests in the test suite passed.」
set -euo pipefail

PKG=gmp
VER=6.3.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
DOCDIR=/usr/share/doc/gmp-$VER
CONFLOG=/sources/.gmp-configure.log
MAKELOG=/sources/.gmp-make.log
HTMLLOG=/sources/.gmp-make-html.log
CHECKLOG=/sources/.gmp-make-check.log
INSTLOG=/sources/.gmp-make-install.log
INSTHTMLLOG=/sources/.gmp-make-install-html.log
SUMLOG=/sources/.gmp-test-summary.log

echo "===== LFS 13.0-systemd §8.22 GMP-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The GMP package contains math libraries. These have useful"
echo "  functions for arbitrary precision arithmetic."
echo "手册数据：Approximate build time 0.3 SBU，Required disk space 54 MB"
echo "手册存档：/workspace/docs/book/chapter08-gmp.html（宿主机 \$LFS_ROOT/docs/book/）"
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
echo "----- 手册 Note① 的适用性判定（32 位 x86 + 环境中已设 CFLAGS 才需要 ABI=32） -----"
echo "手册原文：If you are building for 32-bit x86, but you have a CPU which is capable"
echo "  of running 64-bit code and you have specified CFLAGS in the environment, the"
echo "  configure script will attempt to configure for 64-bits and fail. Avoid this by"
echo "  invoking the configure command below with ABI=32 ./configure ..."
echo "  条件 a) 目标是 32 位 x86？uname -m = $(uname -m) —— 否"
if [ -n "${CFLAGS+x}" ]; then
  echo "  条件 b) 环境中已设 CFLAGS？是（CFLAGS='$CFLAGS'）"
else
  echo "  条件 b) 环境中已设 CFLAGS？否（CFLAGS 未设置，§7.4 的 env -i 环境不带它）"
fi
echo "  结论：两个前提均不成立，不使用 ABI=32，按手册正文原样执行 ./configure。"
echo "----- 手册 Note② 的处置（--host=none-linux-gnu 是可选项） -----"
echo "手册原文：The default settings of GMP produce libraries optimized for the host"
echo "  processor. If libraries suitable for processors less capable than the host's CPU"
echo "  are desired, generic libraries can be created by appending the"
echo "  --host=none-linux-gnu option to the configure command."
echo "  本项目产物只在本机（及同款 QEMU/CPU）上运行，不需要降级到通用库，"
echo "  故按手册正文原样执行，不加 --host=none-linux-gnu。"
echo "  本机 CPU：$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -n1)"
echo

echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0
echo "1) 上一任务 §8.21 Binutils-2.46.0 的产物（手册顺序上的前一节，确认其已完成）："
for f in /usr/bin/ld /usr/bin/as /usr/bin/ar /usr/bin/nm /usr/bin/ranlib \
         /usr/bin/objdump /usr/bin/readelf /usr/bin/strip /usr/lib/libbfd.so \
         /usr/lib/libopcodes.so /etc/gprofng.rc; do
  if [ -e "$f" ]; then printf '   OK   %-26s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.21 未完成？）\n' "$f"; rc=1; fi
done
echo "   ld 自述版本：$(ld --version 2>&1 | sed -n 1p)"
echo "   as 自述版本：$(as --version 2>&1 | sed -n 1p)"
echo "   §8.21 要求删除的静态库应已不在（rm -rfv /usr/lib/lib{bfd,ctf,...}.a）："
leftover=$({ ls /usr/lib/libbfd.a /usr/lib/libctf.a /usr/lib/libopcodes.a 2>/dev/null || true; })
if [ -z "$leftover" ]; then echo "     OK   /usr/lib 下无 binutils 静态库"
else echo "     FAIL 仍存在：$leftover"; rc=1; fi
echo "   说明：GMP 的构建全程要用 as/ld/ar/ranlib 汇编与链接（mpn 层是大量 .asm），"
echo "     §8.21 的产物就是本节实际使用的汇编器与链接器。"
echo
echo "2) §8.5 Glibc-2.43 的 C 库与 §6.18/§8.x 的 GCC（本节要编译 C 与 C++）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2 /usr/include/stdio.h; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   g++  版本：$(g++ --version | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("c sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && \
   [ "$("${tmpc%.c}")" = "c sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
tmpx=$(mktemp /tmp/sanity-XXXXXX.cc)
cat > "$tmpx" <<'EOF'
#include <iostream>
int main(){ std::cout << "cxx sanity ok" << std::endl; return 0; }
EOF
if g++ -o "${tmpx%.cc}" "$tmpx" >/dev/null 2>&1 && \
   [ "$("${tmpx%.cc}")" = "cxx sanity ok" ]; then
  echo "   OK   g++ 编译并运行最小 C++ 程序成功（--enable-cxx 的前提）"
else echo "   FAIL 无法用 g++ 编译/运行最小 C++ 程序（--enable-cxx 会失败）"; rc=1; fi
rm -f "$tmpx" "${tmpx%.cc}"
echo
echo "3) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "4) 本节直接依赖的工具（解包 + sed + configure + make + make html + check + 安装）："
for t in tar xz make gcc g++ ld as ar ranlib sed grep awk tee install ln rm mkdir \
         cmp diff md5sum readelf objdump ldd find stat bash sort head tail m4 \
         makeinfo perl; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   makeinfo 版本：$(makeinfo --version 2>&1 | sed -n 1p)"
echo "   说明：手册命令 4/8 的 make html 由 doc/Makefile 调用 makeinfo --html 生成，"
echo "     命令 8/8 的 make install-html 再把它装进 --docdir 指定的目录，"
echo "     故 §7.11 Texinfo 的 makeinfo 是本节的硬依赖。"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   awk  版本：$(awk --version 2>&1 | sed -n 1p)"
echo "   说明：手册命令 6/8 用 awk 在 gmp-check-log 上求 '# PASS:' 第 3 列之和。"
echo
echo "5) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "   本节无补丁（手册 §8.22 未引用任何 patch）；/sources 中匹配 gmp*patch 的文件："
gmp_patches=$({ ls /sources 2>/dev/null | grep -E '^gmp.*patch' || true; })
echo "     ${gmp_patches:-无}"
echo
echo "6) §7.3 虚拟内核文件系统与 §7.6 基础文件（测试程序要读写 /dev、/proc、/tmp）："
for f in /dev/null /dev/zero /dev/full /dev/urandom /dev/tty /proc/self /sys \
         /etc/passwd /etc/group /tmp /var/tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "7) 安装目标目录与安装前的 GMP 痕迹（GMP 是第一次装进本系统）："
for d in /usr/lib /usr/include /usr/lib/pkgconfig /usr/share/info /usr/share/doc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
pre=$({ ls -d /usr/lib/libgmp* /usr/lib/libgmpxx* /usr/include/gmp.h \
        /usr/include/gmpxx.h /usr/lib/pkgconfig/gmp*.pc "$DOCDIR" 2>/dev/null || true; })
if [ -z "$pre" ]; then
  echo "   INFO 系统中当前没有任何 GMP 文件 —— 符合预期：第 5/6 章的 GCC 是把 gmp/mpfr/mpc"
  echo "     解包进 gcc 源码树内联构建的，从未把 GMP 装进 \$LFS，本节是首次安装。"
else
  echo "   INFO 安装前已存在的 GMP 相关文件（本节会覆盖）："; echo "$pre" | sed 's/^/     /'
fi
echo
echo "8) 磁盘空间（手册要求 54 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 204800 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 54 MB"
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
echo "手册 §8.22 全节没有 mkdir build —— GMP 在源码目录内直接 configure（in-tree build）。"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
echo "上游版本自述："
gmp_v=$(sed -n 's/^m4_define(<__GMP_VERSION>, *\([0-9]*\)).*/\1/p' configure.ac | head -n1)
echo "  configure.ac 的 AC_INIT 行：$(grep -n 'AC_INIT' configure.ac | head -n1)"
conf_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'\$/\1/p" configure | head -n1)
conf_str=$(sed -n "s/^PACKAGE_STRING='\(.*\)'\$/\1/p" configure | head -n1)
echo "  configure   ：PACKAGE_VERSION=$conf_ver  PACKAGE_STRING='$conf_str'"
echo "  gmp-h.in 中的版本宏："
grep -nE '^#define __GNU_MP_VERSION' gmp-h.in | sed 's/^/    /'
if [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $conf_ver 与手册 §8.22 的 GMP-$VER 一致"
else echo "  FAIL 源码自述版本为 '$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo
echo "----- 测试结构预读（决定 make check 的判定标准） -----"
echo "顶层 Makefile.am 的 SUBDIRS（make check 会逐个递归）："
grep -E '^SUBDIRS = ' Makefile.am | sed 's/^/  /'
echo "各测试子目录的 check_PROGRAMS/TESTS 声明所在（automake 并行测试框架）："
{ ls tests 2>/dev/null || true; } | sed 's/^/  tests\//'
echo "手册给出的唯一量化判据："
echo "  「Ensure that at least 199 tests in the test suite passed.」"
echo "  「awk '/# PASS:/{total+=\$3} ; END{print total}' gmp-check-log」"
echo "  即：把 gmp-check-log 里所有 automake 汇总块的 '# PASS: N' 相加，要求 >= 199。"
echo "判定标准（本脚本采用，先手册后自加，二者都要满足）："
echo "  硬判据 1（手册）：awk 求和的 PASS 总数 >= 199；"
echo "  硬判据 2（手册 Important：测试 critical，不得跳过）：make check 必须真的跑完，"
echo "    且退出码为 0 —— 手册 §8.22 没有给出任何允许失败的例外说明；"
echo "  硬判据 3（手册 Caution）：输出中不得出现 'Illegal instruction'；"
echo "  硬判据 4（自加，与 1 一致性互校）：汇总块合计 FAIL=0、XPASS=0、ERROR=0。"
echo

echo "================= 8.22.1. Installation of GMP ================="
echo
echo "----- 手册命令 1/8：sed（gcc-15 兼容性调整） -----"
echo "手册原文：First, make an adjustment for compatibility with gcc-15 and later:"
echo "手册命令：sed -i '/long long t1;/,+1s/()/(...)/' configure"
echo "改动前，configure 中匹配 'long long t1;' 的行及其下一行："
{ grep -nA1 'long long t1;' configure || true; } | sed 's/^/  /'
cp -p configure /tmp/gmp-configure.orig
sed -i '/long long t1;/,+1s/()/(...)/' configure
echo "改动后，同样位置："
{ grep -nA1 'long long t1;' configure || true; } | sed 's/^/  /'
echo "sed 造成的完整差异（diff /tmp/gmp-configure.orig configure）："
{ diff /tmp/gmp-configure.orig configure || true; } | sed 's/^/  /'
changed=$({ diff /tmp/gmp-configure.orig configure || true; } | grep -c '^> ' || true)
echo "被改写的行数：$changed"
if [ "$changed" -eq 2 ]; then
  echo "  OK   恰好 2 行被改写（configure 里有两处相同的 __attribute__ 探测片段，"
  echo "       每处把紧随 'typedef unsigned long long t1;' 之后的 'void g(){}'"
  echo "       改成 'void g(...){}'）"
else
  echo "  FAIL 期望改写 2 行，实际 $changed 行" >&2; exit 1
fi
n_new=$(grep -c 'void g(\.\.\.){}' configure || true)
n_old=$(grep -c '^void g(){}' configure || true)
echo "  改写后 'void g(...){}' 出现 $n_new 次，残留的 'void g(){}' 出现 $n_old 次"
if [ "$n_new" -eq 2 ]; then echo "  OK   两处均已改写"
else echo "  FAIL 'void g(...){}' 出现 $n_new 次，期望 2 次" >&2; exit 1; fi
echo "  背景：gcc-15 起 C 语言默认 -std=gnu23，空参数列表 () 等价于 (void)，"
echo "    原来的 'void g(){} void h(){}' 加上后面的 'g == h' 比较会因原型不兼容而报错，"
echo "    导致该 configure 探测误判；改成 (...) 后恢复旧行为。"
rm -f /tmp/gmp-configure.orig
echo

echo "----- 手册命令 2/8：configure -----"
echo "手册原文：Prepare GMP for compilation:"
echo "手册命令：./configure --prefix=/usr    \\"
echo "                     --enable-cxx     \\"
echo "                     --disable-static \\"
echo "                     --docdir=/usr/share/doc/gmp-$VER"
echo "手册对新选项的说明："
echo "  --enable-cxx                      This parameter enables C++ support"
echo "  --docdir=/usr/share/doc/gmp-$VER  This variable specifies the correct place"
echo "                                    for the documentation."
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-$VER > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 60 行："; tail -n 60 "$CONFLOG" | sed 's/^/  /'
  [ -f config.log ] && { echo "config.log 末尾 60 行："; tail -n 60 config.log | sed 's/^/  /'; }
  exit $conf_rc
fi
echo "configure 关键探测结果摘要："
{ grep -E '^checking (build system type|host system type|for (gcc|g\+\+|GNU MP|ABI|the C compiler|C\+\+ compiler)|compiler|whether to enable)' "$CONFLOG" \
  | head -n 30 || true; } | sed 's/^/  /'
echo "configure 选定的 ABI / CPU / 编译选项（GMP 特有）："
{ grep -E '^checking ABI|^checking compiler|^checking for build system compiler|^checking whether assembler|^checking for shared library versioning' "$CONFLOG" \
  | head -n 20 || true; } | sed 's/^/  /'
echo "configure 末尾 20 行："
tail -n 20 "$CONFLOG" | sed 's/^/  /'
echo
echo "----- 核对手册给的 4 个选项确实生效 -----"
crc=0
echo "a) --prefix=/usr"
grep -E '^(prefix|exec_prefix|libdir|includedir|infodir|docdir|datarootdir) = ' Makefile | sed 's/^/     /'
got_prefix=$(sed -n 's/^prefix = //p' Makefile | head -n1)
if [ "$got_prefix" = /usr ]; then echo "     OK   prefix = /usr"
else echo "     FAIL prefix 为 '$got_prefix'，不是 /usr"; crc=1; fi
got_libdir=$(sed -n 's/^libdir = //p' Makefile | head -n1)
got_incdir=$(sed -n 's/^includedir = //p' Makefile | head -n1)
echo "     INFO libdir = $got_libdir，includedir = $got_incdir（均由 --prefix=/usr 展开）"
echo "b) --docdir=$DOCDIR"
got_docdir=$(sed -n 's/^docdir = //p' Makefile | head -n1)
if [ "$got_docdir" = "$DOCDIR" ]; then echo "     OK   docdir = $got_docdir"
else echo "     FAIL docdir 为 '$got_docdir'，不是 $DOCDIR"; crc=1; fi
echo "c) --enable-cxx"
echo "     顶层 Makefile 中的 WANT_CXX 条件产物（GMPXX_LTLIBRARIES_OPTION / include_HEADERS）："
{ grep -E '^(GMPXX_LTLIBRARIES_OPTION|GMPXX_HEADERS_OPTION|lib_LTLIBRARIES|include_HEADERS|pkgconfig_DATA) = ' Makefile || true; } | sed 's/^/       /'
cxx_lib=$(sed -n 's/^GMPXX_LTLIBRARIES_OPTION = //p' Makefile | head -n1)
cxx_hdr=$(sed -n 's/^GMPXX_HEADERS_OPTION = //p' Makefile | head -n1)
if [ "$cxx_lib" = "libgmpxx.la" ] && [ "$cxx_hdr" = "gmpxx.h" ]; then
  echo "     OK   C++ 支持已开启（将构建 libgmpxx.la 并安装 gmpxx.h）"
else
  echo "     FAIL C++ 支持未开启（GMPXX_LTLIBRARIES_OPTION='$cxx_lib' GMPXX_HEADERS_OPTION='$cxx_hdr'）"; crc=1
fi
echo "     cxx 子目录的 Makefile 是否生成："
if [ -f cxx/Makefile ]; then echo "       OK   cxx/Makefile 存在"
else echo "       FAIL cxx/Makefile 未生成"; crc=1; fi
echo "     config.log 中的 --enable-cxx 记录："
{ grep -m1 -- '--enable-cxx' config.log || true; } | sed 's/^/       /'
echo "d) --disable-static"
{ grep -E '^(enable_static|enable_shared) = ' Makefile || true; } | sed 's/^/       /'
echo "     libtool 的 build_old_libs / build_libtool_libs："
{ grep -E '^(build_old_libs|build_libtool_libs)=' libtool || true; } | sed 's/^/       /'
old_libs=$(sed -n 's/^build_old_libs=//p' libtool | head -n1)
new_libs=$(sed -n 's/^build_libtool_libs=//p' libtool | head -n1)
if [ "$old_libs" = "no" ]; then echo "     OK   build_old_libs=no（不构建 .a 静态库）"
else echo "     FAIL build_old_libs='$old_libs'，--disable-static 未生效"; crc=1; fi
if [ "$new_libs" = "yes" ]; then echo "     OK   build_libtool_libs=yes（构建共享库）"
else echo "     FAIL build_libtool_libs='$new_libs'"; crc=1; fi
echo "e) 生成的 gmp.h 与 pkg-config 文件"
if [ -f gmp.h ]; then
  echo "     OK   gmp.h 已生成（$(wc -l < gmp.h) 行）"
  { grep -E '^#define __GNU_MP_VERSION' gmp.h || true; } | sed 's/^/       /'
  h_major=$(sed -n 's/^#define __GNU_MP_VERSION  *//p' gmp.h | head -n1)
  h_minor=$(sed -n 's/^#define __GNU_MP_VERSION_MINOR  *//p' gmp.h | head -n1)
  h_patch=$(sed -n 's/^#define __GNU_MP_VERSION_PATCHLEVEL  *//p' gmp.h | head -n1)
  if [ "$h_major.$h_minor.$h_patch" = "$VER" ]; then
    echo "       OK   gmp.h 自述版本 $h_major.$h_minor.$h_patch = $VER"
  else
    echo "       FAIL gmp.h 自述版本 $h_major.$h_minor.$h_patch 与 $VER 不符"; crc=1
  fi
else echo "     FAIL gmp.h 未生成"; crc=1; fi
for f in gmp.pc gmpxx.pc; do
  if [ -f "$f" ]; then printf '     OK   %s 已生成\n' "$f"; sed 's/^/       /' "$f"
  else printf '     FAIL %s 未生成\n' "$f"; crc=1; fi
done
echo "f) 各子目录 Makefile 是否齐备（顶层 SUBDIRS 的每一项）："
for d in tests mpn mpz mpq mpf printf scanf rand cxx demos tune doc; do
  if [ -f "$d/Makefile" ]; then printf '     OK   %s/Makefile\n' "$d"
  else printf '     FAIL %s/Makefile 未生成\n' "$d"; crc=1; fi
done
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册 §8.22 的 4 个选项"
echo

echo "----- 手册命令 3/8：make -----"
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
ill=$(grep -c 'Illegal instruction' "$MAKELOG" || true)
if [ "$ill" -eq 0 ]; then
  echo "  OK   make 输出中无 'Illegal instruction'（手册 Caution 关注的症状）"
else
  echo "  FAIL make 输出中出现 $ill 处 'Illegal instruction' —— 手册 Caution 要求改用"
  echo "       --host=none-linux-gnu 重新配置重建" >&2
  { grep -n 'Illegal instruction' "$MAKELOG" || true; } | sed 's/^/    /' >&2
  exit 1
fi
echo "make 输出末尾 10 行："
tail -n 10 "$MAKELOG" | sed 's/^/  /'
echo
echo "----- 编译结果确认 -----"
mrc=0
echo "  libtool 归档与 .libs 下的共享库实体："
{ ls -l libgmp.la libgmpxx.la 2>/dev/null || true; } | sed 's/^/    /'
{ ls -l .libs/libgmp.so* .libs/libgmpxx.so* 2>/dev/null || true; } | sed 's/^/    /'
for f in libgmp.la libgmpxx.la; do
  if [ -f "$f" ]; then printf '    OK   %s\n' "$f"; else printf '    FAIL %s 未生成\n' "$f"; mrc=1; fi
done
gmp_so=$({ ls .libs/libgmp.so.*.*.* 2>/dev/null || true; } | head -n1)
gmpxx_so=$({ ls .libs/libgmpxx.so.*.*.* 2>/dev/null || true; } | head -n1)
if [ -n "$gmp_so" ]; then
  printf '    OK   %s（%s 字节，%s）\n' "$gmp_so" "$(stat -Lc %s "$gmp_so")" "$(file -b "$gmp_so" | cut -d, -f1-2)"
else echo "    FAIL 未生成 .libs/libgmp.so.*"; mrc=1; fi
if [ -n "$gmpxx_so" ]; then
  printf '    OK   %s（%s 字节，%s）—— --enable-cxx 的产物\n' "$gmpxx_so" "$(stat -Lc %s "$gmpxx_so")" "$(file -b "$gmpxx_so" | cut -d, -f1-2)"
else echo "    FAIL 未生成 .libs/libgmpxx.so.*（--enable-cxx 未产出 C++ 库）"; mrc=1; fi
echo "  --disable-static 的验证：构建目录内不应有 libgmp.a / libgmpxx.a"
stat_a=$({ ls .libs/libgmp.a .libs/libgmpxx.a 2>/dev/null || true; })
if [ -z "$stat_a" ]; then echo "    OK   构建目录内无静态库"
else echo "    FAIL 生成了静态库：$stat_a"; mrc=1; fi
echo "  SONAME（GMP 自己在 Makefile.am 里定的 libtool 版本号）："
for so in "$gmp_so" "$gmpxx_so"; do
  [ -n "$so" ] || continue
  printf '    %-34s SONAME=%s\n' "$so" "$(readelf -d "$so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')"
done
echo "  未安装产物的冒烟测试（直接链接构建目录里的 libgmp）："
tmpd=$(mktemp -d /tmp/gmp-build-smoke-XXXXXX)
cat > "$tmpd/s.c" <<'EOF'
#include <stdio.h>
#include <gmp.h>
int main(void){
  mpz_t a, b, r; mpz_init_set_ui(a, 2); mpz_init_set_ui(b, 0); mpz_init(r);
  mpz_pow_ui(r, a, 128);
  gmp_printf("2^128=%Zd\n", r);
  printf("version=%s\n", gmp_version);
  return 0;
}
EOF
if gcc -o "$tmpd/s" "$tmpd/s.c" -I. -L.libs -lgmp >/dev/null 2>&1; then
  smoke=$(LD_LIBRARY_PATH=$PWD/.libs "$tmpd/s" 2>&1)
  echo "$smoke" | sed 's/^/    /'
  exp="2^128=340282366920938463463374607431768211456"
  case "$smoke" in
    *"$exp"*) echo "    OK   2^128 计算结果正确" ;;
    *) echo "    FAIL 2^128 计算结果不正确"; mrc=1 ;;
  esac
  case "$smoke" in
    *"version=$VER"*) echo "    OK   构建产物自述版本 $VER" ;;
    *) echo "    FAIL 构建产物自述版本不是 $VER"; mrc=1 ;;
  esac
else
  echo "    FAIL 无法链接构建目录里的 libgmp"; mrc=1
fi
rm -rf "$tmpd"
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 4/8：make html -----"
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
sed 's/^/  /' "$HTMLLOG"
echo "生成的 HTML 文档（doc/ 下）："
{ ls -ld doc/gmp.html* 2>/dev/null || true; } | sed 's/^/  /'
hrc=0
if [ -d doc/gmp.html ]; then
  echo "  OK   doc/gmp.html/ 是按节点拆分的目录，共 $(ls doc/gmp.html | wc -l) 个文件"
  echo "  前 10 个文件："; { ls doc/gmp.html | head -n 10 || true; } | sed 's/^/    /'
  [ -f doc/gmp.html/index.html ] && echo "  OK   doc/gmp.html/index.html 存在" \
    || { echo "  FAIL doc/gmp.html/index.html 缺失"; hrc=1; }
elif [ -f doc/gmp.html ]; then
  echo "  OK   doc/gmp.html 是单文件（$(stat -Lc %s doc/gmp.html) 字节）"
else
  echo "  FAIL 未生成 doc/gmp.html"; hrc=1
fi
echo "  同时确认 info 文档已由上一条 make 生成（info_TEXINFOS = gmp.texi）："
if [ -f doc/gmp.info ]; then echo "    OK   doc/gmp.info（$(stat -Lc %s doc/gmp.info) 字节）"
else echo "    INFO doc/gmp.info 不在 doc/ 下，查找："; { find . -name 'gmp.info*' || true; } | sed 's/^/      /'; fi
[ $hrc -eq 0 ] || { echo "错误：make html 未产出预期文档" >&2; exit 1; }
echo

echo "----- 手册命令 5/8：make check（本节的测试） -----"
echo "手册 Important 原文：The test suite for GMP in this section is considered critical."
echo "  Do not skip it under any circumstances."
echo "手册原文：Test the results:"
echo "手册命令：make check 2>&1 | tee gmp-check-log"
echo "（按手册原样带 tee 执行：gmp-check-log 落在源码目录，供下一条 awk 命令读取；"
echo "  同时复制一份到 $CHECKLOG 以便宿主机侧留档。"
echo "  注意本脚本用 PIPESTATUS 取 make 自己的退出码，而不是 tee 的退出码 ——"
echo "  PIPESTATUS 会被紧随其后的任何一条命令（包括赋值本身）重置，所以必须一次性"
echo "  整个数组复制出来，不能先读 [0] 再读 [1]。）"
set +e
make check 2>&1 | tee gmp-check-log
pipe_st=("${PIPESTATUS[@]}")
set -e
check_rc=${pipe_st[0]}
tee_rc=${pipe_st[1]}
cp -p gmp-check-log "$CHECKLOG"
echo
echo "----- make check 结论 -----"
echo "make check 退出码（PIPESTATUS[0]）：$check_rc；tee 退出码：$tee_rc"
echo "gmp-check-log 行数：$(wc -l < gmp-check-log)"
echo
echo "手册命令 6/8：awk '/# PASS:/{total+=\$3} ; END{print total}' gmp-check-log"
pass_total=$(awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log)
echo "  输出：$pass_total"
if [ -z "$pass_total" ]; then
  echo "  注意：手册命令输出为空 —— gmp-check-log 中一条 '# PASS:' 都没有，"
  echo "    说明测试汇总块未产生（测试根本没跑起来）。断言按 0 处理。"
  pass_total=0
fi
echo "手册判据：Ensure that at least 199 tests in the test suite passed."
echo
echo "各 automake 汇总块（Testsuite summary）逐个列出："
{ grep -nE '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary|=+)' gmp-check-log || true; } \
  | sed 's/^/  /'
echo
sum_of() { awk -v k="$1" '$0 ~ "^# "k": " {s += $3} END {print s+0}' gmp-check-log; }
t_total=$(sum_of TOTAL); t_pass=$(sum_of PASS);   t_fail=$(sum_of FAIL)
t_skip=$(sum_of SKIP);   t_xfail=$(sum_of XFAIL); t_xpass=$(sum_of XPASS)
t_err=$(sum_of ERROR)
echo "全部汇总块合计："
printf '  TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
  "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
echo "非 PASS 的逐项结果（FAIL/XFAIL/XPASS/ERROR/SKIP）："
{ grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' gmp-check-log || true; } | sed 's/^/  /'
echo "PASS 行条数（逐项，供与 '# PASS:' 求和互校）：$(grep -cE '^PASS: ' gmp-check-log || true)"
echo
{
  echo "===== §8.22 GMP-$VER 测试汇总 ====="
  echo "make check 退出码：$check_rc"
  echo "手册 awk 判据的 PASS 总数：$pass_total（要求 >= 199）"
  printf 'TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
    "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
  echo "----- 非 PASS 项 -----"
  { grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' gmp-check-log || true; }
  echo "----- 各汇总块 -----"
  { grep -E '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary)' gmp-check-log || true; }
} > "$SUMLOG"
trc=0
echo "判据核对："
if [ "$check_rc" -eq 0 ]; then
  echo "  OK   硬判据 2：make check 退出码 0（手册 §8.22 未给出任何允许失败的例外）"
else
  echo "  FAIL 硬判据 2：make check 退出码 $check_rc"; trc=1
fi
if [ "$pass_total" -ge 199 ]; then
  echo "  OK   硬判据 1（手册）：PASS 总数 $pass_total >= 199"
else
  echo "  FAIL 硬判据 1（手册）：PASS 总数 $pass_total < 199"; trc=1
fi
ill=$(grep -c 'Illegal instruction' gmp-check-log || true)
if [ "$ill" -eq 0 ]; then
  echo "  OK   硬判据 3（手册 Caution）：测试输出中无 'Illegal instruction'"
else
  echo "  FAIL 硬判据 3（手册 Caution）：出现 $ill 处 'Illegal instruction'，"
  echo "       按手册应改用 --host=none-linux-gnu 重新配置重建"
  { grep -n 'Illegal instruction' gmp-check-log || true; } | sed 's/^/    /'
  trc=1
fi
[ "$t_fail"  = 0 ] || { echo "  FAIL 硬判据 4：汇总 FAIL=$t_fail"; trc=1; }
[ "$t_err"   = 0 ] || { echo "  FAIL 硬判据 4：汇总 ERROR=$t_err"; trc=1; }
[ "$t_xpass" = 0 ] || { echo "  FAIL 硬判据 4：汇总 XPASS=$t_xpass"; trc=1; }
if [ "$t_fail" = 0 ] && [ "$t_err" = 0 ] && [ "$t_xpass" = 0 ]; then
  echo "  OK   硬判据 4（自加）：FAIL=0、XPASS=0、ERROR=0"
fi
if [ "$t_total" -gt 0 ] && [ "$((t_pass + t_skip + t_xfail + t_fail + t_xpass + t_err))" = "$t_total" ]; then
  echo "  OK   汇总自洽：PASS+SKIP+XFAIL+FAIL+XPASS+ERROR = TOTAL($t_total)"
else
  echo "  FAIL 汇总不自洽：各项之和 != TOTAL($t_total)"; trc=1
fi
if [ $trc -ne 0 ]; then
  echo "错误：测试结果不符合手册要求；完整输出见 $CHECKLOG" >&2
  echo "  make check 末尾 80 行：" >&2
  tail -n 80 gmp-check-log | sed 's/^/  /' >&2
  exit 1
fi
echo
echo "测试结论：手册 §8.22 的 Important 要求本节测试必跑，本次已完整跑完 make check。"
echo "  手册量化判据 PASS 总数 = $pass_total（>= 199 ✓）；"
echo "  automake 汇总合计 TOTAL=$t_total PASS=$t_pass SKIP=$t_skip XFAIL=$t_xfail，"
echo "  FAIL=0、XPASS=0、ERROR=0；无 'Illegal instruction'（手册 Caution 未触发）。"
echo

echo "----- 手册命令 7/8：make install -----"
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

echo "----- 手册命令 8/8：make install-html -----"
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
echo "make install-html 输出："
sed 's/^/  /' "$INSTHTMLLOG"
echo

echo "----- 安装后检查（手册 §8.22.2 Contents of GMP） -----"
echo "手册列出的内容："
echo "  Installed libraries: libgmp.so and libgmpxx.so"
echo "  Installed directory: /usr/share/doc/gmp-$VER"
echo "  libgmp   ：Contains precision math functions"
echo "  libgmpxx ：Contains C++ precision math functions"
rc=0
echo
echo "1) Installed libraries（手册明确列出的两个）："
for base in libgmp libgmpxx; do
  if [ -L "/usr/lib/$base.so" ]; then
    printf '   OK   /usr/lib/%s.so -> %s\n' "$base" "$(readlink /usr/lib/$base.so)"
  elif [ -e "/usr/lib/$base.so" ]; then
    printf '   OK   /usr/lib/%s.so（普通文件，%s 字节）\n' "$base" "$(stat -Lc %s /usr/lib/$base.so)"
  else
    printf '   FAIL /usr/lib/%s.so 缺失\n' "$base"; rc=1
  fi
done
echo "   /usr/lib 下全部 GMP 库文件："
{ ls -l /usr/lib/libgmp.* /usr/lib/libgmp.so.* /usr/lib/libgmpxx.* /usr/lib/libgmpxx.so.* 2>/dev/null || true; } | sort -u -k9 | sed 's/^/     /'
echo "   共享库实体的 SONAME 与类型："
for so in $({ ls /usr/lib/libgmp.so.*.*.* /usr/lib/libgmpxx.so.*.*.* 2>/dev/null || true; }); do
  printf '     %-32s %s\n' "$(basename "$so")" "$(file -b "$so" | cut -d, -f1-2)"
  printf '     %-32s SONAME=%s\n' "" "$(readelf -d "$so" | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')"
done
echo
echo "2) --disable-static 的验证：/usr/lib 下不应出现 libgmp.a / libgmpxx.a"
stale=$({ ls /usr/lib/libgmp.a /usr/lib/libgmpxx.a 2>/dev/null || true; })
if [ -z "$stale" ]; then echo "   OK   未安装任何 GMP 静态库"
else echo "   FAIL 存在静态库：$stale"; rc=1; fi
echo "   libtool 归档（.la，LFS 未要求删除，仅记录）："
{ ls -l /usr/lib/libgmp.la /usr/lib/libgmpxx.la 2>/dev/null || echo "     （无）"; } | sed 's/^/     /'
echo
echo "3) 头文件（手册 Contents 未单列，但 make install 会装，后续 §8.23 MPFR 依赖 gmp.h）："
for f in /usr/include/gmp.h /usr/include/gmpxx.h; do
  if [ -f "$f" ]; then printf '   OK   %-24s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   已安装 gmp.h 的版本宏："
{ grep -E '^#define __GNU_MP_VERSION' /usr/include/gmp.h || true; } | sed 's/^/     /'
i_major=$(sed -n 's/^#define __GNU_MP_VERSION  *//p' /usr/include/gmp.h | head -n1)
i_minor=$(sed -n 's/^#define __GNU_MP_VERSION_MINOR  *//p' /usr/include/gmp.h | head -n1)
i_patch=$(sed -n 's/^#define __GNU_MP_VERSION_PATCHLEVEL  *//p' /usr/include/gmp.h | head -n1)
if [ "$i_major.$i_minor.$i_patch" = "$VER" ]; then
  echo "     OK   已安装 gmp.h 自述版本 $i_major.$i_minor.$i_patch = $VER"
else echo "     FAIL 已安装 gmp.h 自述版本 $i_major.$i_minor.$i_patch 与 $VER 不符"; rc=1; fi
echo
echo "4) pkg-config 文件（Makefile.am：pkgconfig_DATA = gmp.pc，WANT_CXX 时追加 gmpxx.pc）："
for f in /usr/lib/pkgconfig/gmp.pc /usr/lib/pkgconfig/gmpxx.pc; do
  if [ -f "$f" ]; then
    printf '   OK   %s\n' "$f"; sed 's/^/     /' "$f"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   用 §8.20 的 pkgconf 查询（验证 .pc 可被解析）："
if command -v pkgconf >/dev/null 2>&1 || command -v pkg-config >/dev/null 2>&1; then
  pc=$(command -v pkg-config 2>/dev/null || command -v pkgconf)
  echo "     $pc --modversion gmp   : $("$pc" --modversion gmp 2>&1)"
  echo "     $pc --modversion gmpxx : $("$pc" --modversion gmpxx 2>&1)"
  echo "     $pc --libs gmp         : $("$pc" --libs gmp 2>&1)"
  echo "     $pc --libs gmpxx       : $("$pc" --libs gmpxx 2>&1)"
  pcver=$("$pc" --modversion gmp 2>/dev/null || true)
  if [ "$pcver" = "$VER" ]; then echo "     OK   pkg-config 报告的 gmp 版本 = $VER"
  else echo "     FAIL pkg-config 报告的 gmp 版本 '$pcver' 与 $VER 不符"; rc=1; fi
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
  if [ "$nfile" -gt 0 ]; then echo "   OK   文档目录非空（make install-html 的产物）"
  else echo "   FAIL 文档目录为空"; rc=1; fi
  idx=$({ find "$DOCDIR" -type f \( -name 'index.html' -o -name 'gmp.html' \) | head -n 3 || true; })
  if [ -n "$idx" ]; then
    echo "   HTML 入口："; echo "$idx" | sed 's/^/     /'
    first_html=$(echo "$idx" | head -n1)
    echo "   入口文件首行：$(head -n1 "$first_html")"
    echo "   入口文件中出现的 GMP 版本串："
    { grep -o "GNU MP [0-9.]*" "$first_html" | head -n 3 || true; } | sed 's/^/     /'
  else
    echo "   FAIL 文档目录下没有 index.html / gmp.html"; rc=1
  fi
else
  echo "   FAIL $DOCDIR 不存在"; rc=1
fi
echo
echo "6) info 文档（info_TEXINFOS = gmp.texi，由 make install 安装）："
for f in /usr/share/info/gmp.info; do
  if [ -e "$f" ]; then printf '   OK   %-30s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   INFO %s 不存在，查找实际落点：\n' "$f"
       { find /usr/share/info -name 'gmp.info*' || true; } | sed 's/^/     /'; fi
done
echo "   /usr/share/info 中的 gmp 条目："
{ ls /usr/share/info | grep -i gmp || echo "（无）"; } | sed 's/^/     /'
echo
echo "7) 动态链接器缓存与库可见性（后续 §8.23 MPFR 的 configure 要找到 libgmp）："
echo "   /etc/ld.so.conf（若存在）："
{ cat /etc/ld.so.conf 2>/dev/null || echo "     （无 /etc/ld.so.conf —— LFS 到 §8.x 尚未创建，属正常）"; } | sed 's/^/     /'
echo "   libgmp.so 的动态依赖："
{ ldd /usr/lib/libgmp.so || true; } | sed 's/^/     /'
echo "   libgmpxx.so 的动态依赖（应含 libgmp 与 libstdc++）："
{ ldd /usr/lib/libgmpxx.so || true; } | sed 's/^/     /'
xxdep=$({ ldd /usr/lib/libgmpxx.so || true; })
case "$xxdep" in
  *libgmp.so*) echo "     OK   libgmpxx.so 链接到 libgmp.so" ;;
  *) echo "     FAIL libgmpxx.so 未链接 libgmp.so"; rc=1 ;;
esac
case "$xxdep" in
  *libstdc++*) echo "     OK   libgmpxx.so 链接到 libstdc++" ;;
  *) echo "     FAIL libgmpxx.so 未链接 libstdc++"; rc=1 ;;
esac
case "$xxdep" in
  */tools/*) echo "     FAIL 仍链接 /tools 下的库"; rc=1 ;;
  *) echo "     OK   未链接任何 /tools 路径" ;;
esac
echo
echo "----- 功能验证（对照手册 §8.22.2 的两句说明，用已安装的库逐项验证） -----"
echo "手册：libgmp —— Contains precision math functions"
echo "手册：libgmpxx —— Contains C++ precision math functions"
tmpd=$(mktemp -d /tmp/gmp-verify-XXXXXX)
echo "a) libgmp 的任意精度整数（mpz）—— 2^1000 与 100! 的精确值位数："
cat > "$tmpd/a.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <gmp.h>
/* 用 mpz_get_str 的实际串长取位数：mpz_sizeinbase 在非 2 的幂进制下可能大 1 */
static size_t digits10(const mpz_t x){
  char *s = mpz_get_str(NULL, 10, x); size_t n = strlen(s); free(s); return n;
}
int main(void){
  mpz_t r, f; unsigned long i;
  mpz_init(r); mpz_ui_pow_ui(r, 2, 1000);
  printf("digits(2^1000)=%zu\n", digits10(r));
  mpz_init_set_ui(f, 1);
  for (i = 2; i <= 100; i++) mpz_mul_ui(f, f, i);
  printf("digits(100!)=%zu\n", digits10(f));
  printf("gmp_version=%s\n", gmp_version);
  mpz_clear(r); mpz_clear(f);
  return 0;
}
EOF
if gcc -o "$tmpd/a" "$tmpd/a.c" -lgmp > "$tmpd/a.cc.log" 2>&1; then
  out_a=$("$tmpd/a" 2>&1)
  echo "$out_a" | sed 's/^/     /'
  case "$out_a" in
    *"digits(2^1000)=302"*) echo "     OK   2^1000 有 302 位十进制数字" ;;
    *) echo "     FAIL 2^1000 位数不是 302"; rc=1 ;;
  esac
  case "$out_a" in
    *"digits(100!)=158"*) echo "     OK   100! 有 158 位十进制数字" ;;
    *) echo "     FAIL 100! 位数不是 158"; rc=1 ;;
  esac
  case "$out_a" in
    *"gmp_version=$VER"*) echo "     OK   已安装库自述版本 $VER" ;;
    *) echo "     FAIL 已安装库自述版本不是 $VER"; rc=1 ;;
  esac
else
  echo "     FAIL 无法用已安装的 gmp.h + -lgmp 编译 C 程序："; sed 's/^/       /' "$tmpd/a.cc.log"; rc=1
fi
echo "b) libgmp 的任意精度有理数（mpq）与浮点数（mpf）："
cat > "$tmpd/b.c" <<'EOF'
#include <stdio.h>
#include <gmp.h>
int main(void){
  mpq_t q; mpf_t f;
  mpq_init(q); mpq_set_ui(q, 1, 3); mpq_canonicalize(q);
  gmp_printf("1/3=%Qd\n", q);
  mpf_set_default_prec(256);
  mpf_init(f); mpf_sqrt_ui(f, 2);
  gmp_printf("sqrt2=%.20Ff\n", f);
  mpq_clear(q); mpf_clear(f);
  return 0;
}
EOF
if gcc -o "$tmpd/b" "$tmpd/b.c" -lgmp > "$tmpd/b.cc.log" 2>&1; then
  out_b=$("$tmpd/b" 2>&1)
  echo "$out_b" | sed 's/^/     /'
  case "$out_b" in
    *"1/3=1/3"*) echo "     OK   mpq 有理数正常" ;;
    *) echo "     FAIL mpq 输出不是 1/3"; rc=1 ;;
  esac
  case "$out_b" in
    *"sqrt2=1.41421356237309504880"*) echo "     OK   mpf 的 sqrt(2) 前 20 位小数正确" ;;
    *) echo "     FAIL mpf 的 sqrt(2) 前 20 位小数不正确（期望 1.41421356237309504880）"; rc=1 ;;
  esac
else
  echo "     FAIL 无法编译 mpq/mpf 测试程序："; sed 's/^/       /' "$tmpd/b.cc.log"; rc=1
fi
echo "c) libgmpxx 的 C++ 接口（--enable-cxx 的直接验证：gmpxx.h + -lgmpxx）："
cat > "$tmpd/c.cpp" <<'EOF'
#include <iostream>
#include <gmpxx.h>
int main(){
  mpz_class a("123456789012345678901234567890");
  mpz_class b = a * a;
  std::cout << "square=" << b << std::endl;
  mpq_class q(1, 7);
  std::cout << "1/7=" << q << std::endl;
  mpf_class f(0, 256);
  f = sqrt(mpf_class(2, 256));
  std::cout << "cxx_ok" << std::endl;
  return 0;
}
EOF
if g++ -o "$tmpd/c" "$tmpd/c.cpp" -lgmpxx -lgmp > "$tmpd/c.cc.log" 2>&1; then
  out_c=$("$tmpd/c" 2>&1)
  echo "$out_c" | sed 's/^/     /'
  exp_sq="square=15241578753238836750495351562536198787501905199875019052100"
  case "$out_c" in
    *"$exp_sq"*) echo "     OK   mpz_class 大整数平方结果正确" ;;
    *) echo "     FAIL mpz_class 平方结果不正确"; rc=1 ;;
  esac
  case "$out_c" in
    *"1/7=1/7"*) echo "     OK   mpq_class 有理数正常" ;;
    *) echo "     FAIL mpq_class 输出不是 1/7"; rc=1 ;;
  esac
  case "$out_c" in
    *cxx_ok*) echo "     OK   C++ 精度数学接口（手册所述 libgmpxx 的职责）可用" ;;
    *) echo "     FAIL C++ 程序未正常结束"; rc=1 ;;
  esac
  echo "     该 C++ 程序的动态依赖："; { ldd "$tmpd/c" || true; } | sed 's/^/       /'
else
  echo "     FAIL 无法用 gmpxx.h + -lgmpxx 编译 C++ 程序（--enable-cxx 未真正可用）："
  sed 's/^/       /' "$tmpd/c.cc.log"; rc=1
fi
echo "d) 后续包的可用性预演（§8.23 MPFR 的 configure 会做的事：找到 gmp.h 与 -lgmp）："
cat > "$tmpd/d.c" <<'EOF'
#include <gmp.h>
int main(void){
#if __GNU_MP_VERSION < 6
#error "gmp too old"
#endif
  mpz_t t; mpz_init(t); mpz_clear(t); return 0;
}
EOF
if gcc -o "$tmpd/d" "$tmpd/d.c" -lgmp > "$tmpd/d.cc.log" 2>&1 && "$tmpd/d"; then
  echo "     OK   默认搜索路径下即可 #include <gmp.h> 并 -lgmp 链接运行（无需额外 -I/-L）"
else
  echo "     FAIL 默认搜索路径下无法使用 gmp："; sed 's/^/       /' "$tmpd/d.cc.log"; rc=1
fi
rm -rf "$tmpd"
echo
echo "8) 本节写入系统的文件清单（按 install 日志与实际落点核对）："
{ ls -l /usr/lib/libgmp.* /usr/lib/libgmp.so.* /usr/lib/libgmpxx.* /usr/lib/libgmpxx.so.* /usr/include/gmp.h /usr/include/gmpxx.h \
       /usr/lib/pkgconfig/gmp.pc /usr/lib/pkgconfig/gmpxx.pc 2>/dev/null || true; } | sed 's/^/     /'
echo "   $DOCDIR：$(find "$DOCDIR" -type f 2>/dev/null | wc -l) 个文件"
echo "   /usr/share/info 下的 gmp*：$({ ls /usr/share/info/gmp* 2>/dev/null || true; } | tr '\n' ' ')"
[ $rc -eq 0 ] || { echo "错误：GMP 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.22.sh"
echo "  移入 \$LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure         完整输出：$CONFLOG"
echo "  make              完整输出：$MAKELOG"
echo "  make html         完整输出：$HTMLLOG"
echo "  make check        完整输出：$CHECKLOG（= 手册的 gmp-check-log 副本）"
echo "  make install      完整输出：$INSTLOG"
echo "  make install-html 完整输出：$INSTHTMLLOG"
echo "  测试汇总          ：$SUMLOG"
echo "清理前 /sources 下的 gmp 相关条目："
{ ls -d /sources/gmp* 2>/dev/null || true; } | sed 's/^/  /'
echo "  待删除：$(du -sh "/sources/$SRCDIR" 2>/dev/null | cut -f1)	/sources/$SRCDIR"
cd /sources
rm -rf "$SRCDIR"
if [ -d "/sources/$SRCDIR" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCDIR（手册的 gmp-check-log 在其中，副本已留在 $CHECKLOG）"
echo "清理后 /sources 下的 gmp 相关条目（应只剩 tarball）："
{ ls -d /sources/gmp* 2>/dev/null || true; } | sed 's/^/  /'
echo "  OK   源码构建目录已删除"
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -mindepth 1 -type d || true; } | sed 's/^/  /'
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo

echo "================= 本节结论 ================="
echo "手册 §8.22 的 8 条命令全部按原样执行完毕："
echo "  1. sed -i '/long long t1;/,+1s/()/(...)/' configure  —— 完成，恰好 2 行被改写"
echo "  2. ./configure --prefix=/usr --enable-cxx --disable-static --docdir=$DOCDIR"
echo "                                                      —— 完成，4 个选项逐条核对生效"
echo "  3. make                                             —— 完成"
echo "  4. make html                                        —— 完成"
echo "  5. make check 2>&1 | tee gmp-check-log              —— 完成，退出码 $check_rc"
echo "  6. awk '/# PASS:/{total+=\$3} ; END{print total}'    —— 完成，输出 $pass_total"
echo "  7. make install                                     —— 完成"
echo "  8. make install-html                                —— 完成"
echo
echo "测试结论（手册 Important：本节测试 critical，不得跳过）："
echo "  PASS 总数（手册 awk 判据）: $pass_total   要求 >= 199"
echo "  TOTAL                     : $t_total"
echo "  PASS                      : $t_pass"
echo "  FAIL                      : $t_fail（要求 0）"
echo "  SKIP                      : $t_skip"
echo "  XFAIL                     : $t_xfail"
echo "  XPASS                     : $t_xpass（要求 0）"
echo "  ERROR                     : $t_err（要求 0）"
echo "  Illegal instruction       : 0（手册 Caution 未触发，无需 --host=none-linux-gnu）"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.22 GMP-$VER 完成 ====="
