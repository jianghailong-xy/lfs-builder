#!/usr/bin/env bash
# LFS 13.0-systemd §8.13 Pcre2-10.47
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.13.1 Installation of Pcre2 的命令序列（全部，一条不多一条不少）：
#   ./configure --prefix=/usr                       \
#               --docdir=/usr/share/doc/pcre2-10.47 \
#               --enable-unicode                    \
#               --enable-jit                        \
#               --enable-pcre2-16                   \
#               --enable-pcre2-32                   \
#               --enable-pcre2grep-libz             \
#               --enable-pcre2grep-libbz2           \
#               --enable-pcre2test-libreadline      \
#               --disable-static
#   make
#   make check
#   make install
# 本节没有 sed、没有 patch、没有可选命令。
set -euo pipefail

PKG=pcre2
VER=10.47
TARBALL=$PKG-$VER.tar.bz2
SRCDIR=$PKG-$VER
DOCDIR=/usr/share/doc/pcre2-$VER
CONFLOG=/sources/.pcre2-configure.log
MAKELOG=/sources/.pcre2-make.log
CHECKLOG=/sources/.pcre2-make-check.log
INSTLOG=/sources/.pcre2-make-install.log

echo "===== LFS 13.0-systemd §8.13 Pcre2-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The pcre2 package contains a new generation of the Perl Compatible"
echo "  Regular Expression libraries."
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 28 MB"
echo "手册存档：/workspace/docs/book/chapter08-pcre2.html（宿主机 \$LFS_ROOT/docs/book/）"
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
echo "1) §8.12 Readline-8.3 的关键产物 —— 手册 --enable-pcre2test-libreadline 要求"
echo "   readline/readline.h、readline/history.h 与可链接的 libreadline："
for f in /usr/lib/libreadline.so /usr/lib/libreadline.so.8 /usr/lib/libhistory.so \
         /usr/lib/libhistory.so.8 /usr/include/readline/readline.h \
         /usr/include/readline/history.h /usr/lib/pkgconfig/readline.pc; do
  if [ -e "$f" ]; then printf '   OK   %-38s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.12 未完成？）\n' "$f"; rc=1; fi
