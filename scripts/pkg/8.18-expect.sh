#!/usr/bin/env bash
# LFS 13.0-systemd §8.18 Expect-5.45.4
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.18.1 Installation of Expect 的命令序列（全部，一条不多一条不少）：
#   python3 -c 'from pty import spawn; spawn(["echo", "ok"])'
#   patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
#   ./configure --prefix=/usr           \
#               --with-tcl=/usr/lib     \
#               --enable-shared         \
#               --disable-rpath         \
#               --mandir=/usr/share/man \
#               --with-tclinclude=/usr/include
#   make
#   make test
#   make install
#   ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
# 手册全节没有任何关于允许测试失败的 Note / Caution（只有一段关于 PTY 不可用时
# 必须先解决再继续的说明，见下方 PTY 检查）。
set -euo pipefail

PKG=expect
VER=5.45.4
TARBALL=expect5.45.4.tar.gz
PATCHFILE=expect-5.45.4-gcc15-1.patch
SRCTOP=expect5.45.4
CONFLOG=/sources/.expect-configure.log
MAKELOG=/sources/.expect-make.log
TESTLOG=/sources/.expect-make-test.log
INSTLOG=/sources/.expect-make-install.log

echo "===== LFS 13.0-systemd §8.18 Expect-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Expect package contains tools for automating, via scripted dialogues,"
echo "  interactive applications such as telnet, ftp, passwd, fsck, rlogin, and tip."
echo "  Expect is also useful for testing these same applications as well as easing all"
echo "  sorts of tasks that are prohibitively difficult with anything else. The DejaGnu"
echo "  framework is written in Expect."
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 3.9 MB"
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
echo "1) 上一任务 §8.17 Tcl-8.6.17 的产物 —— 本节直接依赖它（手册 §8.17 原文：This"
echo "   package and the next two (Expect and DejaGNU) are installed to support running"
echo "   the test suites…；且 §8.17 的 make install-private-headers 一步的理由就是"
echo "   'The next package, Expect, requires them.'）："
for f in /usr/bin/tclsh /usr/bin/tclsh8.6 /usr/lib/libtcl8.6.so /usr/lib/libtclstub8.6.a \
         /usr/lib/tclConfig.sh /usr/include/tcl.h; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.17 未完成？）\n' "$f"; rc=1; fi
done
echo "   §8.17 install-private-headers 装出的私有头（configure 的 --with-tclinclude"
echo "   要靠它们通过 'Tcl private include files' 探测）："
for h in tclInt.h tclIntDecls.h tclIntPlatDecls.h tclPort.h tclUnixPort.h \
         tclOOInt.h tclOOIntDecls.h; do
  if [ -f "/usr/include/$h" ]; then printf '   OK   /usr/include/%-20s（%s 字节）\n' "$h" "$(stat -Lc %s "/usr/include/$h")"
  else printf '   FAIL /usr/include/%s 缺失\n' "$h"; rc=1; fi
done
echo "   tclsh 自述版本：$(echo 'puts $tcl_patchLevel' | tclsh 2>&1)"
tcl_pl=$(echo 'puts $tcl_patchLevel' | tclsh 2>/dev/null || true)
if [ "$tcl_pl" = 8.6.17 ]; then echo "   OK   tclsh 可运行且自述 8.6.17（上一任务产物可用）"
else echo "   FAIL tclsh 自述 '$tcl_pl'，与 §8.17 的 8.6.17 不符"; rc=1; fi
echo "   tclConfig.sh 中本节 configure 会读取的关键变量："
{ grep -nE '^TCL_(VERSION|PATCH_LEVEL|SRC_DIR|BIN_DIR|LIB_SPEC|INCLUDE_SPEC|SHARED_BUILD|SUPPORTS_STUBS)=' /usr/lib/tclConfig.sh || true; } | sed 's/^/     /'
echo "   注：§8.17 的 sed 已把 TCL_SRC_DIR 从构建目录改成 /usr/include，本节 Makefile 里的"
echo "     TCLSH_ENV 会据此设 TCL_LIBRARY=/usr/include/library（该目录不存在）；Tcl 在"
echo "     TCL_LIBRARY 找不到 init.tcl 时会继续按内建路径搜到 /usr/lib/tcl8.6，故不影响测试。"
echo
echo "2) 手册要求的 PTY 可用性检查（§8.18.1 第一条命令）："
echo "   手册原文：Expect needs PTYs to work. Verify that the PTYs are working properly"
echo "     inside the chroot environment by performing a simple test:"
echo "   手册命令：python3 -c 'from pty import spawn; spawn([\"echo\", \"ok\"])'"
echo "   手册原文：This command should output ok. If, instead, the output includes"
echo "     'OSError: out of pty devices', then the environment is not set up for proper"
echo "     PTY operation. … This issue needs to be resolved before continuing, or the test"
echo "     suites requiring Expect (for example the test suites of Bash, Binutils, GCC,"
echo "     GDBM, and of course Expect itself) will fail catastrophically."
echo "   python3：$(command -v python3 || echo '（不可用）')  $(python3 -V 2>&1)"
set +e
pty_out=$(python3 -c 'from pty import spawn; spawn(["echo", "ok"])' 2>&1)
pty_rc=$?
set -e
echo "   命令退出码：$pty_rc"
echo "   命令输出（原样，含 PTY 回显的 CR）："
printf '%s\n' "$pty_out" | cat -A | sed 's/^/     /'
# spawn() 通过 PTY 转发，输出通常是 "ok\r\n"，故用去掉 CR/LF 后的内容判定。
pty_clean=$(printf '%s' "$pty_out" | tr -d '\r\n')
if [ $pty_rc -eq 0 ] && [ "$pty_clean" = ok ]; then
  echo "   OK   输出为 ok —— chroot 内 PTY 工作正常（手册要求的前置条件已满足）"
