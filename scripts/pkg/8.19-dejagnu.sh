#!/usr/bin/env bash
# LFS 13.0-systemd §8.19 DejaGNU-1.6.3
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.19.1 Installation of DejaGNU 的命令序列（全部，一条不多一条不少）：
#   mkdir -v build
#   cd       build
#   ../configure --prefix=/usr
#   makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
#   makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi
#   make check
#   make install
#   install -v -dm755  /usr/share/doc/dejagnu-1.6.3
#   install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
# 手册全节没有任何关于允许测试失败的 Note / Caution，也没有 make（本包是纯脚本包，
# 唯一被编译的是测试用的 check_PROGRAMS = unit，由 make check 自己带出来）。
set -euo pipefail

PKG=dejagnu
VER=1.6.3
TARBALL=dejagnu-1.6.3.tar.gz
SRCTOP=dejagnu-1.6.3
CONFLOG=/sources/.dejagnu-configure.log
MKINFOLOG=/sources/.dejagnu-makeinfo.log
CHECKLOG=/sources/.dejagnu-make-check.log
INSTLOG=/sources/.dejagnu-make-install.log

echo "===== LFS 13.0-systemd §8.19 DejaGNU-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The DejaGnu package contains a framework for running test suites on GNU"
echo "  tools. It is written in expect, which itself uses Tcl (Tool Command Language)."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 6.9 MB"
echo

echo "================= 运行环境（手册 §7.4 的 chroot 环境） ================="
echo "date      : $(date -Is)"
echo "id        : $(id)"
echo "whoami    : $(whoami)"
echo "PATH      : $PATH"
echo "HOME      : $HOME"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "TESTSUITEFLAGS: ${TESTSUITEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
esac
echo "  OK   PATH 中不含 /tools/bin（交叉工具链已不再使用）"
echo

echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0
echo "1) 上一任务 §8.18 Expect-5.45.4 的产物 —— 本节直接依赖它（手册 §8.19 原文："
echo "   'It is written in expect, which itself uses Tcl'；DejaGnu 的 runtest 就是一个"
echo "   定位 expect 解释器并把控制权交给它的包装脚本，make check 也是靠它跑起来的）："
for f in /usr/bin/expect /usr/lib/libexpect5.45.4.so /usr/lib/expect5.45.4/pkgIndex.tcl; do
  if [ -e "$f" ]; then printf '   OK   %-42s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.18 未完成？）\n' "$f"; rc=1; fi
done
exp_v=$(expect -v 2>&1 | sed -n 1p)
echo "   expect 自述版本：$exp_v"
case "$exp_v" in
  *5.45.4*) echo "   OK   expect 可运行且自述 5.45.4（上一任务产物可用）" ;;
  *) echo "   FAIL expect 自述 '$exp_v' 与 §8.18 的 5.45.4 不符"; rc=1 ;;
esac
echo "   expect 的 spawn/send/expect 全链路（runtest 的每一条用例都依赖它）："
smoke=$(expect -c 'set timeout 10
spawn -noecho /usr/bin/cat
expect_after timeout { puts "TIMEOUT"; exit 1 }
send "dejagnu-pre-check\r"
expect "dejagnu-pre-check"
send \004
expect eof
puts "PRECHECK-OK"' 2>&1 | tr -d '\r')
printf '%s\n' "$smoke" | sed 's/^/     /'
case "$smoke" in
  *PRECHECK-OK*) echo "     OK   expect 能经真实 PTY 驱动子进程" ;;
  *) echo "     FAIL expect 冒烟失败"; rc=1 ;;
esac
echo
echo "2) §8.17 Tcl-8.6.17 的产物（expect 与 runtest 的解释器底座）："
for f in /usr/bin/tclsh /usr/lib/libtcl8.6.so; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
tcl_pl=$(echo 'puts $tcl_patchLevel' | tclsh 2>/dev/null || true)
echo "   tclsh 自述版本：$tcl_pl"
[ "$tcl_pl" = 8.6.17 ] || { echo "   FAIL tclsh 自述与 §8.17 的 8.6.17 不符"; rc=1; }
echo
echo "3) 手册命令直接调用的 makeinfo（§7.11 Texinfo 装出的 texi2any）："
if [ -e /usr/bin/makeinfo ]; then
  echo "   OK   /usr/bin/makeinfo -> $(readlink -f /usr/bin/makeinfo)"
  echo "   版本：$(makeinfo --version | sed -n 1p)"
