#!/usr/bin/env bash
# LFS 13.0-systemd §8.14 M4-1.4.21
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.14.1 Installation of M4 的命令序列（全部，一条不多一条不少）：
#   ./configure --prefix=/usr
#   make
#   make check
#   make install
# 本节没有 sed、没有 patch、没有可选命令，也没有任何关于允许失败的 Note / Caution。
set -euo pipefail

PKG=m4
VER=1.4.21
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
CONFLOG=/sources/.m4-configure.log
MAKELOG=/sources/.m4-make.log
CHECKLOG=/sources/.m4-make-check.log
INSTLOG=/sources/.m4-make-install.log

echo "===== LFS 13.0-systemd §8.14 M4-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The M4 package contains a macro processor."
echo "手册数据：Approximate build time 0.4 SBU，Required disk space 61 MB"
echo "手册存档：/workspace/docs/book/chapter08-m4.html（宿主机 \$LFS_ROOT/docs/book/）"
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
echo "1) 上一任务 §8.13 Pcre2-10.47 的产物（手册顺序上的前一节，确认其已完成）："
for f in /usr/bin/pcre2grep /usr/bin/pcre2test /usr/lib/libpcre2-8.so \
         /usr/lib/libpcre2-16.so /usr/lib/libpcre2-32.so /usr/lib/libpcre2-posix.so \
         /usr/include/pcre2.h; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.13 未完成？）\n' "$f"; rc=1; fi
done
echo "   pcre2grep 自述版本：$(pcre2grep --version 2>&1 | awk 'NR==1')"
echo "   说明：M4 本身不依赖 Pcre2，此处只用于确认「上一任务产物可用」。"
echo
echo "2) §8.5 Glibc-2.43 的 C 库与工具链（本节要 configure + 编译大量 C 代码）："
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
echo "4) 本节直接依赖的工具（解包 + configure + make + make check + 安装）："
for t in tar xz make gcc ld ar ranlib sed grep awk install ln rm mkdir cmp diff \
         md5sum readelf objdump ldd find stat bash sort head tail perl; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   awk  版本：$(awk --version 2>&1 | sed -n 1p)"
echo "   说明：checks/ 目录的 check-them 用 sed/awk/diff/cmp 逐例比对，"
echo "     checks/stamp-checks 的 get-them 规则用 \$(AWK) 从 doc/m4.texi 抽取用例。"
echo
echo "5) §8.11 File-5.46 与 §8.12 Readline-8.3（同为第 8 章已完成节，仅记录环境完整性）："
for f in /usr/bin/file /usr/lib/libreadline.so.8; do
  if [ -e "$f" ]; then printf '   OK   %-30s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   INFO %s 缺失\n' "$f"; fi
done
echo
echo "6) 安装目标目录（手册 §8.14.2 Contents：Installed program: m4）："
for d in /usr/bin /usr/share/man/man1 /usr/share/info /usr/share/locale; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo
echo "7) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo
echo "8) §7.3 虚拟内核文件系统与 §7.6 基础文件（gnulib 测试要读写 /dev、/proc、/tmp）："
for f in /dev/null /dev/zero /dev/full /dev/urandom /dev/tty /proc/self /sys \
         /etc/passwd /etc/group /tmp /var/tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "9) 安装前系统中的 M4 痕迹（§6.2 已用交叉工具链装过一次 m4，本节是用最终工具链重装）："
for f in /usr/bin/m4 /usr/share/man/man1/m4.1 /usr/share/info/m4.info; do
  if [ -e "$f" ]; then printf '   INFO %-30s 已存在（%s 字节，来自 §6.2）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   INFO %-30s 不存在\n' "$f"; fi
done
if [ -x /usr/bin/m4 ]; then
  echo "   现有 m4 自述：$(m4 --version 2>&1 | sed -n 1p)"
  echo "   现有 m4 动态依赖："; ldd /usr/bin/m4 | sed 's/^/     /'