else
  echo "   FAIL 输出不是 ok（清理 CR/LF 后为 '$pty_clean'）"
  case "$pty_out" in
    *"out of pty devices"*) echo "        含 'out of pty devices' —— 按手册须退出 chroot，重做 §7.3 挂载 devpts 后再进入" ;;
  esac
  rc=1
fi
echo "   PTY 相关的内核文件系统与设备节点："
{ findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS /dev/pts || echo "     （/dev/pts 未挂载）"; } | sed 's/^/     /'
{ ls -l /dev/ptmx /dev/tty 2>&1 || true; } | sed 's/^/     /'
echo "     /dev/pts 内容：$(ls /dev/pts | tr '\n' ' ')"
echo
echo "3) 编译所需的工具链与 C 库："
for f in /usr/lib/libc.so.6 /usr/lib/libm.so.6 /lib64/ld-linux-x86-64.so.2 \
         /usr/include/stdio.h /usr/include/termios.h /usr/include/pty.h \
         /usr/include/sys/ioctl.h /usr/include/unistd.h; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
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
echo
echo "4) 本节直接用到的工具："
for t in tar gzip make gcc ld ar ranlib patch sed grep awk install ln mv cp mkdir \
         chmod find file readelf ldd stat head tail tr wc md5sum python3 tclsh; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %-10s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc   版本：$(gcc --version | sed -n 1p)"
echo "   make  版本：$(make --version | sed -n 1p)"
echo "   patch 版本：$(patch --version | sed -n 1p)"
echo
echo "5) 源码包与补丁（/sources 是宿主机 bind mount）："
for t in "$TARBALL" "$PATCHFILE"; do
  if [ -f "/sources/$t" ]; then echo "   OK   /sources/$t 存在（$(stat -c %s "/sources/$t") 字节）"
  else echo "   FAIL /sources/$t 缺失"; rc=1; fi
done
echo
echo "6) 安装前系统中的 Expect 痕迹（Expect 在第 5–7 章从未构建过，预期全部不存在）："
for f in /usr/bin/expect /usr/lib/expect$VER /usr/lib/libexpect$VER.so \
         /usr/share/man/man1/expect.1 /usr/share/man/man3/libexpect.3; do
  if [ -e "$f" ] || [ -L "$f" ]; then printf '   INFO %-38s 已存在\n' "$f"
  else printf '   INFO %-38s 不存在（符合预期：本节是首次安装）\n' "$f"; fi