else echo "   FAIL /usr/bin/makeinfo 缺失（§7.11 未完成？）"; rc=1; fi
echo "   注：手册的两条 makeinfo 命令输出到 build/doc/ 下，而 configure 并不创建该目录；"
echo "     texi2any 7.2 会自行创建输出文件所在目录，故手册命令可原样执行。"
echo
echo "4) make check 需要的编译器（Makefile.am: check_PROGRAMS = unit，"
echo "   unit_SOURCES = testsuite/libdejagnu/unit.cc，是一段 C++）："
for t in gcc g++; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-4s %s —— %s\n' "$t" "$(command -v $t)" "$($t --version | sed -n 1p)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
tmpcc=$(mktemp /tmp/sanity-XXXXXX.cc)
cat > "$tmpcc" <<'EOF'
#include <cstdio>
int main(){ std::printf("g++ sanity ok\n"); return 0; }
EOF
if g++ -o "${tmpcc%.cc}" "$tmpcc" >/dev/null 2>&1 && [ "$("${tmpcc%.cc}")" = "g++ sanity ok" ]; then
  echo "   OK   g++ 编译并运行最小 C++ 程序成功"
else echo "   FAIL 无法用 g++ 编译/运行最小 C++ 程序"; rc=1; fi
rm -f "$tmpcc" "${tmpcc%.cc}"
echo
echo "5) 本节直接用到的工具："
for t in tar gzip make gcc sed grep awk gawk install ln mv cp mkdir chmod find file \
         stat head tail tr wc md5sum diff expect tclsh makeinfo sh; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-9s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %-9s 不可用\n' "$t"; rc=1; fi
done
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   （testsuite/launcher.all/command 下的用例会调用 .sh/.awk/.gawk/.tcl 四种脚本，"
echo "     故 gawk 与 tclsh 同样是测试的硬依赖。）"
echo
echo "6) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo
echo "7) 安装前系统中的 DejaGNU 痕迹（DejaGNU 在第 5–7 章从未构建过，预期全部不存在）："
for f in /usr/bin/dejagnu /usr/bin/runtest /usr/share/dejagnu /usr/include/dejagnu.h \
         /usr/share/info/dejagnu.info /usr/share/doc/dejagnu-$VER; do
  if [ -e "$f" ] || [ -L "$f" ]; then printf '   INFO %-38s 已存在\n' "$f"
  else printf '   INFO %-38s 不存在（符合预期：本节是首次安装）\n' "$f"; fi
done
echo
echo "8) 磁盘空间（手册要求 6.9 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 262144 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 6.9 MB"
else echo "   FAIL 可用空间不足：$((avail_k/1024)) MB"; rc=1; fi
echo
echo "9) /tools 已按 §7.13.1 删除："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCTOP"
tar -xf "$TARBALL"
cd "$SRCTOP"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
src_ver=$(sed -n "s/^PACKAGE_VERSION='\\(.*\\)'\$/\\1/p" configure | awk 'NR==1')
echo "configure 自述 PACKAGE_VERSION = $src_ver"
if [ "$src_ver" = "$VER" ]; then echo "  OK   源码自述版本与手册 §8.19 的 DejaGNU-$VER 一致"
else echo "  FAIL 源码自述版本为 '$src_ver'，与 $VER 不符" >&2; exit 1; fi
echo "测试套件构成（Makefile.am: DEJATOOL = launcher libdejagnu report-card runtest，"
echo "  make check 会对这 4 个 tool 各跑一次 runtest --tool <tool> --srcdir ..）："
{ ls testsuite/ || true; } | sed 's/^/  /'
echo

echo "================= 8.19.1. Installation of DejaGNU ================="
echo
echo "----- 手册命令 1/8：mkdir -v build -----"
echo "手册原文：The upstream recommends building DejaGNU in a dedicated build directory:"
mkdir -v build
echo "----- 手册命令 2/8：cd build -----"
cd build
echo "  当前目录：$PWD"
echo