done
echo "   libreadline 链接自检（与 configure 的 AC_CHECK_LIB([readline],[readline]) 同形）："
tmpc=$(mktemp /tmp/rl-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>
int main(void){ using_history(); printf("readline %s ok\n", rl_library_version); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" -lreadline >/dev/null 2>&1; then
  echo "     OK   -lreadline 单独即可链接：$("${tmpc%.c}")"
else
  echo "     FAIL 无法用 -lreadline 链接（configure 会退回 -ltinfo/-lncursesw 等）"; rc=1
fi
rm -f "$tmpc" "${tmpc%.c}"
echo
echo "2) §8.6 Zlib-1.3.2（--enable-pcre2grep-libz 要 zlib.h + libz）与"
echo "   §8.7 Bzip2-1.0.8（--enable-pcre2grep-libbz2 要 bzlib.h + libbz2）："
for f in /usr/include/zlib.h /usr/lib/libz.so /usr/lib/libz.so.1 \
         /usr/include/bzlib.h /usr/lib/libbz2.so /usr/lib/libbz2.so.1; do
  if [ -e "$f" ]; then printf '   OK   %-30s -> %-22s（%s 字节）\n' \
       "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
tmpc=$(mktemp /tmp/zb-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
#include <zlib.h>
#include <bzlib.h>
int main(void){ printf("zlib %s / bzlib %s\n", zlibVersion(), BZ2_bzlibVersion()); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" -lz -lbz2 >/dev/null 2>&1; then
  echo "   OK   -lz -lbz2 链接成功：$("${tmpc%.c}")"
else echo "   FAIL 无法同时链接 -lz -lbz2"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo "   RunGrepTest 还要用到 gzip / bzip2 两个命令行工具来造压缩测试样本："
for t in gzip bzip2; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-6s %s（%s）\n' "$t" "$(command -v $t)" "$($t --version 2>&1 | sed -n 1p)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo
echo "3) §8.5 Glibc-2.43 的 C 库与工具链可用（本节要 configure + 编译 C 代码）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2; do
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
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "5) 本节直接依赖的工具（解包 + configure + make + make check + 安装）："
for t in tar bzip2 make gcc ld ar ranlib sed grep awk install ln rm mkdir cmp diff \
         md5sum readelf objdump ldd find stat bash sort head tail perl; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   perl 版本：$(perl --version 2>/dev/null | sed -n 2p | sed 's/^ *//')"
echo "   说明：perl 只被可选的 RunTest -perltest / perltest.sh 使用，automake 的 TESTS"
echo "     里不含它；列出仅为记录。"
echo
echo "6) 安装目标目录："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/share/man/man3 \
         /usr/lib/pkgconfig; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo "   INFO $DOCDIR：$( [ -d "$DOCDIR" ] && echo 已存在 || echo '不存在，make install 会创建' )"
echo
echo "7) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo
echo "8) §7.3 虚拟内核文件系统与 §7.6 基础文件（RunTest 要写临时文件、读 /dev/null）："
for f in /dev/null /dev/zero /dev/urandom /proc/self /sys /etc/passwd /etc/group /tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "9) 安装前系统中的 Pcre2 痕迹（第 5/6/7 章都没有 Pcre2 这一节，本节应是首次安装）："
pre_existing=0
for f in /usr/bin/pcre2grep /usr/bin/pcre2test /usr/bin/pcre2-config \
         /usr/lib/libpcre2-8.so /usr/lib/libpcre2-16.so /usr/lib/libpcre2-32.so \
         /usr/lib/libpcre2-posix.so /usr/include/pcre2.h "$DOCDIR"; do
  if [ -e "$f" ]; then printf '   INFO %-32s 已存在（重装场景）\n' "$f"; pre_existing=1
  else printf '   INFO %-32s 不存在（首次安装，符合预期）\n' "$f"; fi
done
if [ "$pre_existing" -eq 0 ]; then echo "   结论：首次安装。"
else echo "   结论：系统里已有 Pcre2 痕迹，本次为重装。"; fi
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
maj=$(sed -n 's/^m4_define(pcre2_major, *\[\([0-9]*\)\]).*/\1/p' configure.ac | head -n1)
min=$(sed -n 's/^m4_define(pcre2_minor, *\[\([0-9]*\)\]).*/\1/p' configure.ac | head -n1)
pre=$(sed -n 's/^m4_define(pcre2_prerelease, *\[\(.*\)\]).*/\1/p' configure.ac | head -n1)
pdate=$(sed -n 's/^m4_define(pcre2_date, *\[\(.*\)\]).*/\1/p' configure.ac | head -n1)
echo "  configure.ac：pcre2_major=$maj  pcre2_minor=$min  pcre2_prerelease='${pre}'  pcre2_date=$pdate"
conf_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'$/\1/p" configure | head -n1)
echo "  configure   ：PACKAGE_VERSION=$conf_ver"
if [ "$maj.$min" = "$VER" ] && [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $conf_ver 与手册 §8.13 的 Pcre2-$VER 一致"
else echo "  FAIL 源码自述版本为 '$maj.$min'/'$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁、无 sed：手册 §8.13 的命令序列只有 configure/make/make check/make install"
p2_patches=$(ls /sources | grep -Ei '^pcre2.*patch' || true)
echo "  （/sources 中匹配 pcre2*patch 的文件：${p2_patches:-无}）"
echo "automake 测试清单（Makefile.am 的 TESTS，决定 make check 要跑哪几项）："
grep -nE '^\s*TESTS \+=|^\s*XFAIL_TESTS \+=' Makefile.am | sed 's/^/  /'
echo "  本次配置为 8/16/32 位全开 + JIT 开，故 TESTS 展开为："
echo "    pcre2posix_test（WITH_PCRE2_8）、pcre2_jit_test（WITH_JIT）、RunTest、RunGrepTest（WITH_PCRE2_8）"
echo "  XFAIL_TESTS 仅在 WITH_EBCDIC 下才含 RunGrepTest —— 本节不启用 EBCDIC，"
echo "  故期望 4 项全部 PASS、无 XFAIL、无 ERROR。"
echo

echo "================= 8.13.1. Installation of Pcre2 ================="
echo
echo "----- 手册命令 1/4：configure -----"
echo "手册原文：Prepare pcre2 for compilation:"
echo "手册命令："
echo "  ./configure --prefix=/usr                       \\"
echo "              --docdir=/usr/share/doc/pcre2-$VER \\"
echo "              --enable-unicode                    \\"
echo "              --enable-jit                        \\"
echo "              --enable-pcre2-16                   \\"
echo "              --enable-pcre2-32                   \\"
echo "              --enable-pcre2grep-libz             \\"
echo "              --enable-pcre2grep-libbz2           \\"
echo "              --enable-pcre2test-libreadline      \\"
echo "              --disable-static"
echo "手册对新增选项的说明："
echo "  --enable-unicode                : enables Unicode support and includes the functions"
echo "                                    for handling UTF-8/16/32 character strings."
echo "  --enable-jit                    : enables Just-in-time compiling, which can greatly"
echo "                                    speed up pattern matching."
echo "  --enable-pcre2-16               : enables 16 bit character support."
echo "  --enable-pcre2-32               : enables 32 bit character support."
echo "  --enable-pcre2grep-libz         : adds support for reading .gz compressed files to pcre2grep."
echo "  --enable-pcre2grep-libbz2       : adds support for reading .bz2 compressed files to pcre2grep."
echo "  --enable-pcre2test-libreadline  : adds line editing and history features to pcre2test."
echo "（--disable-static 是全书通用约定，见手册 §8.2 关于不安装静态库的说明。）"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr                       \
            --docdir=/usr/share/doc/pcre2-$VER  \
            --enable-unicode                    \
            --enable-jit                        \
            --enable-pcre2-16                   \
            --enable-pcre2-32                   \
            --enable-pcre2grep-libz             \
            --enable-pcre2grep-libbz2           \
            --enable-pcre2test-libreadline      \
            --disable-static > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo
echo "configure 末尾的配置摘要（上游自己打印的 pcre2-$VER configuration summary）："
sed -n '/configuration summary/,$p' "$CONFLOG" | sed 's/^/  /'
echo
echo "----- 逐项核对手册要求的开关确实生效（config.h + Makefile） -----"
crc=0
check_def() {  # <宏名> <说明>
  local m=$1 d=$2 line
  line=$(grep -E "^#define $m " src/config.h || true)
  if [ -n "$line" ]; then printf '  OK   %-22s %-46s %s\n' "$m" "$line" "$d"
  else printf '  FAIL %-22s 未定义（src/config.h 中为 /* #undef %s */）  %s\n' "$m" "$m" "$d"; crc=1; fi
}
check_def SUPPORT_UNICODE      "<- --enable-unicode"
check_def SUPPORT_JIT          "<- --enable-jit"
check_def SUPPORT_PCRE2_8      "（8 位库，默认开）"
check_def SUPPORT_PCRE2_16     "<- --enable-pcre2-16"
check_def SUPPORT_PCRE2_32     "<- --enable-pcre2-32"
check_def SUPPORT_LIBZ         "<- --enable-pcre2grep-libz"
check_def SUPPORT_LIBBZ2       "<- --enable-pcre2grep-libbz2"
check_def SUPPORT_LIBREADLINE  "<- --enable-pcre2test-libreadline"
echo "  configure 为 pcre2test 选定的 readline 链接参数："
grep -E '^LIBREADLINE = ' Makefile | sed 's/^/    /'
libreadline_val=$(sed -n 's/^LIBREADLINE = //p' Makefile | head -n1)
case "$libreadline_val" in
  *-lreadline*) echo "    OK   含 -lreadline" ;;
  *) echo "    FAIL LIBREADLINE 为 '$libreadline_val'，未含 -lreadline"; crc=1 ;;
esac
echo "  --disable-static 生效确认（libtool 的 build_old_libs 应为 no）："
grep -E '^build_old_libs=' libtool | sed 's/^/    /'
if [ "$(sed -n 's/^build_old_libs=//p' libtool | head -n1)" = no ]; then
  echo "    OK   不会生成 .a 静态库"
else echo "    FAIL build_old_libs 不是 no"; crc=1; fi
echo "  --prefix / --docdir 生效确认："
grep -E '^(prefix|docdir) = ' Makefile | sed 's/^/    /'
[ "$(sed -n 's/^prefix = //p' Makefile | head -n1)" = /usr ] || { echo "    FAIL prefix 不是 /usr"; crc=1; }
[ "$(sed -n 's/^docdir = //p' Makefile | head -n1)" = "$DOCDIR" ] || { echo "    FAIL docdir 不是 $DOCDIR"; crc=1; }
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册要求的选项不符" >&2; exit 1; }
echo "  OK   手册要求的 9 个开关全部按预期生效"
echo

echo "----- 手册命令 2/4：make -----"
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
echo
echo "----- 编译结果确认 -----"
mrc=0
for f in .libs/libpcre2-8.so .libs/libpcre2-16.so .libs/libpcre2-32.so \
         .libs/libpcre2-posix.so; do
  if [ -e "$f" ]; then printf '  OK   %-28s %s 字节\n' "$f" "$(stat -Lc %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; mrc=1; fi
done
# pcre2grep / pcre2test 链接的是尚未安装的共享库，libtool 会在构建根放一个包装脚本，
# 真正的 ELF 可执行文件在 .libs/ 下；两种布局都接受，但至少要有一个能跑。
for b in pcre2grep pcre2test; do
  if [ -x ".libs/$b" ]; then printf '  OK   %-28s %s 字节（libtool 的真实 ELF）\n' ".libs/$b" "$(stat -Lc %s ".libs/$b")"
  elif [ -x "$b" ]; then printf '  OK   %-28s %s 字节\n' "$b" "$(stat -Lc %s "$b")"
  else printf '  FAIL %s 未生成\n' "$b"; mrc=1; fi
done
echo "  共享库 SONAME："
for l in libpcre2-8 libpcre2-16 libpcre2-32 libpcre2-posix; do
  objdump -p .libs/$l.so 2>/dev/null | awk -v n="$l" '/SONAME/{printf "    %-16s %s\n", n, $2}' || true
done
echo "  静态库残留检查（--disable-static，应为空）："
sta=$(find . -name 'libpcre2*.a' | sed 's/^/    /' || true)
echo "${sta:-    （无）}"
[ -z "$sta" ] || { echo "  FAIL 生成了静态库"; mrc=1; }
echo "  刚编译出的 pcre2test -C（JIT / Unicode / 各位宽支持）："
./pcre2test -C > /tmp/.pcre2-C-build.txt 2>&1 || true
sed 's/^/    /' /tmp/.pcre2-C-build.txt
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 3/4：make check（本节的测试） -----"
echo "手册原文：To test the results, issue:  make check"
echo "（手册本节没有任何关于测试结果的 Note / Caution，即要求测试全部通过。"
echo "  判定依据：make check 退出码为 0，且 automake 并行测试框架的汇总里"
echo "  TOTAL=PASS=4、FAIL=0、XFAIL=0、XPASS=0、ERROR=0、SKIP=0。）"
echo "完整输出写入 $CHECKLOG。"
set +e
make check > "$CHECKLOG" 2>&1
check_rc=$?
set -e
echo
echo "make check 完整输出（$(wc -l < "$CHECKLOG") 行）："
sed 's/^/  /' "$CHECKLOG"
echo
echo "----- make check 结论 -----"
echo "make check 退出码：$check_rc"
echo "逐项结果（automake 每个测试一行 PASS/FAIL/SKIP/XFAIL/ERROR）："
grep -E '^(PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):' "$CHECKLOG" | sed 's/^/  /' || true
echo "汇总行："
grep -E '^# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):' "$CHECKLOG" | sed 's/^/  /' || true
get_total() { sed -n "s/^# $1: *\([0-9]*\)\$/\1/p" "$CHECKLOG" | head -n1; }
t_total=$(get_total TOTAL); t_pass=$(get_total PASS); t_fail=$(get_total FAIL)
t_skip=$(get_total SKIP);   t_xfail=$(get_total XFAIL); t_xpass=$(get_total XPASS)
t_err=$(get_total ERROR)
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make check 退出码非 0（$check_rc）" >&2
  echo "  失败项的详细日志（automake 会把失败测试的 .log 内容打印在汇总之后）见 $CHECKLOG" >&2
  for l in pcre2posix_test.log pcre2_jit_test.log RunTest.log RunGrepTest.log; do
    [ -f "$l" ] && { echo "  ---- $l ----" >&2; tail -n 40 "$l" >&2; }
  done
  exit "$check_rc"
fi
echo "统计（期望 TOTAL=PASS=4，其余全 0）："
printf '  TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
  "${t_total:-?}" "${t_pass:-?}" "${t_fail:-?}" "${t_skip:-?}" "${t_xfail:-?}" "${t_xpass:-?}" "${t_err:-?}"
trc=0
[ "$t_total" = 4 ] || { echo "  FAIL TOTAL 不是 4（本配置下 TESTS 应展开为 4 项）"; trc=1; }
[ "$t_pass"  = 4 ] || { echo "  FAIL PASS 不是 4"; trc=1; }
for v in "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"; do
  [ "$v" = 0 ] || { echo "  FAIL FAIL/SKIP/XFAIL/XPASS/ERROR 中有非 0 项"; trc=1; break; }
done
[ $trc -eq 0 ] || { echo "错误：测试结果不符合手册要求（手册对本节没有允许失败的说明）" >&2; exit 1; }
echo "  OK   4 项测试（pcre2posix_test / pcre2_jit_test / RunTest / RunGrepTest）全部 PASS"
echo "结论：§8.13 的 make check 退出码 0，4/4 全部通过，无失败、无跳过、无预期外结果 ——"
echo "  本节测试完全符合手册要求，无手册允许的例外需要说明。"
echo

echo "----- 手册命令 4/4：make install -----"
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
echo "安装到 /usr/bin、/usr/lib、/usr/include 的条目（摘自 install 日志）："
grep -E '^(libtool: install|libtool: finish| *(/usr/bin/)?install)' "$INSTLOG" \
  | grep -oE '/usr/(bin|lib|include|share)[^ "]*' | sort -u | sed 's/^/  /' || true
echo

echo "----- 安装后检查（手册 §8.13.2 Contents of Pcre2） -----"
echo "手册列出的内容："
echo "  Installed programs: pcre2grep and pcre2test"
echo "  Installed library : libpcre2-8.so, libpcre2-16.so, libpcre2-32.so, and libpcre2-posix.so"
rc=0
echo "1) Installed programs："
for f in /usr/bin/pcre2grep /usr/bin/pcre2test; do
  if [ -x "$f" ]; then printf '   OK   %-22s（%s 字节，%s）\n' "$f" "$(stat -Lc %s "$f")" "$(file -b "$f" | cut -d, -f1-2)"
  else printf '   FAIL %s 缺失或不可执行\n' "$f"; rc=1; fi
done
echo "   （pcre2-config 与 libpcre2*.pc 手册未在 Contents 中列出，但由 make install 一并安装）"
for f in /usr/bin/pcre2-config; do
  if [ -x "$f" ]; then printf '   INFO %-22s（%s 字节）版本自述：%s\n' "$f" "$(stat -Lc %s "$f")" "$($f --version)"
  else printf '   INFO %s 未安装\n' "$f"; fi
done
echo "2) Installed libraries："
for l in libpcre2-8 libpcre2-16 libpcre2-32 libpcre2-posix; do
  so=/usr/lib/$l.so
  if [ -e "$so" ]; then
    printf '   OK   %-26s -> %-26s（%s 字节）\n' "$so" "$(readlink -f "$so" | sed 's|.*/||')" "$(stat -Lc %s "$so")"
    objdump -p "$so" | awk '/SONAME/{printf "        SONAME %s\n", $2}' || true
  else printf '   FAIL %s 缺失\n' "$so"; rc=1; fi
done
echo "   静态库不应安装（--disable-static）："
sta=$(ls /usr/lib/libpcre2*.a 2>/dev/null || true)
if [ -z "$sta" ]; then echo "     OK   /usr/lib 下无 libpcre2*.a"
else echo "$sta" | sed 's/^/     FAIL 存在静态库：/'; rc=1; fi
echo "   .la 文件（libtool 归档，本书不特别处理，仅记录）："
ls /usr/lib/libpcre2*.la 2>/dev/null | sed 's/^/     INFO /' || echo "     INFO （无）"
echo "3) 头文件与 pkg-config："
for f in /usr/include/pcre2.h /usr/include/pcre2posix.h \
         /usr/lib/pkgconfig/libpcre2-8.pc /usr/lib/pkgconfig/libpcre2-16.pc \
         /usr/lib/pkgconfig/libpcre2-32.pc /usr/lib/pkgconfig/libpcre2-posix.pc; do
  if [ -e "$f" ]; then printf '   OK   %-40s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   pcre2.h 中的版本宏："
grep -E '^#define PCRE2_(MAJOR|MINOR|DATE)' /usr/include/pcre2.h | sed 's/^/     /'
h_major=$(sed -n 's/^#define PCRE2_MAJOR *\([0-9]*\).*/\1/p' /usr/include/pcre2.h | head -n1)
h_minor=$(sed -n 's/^#define PCRE2_MINOR *\([0-9]*\).*/\1/p' /usr/include/pcre2.h | head -n1)
if [ "$h_major.$h_minor" = "$VER" ]; then echo "     OK   已安装头文件自述版本 $h_major.$h_minor"
else echo "     FAIL 已安装头文件版本 $h_major.$h_minor 与 $VER 不符"; rc=1; fi
echo "4) man 页与文档目录（--docdir=$DOCDIR）："
for f in /usr/share/man/man1/pcre2grep.1 /usr/share/man/man1/pcre2test.1 \
         /usr/share/man/man3/pcre2.3 /usr/share/man/man3/pcre2api.3; do
  if [ -e "$f" ]; then printf '   OK   %-38s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   man3 页总数：$(ls /usr/share/man/man3/pcre2*.3 2>/dev/null | wc -l)"
if [ -d "$DOCDIR" ]; then
  echo "   OK   $DOCDIR 存在，共 $(find "$DOCDIR" -type f | wc -l) 个文件："
  ls "$DOCDIR" | sed 's/^/     /'
else echo "   FAIL $DOCDIR 不存在"; rc=1; fi
echo
echo "----- 功能验证（确认手册要求的各项特性在已安装的程序里真的可用） -----"
echo "a) pcre2test -C（Unicode / JIT / 8-16-32 位）—— 用已安装的 /usr/bin/pcre2test："
CCAP=/tmp/.pcre2-C-installed.txt
pcre2test -C > "$CCAP" 2>&1 || true
sed 's/^/   /' "$CCAP"
has() { [ "$(grep -cF "$1" "$CCAP" || true)" -gt 0 ]; }
for feat in "8-bit support" "16-bit support" "32-bit support"; do
  if has "  $feat"; then printf '   OK   pcre2test -C 报告 %s\n' "$feat"
  else printf '   FAIL pcre2test -C 未报告 %s\n' "$feat"; rc=1; fi
done
if has "  UTF and UCP support ("; then
  echo "   OK   Unicode 支持已启用：$(grep -F 'UTF and UCP support' "$CCAP" | sed 's/^ *//')"
else echo "   FAIL pcre2test -C 报告 'No Unicode support'（--enable-unicode 未生效）"; rc=1; fi
if has "  Just-in-time compiler support" && ! has "  No just-in-time compiler support"; then
  echo "   OK   JIT 支持已启用：$(grep -A2 -F 'Just-in-time compiler support' "$CCAP" | sed 's/^ *//' | tr '\n' ' ')"
else echo "   FAIL pcre2test -C 报告 'No just-in-time compiler support'（--enable-jit 未生效）"; rc=1; fi
if has "Can allocate executable memory: yes"; then
  echo "   OK   JIT 可分配可执行内存（chroot 环境未阻止 PROT_EXEC 映射）"
else
  echo "   INFO JIT 可执行内存分配行：$(grep -F 'Can allocate executable memory' "$CCAP" | sed 's/^ *//')"
fi
rm -f "$CCAP"
echo "b) pcre2test 与 libreadline 的链接（--enable-pcre2test-libreadline）："
ldd /usr/bin/pcre2test | sed 's/^/   /'
if [ -n "$(ldd /usr/bin/pcre2test | grep -F libreadline || true)" ]; then
  echo "   OK   pcre2test 动态链接了 libreadline"
else echo "   FAIL pcre2test 未链接 libreadline"; rc=1; fi
echo "c) pcre2grep 与 libz / libbz2 的链接（--enable-pcre2grep-libz / -libbz2）："
ldd /usr/bin/pcre2grep | sed 's/^/   /'
for l in libz.so libbz2.so; do
  if [ -n "$(ldd /usr/bin/pcre2grep | grep -F "$l" || true)" ]; then
    printf '   OK   pcre2grep 动态链接了 %s\n' "$l"
  else printf '   FAIL pcre2grep 未链接 %s\n' "$l"; rc=1; fi
done
echo "d) pcre2grep 实际匹配 + 读取 .gz / .bz2（手册所述 libz/libbz2 支持的直接验证）："
tmpd=$(mktemp -d /tmp/pcre2-verify-XXXXXX)
printf 'alpha 123\nbeta 456\ngamma 789\n' > "$tmpd/plain.txt"
gzip  -c "$tmpd/plain.txt" > "$tmpd/plain.txt.gz"
bzip2 -c "$tmpd/plain.txt" > "$tmpd/plain.txt.bz2"
echo "   pcre2grep '\\bbeta\\s+\\d+' plain.txt      -> $(pcre2grep '\bbeta\s+\d+' "$tmpd/plain.txt")"
gz_out=$(pcre2grep '\bgamma\s+\d+' "$tmpd/plain.txt.gz")
bz_out=$(pcre2grep '\balpha\s+\d+' "$tmpd/plain.txt.bz2")
echo "   pcre2grep '\\bgamma\\s+\\d+' plain.txt.gz  -> $gz_out"
echo "   pcre2grep '\\balpha\\s+\\d+' plain.txt.bz2 -> $bz_out"
[ "$gz_out" = "gamma 789" ] || { echo "   FAIL 读取 .gz 失败"; rc=1; }
[ "$bz_out" = "alpha 123" ] || { echo "   FAIL 读取 .bz2 失败"; rc=1; }
[ "$gz_out" = "gamma 789" ] && [ "$bz_out" = "alpha 123" ] && \
  echo "   OK   pcre2grep 直接读取 .gz 与 .bz2 均正常（Perl 语法 \\b \\s \\d 也生效）"
echo "e) pcre2test 跑一条 Unicode + JIT 的模式（用已安装的二进制，非构建目录里的）："
cat > "$tmpd/t.pcre2" <<'EOF'
/(?i)stra\x{df}e/utf,jit
    STRASSE
    Stra\x{df}e
EOF
pcre2test "$tmpd/t.pcre2" > "$tmpd/t.out" 2>&1 || true
sed 's/^/   /' "$tmpd/t.out"
echo "f) 三个位宽的库 + libpcre2-posix 均可链接调用："
cat > "$tmpd/w.c" <<'EOF'
#include <stdio.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
int main(void){
  int err; PCRE2_SIZE eo;
  pcre2_code *re = pcre2_compile((PCRE2_SPTR)"^a(b+)c$", PCRE2_ZERO_TERMINATED, 0, &err, &eo, NULL);
  if (!re) { printf("compile failed\n"); return 1; }
  pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
  int r = pcre2_match(re, (PCRE2_SPTR)"abbbc", 5, 0, 0, md, NULL);
  printf("pcre2_match(8-bit) = %d\n", r);
  pcre2_match_data_free(md); pcre2_code_free(re);
  return r > 0 ? 0 : 1;
}
EOF
if gcc -o "$tmpd/w8" "$tmpd/w.c" -lpcre2-8 && "$tmpd/w8"; then
  echo "   OK   -lpcre2-8 链接与 pcre2_match 调用正常"
else echo "   FAIL 8 位库调用失败"; rc=1; fi
for w in 16 32; do
  cat > "$tmpd/probe$w.c" <<EOF
#include <stdio.h>
#define PCRE2_CODE_UNIT_WIDTH $w
#include <pcre2.h>
static PCRE2_UCHAR pat[] = { 'a', '+', 0 };
int main(void){
  int err; PCRE2_SIZE eo;
  pcre2_code *re = pcre2_compile(pat, PCRE2_ZERO_TERMINATED, 0, &err, &eo, NULL);
  if (!re) { printf("compile failed\n"); return 1; }
  pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
  PCRE2_UCHAR subj[] = { 'x', 'a', 'a', 'a', 0 };
  int r = pcre2_match(re, subj, 4, 0, 0, md, NULL);
  printf("pcre2_match(${w}-bit) = %d\n", r);
  pcre2_match_data_free(md); pcre2_code_free(re);
  return r > 0 ? 0 : 1; }
EOF
  if gcc -o "$tmpd/p$w" "$tmpd/probe$w.c" -lpcre2-$w >/dev/null 2>&1 && out=$("$tmpd/p$w"); then
    echo "   OK   -lpcre2-$w 链接与匹配调用正常：$out"
  else echo "   FAIL -lpcre2-$w 链接或调用失败"; rc=1; fi
done
cat > "$tmpd/posix.c" <<'EOF'
#include <stdio.h>
#include <pcre2posix.h>
int main(void){ regex_t re;
  if (pcre2_regcomp(&re, "^h(e+)llo$", 0)) { printf("regcomp failed\n"); return 1; }
  int r = pcre2_regexec(&re, "heeello", 0, NULL, 0);
  printf("pcre2_regexec = %d (0 = matched)\n", r);
  pcre2_regfree(&re); return r; }
EOF
if gcc -o "$tmpd/posix" "$tmpd/posix.c" -lpcre2-posix -lpcre2-8 && "$tmpd/posix"; then
  echo "   OK   -lpcre2-posix 链接与 POSIX 包装接口调用正常"
else echo "   FAIL libpcre2-posix 调用失败"; rc=1; fi
echo "g) pcre2-config 输出（供其他包的 configure 探测用）："
for a in --version --prefix --libs8 --libs16 --libs32 --libs-posix --cflags; do
  printf '   pcre2-config %-13s -> %s\n' "$a" "$(pcre2-config $a 2>&1)"
done
rm -rf "$tmpd"
echo
echo "5) 本节写入系统的文件清单："
ls -l /usr/bin/pcre2grep /usr/bin/pcre2test /usr/bin/pcre2-config \
      /usr/lib/libpcre2-*.so* /usr/lib/pkgconfig/libpcre2-*.pc \
      /usr/include/pcre2.h /usr/include/pcre2posix.h 2>/dev/null | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Pcre2 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.13.sh"
echo "  移入 \$LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make check   完整输出：$CHECKLOG"
echo "  make install 完整输出：$INSTLOG"
cd /sources
rm -rf "$SRCDIR"
if [ -d "/sources/$SRCDIR" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCDIR"
echo "/sources 下的解包残留（应为空）："
find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.13 完成，结束时间：$(date -Is) ====="