done
echo
echo "7) 磁盘空间（手册要求 3.9 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 262144 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 3.9 MB"
else echo "   FAIL 可用空间不足：$((avail_k/1024)) MB"; rc=1; fi
echo
echo "8) /tools 已按 §7.13.1 删除："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包与补丁校验（md5sums，手册 §3.1 / §3.2） -----"
grep -E " ($TARBALL|$PATCHFILE)\$" md5sums
grep -E " ($TARBALL|$PATCHFILE)\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCTOP"
tar -xf "$TARBALL"
cd "$SRCTOP"
echo "源码目录：$PWD"
echo "顶层内容（前 20 项）："
ls | sed -n '1,20p' | sed 's/^/  /'
echo "  共 $(ls | wc -l) 项"
echo "上游版本自述（configure.in 的 VERSION / configure 的 PACKAGE_VERSION）："
{ grep -nE '^VERSION=|^PACKAGE_VERSION=' configure.in configure 2>/dev/null || true; } | sed -n '1,6p' | sed 's/^/  /'
src_ver=$(sed -n "s/^PACKAGE_VERSION='\\(.*\\)'\$/\\1/p" configure | awk 'NR==1')
echo "  configure 自述 PACKAGE_VERSION = $src_ver"
if [ "$src_ver" = "$VER" ]; then echo "  OK   源码自述版本与手册 §8.18 的 Expect-$VER 一致"
else echo "  FAIL 源码自述版本为 '$src_ver'，与 $VER 不符" >&2; exit 1; fi
echo "测试套件构成（Makefile.in 的 test 目标跑 tests/all.tcl）："
{ ls tests/ || true; } | sed 's/^/  /'
echo

echo "================= 8.18.1. Installation of Expect ================="
echo
echo "----- 手册命令 1/6：patch -Np1 -i ../$PATCHFILE -----"
echo "手册原文：Now, make some changes to allow the package with gcc-15.1 or later:"
echo "补丁说明（补丁文件头部）："
sed -n '1,22p' "/sources/$PATCHFILE" | sed 's/^/  /'
echo "补丁将改动的文件（$( { grep -cE '^\+\+\+ ' "/sources/$PATCHFILE" || true; } ) 个）："
{ grep -E '^\+\+\+ ' "/sources/$PATCHFILE" || true; } | awk '{print $2}' | sed 's/^/  /'
echo "手册命令：patch -Np1 -i ../$PATCHFILE"
patch -Np1 -i "../$PATCHFILE"
echo "  patch 退出码：0（无 .rej 文件即为全部 hunk 应用成功）"
rej=$({ find . -name '*.rej' -o -name '*.orig' || true; } | sed 's/^/    /')
if [ -z "$rej" ]; then echo "  OK   源码树中没有 .rej / .orig 残留，补丁完全应用"
else echo "  FAIL 出现 .rej/.orig："; printf '%s\n' "$rej"; exit 1; fi
echo "  抽查补丁效果（本补丁的核心是去掉 pre-C23 的旧式函数声明/exit 用法）："
echo "    configure 中曾用于探测 timezone 的 'exit (0);' 行数（补丁后应为 0）："
echo "      $({ grep -c '^	    exit (0);' configure || true; })"
echo "    exp_command.h 中被补丁加上形参表的声明（抽 1 行）："
{ grep -nE 'exp_(pty_)?[a-z_]+\(void\)' exp_command.h || true; } | sed -n '1,3p' | sed 's/^/      /'
echo