echo "----- 手册命令 3/8：../configure --prefix=/usr （Prepare DejaGNU for compilation） -----"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
../configure --prefix=/usr > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "configure 完整输出（本节 configure 很短，全文照录）："
sed 's/^/  /' "$CONFLOG"
echo
echo "----- 核对 --prefix=/usr 确实生效 -----"
crc=0
[ -f Makefile ] || { echo "  FAIL configure 未生成 Makefile"; exit 1; }
{ grep -nE '^(prefix|exec_prefix|bindir|includedir|infodir|mandir|datarootdir|pkgdatadir|srcdir|top_srcdir|EXPECT|RUNTEST|DEJATOOL)[[:space:]]*=' Makefile || true; } | sed 's/^/    /'
got_prefix=$(sed -n 's/^prefix[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
if [ "$got_prefix" = /usr ]; then echo "    OK   prefix = /usr"
else echo "    FAIL prefix 为 '$got_prefix'"; crc=1; fi
got_srcdir=$(sed -n 's/^srcdir[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
if [ "$got_srcdir" = .. ]; then echo "    OK   srcdir = ..（确为手册要求的 dedicated build directory / VPATH 构建）"
else echo "    FAIL srcdir 为 '$got_srcdir'，不是独立构建目录"; crc=1; fi
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册"
echo

echo "----- 手册命令 4/8 与 5/8：两条 makeinfo（生成 §8.19.1 末尾要安装的文档） -----"
echo "手册命令：makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi"
echo "          makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi"
echo "（这两条不是 configure 的一部分，但手册把它们放在 'Prepare DejaGNU for"
echo "  compilation' 这一段里；它们的产物 doc/dejagnu.html 与 doc/dejagnu.txt 会在"
echo "  本节最后一条 install 命令中被装进 /usr/share/doc/dejagnu-$VER。）"
echo "输入文件：../doc/dejagnu.texi（$(stat -Lc %s ../doc/dejagnu.texi) 字节）"
echo "完整输出（含告警）写入 $MKINFOLOG。"
set +e
{ makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi; } > "$MKINFOLOG" 2>&1
mi1_rc=$?
{ makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi; } >> "$MKINFOLOG" 2>&1
mi2_rc=$?
set -e
echo "makeinfo --html     退出码：$mi1_rc"
echo "makeinfo --plaintext 退出码：$mi2_rc"
echo "两条 makeinfo 的全部输出（$(wc -l < "$MKINFOLOG") 行；texi2any 对这份 2021 年的"
echo "  texi 源文件通常只报告一些非致命 warning）："
sed 's/^/  /' "$MKINFOLOG"
if [ $mi1_rc -ne 0 ] || [ $mi2_rc -ne 0 ]; then
  echo "错误：makeinfo 失败" >&2; exit 1
fi
mrc=0
for f in doc/dejagnu.html doc/dejagnu.txt; do
  if [ -s "$f" ]; then printf '  OK   %-18s（%s 字节，%s）\n' "$f" "$(stat -Lc %s "$f")" "$(file -b "$f" | cut -d, -f1)"
  else printf '  FAIL %s 未生成或为空\n' "$f"; mrc=1; fi
done
echo "  doc/dejagnu.html 首行标题：$({ grep -m1 -o '<title>[^<]*</title>' doc/dejagnu.html || true; })"
echo "  doc/dejagnu.txt  前 3 行："
head -n 3 doc/dejagnu.txt | sed 's/^/    /'
[ $mrc -eq 0 ] || { echo "错误：makeinfo 产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 6/8：make check （To test the results） -----"
echo "手册原文：To test the results, issue:  make check"
echo "（手册 §8.19 全节没有任何关于测试结果的 Note / Caution，即要求测试无意外失败。"
echo "  Makefile 的 check-am 先 make check_PROGRAMS（编译 unit.cc），再 make check-DEJAGNU；"
echo "  后者对 DEJATOOL = launcher libdejagnu report-card runtest 逐个执行"
echo "    \$(top_srcdir)/runtest --tool <tool> --srcdir .."
echo "  并在任一 runtest 返回非零时把整体退出码置 1。每个 tool 产出 <tool>.sum/<tool>.log，"
echo "  .sum 末尾是 '=== <tool> Summary ===' 与 '# of ...' 计数。"
echo "  判据：make check 退出码 0，4 个 tool 的 Summary 全部出现，"
echo "        unexpected failures / unexpected successes / unresolved 全为 0，且有实打实的"
echo "        expected passes。）"
echo "完整输出写入 $CHECKLOG。"
check_start=$(date -Is)
set +e
make check > "$CHECKLOG" 2>&1
check_rc=$?
set -e
check_end=$(date -Is)
echo "make check 退出码：$check_rc（$check_start -> $check_end，输出 $(wc -l < "$CHECKLOG") 行）"
echo
echo "----- make check 完整输出 -----"
sed 's/^/  /' "$CHECKLOG"
echo
echo "----- 各 tool 的 .sum 汇总（runtest 写在构建目录里的正式结论） -----"
sum_files=$({ ls launcher.sum libdejagnu.sum report-card.sum runtest.sum 2>/dev/null || true; })
echo "  找到的 .sum 文件：$(echo "$sum_files" | tr '\n' ' ')"
for s in $sum_files; do
  echo "  ===== $s ====="
  { sed -n '/=== .* Summary ===/,$p' "$s" || true; } | sed 's/^/    /'
done
echo
echo "----- 计数统计（跨 4 个 tool 求和，取自 make check 输出） -----"
count_of() {   # <类别名>
  awk -v pat="# of $1" 'index($0, pat)==1 { n=$NF; if (n ~ /^[0-9]+$/) s+=n } END{print s+0}' "$CHECKLOG"
}
n_pass=$(count_of "expected passes")
n_fail=$(count_of "unexpected failures")
n_xsucc=$(count_of "unexpected successes")
n_xfail=$(count_of "expected failures")
n_unres=$(count_of "unresolved testcases")
n_untst=$(count_of "untested testcases")
n_unsup=$(count_of "unsupported tests")
printf '  expected passes      = %d\n' "$n_pass"
printf '  unexpected failures  = %d\n' "$n_fail"
printf '  unexpected successes = %d\n' "$n_xsucc"
printf '  expected failures    = %d\n' "$n_xfail"
printf '  unresolved testcases = %d\n' "$n_unres"
printf '  untested testcases   = %d\n' "$n_untst"
printf '  unsupported tests    = %d\n' "$n_unsup"
echo "  出现的 Summary 行："
{ grep -nE '=== .* Summary ===' "$CHECKLOG" || true; } | sed 's/^/    /'
n_summary=$({ grep -cE '=== .* Summary ===' "$CHECKLOG" || true; })
echo "  Summary 行数：$n_summary（预期 4：launcher / libdejagnu / report-card / runtest）"
echo "  失败用例明细（FAIL: / ERROR: / UNRESOLVED: 开头的行，应为空）："
{ grep -nE '^(FAIL|ERROR|UNRESOLVED|XPASS):' "$CHECKLOG" || true; } | sed 's/^/    /'
echo
echo "----- make check 结论 -----"
trc=0
if [ "$check_rc" -eq 0 ]; then echo "  OK   make check 退出码 0"
else echo "  FAIL make check 退出码 $check_rc"; trc=1; fi
if [ "$n_summary" -eq 4 ]; then echo "  OK   4 个 tool 的 Summary 全部出现"
else echo "  FAIL 只找到 $n_summary 个 Summary（预期 4），测试疑似未跑全"; trc=1; fi
for t in launcher libdejagnu report-card runtest; do
  if { grep -q "=== $t Summary ===" "$CHECKLOG"; }; then printf '    OK   %-12s 已运行\n' "$t"
  else printf '    FAIL %-12s 未运行\n' "$t"; trc=1; fi
done
if [ "$n_pass" -ge 20 ]; then echo "  OK   expected passes = $n_pass（有实打实的通过用例，测试确实跑起来了）"
else echo "  FAIL expected passes 只有 $n_pass，测试疑似未跑全"; trc=1; fi
if [ "$n_fail" -eq 0 ]; then echo "  OK   unexpected failures = 0（手册 §8.19 未允许任何失败）"
else echo "  FAIL unexpected failures = $n_fail"; trc=1; fi
if [ "$n_xsucc" -eq 0 ]; then echo "  OK   unexpected successes = 0"
else echo "  FAIL unexpected successes = $n_xsucc"; trc=1; fi
if [ "$n_unres" -eq 0 ]; then echo "  OK   unresolved testcases = 0"
else echo "  FAIL unresolved testcases = $n_unres"; trc=1; fi
[ $trc -eq 0 ] || { echo "错误：测试结果不符合手册要求" >&2; exit 1; }
echo "结论：§8.19 的 make check 退出码 0，launcher / libdejagnu / report-card / runtest"
echo "  四个 tool 全部运行，合计 expected passes=$n_pass，unexpected failures=0、"
echo "  unexpected successes=0、unresolved=0（untested=$n_untst，unsupported=$n_unsup）。"
echo

echo "----- 手册命令 7/8：make install （Install the package） -----"
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
echo "make install 完整输出："
sed 's/^/  /' "$INSTLOG"
echo

echo "----- 手册命令 8/8：安装手册生成的两份文档 -----"
echo "手册命令：install -v -dm755  /usr/share/doc/dejagnu-$VER"
install -v -dm755  /usr/share/doc/dejagnu-$VER
echo "手册命令：install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-$VER"
install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-$VER
echo "安装结果："
ls -l /usr/share/doc/dejagnu-$VER | sed 's/^/  /'
echo

echo "================= 安装后检查（手册 §8.19.2 Contents of DejaGNU） ================="
echo "手册列出的内容："
echo "  Installed programs: dejagnu and runtest"
echo "  Short Descriptions:"
echo "    dejagnu —— DejaGNU auxiliary command launcher"
echo "    runtest —— A wrapper script that locates the proper expect shell and then"
echo "               runs DejaGNU"
rc=0
echo
echo "1) Installed program：/usr/bin/dejagnu"
if [ -x /usr/bin/dejagnu ]; then
  printf '   OK   /usr/bin/dejagnu（%s 字节，%s）\n' "$(stat -Lc %s /usr/bin/dejagnu)" "$(file -b /usr/bin/dejagnu | cut -d, -f1)"
else echo "   FAIL /usr/bin/dejagnu 缺失或不可执行"; rc=1; fi
echo "   dejagnu --version："
{ dejagnu --version 2>&1 || true; } | sed -n '1,4p' | sed 's/^/     /'
dj_v=$({ dejagnu --version 2>&1 || true; } | sed -n 1p)
case "$dj_v" in
  *"$VER"*) echo "     OK   自述含 $VER" ;;
  *) echo "     FAIL 自述 '$dj_v' 不含 $VER"; rc=1 ;;
esac
echo
echo "2) Installed program：/usr/bin/runtest"
if [ -x /usr/bin/runtest ]; then
  printf '   OK   /usr/bin/runtest（%s 字节，%s）\n' "$(stat -Lc %s /usr/bin/runtest)" "$(file -b /usr/bin/runtest | cut -d, -f1)"
else echo "   FAIL /usr/bin/runtest 缺失或不可执行"; rc=1; fi
echo "   runtest --version（手册说它是'定位合适的 expect shell 再运行 DejaGNU'的包装脚本，"
echo "     这条命令会真正把 expect 拉起来，因此也顺带验证了 §8.18 的产物可被它找到）："
{ runtest --version 2>&1 || true; } | sed -n '1,6p' | sed 's/^/     /'
rt_out=$({ runtest --version 2>&1 || true; })
# runtest.exp 第 492-494 行用 "DejaGnu version\t$frame_version" 输出，分隔符是 TAB
# 而不是空格，故这里把版本号与标签分开匹配。
rt_ver=$(printf '%s\n' "$rt_out" | sed -n 's/^DejaGnu version[[:space:]]*//p' | awk 'NR==1')
echo "     解析出的 DejaGnu 版本号：'$rt_ver'"
if [ "$rt_ver" = "$VER" ]; then echo "     OK   自述 DejaGnu version = $VER"
else echo "     FAIL 自述的 DejaGnu 版本为 '$rt_ver'，与 $VER 不符"; rc=1; fi
case "$rt_out" in
  *"Expect version"*) echo "     OK   自述中报告了它找到的 Expect 版本（wrapper 已成功定位 expect shell）" ;;
  *) echo "     FAIL 自述中未报告 Expect 版本"; rc=1 ;;