fi
echo "   结论：本节按手册用第 8 章的最终工具链重新构建并覆盖安装 m4。"
echo
echo "10) 磁盘空间（手册要求 61 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 204800 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 61 MB"
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
ac_init=$(grep -n 'AC_INIT' configure.ac | awk 'NR==1')
echo "  configure.ac：$ac_init"
conf_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'\$/\1/p" configure | awk 'NR==1')
conf_str=$(sed -n "s/^PACKAGE_STRING='\(.*\)'\$/\1/p" configure | awk 'NR==1')
echo "  configure   ：PACKAGE_VERSION=$conf_ver  PACKAGE_STRING='$conf_str'"
echo "  .version    ：$(cat .version 2>/dev/null || echo '（无）')"
if [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $conf_ver 与手册 §8.14 的 M4-$VER 一致"
else echo "  FAIL 源码自述版本为 '$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁、无 sed：手册 §8.14 的命令序列只有 configure/make/make check/make install"
m4_patches=$(ls /sources | grep -E '^m4.*patch' || true)
echo "  （/sources 中匹配 m4*patch 的文件：${m4_patches:-无}）"
echo
echo "----- 测试结构预读（决定 make check 的判定标准） -----"
echo "顶层 Makefile.am 的 SUBDIRS（make check 会逐个递归）："
grep -E '^SUBDIRS = ' Makefile.am | sed 's/^/  /'
echo "两套测试的来源："
echo "  a) checks/ —— M4 自带的手册用例回归，由 checks/Makefile.am 的 check-local 驱动："
grep -nE '^(DOC_CHECKS|CHECKS) =|^check-local:' checks/Makefile.am | sed 's/^/     /'
echo "     doc 用例文件数（checks/*[0-9][0-9][0-9].*）：$(ls checks/*[0-9][0-9][0-9].* 2>/dev/null | wc -l)，"
echo "     另加 checks/stackovf.test（栈溢出检测，OS 不支持时以状态 77 记为 skipped）。"
echo "     check-them 的判定：全部通过时打印 'All checks successful' 并 exit 0；"
echo "     有失败时打印 'Failed checks were:' 并 exit 1。"
echo "  b) tests/ —— gnulib 的单元测试，走 automake 并行测试框架，最后打印"
echo "     '# TOTAL/PASS/SKIP/XFAIL/FAIL/XPASS/ERROR' 汇总；本包 XFAIL_TESTS 为空："
grep -nE '^XFAIL_TESTS' tests/gnulib.mk | sed 's/^/     /'
echo "     tests/gnulib.mk 中 'TESTS +=' 声明条数（实际启用数由 configure 决定）：$(grep -c '^TESTS +=' tests/gnulib.mk)"
echo "判定标准（手册 §8.14 无任何允许失败的 Note/Caution）："
echo "  make check 退出码必须为 0；checks/ 必须出现 'All checks successful'；"
echo "  automake 汇总中 FAIL / XPASS / ERROR 必须全为 0（SKIP 属正常，逐项列出说明）。"
echo

echo "================= 8.14.1. Installation of M4 ================="
echo
echo "----- 手册命令 1/4：configure -----"
echo "手册原文：Prepare M4 for compilation:"
echo "手册命令：./configure --prefix=/usr"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "configure 生成的文件（config.status: creating ...，据此确定 config.h 的真实位置）："
grep -E '^config\.status: creating (config\.h|lib/config\.h|Makefile|src/Makefile|checks/Makefile|tests/Makefile|doc/Makefile)' "$CONFLOG" | sed 's/^/  /' || true
echo "  configure.ac 的 AC_CONFIG_HEADERS 声明："
grep -n 'AC_CONFIG_HEADERS' configure.ac | sed 's/^/    /'
echo "configure 关键探测结果摘要："
grep -E '^checking for (gcc|C compiler|GNU make)|^checking whether the C compiler works|^checking for (an ANSI C-conforming const|library containing|sigsegv|stack)' "$CONFLOG" \
  | head -n 20 | sed 's/^/  /' || true
echo "configure 末尾 15 行："
tail -n 15 "$CONFLOG" | sed 's/^/  /'
echo
echo "----- 核对 --prefix=/usr 确实生效 -----"
crc=0
grep -E '^(prefix|exec_prefix|bindir|mandir|infodir|datarootdir) = ' Makefile | sed 's/^/  /'
got_prefix=$(sed -n 's/^prefix = //p' Makefile | awk 'NR==1')
if [ "$got_prefix" = /usr ]; then echo "  OK   prefix = /usr（手册 --prefix=/usr）"
else echo "  FAIL prefix 为 '$got_prefix'，不是 /usr"; crc=1; fi
for pair in "bindir:\${exec_prefix}/bin" "mandir:\${datarootdir}/man" "infodir:\${datarootdir}/info"; do
  k=${pair%%:*}
  v=$(sed -n "s/^$k = //p" Makefile | awk 'NR==1')
  printf '  INFO %-8s = %s\n' "$k" "$v"
done
echo "  生成的配置头（AC_CONFIG_HEADERS 指定为 lib/config.h，不在顶层）："
if [ -f lib/config.h ]; then
  echo "    OK   lib/config.h 存在（$(wc -l < lib/config.h) 行）"
  echo "    PACKAGE_VERSION / PACKAGE_STRING 宏："
  grep -E '^#define PACKAGE_(VERSION|STRING) ' lib/config.h | sed 's/^/      /'
  h_ver=$(sed -n 's/^#define PACKAGE_VERSION "\(.*\)"$/\1/p' lib/config.h | awk 'NR==1')
  if [ "$h_ver" = "$VER" ]; then echo "      OK   lib/config.h 自述版本 $h_ver"
  else echo "      FAIL lib/config.h 版本 '$h_ver' 与 $VER 不符"; crc=1; fi
else echo "    FAIL lib/config.h 未生成"; crc=1; fi
echo "  各子目录 Makefile 是否齐备（顶层 SUBDIRS 的每一项）："
for d in . examples lib src doc checks po tests; do
  f=$d/Makefile
  [ "$d" = po ] && f=po/Makefile
  if [ -f "$f" ]; then printf '    OK   %s\n' "$f"
  else printf '    FAIL %s 未生成\n' "$f"; crc=1; fi
done
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册的 --prefix=/usr"
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
if [ -x src/m4 ]; then
  printf '  OK   %-16s %s 字节，%s\n' "src/m4" "$(stat -Lc %s src/m4)" "$(file -b src/m4 | cut -d, -f1-2)"
else echo "  FAIL src/m4 未生成"; mrc=1; fi
if [ -f lib/libm4.a ]; then
  echo "  OK   lib/libm4.a（$(stat -Lc %s lib/libm4.a) 字节）—— gnulib 便利库，noinst_LIBRARIES，不会被安装"
else echo "  FAIL lib/libm4.a 未生成"; mrc=1; fi
echo "  刚编译出的 src/m4 自述版本："
build_ver=$(./src/m4 --version 2>&1 | sed -n 1p)
echo "    $build_ver"
case "$build_ver" in
  *"$VER"*) echo "    OK   构建产物自述含 $VER" ;;
  *) echo "    FAIL 构建产物自述不含 $VER"; mrc=1 ;;
