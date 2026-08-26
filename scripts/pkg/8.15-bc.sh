#!/usr/bin/env bash
# LFS 13.0-systemd §8.15 Bc-7.0.3
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.15.1 Installation of Bc 的命令序列（全部，一条不多一条不少）：
#   CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r
#   make
#   make test
#   make install
# 本节没有 sed、没有 patch、没有可选命令，也没有任何关于允许失败的 Note / Caution。
#
# 手册对 configure 选项的解释（§8.15.1 "The meaning of the configure options"）：
#   CC='gcc -std=c99'  This parameter specifies the compiler and C standard to use.
#   -G                 Omit parts of the test suite that won't work until the bc
#                      program has been installed.
#   -O3                Specify the optimization to use.
#   -r                 Enable the use of Readline to improve the line editing
#                      feature of bc.
set -euo pipefail

PKG=bc
VER=7.0.3
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
CONFLOG=/sources/.bc-configure.log
MAKELOG=/sources/.bc-make.log
TESTLOG=/sources/.bc-make-test.log
INSTLOG=/sources/.bc-make-install.log

echo "===== LFS 13.0-systemd §8.15 Bc-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Bc package contains an arbitrary precision numeric processing language."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 7.8 MB"
echo "手册存档：/workspace/docs/book/chapter08-bc.html（宿主机 /root/lfs/docs/book/）"
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
echo "1) 上一任务 §8.14 M4-1.4.21 的产物（确认其已完成、产物可用）："
for f in /usr/bin/m4 /usr/share/man/man1/m4.1 /usr/share/info/m4.info; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.14 未完成？）\n' "$f"; rc=1; fi
done
echo "   m4 自述版本：$(m4 --version 2>&1 | sed -n 1p)"
m4_smoke=$(printf 'define(`X'"'"',`m4-ok'"'"')X\n' | m4)
echo "   m4 冒烟：define(\`X',\`m4-ok')X -> $m4_smoke"
[ "$m4_smoke" = "m4-ok" ] || { echo "   FAIL 上一任务的 m4 不能正常展开宏"; rc=1; }
echo "   说明：Bc 不依赖 M4，此处只用于确认「上一任务产物可用」。"
echo
echo "2) §8.12 Readline-8.3（本节 configure 的 -r 选项要求可用的 readline）："
echo "   手册 -r 的原文：Enable the use of Readline to improve the line editing feature of bc."
for f in /usr/include/readline/readline.h /usr/include/readline/history.h \
         /usr/lib/libreadline.so /usr/lib/libreadline.so.8 /usr/lib/libhistory.so; do
  if [ -e "$f" ]; then printf '   OK   %-38s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.12 未完成？）\n' "$f"; rc=1; fi