esac
case "$rt_out" in
  *"Tcl version"*) echo "     OK   自述中报告了 Tcl 版本" ;;
  *) echo "     FAIL 自述中未报告 Tcl 版本"; rc=1 ;;
esac
echo
echo "3) 手册未逐项列出、但由 make install 一并装入的支撑文件"
echo "   （runtest 在运行别的包的测试套件时会读取它们；第 8 章后续多个包的 make check"
echo "     正是靠这些 .exp 库工作的）："
echo "   （注：Makefile.am 里这些库写作 pkgdata_DATA = lib/framework.exp 等，但 automake"
echo "     的 _DATA 变量安装时会剥掉目录前缀，因此它们平铺在 /usr/share/dejagnu/ 下，"
echo "     并没有 lib/ 子目录；只有 config/、baseboards/、commands/、libexec/ 这几个"
echo "     单独定义了 *dir 的组才有子目录。）"
for f in /usr/share/dejagnu/runtest.exp /usr/share/dejagnu/framework.exp \
         /usr/share/dejagnu/remote.exp /usr/share/dejagnu/target.exp \
         /usr/share/dejagnu/utils.exp /usr/share/dejagnu/dejagnu.exp \
         /usr/share/dejagnu/config/unix.exp /usr/share/dejagnu/commands/help.sh \
         /usr/share/dejagnu/baseboards/unix.exp /usr/share/dejagnu/libexec/config.guess \
         /usr/include/dejagnu.h; do
  if [ -e "$f" ]; then printf '   OK   %-46s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   /usr/share/dejagnu 目录规模：$(find /usr/share/dejagnu -type f | wc -l) 个文件，"