esac
echo "  src/m4 的动态依赖（构建目录内的产物）："
ldd src/m4 | sed 's/^/    /'
echo "  m4 冒烟测试（未安装的构建产物）："
smoke=$(printf 'define(`X'"'"',`hi'"'"')X\n' | ./src/m4)
echo "    define(\`X',\`hi')X  ->  $smoke"
[ "$smoke" = "hi" ] || { echo "    FAIL 构建产物宏展开结果不是 hi"; mrc=1; }
echo "  doc 目录的 info / man 产物："
for f in doc/m4.info doc/m4.1; do
  if [ -f "$f" ]; then printf '    OK   %-14s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '    FAIL %s 未生成\n' "$f"; mrc=1; fi
done
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 3/4：make check（本节的测试） -----"
echo "手册原文：To test the results, issue:  make check"
echo "（手册 §8.14 全节没有任何关于测试结果的 Note / Caution，即要求测试全部通过。"
echo "  判定：退出码 0 + checks/ 打印 'All checks successful' + automake 汇总中"
echo "  FAIL=XPASS=ERROR=0。SKIP 是 gnulib/stackovf 在本环境下的正常跳过，逐项列出。）"
echo "完整输出写入 $CHECKLOG。"
set +e
make check > "$CHECKLOG" 2>&1
check_rc=$?
set -e
echo
echo "----- make check 结论 -----"
echo "make check 退出码：$check_rc（输出 $(wc -l < "$CHECKLOG") 行）"
echo
echo "----- make check 完整输出（$(wc -l < "$CHECKLOG") 行） -----"
sed 's/^/  /' "$CHECKLOG"
echo "----- make check 完整输出结束 -----"
echo
echo "a) checks/ —— M4 自带手册用例回归（check-them 的输出）："
echo "   'Checking <file>' 行数（实际跑过的用例数）：$(grep -c '^Checking ' "$CHECKLOG" || true)"
echo "   check-them 的结论行："
{ grep -nE '^(All checks successful|Failed checks were:|Skipped checks were:)' "$CHECKLOG" || true; } | sed 's/^/     /'
echo "   跳过的用例（若有）："
{ sed -n '/^Skipped checks were:/{n;p;}' "$CHECKLOG" || true; } | sed 's/^/     /'
checks_ok=$(grep -c '^All checks successful$' "$CHECKLOG" || true)
checks_bad=$(grep -c '^Failed checks were:$' "$CHECKLOG" || true)
echo
echo "b) tests/ —— gnulib 单元测试（automake 并行测试框架汇总）："
echo "   汇总块："
{ grep -E '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary)' "$CHECKLOG" || true; } | sed 's/^/     /'
echo "   非 PASS 的逐项结果（FAIL/XFAIL/XPASS/ERROR/SKIP）："
{ grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; } | sed 's/^/     /'
echo "   PASS 项数：$(grep -cE '^PASS: ' "$CHECKLOG" || true)"
sum_of() { awk -v k="$1" '$0 ~ "^# "k": " {s += $3} END {print s+0}' "$CHECKLOG"; }
t_total=$(sum_of TOTAL); t_pass=$(sum_of PASS);   t_fail=$(sum_of FAIL)
t_skip=$(sum_of SKIP);   t_xfail=$(sum_of XFAIL); t_xpass=$(sum_of XPASS)
t_err=$(sum_of ERROR)
echo "   全部汇总块合计："
printf '     TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
  "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