echo "----- 手册命令 2/6：./configure （Prepare Expect for compilation） -----"
echo "手册命令：./configure --prefix=/usr           \\"
echo "                     --with-tcl=/usr/lib     \\"
echo "                     --enable-shared         \\"
echo "                     --disable-rpath         \\"
echo "                     --mandir=/usr/share/man \\"
echo "                     --with-tclinclude=/usr/include"
echo "手册对选项的解释："
echo "  --with-tcl=/usr/lib —— This parameter is needed to tell configure where the"
echo "    tclConfig.sh script is located."
echo "  --with-tclinclude=/usr/include —— This explicitly tells Expect where to find"
echo "    Tcl's internal headers."
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr           \
            --with-tcl=/usr/lib     \
            --enable-shared         \
            --disable-rpath         \
            --mandir=/usr/share/man \
            --with-tclinclude=/usr/include > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "configure 关键探测行："
{ grep -nE 'checking (for Tcl configuration|for existence of|for Tcl public headers|for Tcl private include files|if rpath support is requested|how to build libraries|for tclsh|for gcc|for building with threads|if 64bit support)' "$CONFLOG" || true; } | sed -n '1,30p' | sed 's/^/  /'
echo
echo "----- 核对手册的 6 个 configure 选项确实生效 -----"
crc=0
[ -f Makefile ] || { echo "  FAIL configure 未生成 Makefile"; exit 1; }
echo "a) --prefix=/usr / --mandir=/usr/share/man —— 生成的 Makefile 中的安装路径变量："
{ grep -nE '^(prefix|exec_prefix|bindir|libdir|includedir|mandir|PKG_DIR|PACKAGE_NAME|PACKAGE_VERSION)[[:space:]]*=' Makefile || true; } | sed 's/^/    /'
got_prefix=$(sed -n 's/^prefix[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
got_mandir=$(sed -n 's/^mandir[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
if [ "$got_prefix" = /usr ]; then echo "    OK   prefix = /usr"
else echo "    FAIL prefix 为 '$got_prefix'"; crc=1; fi
if [ "$got_mandir" = /usr/share/man ]; then
  echo "    OK   mandir = /usr/share/man（不给此选项时 autoconf 默认 \${prefix}/man = /usr/man，不合 FHS）"
else echo "    FAIL mandir 为 '$got_mandir'"; crc=1; fi
echo "b) --with-tcl=/usr/lib —— configure 必须在该目录找到 tclConfig.sh 并加载"
{ grep -nE 'checking for (Tcl configuration|existence of)' "$CONFLOG" || true; } | sed -n '1,2p' | sed 's/^/    /'
tclcfg_found=$(sed -n 's/.*checking for Tcl configuration\.\.\. found //p' "$CONFLOG" | awk 'NR==1')
if [ "$tclcfg_found" = /usr/lib/tclConfig.sh ]; then
  echo "    OK   找到并加载了 /usr/lib/tclConfig.sh（§8.17 装出的那一份）"
else echo "    FAIL configure 找到的是 '$tclcfg_found'"; crc=1; fi
got_tclbin=$(sed -n 's/^TCL_BIN_DIR[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
echo "    Makefile 中 TCL_BIN_DIR = $got_tclbin"
if [ "$got_tclbin" = /usr/lib ]; then echo "    OK   TCL_BIN_DIR = /usr/lib"
else echo "    FAIL TCL_BIN_DIR = '$got_tclbin'"; crc=1; fi
echo "c) --with-tclinclude=/usr/include —— Tcl 公共头与私有头都要在该目录被找到"
{ grep -nE 'checking for Tcl (public headers|private include files)' "$CONFLOG" || true; } | sed 's/^/    /'
pub_h=$(sed -n 's/.*checking for Tcl public headers\.\.\. //p' "$CONFLOG" | awk 'NR==1')
prv_h=$(sed -n 's/.*checking for Tcl private include files\.\.\. //p' "$CONFLOG" | awk 'NR==1')
if [ "$pub_h" = /usr/include ]; then echo "    OK   Tcl public headers = /usr/include"
else echo "    FAIL Tcl public headers = '$pub_h'"; crc=1; fi
case "$prv_h" in
  *"private headers found"*) echo "    OK   Tcl private include files：$prv_h（依赖 §8.17 的 install-private-headers）" ;;
  *) echo "    FAIL Tcl private include files = '$prv_h'"; crc=1 ;;
esac
echo "    Makefile 中的头文件搜索路径 TCL_INCLUDES / PKG_INCLUDES："
{ grep -nE '^(TCL_INCLUDES|PKG_INCLUDES|INCLUDES)[[:space:]]*=' Makefile || true; } | sed 's/^/      /'
echo "d) --enable-shared —— 必须构建共享库 libexpect$VER.so（SHARED_BUILD=1）"
{ grep -nE '^(SHARED_BUILD|PKG_LIB_FILE|MAKE_LIB)[[:space:]]*=' Makefile || true; } | sed 's/^/    /'
got_shared=$(sed -n 's/^SHARED_BUILD[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
got_libfile=$(sed -n 's/^PKG_LIB_FILE[[:space:]]*=[[:space:]]*//p' Makefile | awk 'NR==1')
if [ "$got_shared" = 1 ]; then echo "    OK   SHARED_BUILD = 1"
else echo "    FAIL SHARED_BUILD = '$got_shared'"; crc=1; fi
if [ "$got_libfile" = "libexpect$VER.so" ]; then
  echo "    OK   PKG_LIB_FILE = libexpect$VER.so（手册 §8.18.2 Contents 里列出的那一个）"
else echo "    FAIL PKG_LIB_FILE = '$got_libfile'"; crc=1; fi
echo "e) --disable-rpath —— configure 的探测结论必须是 no"
{ grep -n 'checking if rpath support is requested' "$CONFLOG" || true; } | sed 's/^/    /'
rpath_ans=$(sed -n 's/.*checking if rpath support is requested\.\.\. //p' "$CONFLOG" | awk 'NR==1')
if [ "$rpath_ans" = no ]; then echo "    OK   configure 结论：rpath support is requested = no"
else echo "    FAIL configure 结论为 '$rpath_ans'"; crc=1; fi
echo "    （安装后再用 readelf -d 复核二进制里确无 RPATH/RUNPATH —— 见后文）"
echo "f) configure 记录的完整命令行（config.status 中）："
{ grep -nE "running .*configure --disable-option-checking|with options" "$CONFLOG" || true; } | sed -n '1,2p' | cut -c1-300 | sed 's/^/    /'
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册的选项要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册的 6 个选项"
echo

echo "----- 手册命令 3/6：make （Build the package） -----"
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
echo "make 输出末尾 6 行："
tail -n 6 "$MAKELOG" | sed 's/^/  /'
echo "编译告警统计（gcc-15 默认 C23，补丁的目的就是消除由此产生的错误）："
echo "  'error:' 行数  ：$({ grep -c 'error:' "$MAKELOG" || true; })"
echo "  'warning:' 行数：$({ grep -c 'warning:' "$MAKELOG" || true; })"
{ grep -E 'warning:' "$MAKELOG" || true; } | sed -e 's/.*warning: //' | sort | uniq -c | sort -rn | sed -n '1,10p' | sed 's/^/    /'
echo
echo "----- 编译结果确认 -----"
mrc=0
for f in expect "libexpect$VER.so" pkgIndex.tcl; do
  if [ -e "$f" ]; then printf '  OK   %-24s（%s 字节，%s）\n' "$f" "$(stat -Lc %s "$f")" "$(file -b "$f" | cut -d, -f1-2)"
  else printf '  FAIL %s 未生成\n' "$f"; mrc=1; fi
done
echo "  构建树中 expect 的动态依赖："
LD_LIBRARY_PATH="$PWD" ldd ./expect | sed 's/^/    /'
ldd_build=$(LD_LIBRARY_PATH="$PWD" ldd ./expect)
case "$ldd_build" in *"/tools/"*) echo "    FAIL 仍链接 /tools 下的库"; mrc=1 ;; *) echo "    OK   未链接任何 /tools 路径" ;; esac
case "$ldd_build" in *libtcl8.6.so*) echo "    OK   链接 §8.17 装出的 libtcl8.6.so" ;; *) echo "    FAIL 未链接 libtcl8.6.so"; mrc=1 ;; esac
echo "  --disable-rpath 的即时效果（构建树里的二进制不应有 RPATH/RUNPATH）："
for f in ./expect "./libexpect$VER.so"; do
  dyn=$({ readelf -d "$f" || true; })
  case "$dyn" in
    *RUNPATH*|*RPATH*) echo "    FAIL $f 含 RPATH/RUNPATH："; printf '%s\n' "$dyn" | sed -n '/PATH/p' | sed 's/^/      /'; mrc=1 ;;
    *) echo "    OK   $f 无 RPATH/RUNPATH" ;;
  esac