echo "     子目录：$({ ls -d /usr/share/dejagnu/*/ 2>/dev/null || true; } | tr '\n' ' ')"
echo
echo "4) man 页与 info（dist_man_MANS / info_TEXINFOS）："
for m in /usr/share/man/man1/dejagnu.1 /usr/share/man/man1/dejagnu-help.1 \
         /usr/share/man/man1/dejagnu-report-card.1 /usr/share/man/man1/runtest.1; do
  if [ -f "$m" ]; then printf '   OK   %-46s（%s 字节）\n' "$m" "$(stat -Lc %s "$m")"
  else printf '   FAIL %s 缺失\n' "$m"; rc=1; fi
done
if [ -f /usr/share/info/dejagnu.info ]; then
  printf '   OK   /usr/share/info/dejagnu.info（%s 字节）\n' "$(stat -Lc %s /usr/share/info/dejagnu.info)"
else echo "   FAIL /usr/share/info/dejagnu.info 缺失"; rc=1; fi
echo "   info 目录索引中的 DejaGnu 条目："
{ grep -n -i 'dejagnu' /usr/share/info/dir || true; } | sed 's/^/     /'
echo
echo "5) 手册最后两条命令装出的文档："
for f in /usr/share/doc/dejagnu-$VER/dejagnu.html /usr/share/doc/dejagnu-$VER/dejagnu.txt; do
  if [ -f "$f" ]; then
    printf '   OK   %-46s（%s 字节，权限 %s）\n' "$f" "$(stat -Lc %s "$f")" "$(stat -Lc %a "$f")"
    [ "$(stat -Lc %a "$f")" = 644 ] || { echo "   FAIL 权限不是 644（手册 install -m644）"; rc=1; }
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
d_mode=$(stat -Lc %a /usr/share/doc/dejagnu-$VER)
if [ "$d_mode" = 755 ]; then echo "   OK   /usr/share/doc/dejagnu-$VER 权限 755（手册 install -dm755）"
else echo "   FAIL /usr/share/doc/dejagnu-$VER 权限为 $d_mode"; rc=1; fi
echo
echo "6) 功能冒烟测试（用刚装好的 runtest 在源码树之外跑一个最小测试套件 ——"
echo "   这正是第 8 章后续各包 make check 使用 DejaGNU 的方式）："
src=0
smokedir=$(mktemp -d /tmp/dejagnu-smoke-XXXXXX)
# 目录布局按 runtest.exp 的约定（第 716-738 行：testsuite 必须在 $srcdir/testsuite/；
# 第 1874 行：测试树是 $testsuitedir 下名字以 $tool 开头的子目录；第 1104-1105 行：
# tool init 文件在 $testsuitedir/lib/ 下）：
#   $smokedir/testsuite/lib/smoke.exp   —— tool init 文件
#   $smokedir/testsuite/smoke.test/basic.exp —— 测试用例
mkdir -p "$smokedir/testsuite/lib" "$smokedir/testsuite/smoke.test"
cat > "$smokedir/testsuite/lib/smoke.exp" <<'EOF'
# tool init file for the "smoke" tool; nothing to set up.
proc smoke_version {} { return "smoke-1.0" }
EOF
cat > "$smokedir/testsuite/smoke.test/basic.exp" <<'EOF'
if { [catch {exec /usr/bin/echo dejagnu-smoke} output] == 0
     && $output eq "dejagnu-smoke" } {
    pass "runtest executes a program and captures its output"
} else {
    fail "runtest executes a program and captures its output"
}