echo
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make check 退出码非 0（$check_rc）—— 手册对本节没有允许失败的说明" >&2
  echo "  失败项详情（automake 会把失败测试的 .log 打印在汇总之后），完整输出见 $CHECKLOG" >&2
  { grep -nE '^(FAIL|ERROR|XPASS): ' "$CHECKLOG" || true; } | sed 's/^/  /' >&2
  echo "  make check 末尾 60 行：" >&2
  tail -n 60 "$CHECKLOG" | sed 's/^/  /' >&2
  exit "$check_rc"
fi
trc=0
if [ "$checks_ok" -ge 1 ] && [ "$checks_bad" -eq 0 ]; then
  echo "  OK   checks/：'All checks successful'（无 'Failed checks were:'）"
else
  echo "  FAIL checks/：未出现 'All checks successful'（All=$checks_ok Failed=$checks_bad）"; trc=1
fi
[ "$t_fail"  = 0 ] || { echo "  FAIL automake 汇总 FAIL=$t_fail"; trc=1; }
[ "$t_err"   = 0 ] || { echo "  FAIL automake 汇总 ERROR=$t_err"; trc=1; }
[ "$t_xpass" = 0 ] || { echo "  FAIL automake 汇总 XPASS=$t_xpass"; trc=1; }
if [ "$t_total" -gt 0 ] && [ "$((t_pass + t_skip + t_xfail))" = "$t_total" ]; then
  echo "  OK   automake 汇总：PASS($t_pass)+SKIP($t_skip)+XFAIL($t_xfail) = TOTAL($t_total)，无 FAIL/XPASS/ERROR"
else
  echo "  FAIL automake 汇总不自洽：PASS+SKIP+XFAIL != TOTAL"; trc=1
fi
[ $trc -eq 0 ] || { echo "错误：测试结果不符合手册要求" >&2; exit 1; }
echo
echo "结论：§8.14 的 make check 退出码 0。"
echo "  checks/  ：M4 手册用例回归全部通过（All checks successful）；"
echo "  tests/   ：gnulib 单元测试 TOTAL=$t_total，PASS=$t_pass，SKIP=$t_skip，XFAIL=$t_xfail，"
echo "             FAIL=0、XPASS=0、ERROR=0。"
echo "  SKIP 项均为 gnulib 在本环境（chroot、root 身份、无相应内核/库特性）下的自我跳过，"
echo "  automake 不视其为失败；手册 §8.14 未列出任何允许的失败项，本次也确无失败项。"
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
echo "安装到 /usr 下的条目（摘自 install 日志）："
{ grep -oE '/usr/(bin|share|lib|include)[^ "'"'"']*' "$INSTLOG" || true; } | sort -u | sed 's/^/  /'
echo

echo "----- 安装后检查（手册 §8.14.2 Contents of M4） -----"
echo "手册列出的内容："
echo "  Installed program: m4"
echo "  m4 的说明：Copies the given files while expanding the macros that they contain."
echo "    These macros are either built-in or user-defined and can take any number of"
echo "    arguments. Besides performing macro expansion, m4 has built-in functions for"
echo "    including named files, running Unix commands, performing integer arithmetic,"
echo "    manipulating text, recursion, etc."
rc=0
echo "1) Installed program：/usr/bin/m4"
if [ -x /usr/bin/m4 ]; then
  printf '   OK   /usr/bin/m4（%s 字节，%s）\n' "$(stat -Lc %s /usr/bin/m4)" "$(file -b /usr/bin/m4 | cut -d, -f1-2)"