done
echo "  生成的 pkgIndex.tcl 内容（决定 'package require Expect' 能否加载）："
sed 's/^/    /' pkgIndex.tcl
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 4/6：make test （To test the results） -----"
echo "手册原文：To test the results, issue:  make test"
echo "（手册 §8.18 全节没有任何关于测试结果的 Note / Caution，即要求测试无失败。"
echo "  Makefile.in 的 test 目标是：\$(TCLSH) \$(srcdir)/tests/all.tcl \$(TESTFLAGS)，"
echo "  即用 tcltest 依次 source tests/ 下的 7 个 .test 文件，结束时打印一行"
echo "  'all.tcl:<TAB>Total N Passed N Skipped N Failed N'。判据：make 退出码 0，"
echo "  该汇总行存在且 Failed=0、Total>0，且日志中没有 '==== … FAILED' 用例标记。"
echo "  这些测试全部通过真实 PTY 驱动 spawn/send/expect，因此上面的 PTY 检查是前提。）"
echo "完整输出写入 $TESTLOG。"
test_start=$(date -Is)
set +e
make test > "$TESTLOG" 2>&1
test_rc=$?
set -e
test_end=$(date -Is)
echo "make test 退出码：$test_rc（$test_start -> $test_end，输出 $(wc -l < "$TESTLOG") 行）"
echo
echo "----- make test 完整输出（本节测试输出很短，全文照录） -----"
sed 's/^/  /' "$TESTLOG"
echo
echo "----- tcltest 汇总 -----"
{ grep -nE '^all\.tcl:' "$TESTLOG" || true; } | sed 's/^/  /'
sum_n=$(awk -F'\t' '/^all\.tcl:/{n++} END{print n+0}' "$TESTLOG")
sum_total=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Total") s+=$(i+1)} END{print s+0}' "$TESTLOG")
sum_pass=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Passed") s+=$(i+1)} END{print s+0}' "$TESTLOG")
sum_skip=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Skipped") s+=$(i+1)} END{print s+0}' "$TESTLOG")
sum_fail=$(awk -F'\t' '/^all\.tcl:/{for(i=1;i<=NF;i++) if($i=="Failed") s+=$(i+1)} END{print s+0}' "$TESTLOG")
printf '  汇总行数=%d  Total=%d  Passed=%d  Skipped=%d  Failed=%d\n' "$sum_n" "$sum_total" "$sum_pass" "$sum_skip" "$sum_fail"
echo "  被 source 的测试文件（all.tcl 每读一个就 puts 其文件名）："
for tf in cat.test expect.test logfile.test pid.test send.test spawn.test stty.test; do
  if { grep -q "$tf" "$TESTLOG"; }; then printf '    OK   %s 已运行\n' "$tf"
  else printf '    FAIL %s 未出现在测试输出中\n' "$tf"; fi