done
echo "   libreadline.so.8 指向：$(readlink -f /usr/lib/libreadline.so.8)"
echo "   注意（读上游 configure.sh 后的结论）：configure.sh 的 -r 只是把 hist_impl 设成"
echo "     readline，随后它会拿 \$CC 预处理 src/history.c 做探测；**探测失败时它不会报错**，"
echo "     而是打印 'History does not work. Disabling history...' 并静默退回 hist=0、"
echo "     不再链接 -lreadline。所以本脚本必须显式核对 configure 日志里的 'History works.'"
echo "     以及生成的 Makefile 中的 -DBC_ENABLE_READLINE=1 / -lreadline。"
echo
echo "3) §8.5 Glibc-2.43 的 C 库与工具链（本节要 configure + 编译 C 代码）："
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
if gcc -std=c99 -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && \
   [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc -std=c99 编译并运行最小 C 程序成功（手册用的正是 CC='gcc -std=c99'）"
else echo "   FAIL 无法用 gcc -std=c99 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "5) 本节直接依赖的工具（解包 + configure + make + make test + 安装）："
for t in tar xz make gcc ld sed grep awk install ln rm mkdir cat sh \
         readlink stat find file ldd sort head tail tr wc dirname basename gencat locale; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   sh   ：$(readlink -f "$(command -v sh)")（configure.sh 与 tests/*.sh 都是 POSIX sh 脚本）"
echo "   说明：gencat 来自 §8.5 Glibc，configure.sh 用它探测 NLS（消息目录）支持；"
echo "     locale -a 决定 make install 实际安装哪些 .cat 文件（未给 --install-all-locales）。"
echo
echo "6) 安装目标目录（手册 §8.15.2 Contents：Installed programs: bc and dc）："
for d in /usr/bin /usr/share/man/man1 /usr/share/locale; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo
echo "7) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo
echo "8) §7.3 虚拟内核文件系统与 §7.6 基础文件（测试脚本要读写 /dev、/proc、/tmp）："
for f in /dev/null /dev/zero /dev/urandom /dev/tty /proc/self /sys \
         /etc/passwd /etc/group /tmp /var/tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "9) 安装前系统中的 bc / dc 痕迹（Bc 在第 5–7 章从未构建过，预期全部不存在）："
for f in /usr/bin/bc /usr/bin/dc /usr/share/man/man1/bc.1 /usr/share/man/man1/dc.1; do
  if [ -e "$f" ]; then printf '   INFO %-32s 已存在（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   INFO %-32s 不存在（符合预期：本节是首次安装）\n' "$f"; fi
done
echo
echo "10) 磁盘空间（手册要求 7.8 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 102400 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 7.8 MB"
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
echo "上游版本自述（Bc 不用 autoconf，版本写在 include/version.h）："
{ grep -n '#define VERSION' include/version.h || true; } | sed 's/^/  /'
src_ver=$(sed -n 's/^#define VERSION[[:space:]]\+//p' include/version.h | awk 'NR==1')
echo "  include/version.h：VERSION = $src_ver"
if [ "$src_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $src_ver 与手册 §8.15 的 Bc-$VER 一致"
else echo "  FAIL 源码自述版本为 '$src_ver'，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁、无 sed：手册 §8.15 的命令序列只有 configure/make/make test/make install"
bc_patches=$(ls /sources | grep -E '^bc.*patch' || true)
echo "  （/sources 中匹配 bc*patch 的文件：${bc_patches:-无}）"
echo "  configure 与 configure.sh 的关系："
ls -l configure configure.sh | sed 's/^/    /'
echo

echo "----- 测试结构预读（决定 make test 的判定标准） -----"
echo "上游 Makefile.in 中 test 目标的构成（%%TESTS%% 由 configure.sh 替换）："
{ grep -nE '^(check|test):' Makefile.in || true; } | sed 's/^/  /'
echo "  configure.sh 里 tests 的默认值（bc 与 dc 都构建时）："
{ grep -n '^tests="test_bc timeconst test_dc"' configure.sh || true; } | sed 's/^/    /'
echo "成功标志（Makefile.in 中 test_bc / test_dc 的收尾 printf）："
{ grep -nE "All (bc|dc) tests passed" Makefile.in || true; } | sed 's/^/  /'
echo "-G（--disable-generated-tests）的作用（configure.sh）："
{ grep -nE '^\t\tG\) generate_tests=0' configure.sh || true; } | sed 's/^/  /'
echo "  该变量最终作为 tests/test.sh 的第 3 个位置参数 generate_tests 传入；"
echo "  tests/test.sh 在 generate_tests=0 且没有现成期望输出时打印 'Skipping <d> <t> test'："
{ grep -nE "printf 'Skipping %s %s test" tests/test.sh || true; } | sed 's/^/    /'
echo "  这正是手册对 -G 的说明：Omit parts of the test suite that won't work until"
echo "  the bc program has been installed."
echo "单个用例通过时 tests/test.sh 的收尾（exec printf 'pass'）："
{ grep -n "exec printf 'pass" tests/test.sh || true; } | sed 's/^/  /'
echo "history 测试不在 test 目标内（它属于 history_all_tests / test_history 目标）："
{ grep -nE '^(history_all_tests|test_history):' Makefile.in || true; } | sed 's/^/  /'
echo "判定标准（手册 §8.15 无任何允许失败的 Note/Caution）："
echo "  make test 退出码必须为 0；输出中必须同时出现 'All bc tests passed.' 与"
echo "  'All dc tests passed.'；不得出现失败/错误行。'Skipping ... test' 是 -G 的"
echo "  预期效果，逐条列出说明。"
echo

echo "================= 8.15.1. Installation of Bc ================="
echo
echo "----- 手册命令 1/4：configure -----"
echo "手册原文：Prepare Bc for compilation:"
echo "手册命令：CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "configure 完整输出（$(wc -l < "$CONFLOG") 行）："
sed 's/^/  /' "$CONFLOG"
echo

echo "----- 核对手册的 4 个 configure 选项确实生效 -----"
crc=0
if [ ! -f Makefile ]; then echo "  FAIL configure 未生成 Makefile"; exit 1; fi
echo "a) --prefix=/usr —— 生成的 Makefile 中的安装路径变量："
{ grep -nE '^(PREFIX|BINDIR|INCLUDEDIR|LIBDIR|MAN1DIR|MAN3DIR|NLSPATH|DESTDIR) = ' Makefile || true; } | sed 's/^/    /'
got_bindir=$(sed -n 's/^BINDIR = //p' Makefile | awk 'NR==1')
got_man1=$(sed -n 's/^MAN1DIR = //p' Makefile | awk 'NR==1')
if [ "$got_bindir" = /usr/bin ]; then echo "    OK   BINDIR = /usr/bin（--prefix=/usr 生效）"
else echo "    FAIL BINDIR 为 '$got_bindir'，不是 /usr/bin"; crc=1; fi
if [ "$got_man1" = /usr/share/man/man1 ]; then echo "    OK   MAN1DIR = /usr/share/man/man1"
else echo "    FAIL MAN1DIR 为 '$got_man1'"; crc=1; fi
echo "b) CC='gcc -std=c99' —— 编译器与 C 标准："
{ grep -nE '^(CC|CFLAGS) = ' Makefile || true; } | sed 's/^/    /'
mk_cc=$(sed -n 's/^CC = //p' Makefile | awk 'NR==1')
mk_cflags=$(sed -n 's/^CFLAGS = //p' Makefile | awk 'NR==1')
if [ "$mk_cc" = "gcc" ]; then echo "    OK   CC = gcc"
else echo "    FAIL CC 为 '$mk_cc'"; crc=1; fi
case " $mk_cflags " in
  *" -std=c99 "*) echo "    OK   CFLAGS 含 -std=c99" ;;
  *) echo "    FAIL CFLAGS 不含 -std=c99：$mk_cflags"; crc=1 ;;
esac
echo "c) -O3 —— 优化级别："
case " $mk_cflags " in
  *" -O3 "*) echo "    OK   CFLAGS 含 -O3" ;;
  *) echo "    FAIL CFLAGS 不含 -O3：$mk_cflags"; crc=1 ;;
esac
echo "d) -r —— 启用 Readline（configure.sh 探测失败会静默回退，故三重核对）："
echo "    d1) configure 日志中的 history 探测结论："
{ grep -nE '^(Testing history|History works|History does not work|Disabling history|Forcing history)' "$CONFLOG" || true; } | sed 's/^/       /'
hist_ok=$(grep -c '^History works\.$' "$CONFLOG" || true)
hist_bad=$(grep -c '^Disabling history\.\.\.$' "$CONFLOG" || true)
if [ "$hist_ok" -ge 1 ] && [ "$hist_bad" -eq 0 ]; then
  echo "       OK   configure 报告 'History works.'，未回退"
else
  echo "       FAIL history 探测未成功（History works=$hist_ok，Disabling=$hist_bad）"; crc=1
fi
echo "    d2) 生成的 Makefile 中的 readline 宏与链接选项："
{ grep -nE '^(BC_ENABLE_HISTORY|BC_ENABLE_NLS) = ' Makefile || true; } | sed 's/^/       /'
{ grep -nE '^LDFLAGS = ' Makefile || true; } | sed 's/^/       /'
mk_ldflags=$(sed -n 's/^LDFLAGS = //p' Makefile | awk 'NR==1')
case " $mk_cflags " in
  *" -DBC_ENABLE_READLINE=1 "*) echo "       OK   CFLAGS 含 -DBC_ENABLE_READLINE=1" ;;
  *) echo "       FAIL CFLAGS 不含 -DBC_ENABLE_READLINE=1"; crc=1 ;;
esac
case " $mk_cflags " in
  *" -DBC_ENABLE_EDITLINE=0 "*) echo "       OK   CFLAGS 含 -DBC_ENABLE_EDITLINE=0（未选 editline）" ;;
  *) echo "       INFO CFLAGS 中未见 -DBC_ENABLE_EDITLINE=0" ;;
esac
case " $mk_ldflags " in
  *" -lreadline "*) echo "       OK   LDFLAGS 含 -lreadline" ;;
  *) echo "       FAIL LDFLAGS 不含 -lreadline：$mk_ldflags"; crc=1 ;;
esac
mk_hist=$(sed -n 's/^BC_ENABLE_HISTORY = //p' Makefile | awk 'NR==1')
if [ "$mk_hist" = 1 ]; then echo "       OK   BC_ENABLE_HISTORY = 1"
else echo "       FAIL BC_ENABLE_HISTORY = '$mk_hist'"; crc=1; fi
echo "e) -G —— 测试用例的 generate_tests 参数（tests/test.sh 的第 3 个位置参数）："
echo "    Makefile 中 test.sh 调用的样例："
{ grep -nE 'test\.sh (bc|dc) [a-z0-9_]+ ' Makefile || true; } | head -n 3 | sed 's/^/      /'
gen0=$(grep -cE 'test\.sh (bc|dc) [a-z0-9_]+ 0 0 ' Makefile || true)
gen1=$(grep -cE 'test\.sh (bc|dc) [a-z0-9_]+ 1 [01] ' Makefile || true)
echo "    generate_tests=0 的调用条数：$gen0；generate_tests=1 的调用条数：$gen1"
if [ "$gen0" -gt 0 ] && [ "$gen1" -eq 0 ]; then
  echo "    OK   全部测试调用的 generate_tests 均为 0（-G 生效）"
else
  echo "    FAIL -G 未生效（gen0=$gen0 gen1=$gen1）"; crc=1
fi
echo "f) test 目标的构成（应为 test_bc timeconst test_dc）："
{ grep -nE '^test: ' Makefile || true; } | sed 's/^/    /'
echo "g) install 目标的构成（据此确定本节会写入系统的东西）："
{ grep -nE '^install: ' Makefile || true; } | sed 's/^/    /'
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册的选项要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册的 CC='gcc -std=c99' + --prefix=/usr + -G + -O3 + -r"
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
echo "  bin/ 目录（上游 scripts/link.sh 把 dc 做成指向 bc 的符号链接）："
ls -l bin | sed 's/^/    /'
if [ -x bin/bc ] && [ ! -L bin/bc ]; then
  printf '  OK   %-10s %s 字节，%s\n' "bin/bc" "$(stat -Lc %s bin/bc)" "$(file -b bin/bc | cut -d, -f1-2)"
else echo "  FAIL bin/bc 未生成或不是普通可执行文件"; mrc=1; fi
if [ -L bin/dc ]; then
  echo "  OK   bin/dc 是符号链接 -> $(readlink bin/dc)（上游 scripts/link.sh 的设计）"
else echo "  FAIL bin/dc 不是符号链接"; mrc=1; fi
echo "  构建产物自述版本："
build_bc_ver=$(./bin/bc --version 2>&1 | sed -n 1p)
build_dc_ver=$(./bin/dc --version 2>&1 | sed -n 1p)
echo "    bc: $build_bc_ver"
echo "    dc: $build_dc_ver"
case "$build_bc_ver" in *"$VER"*) echo "    OK   bc 自述含 $VER" ;; *) echo "    FAIL bc 自述不含 $VER"; mrc=1 ;; esac
case "$build_dc_ver" in *"$VER"*) echo "    OK   dc 自述含 $VER" ;; *) echo "    FAIL dc 自述不含 $VER"; mrc=1 ;; esac
echo "  bin/bc 的动态依赖（-r 生效则必须链接 libreadline）："
ldd bin/bc | sed 's/^/    /'
ldd_build=$(ldd bin/bc)
case "$ldd_build" in
  *libreadline.so*) echo "    OK   链接到 libreadline（手册 -r 选项确实生效）" ;;
  *) echo "    FAIL 未链接 libreadline —— -r 未生效"; mrc=1 ;;
esac
echo "  冒烟测试（未安装的构建产物）："
smoke_bc=$(echo '2^100' | ./bin/bc)
echo "    bc: 2^100 -> $smoke_bc"
[ "$smoke_bc" = "1267650600228229401496703205376" ] || { echo "    FAIL bc 冒烟结果不符"; mrc=1; }
smoke_dc=$(printf '5 3 + p\n' | ./bin/dc)
echo "    dc: 5 3 + p -> $smoke_dc"
[ "$smoke_dc" = "8" ] || { echo "    FAIL dc 冒烟结果不符"; mrc=1; }
echo "  man page 源（上游随包提供，manuals/ 下）："
for f in manuals/bc/A.1 manuals/dc/A.1; do
  if [ -f "$f" ]; then printf '    OK   %-18s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '    INFO %s 不存在\n' "$f"; fi
done
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 3/4：make test（本节的测试） -----"
echo "手册原文：To test bc, run:  make test"
echo "（手册 §8.15 全节没有任何关于测试结果的 Note / Caution，即要求测试全部通过。"
echo "  判定：退出码 0 + 同时出现 'All bc tests passed.' 与 'All dc tests passed.'。"
echo "  'Skipping <d> <t> test' 是手册 -G 选项的预期效果，逐条列出。）"
echo "完整输出写入 $TESTLOG。"
set +e
make test > "$TESTLOG" 2>&1
test_rc=$?
set -e
echo
echo "----- make test 完整输出（$(wc -l < "$TESTLOG") 行） -----"
sed 's/^/  /' "$TESTLOG"
echo "----- make test 完整输出结束 -----"
echo
echo "----- make test 结论 -----"
echo "make test 退出码：$test_rc"
n_pass=$(grep -c 'pass$' "$TESTLOG" || true)
n_skip=$(grep -c '^Skipping ' "$TESTLOG" || true)
n_run=$(grep -c '^Running ' "$TESTLOG" || true)
echo "  以 'pass' 结尾的行数（通过的用例数）：$n_pass"
echo "  'Running ...' 行数：$n_run"
echo "  'Skipping ... test' / 'Skipping ... script' 行数（-G 的预期效果）：$n_skip"
echo "  被跳过的用例逐条列出："
{ grep -n '^Skipping ' "$TESTLOG" || true; } | sed 's/^/    /'
echo "  timeconst 相关输出（tests/bc/scripts/timeconst.bc 未随包分发时只告警）："
{ grep -niE 'timeconst' "$TESTLOG" || true; } | sed 's/^/    /'
echo "  收尾标志行："
{ grep -nE '^All (bc|dc) tests passed\.$' "$TESTLOG" || true; } | sed 's/^/    /'
echo "  输出中是否存在错误/失败字样（仅作展示，判定以退出码与收尾标志为准）："
{ grep -niE '^(.*(error|failed|fail:).*)$' "$TESTLOG" || true; } | head -n 20 | sed 's/^/    /'
echo
if [ "$test_rc" -ne 0 ]; then
  echo "错误：make test 退出码非 0（$test_rc）—— 手册对本节没有允许失败的说明" >&2
  echo "  make test 末尾 60 行：" >&2
  tail -n 60 "$TESTLOG" | sed 's/^/  /' >&2
  exit "$test_rc"
fi
trc=0
bc_ok=$(grep -c '^All bc tests passed\.$' "$TESTLOG" || true)
dc_ok=$(grep -c '^All dc tests passed\.$' "$TESTLOG" || true)
if [ "$bc_ok" -ge 1 ]; then echo "  OK   出现 'All bc tests passed.'"
else echo "  FAIL 未出现 'All bc tests passed.'"; trc=1; fi
if [ "$dc_ok" -ge 1 ]; then echo "  OK   出现 'All dc tests passed.'"
else echo "  FAIL 未出现 'All dc tests passed.'"; trc=1; fi
if [ "$n_pass" -gt 300 ]; then echo "  OK   通过用例数 $n_pass（量级正常）"
else echo "  FAIL 通过用例数只有 $n_pass，测试疑似未真正运行"; trc=1; fi
[ $trc -eq 0 ] || { echo "错误：测试结果不符合手册要求" >&2; exit 1; }
echo
echo "结论：§8.15 的 make test 退出码 0，bc 与 dc 两套测试均打印了各自的"
echo "  'All <x> tests passed.' 收尾标志；通过 $n_pass 例，跳过 $n_skip 例。"
echo "  跳过的用例全部来自手册要求的 -G（--disable-generated-tests）：这些用例的期望"
echo "  输出需要用一个**已安装的** bc 现场生成，手册明确说明 -G 就是 'Omit parts of the"
echo "  test suite that won't work until the bc program has been installed.'，"
echo "  因此属于手册规定的正常结果，不是失败。手册 §8.15 未列出任何允许的失败项，"
echo "  本次也确无失败项。"
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
echo "make install 完整输出："
sed 's/^/  /' "$INSTLOG"
echo

echo "----- 安装后检查（手册 §8.15.2 Contents of Bc） -----"
echo "手册列出的内容："
echo "  Installed programs: bc and dc"
echo "  bc：A command line calculator"
echo "  dc：A reverse-polish command line calculator"
rc=0
echo "1) Installed program：/usr/bin/bc"
if [ -x /usr/bin/bc ]; then
  printf '   OK   /usr/bin/bc（%s 字节，%s）\n' "$(stat -Lc %s /usr/bin/bc)" "$(file -b /usr/bin/bc | cut -d, -f1-2)"
else echo "   FAIL /usr/bin/bc 缺失或不可执行"; rc=1; fi
echo "2) Installed program：/usr/bin/dc"
if [ -x /usr/bin/dc ]; then
  printf '   OK   /usr/bin/dc（%s，%s）\n' "$(ls -l /usr/bin/dc | awk '{print $5" 字节"}')" "$(file -b /usr/bin/dc | cut -d, -f1)"
  if [ -L /usr/bin/dc ]; then echo "        /usr/bin/dc -> $(readlink /usr/bin/dc)（上游 exec-install.sh 保留符号链接形式）"
  else echo "        /usr/bin/dc 是独立文件（非符号链接）"; fi
else echo "   FAIL /usr/bin/dc 缺失或不可执行"; rc=1; fi
inst_bc_ver=$(bc --version 2>&1 | sed -n 1p)
inst_dc_ver=$(dc --version 2>&1 | sed -n 1p)
echo "   已安装 bc 自述版本：$inst_bc_ver"
echo "   已安装 dc 自述版本：$inst_dc_ver"
case "$inst_bc_ver" in *"$VER"*) echo "   OK   bc 自述含 $VER" ;; *) echo "   FAIL bc 自述不含 $VER"; rc=1 ;; esac
case "$inst_dc_ver" in *"$VER"*) echo "   OK   dc 自述含 $VER" ;; *) echo "   FAIL dc 自述不含 $VER"; rc=1 ;; esac
echo "   命令来源（PATH 解析）：bc=$(command -v bc)  dc=$(command -v dc)"
echo "   动态依赖（应链接 libreadline 且不含任何 /tools 路径）："
ldd /usr/bin/bc | sed 's/^/     /'
ldd_out=$(ldd /usr/bin/bc)
case "$ldd_out" in
  *"/tools/"*) echo "     FAIL 仍链接 /tools 下的库"; rc=1 ;;
  *) echo "     OK   未链接任何 /tools 路径" ;;
esac
case "$ldd_out" in
  *libc.so.6*) echo "     OK   链接到 libc.so.6" ;;
  *) echo "     FAIL 未链接 libc.so.6"; rc=1 ;;
esac
case "$ldd_out" in
  *libreadline.so*) echo "     OK   链接到 libreadline（手册 -r 选项的成果，依赖 §8.12 Readline-8.3）" ;;
  *) echo "     FAIL 未链接 libreadline"; rc=1 ;;
esac
echo "3) 手册 Contents 未逐条列出、但由 make install 一并安装的文件："
for f in /usr/share/man/man1/bc.1 /usr/share/man/man1/dc.1; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   bc.1 首行：$(head -n1 /usr/share/man/man1/bc.1)"
echo "   dc.1 首行：$(head -n1 /usr/share/man/man1/dc.1)"
echo "   NLS 消息目录（NLSPATH=$(sed -n 's/^NLSPATH = //p' Makefile | awk 'NR==1')，"
echo "     未给 --install-all-locales 时只安装系统 locale -a 里存在的那些）："
cat_list=$(find /usr/share/locale -name 'bc' -type f 2>/dev/null | sort || true)
cat_link=$(find /usr/share/locale -name 'bc' -type l 2>/dev/null | sort || true)
echo "     普通 .cat 文件数：$(printf '%s\n' "$cat_list" | grep -c . || true)"
echo "     符号链接数      ：$(printf '%s\n' "$cat_link" | grep -c . || true)"
{ printf '%s\n' "$cat_list" "$cat_link" | grep . || true; } | head -n 20 | sed 's/^/       /'
echo "4) 本节不应安装库/头文件（未给 -a/--library，install 目标里没有 install_library）："
for f in /usr/lib/libbcl.a /usr/lib/libbcl.so /usr/include/bcl.h; do
  if [ -e "$f" ]; then echo "   FAIL 不应存在的 $f"; rc=1; else printf '   OK   %-22s 不存在（符合预期）\n' "$f"; fi
done
echo

echo "----- 功能验证（对照手册 §8.15.2 的两条描述，逐项用已安装的 /usr/bin 程序验证） -----"
tmpd=$(mktemp -d /tmp/bc-verify-XXXXXX)
echo "A. bc —— A command line calculator"
echo "a1) 命令行计算器的基本形态：从标准输入读表达式并打印结果"
cat > "$tmpd/a1.bc" <<'EOF'
3 + 4 * 2
EOF
out_a1=$(bc < "$tmpd/a1.bc")
echo "     3 + 4 * 2 -> $out_a1"
if [ "$out_a1" = "11" ]; then echo "     OK   运算符优先级与求值正确"
else echo "     FAIL 期望 11"; rc=1; fi
echo "a2) arbitrary precision（手册简介：arbitrary precision numeric processing language）"
out_a2=$(echo '2^200' | bc)
echo "     2^200 -> $out_a2"
if [ "$out_a2" = "1606938044258990275541962092341162602522202993782792835301376" ]; then
  echo "     OK   61 位大整数精确无误（非 double 精度）"
else echo "     FAIL 2^200 结果不符"; rc=1; fi
echo "a3) scale（任意小数位）"
out_a3=$(echo 'scale=40; 1/3' | bc)
echo "     scale=40; 1/3 -> $out_a3"
if [ "$out_a3" = ".3333333333333333333333333333333333333333" ]; then
  echo "     OK   小数位数与取值正确（注意本 bc 输出不带前导 0）"
else echo "     FAIL scale=40 的 1/3 结果不符"; rc=1; fi
echo "a4) 数学库 -l（sin/cos，验证 numeric processing language 的函数支持）"
out_a4=$(echo 'scale=20; s(0)+c(0)' | bc -l)
echo "     scale=20; s(0)+c(0) -> $out_a4"
if [ "$out_a4" = "1.00000000000000000000" ]; then echo "     OK   -l 数学库可用（sin(0)+cos(0)=1）"
else echo "     FAIL -l 数学库结果不符"; rc=1; fi
echo "a5) language：自定义函数 + 递归 + 循环"
cat > "$tmpd/a5.bc" <<'EOF'
define f(n) {
    if (n < 2) return (1)
    return (n * f(n - 1))
}
f(30)
EOF
out_a5=$(bc "$tmpd/a5.bc" < /dev/null)
echo "     f(n)=n! 递归，f(30) -> $out_a5"
if [ "$out_a5" = "265252859812191058636308480000000" ]; then echo "     OK   函数定义与递归展开正确"
else echo "     FAIL 30! 结果不符"; rc=1; fi
echo "a6) 命令行开关 -e（command line calculator 的非交互用法）"
out_a6=$(bc -e '3*4' -e 'quit')
echo "     bc -e '3*4' -e quit -> $out_a6"
if [ "$out_a6" = "12" ]; then echo "     OK   -e 表达式求值正确"
else echo "     FAIL -e 结果不符"; rc=1; fi
echo "a7) 错误路径：语法错误应有诊断且退出码非 0"
cat > "$tmpd/a7.bc" <<'EOF'
x=
EOF
set +e
bc < "$tmpd/a7.bc" > "$tmpd/a7.out" 2>&1
err_rc=$?
set -e
echo "     退出码：$err_rc"
echo "     诊断输出：$({ grep -m1 . "$tmpd/a7.out" || true; })"
if [ "$err_rc" -ne 0 ]; then echo "     OK   语法错误时返回非 0"
else echo "     FAIL 语法错误却返回 0"; rc=1; fi
echo
echo "B. dc —— A reverse-polish command line calculator"
echo "b1) 逆波兰（后缀）求值：操作数先入栈，运算符后置"
out_b1=$(printf '5 3 + p\n' | dc)
echo "     5 3 + p -> $out_b1"
if [ "$out_b1" = "8" ]; then echo "     OK   后缀加法正确"
else echo "     FAIL 期望 8"; rc=1; fi
echo "b2) 操作数顺序（减法非交换，可证明确实是 RPN 而非中缀）"
out_b2=$(printf '5 3 - p\n' | dc)
echo "     5 3 - p -> $out_b2（RPN 语义为 5-3；若按中缀读则应是 3-5=-2）"
if [ "$out_b2" = "2" ]; then echo "     OK   逆波兰操作数顺序正确"
else echo "     FAIL 期望 2"; rc=1; fi
echo "b3) 幂与任意精度"
out_b3=$(printf '2 200 ^ p\n' | dc)
echo "     2 200 ^ p -> $out_b3"
if [ "$out_b3" = "1606938044258990275541962092341162602522202993782792835301376" ]; then
  echo "     OK   dc 同样是任意精度"
else echo "     FAIL dc 的 2^200 结果不符"; rc=1; fi
echo "b4) 精度寄存器 k 与开方 v"
out_b4=$(printf '20k 2v p\n' | dc)
echo "     20k 2v p -> $out_b4"
if [ "$out_b4" = "1.41421356237309504880" ]; then echo "     OK   k 设定小数位、v 开方均正确"
else echo "     FAIL sqrt(2) 结果不符"; rc=1; fi
echo "b5) 寄存器与栈操作（s 存、l 取、p 打印栈顶）"
out_b5=$(printf '7 sa 6 sb la lb * p\n' | dc)
echo "     7 sa 6 sb la lb * p -> $out_b5"
if [ "$out_b5" = "42" ]; then echo "     OK   寄存器存取与乘法正确"
else echo "     FAIL 期望 42"; rc=1; fi
echo "b6) bc 与 dc 是同一个可执行文件的两种人格（argv[0] 决定）"
echo "     /usr/bin/bc inode：$(stat -Lc %i /usr/bin/bc)   /usr/bin/dc inode：$(stat -Lc %i /usr/bin/dc)"
if [ "$(stat -Lc %i /usr/bin/bc)" = "$(stat -Lc %i /usr/bin/dc)" ]; then
  echo "     OK   两者解析到同一 inode（dc 是指向 bc 的符号链接，见上游 scripts/link.sh）"
else
  echo "     INFO 两者不是同一文件（上游若改为分别安装亦属正常）"
fi
rm -rf "$tmpd"
echo
echo "5) 本节写入系统的文件清单："
{ ls -l /usr/bin/bc /usr/bin/dc /usr/share/man/man1/bc.1 /usr/share/man/man1/dc.1 2>/dev/null || true; } | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Bc 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.15.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make test    完整输出：$TESTLOG"
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
echo "===== §8.15 完成，结束时间：$(date -Is) ====="