set timeout 20
spawn /usr/bin/cat
send "via-pty\r"
expect {
    "via-pty" { pass "expect spawn/send/expect works under runtest" }
    timeout   { fail "expect spawn/send/expect works under runtest" }
    eof       { fail "expect spawn/send/expect works under runtest" }
}
catch { close }
catch { wait }
EOF
set +e
( cd "$smokedir" && runtest --tool smoke --srcdir "$smokedir" ) > "$smokedir/out.txt" 2>&1
smoke_rc=$?
set -e
echo "   runtest --tool smoke --srcdir <tmp> 退出码：$smoke_rc"
sed 's/^/     /' "$smokedir/out.txt"
s_pass=$(awk 'index($0,"# of expected passes")==1 { n=$NF; if (n ~ /^[0-9]+$/) s+=n } END{print s+0}' "$smokedir/out.txt")
s_fail=$(awk 'index($0,"# of unexpected failures")==1 { n=$NF; if (n ~ /^[0-9]+$/) s+=n } END{print s+0}' "$smokedir/out.txt")
echo "   冒烟结果：expected passes=$s_pass，unexpected failures=$s_fail"
if [ "$smoke_rc" -eq 0 ] && [ "$s_pass" -ge 2 ] && [ "$s_fail" -eq 0 ]; then
  echo "   OK   runtest 能在任意目录发现并执行 .exp 测试，且 expect 的 PTY 交互在其中可用"