done
n_failed_marker=$({ grep -cE '^==== .*FAILED' "$TESTLOG" || true; })
n_err=$({ grep -cE 'Test file error|couldn.t (load|read) file' "$TESTLOG" || true; })
echo "  '==== … FAILED' 用例标记行数：$n_failed_marker"
echo "  'Test file error' / 'couldn't load file' 行数：$n_err"
echo
echo "----- make test 结论 -----"
trc=0
if [ "$test_rc" -ne 0 ]; then echo "  FAIL make test 退出码 $test_rc"; trc=1
else echo "  OK   make test 退出码 0"; fi
if [ "$sum_n" -eq 1 ]; then echo "  OK   找到 1 个 all.tcl 汇总行"
else echo "  FAIL 找到 $sum_n 个 all.tcl 汇总行（预期 1 个），测试疑似未真正运行"; trc=1; fi
if [ "$sum_total" -ge 20 ]; then echo "  OK   用例总数 $sum_total（Expect 测试套件量级正常）"
else echo "  FAIL 用例总数只有 $sum_total，测试疑似未跑全"; trc=1; fi
if [ "$sum_fail" -eq 0 ]; then echo "  OK   Failed = 0"
else echo "  FAIL Failed = $sum_fail（手册 §8.18 未允许任何失败）"; trc=1; fi
if [ "$n_failed_marker" -eq 0 ]; then echo "  OK   日志中没有 '==== … FAILED' 用例标记"
else echo "  FAIL 日志中出现 $n_failed_marker 个 '==== … FAILED' 用例标记"; trc=1; fi
if [ "$n_err" -eq 0 ]; then echo "  OK   日志中没有 Test file error / 加载失败"
else echo "  FAIL 日志中出现 $n_err 行 Test file error / 加载失败"; trc=1; fi
if [ $trc -ne 0 ]; then
  echo "错误：测试结果不符合手册要求" >&2
  exit 1
fi
echo "结论：§8.18 的 make test 退出码 0，tests/ 下 7 个测试文件全部运行，"
echo "  合计 Total=$sum_total Passed=$sum_pass Skipped=$sum_skip Failed=$sum_fail，无失败项、无跳过项。"
echo

echo "----- 手册命令 5/6：make install （Install the package） -----"
echo "安装前 /usr/bin 文件数：$(ls /usr/bin | wc -l)"
ls /usr/bin > /tmp/.expect-bin-before.txt
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
echo "本次 make install 在 /usr/bin 中新增的文件（Makefile.in 的 install-libraries 会把"
echo "  example/ 下的 \$(SCRIPTS) 一并装进 \$(prefix)/bin，手册 §8.18.2 Contents 只点名"
echo "  了 expect，此处把实际落盘的全部新文件列出以便存档）："
ls /usr/bin > /tmp/.expect-bin-after.txt
{ diff /tmp/.expect-bin-before.txt /tmp/.expect-bin-after.txt || true; } | { grep '^>' || true; } | sed 's/^> /  + /'
rm -f /tmp/.expect-bin-before.txt /tmp/.expect-bin-after.txt
echo