else echo "   FAIL /usr/bin/m4 缺失或不可执行"; rc=1; fi
inst_ver=$(m4 --version 2>&1 | sed -n 1p)
echo "   已安装 m4 自述版本：$inst_ver"
case "$inst_ver" in
  *"$VER"*) echo "   OK   已安装的 m4 自述版本含 $VER" ;;
  *) echo "   FAIL 已安装的 m4 自述版本不含 $VER"; rc=1 ;;
esac
echo "   已安装二进制与构建产物一致性（cmp src/m4 /usr/bin/m4）："
if cmp -s src/m4 /usr/bin/m4; then
  echo "     OK   完全一致（install 未 strip）"
else
  echo "     INFO 不一致（install 可能做了 strip / 属性调整），两者大小："
  ls -l src/m4 /usr/bin/m4 | sed 's/^/       /'
fi
echo "   动态依赖（应只链接最终的 /usr/lib 下 glibc，不含任何 /tools 路径）："
ldd /usr/bin/m4 | sed 's/^/     /'
ldd_out=$(ldd /usr/bin/m4)
case "$ldd_out" in
  *"/tools/"*) echo "     FAIL 仍链接 /tools 下的库"; rc=1 ;;
  *) echo "     OK   未链接任何 /tools 路径" ;;
esac
case "$ldd_out" in
  *"libc.so.6"*) echo "     OK   链接到 libc.so.6" ;;
  *) echo "     FAIL 未链接 libc.so.6"; rc=1 ;;