else echo "   FAIL 冒烟测试未达预期（应为 >=2 passes / 0 failures）"; src=1; fi
rm -rf "$smokedir"
[ $src -eq 0 ] || rc=1
echo
echo "7) 本节写入系统的主要文件清单："
{ ls -ld /usr/bin/dejagnu /usr/bin/runtest /usr/include/dejagnu.h /usr/share/dejagnu \
      /usr/share/info/dejagnu.info /usr/share/man/man1/runtest.1 \
      /usr/share/doc/dejagnu-$VER 2>&1 || true; } | sed 's/^/   /'
echo
[ $rc -eq 0 ] || { echo "错误：安装后检查未全部通过" >&2; exit 1; }
echo "  OK   §8.19.2 Contents 列出的 dejagnu 与 runtest 均已就位并通过功能验证"
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.19.sh"
echo "  移入 $LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  makeinfo     完整输出：$MKINFOLOG"
echo "  make check   完整输出：$CHECKLOG"
echo "  make install 完整输出：$INSTLOG"
echo "把 4 份 .sum 也带出来存档（runtest 的正式结论文件）："
for s in launcher libdejagnu report-card runtest; do
  if [ -f "$s.sum" ]; then cp -v "$s.sum" "/sources/.dejagnu-$s.sum"; fi
done
cd /sources
rm -rf "$SRCTOP"
echo "已删除 /sources/$SRCTOP"
echo "/sources 下的解包残留（应为空）：$({ ls -d /sources/dejagnu-*/ 2>/dev/null || true; })"
echo "/sources 文件数：$(ls /sources | wc -l)"
echo "根文件系统占用："
df -h / | sed 's/^/  /'
echo
echo "===== §8.19 完成，结束时间：$(date -Is) ====="