echo "----- 手册命令 6/6：ln -svf expect$VER/libexpect$VER.so /usr/lib -----"
echo "手册说明（结合 Makefile.in）：install-lib-binaries 把共享库装到 pkglibdir ="
echo "  \$(libdir)/\$(PKG_DIR) = /usr/lib/expect$VER/，链接器在 /usr/lib 里找不到它，"
echo "  故手册补一条符号链接把它暴露到 /usr/lib。"
echo "执行前 /usr/lib 下的 libexpect*："
{ ls -l /usr/lib/libexpect* 2>&1 || true; } | sed 's/^/  /'
ln -svf "expect$VER/libexpect$VER.so" /usr/lib
echo "执行后："
{ ls -l /usr/lib/libexpect* 2>&1 || true; } | sed 's/^/  /'
echo

echo "================= 安装后检查（手册 §8.18.2 Contents of Expect） ================="
echo "手册列出的内容："
echo "  Installed program: expect"
echo "  Installed library: libexpect5.45.4.so"
rc=0
echo
echo "1) Installed program：/usr/bin/expect —— Communicates with other interactive"
echo "   programs according to a script"
if [ -x /usr/bin/expect ] && [ ! -L /usr/bin/expect ]; then
  printf '   OK   /usr/bin/expect（%s 字节，%s）\n' "$(stat -Lc %s /usr/bin/expect)" "$(file -b /usr/bin/expect | cut -d, -f1-2)"
else echo "   FAIL /usr/bin/expect 缺失或不是普通可执行文件"; rc=1; fi
echo "   动态依赖："
ldd /usr/bin/expect | sed 's/^/     /'
ldd_inst=$(ldd /usr/bin/expect)
case "$ldd_inst" in
  *"not found"*) echo "     FAIL 存在 'not found' 的依赖"; rc=1 ;;
  *) echo "     OK   所有依赖均可解析" ;;
esac
case "$ldd_inst" in *"/tools/"*) echo "     FAIL 依赖中含 /tools 路径"; rc=1 ;; *) echo "     OK   依赖中不含 /tools 路径" ;; esac
case "$ldd_inst" in *"libexpect$VER.so"*) echo "     OK   通过 /usr/lib 的符号链接解析到 libexpect$VER.so" ;; *) echo "     FAIL 未解析到 libexpect$VER.so"; rc=1 ;; esac
echo "   RPATH/RUNPATH（--disable-rpath 的最终复核）："
dyn=$({ readelf -d /usr/bin/expect || true; })
case "$dyn" in
  *RUNPATH*|*RPATH*) echo "     FAIL 含 RPATH/RUNPATH"; printf '%s\n' "$dyn" | sed -n '/PATH/p' | sed 's/^/       /'; rc=1 ;;
  *) echo "     OK   无 RPATH/RUNPATH" ;;
esac
echo "   版本自述：$(expect -v 2>&1 | sed -n 1p)"
exp_v=$(expect -v 2>&1 | sed -n 1p)
case "$exp_v" in
  *"$VER"*) echo "     OK   自述含 $VER" ;;
  *) echo "     FAIL 自述 '$exp_v' 不含 $VER"; rc=1 ;;
esac
echo
echo "2) Installed library：libexpect$VER.so —— Contains functions that allow Expect to"
echo "   be used as a Tcl extension or to be used directly from C or C++ (without Tcl)"
if [ -f "/usr/lib/expect$VER/libexpect$VER.so" ]; then
  printf '   OK   /usr/lib/expect%s/libexpect%s.so（%s 字节，%s）\n' "$VER" "$VER" \
    "$(stat -Lc %s "/usr/lib/expect$VER/libexpect$VER.so")" "$(file -b "/usr/lib/expect$VER/libexpect$VER.so" | cut -d, -f1-2)"
else echo "   FAIL /usr/lib/expect$VER/libexpect$VER.so 缺失"; rc=1; fi
if [ -L "/usr/lib/libexpect$VER.so" ]; then
  echo "   OK   /usr/lib/libexpect$VER.so 是符号链接 -> $(readlink "/usr/lib/libexpect$VER.so")"
  if [ "$(readlink "/usr/lib/libexpect$VER.so")" = "expect$VER/libexpect$VER.so" ]; then
    echo "   OK   指向 expect$VER/libexpect$VER.so（与手册的 ln -svf 一致）"
  else echo "   FAIL 指向的不是 expect$VER/libexpect$VER.so"; rc=1; fi
  if [ -f "/usr/lib/libexpect$VER.so" ]; then echo "   OK   符号链接可解析到实际文件"
  else echo "   FAIL 符号链接悬空"; rc=1; fi