esac
echo "2) 手册 Contents 未列出、但由 make install 一并安装的文件："
for f in /usr/share/man/man1/m4.1 /usr/share/info/m4.info; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   m4.1 首行：$(head -n1 /usr/share/man/man1/m4.1)"
echo "   info 目录项（/usr/share/info/dir 中的 M4 条目）："
{ grep -n 'm4' /usr/share/info/dir 2>/dev/null || echo '     （dir 中暂无 m4 条目）'; } | sed 's/^/     /'
echo "   locale 消息目录（po/，若已装）："
loc=$({ ls -d /usr/share/locale/*/LC_MESSAGES/m4.mo 2>/dev/null || true; } | wc -l)
echo "     /usr/share/locale/*/LC_MESSAGES/m4.mo 共 $loc 个"
echo "   静态库不应被安装（lib/libm4.a 是 noinst 便利库）："
stale=$(ls /usr/lib/libm4.a 2>/dev/null || true)
if [ -z "$stale" ]; then echo "     OK   /usr/lib 下无 libm4.a"
else echo "     FAIL 存在 $stale"; rc=1; fi
echo
echo "----- 功能验证（对照手册 §8.14.2 对 m4 的描述，逐项用已安装的 /usr/bin/m4 验证） -----"
tmpd=$(mktemp -d /tmp/m4-verify-XXXXXX)
echo "a) 用户自定义宏 + 任意个数参数（define / \$1 \$2 \$#）："
cat > "$tmpd/a.m4" <<'EOF'
define(`greet', `hello $1 and $2 (argc=$#)')dnl
greet(`world', `m4')
EOF
out_a=$(m4 "$tmpd/a.m4")
echo "     输出：$out_a"
[ "$out_a" = "hello world and m4 (argc=2)" ] || { echo "     FAIL 用户自定义宏展开不符合预期"; rc=1; }
[ "$out_a" = "hello world and m4 (argc=2)" ] && echo "     OK   宏展开与参数计数正确"
echo "b) 内建宏 include（including named files）："
printf 'included-content\n' > "$tmpd/inc.txt"
out_b=$(printf 'include(`%s/inc.txt'"'"')' "$tmpd" | m4)
echo "     输出：$out_b"
[ "$out_b" = "included-content" ] || { echo "     FAIL include 未按预期读入文件"; rc=1; }
[ "$out_b" = "included-content" ] && echo "     OK   include 可读入命名文件"
echo "c) 内建宏 esyscmd（running Unix commands）："
out_c=$(printf 'esyscmd(`echo unix-cmd-ok'"'"')' | m4 | tr -d '\n')
echo "     输出：$out_c"
[ "$out_c" = "unix-cmd-ok" ] || { echo "     FAIL esyscmd 未执行外部命令"; rc=1; }
[ "$out_c" = "unix-cmd-ok" ] && echo "     OK   esyscmd 可运行 Unix 命令"
echo "d) 内建宏 eval（integer arithmetic）："
out_d=$(printf 'eval(2**10 + 3*7)' | m4)
echo "     eval(2**10 + 3*7) -> $out_d"
[ "$out_d" = "1045" ] || { echo "     FAIL eval 整数运算结果不是 1045"; rc=1; }
[ "$out_d" = "1045" ] && echo "     OK   eval 整数运算正确"
echo "e) 文本操作内建宏（translit / substr / len / regexp）："
# 注意：此处必须用文件喂给 m4，不能用 printf 的格式串 —— printf 会把 \( 和 \1
# 当成自己的转义（\1 变成八进制字符 \001），regexp 的分组与反向引用会被吃掉。
cat > "$tmpd/e.m4" <<'EOF'
translit(`abcdef', `a-f', `A-F')/substr(`abcdef',2,3)/len(`abcdef')/regexp(`abcdef', `c\(d\)e', `\1')
EOF
out_e=$(m4 "$tmpd/e.m4")
echo "     输出：$out_e"
[ "$out_e" = "ABCDEF/cde/6/d" ] || { echo "     FAIL 文本操作内建宏结果不符（期望 ABCDEF/cde/6/d）"; rc=1; }
[ "$out_e" = "ABCDEF/cde/6/d" ] && echo "     OK   translit/substr/len/regexp 均正确"
echo "f) 递归（recursion）—— 手册示例 forloop 风格的递归展开："
cat > "$tmpd/f.m4" <<'EOF'
define(`countdown', `$1 ifelse(eval($1 > 0), 1, `countdown(eval($1 - 1))')')dnl
countdown(5)
EOF
out_f=$(m4 "$tmpd/f.m4" | tr -s ' ' | sed 's/ *$//')
echo "     countdown(5) -> $out_f"
[ "$out_f" = "5 4 3 2 1 0" ] || { echo "     FAIL 递归展开结果不符（期望 '5 4 3 2 1 0'）"; rc=1; }
[ "$out_f" = "5 4 3 2 1 0" ] && echo "     OK   递归展开正确"
echo "g) 处理多个输入文件（Copies the given files while expanding the macros）："
printf 'define(`P'"'"',`one'"'"')P\n' > "$tmpd/g1.m4"
printf 'P-again\n' > "$tmpd/g2.m4"
out_g=$(m4 "$tmpd/g1.m4" "$tmpd/g2.m4" | tr '\n' '|')
echo "     m4 g1.m4 g2.m4 -> $out_g"
[ "$out_g" = "one|one-again|" ] || { echo "     FAIL 多文件处理结果不符（期望 'one|one-again|'）"; rc=1; }
[ "$out_g" = "one|one-again|" ] && echo "     OK   跨文件的宏定义与展开正确"
echo "h) 作为 autoconf/bison 前端的最低要求 —— m4 --version / --help 正常，且支持 GNU 扩展："
m4 --help > "$tmpd/help.txt" 2>&1 || true
echo "     --help 首行：$(head -n1 "$tmpd/help.txt")"
gnu_ext=$(printf 'ifdef(`__gnu__'"'"', `gnu-yes'"'"', `gnu-no'"'"')' | m4)
echo "     ifdef(\`__gnu__') -> $gnu_ext"
[ "$gnu_ext" = "gnu-yes" ] || { echo "     FAIL 未启用 GNU 扩展（后续 autoconf/bison 依赖）"; rc=1; }
[ "$gnu_ext" = "gnu-yes" ] && echo "     OK   GNU 扩展可用"
echo "i) 退出状态与错误诊断（m4 遇到未定义的必需文件应非 0 退出）："
set +e
m4 /nonexistent-file-for-m4-check.m4 > "$tmpd/err.out" 2>&1
err_rc=$?
set -e
echo "     m4 /nonexistent-file-for-m4-check.m4 退出码：$err_rc"
echo "     诊断输出：$(head -n1 "$tmpd/err.out")"
[ "$err_rc" -ne 0 ] || { echo "     FAIL 读取不存在的文件却返回 0"; rc=1; }
[ "$err_rc" -ne 0 ] && echo "     OK   错误路径下正确返回非 0"
rm -rf "$tmpd"
echo
echo "3) 本节写入系统的文件清单："
{ ls -l /usr/bin/m4 /usr/share/man/man1/m4.1 /usr/share/info/m4.info 2>/dev/null || true; } | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：M4 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.14.sh"
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
echo "===== §8.14 完成，结束时间：$(date -Is) ====="