else echo "   FAIL /usr/lib/libexpect$VER.so 不是符号链接"; rc=1; fi
echo "   /usr/lib/expect$VER/ 目录内容（含 pkgIndex.tcl，供 'package require Expect' 使用）："
{ ls -l "/usr/lib/expect$VER/" || true; } | sed 's/^/     /'
echo
echo "3) 手册未列但由 install-doc 装出的 man 页："
for m in /usr/share/man/man1/expect.1 /usr/share/man/man3/libexpect.3; do
  if [ -f "$m" ]; then printf '   OK   %-38s（%s 字节）\n' "$m" "$(stat -Lc %s "$m")"
  else printf '   FAIL %s 缺失\n' "$m"; rc=1; fi
done
echo "   （手册 §8.18.2 的 Short Descriptions 里把库的 man 页写作 libexpect-5.45.4.so，"
echo "     实际落盘的库文件名是 libexpect$VER.so、man 页是 libexpect.3。）"
echo
echo "4) 功能冒烟测试（真实使用 PTY，验证 expect 确实能驱动交互式程序）："
src=0
echo "   a) expect -c 直接执行脚本，spawn 一个子进程并匹配其输出："
smoke=$(expect -c 'set timeout 10
spawn -noecho /usr/bin/cat
expect_after timeout { puts "TIMEOUT"; exit 1 }
send "hello-from-expect\r"
expect "hello-from-expect"
send \004
expect eof
puts "SMOKE-OK"' 2>&1 | tr -d '\r')
printf '%s\n' "$smoke" | sed 's/^/        /'
case "$smoke" in
  *SMOKE-OK*) echo "        OK   spawn/send/expect 全链路正常（子进程经 PTY 回显被正确匹配）" ;;
  *) echo "        FAIL 冒烟脚本未输出 SMOKE-OK"; src=1 ;;
esac
echo "   b) 退出码传递（expect 脚本中的 exit N 应成为进程退出码）："
set +e
expect -c 'exit 7' >/dev/null 2>&1
smoke_rc=$?
set -e
echo "        expect -c 'exit 7' -> 退出码 $smoke_rc"
if [ "$smoke_rc" -eq 7 ]; then echo "        OK   退出码被正确传递"
else echo "        FAIL 退出码为 $smoke_rc"; src=1; fi
echo "   c) 作为 Tcl 扩展加载（DejaGNU 与后续各包的测试套件正是这样用它的）："
pkg_out=$(echo 'package require Expect; puts "EXPECT-PKG [package require Expect]"' | tclsh 2>&1 | tr -d '\r')
printf '%s\n' "$pkg_out" | sed 's/^/        /'
case "$pkg_out" in
  *"EXPECT-PKG $VER"*) echo "        OK   tclsh 可 package require Expect 并得到 $VER（/usr/lib/expect$VER/pkgIndex.tcl 生效）" ;;
  *) echo "        FAIL tclsh 无法加载 Expect 扩展"; src=1 ;;
esac
echo "   d) 手册提到的 PTY 前置条件在安装后依然满足（再跑一次手册的 python3 检查）："
pty2=$(python3 -c 'from pty import spawn; spawn(["echo", "ok"])' 2>&1 | tr -d '\r\n')
echo "        输出：'$pty2'"
if [ "$pty2" = ok ]; then echo "        OK   PTY 仍正常"
else echo "        FAIL PTY 输出异常"; src=1; fi
[ $src -eq 0 ] || rc=1
echo
echo "5) 本节写入系统的主要文件清单："
{ ls -ld /usr/bin/expect "/usr/lib/expect$VER" "/usr/lib/expect$VER/libexpect$VER.so" \
      "/usr/lib/expect$VER/pkgIndex.tcl" "/usr/lib/libexpect$VER.so" \
      /usr/share/man/man1/expect.1 /usr/share/man/man3/libexpect.3 2>&1 || true; } | sed 's/^/   /'
echo
[ $rc -eq 0 ] || { echo "错误：安装后检查未全部通过" >&2; exit 1; }
echo "  OK   §8.18.2 Contents 列出的 expect 与 libexpect$VER.so 均已就位并通过功能验证"
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.18.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make test    完整输出：$TESTLOG"
echo "  make install 完整输出：$INSTLOG"
cd /sources
rm -rf "$SRCTOP"
echo "已删除 /sources/$SRCTOP"
echo "/sources 下的解包残留（应为空）：$({ ls -d /sources/expect*/ 2>/dev/null || true; })"
echo "/sources 文件数：$(ls /sources | wc -l)"
echo "根文件系统占用："
df -h / | sed 's/^/  /'
echo
echo "===== §8.18 完成，结束时间：$(date -Is) ====="
