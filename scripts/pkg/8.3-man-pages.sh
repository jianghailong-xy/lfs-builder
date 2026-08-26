#!/usr/bin/env bash
# LFS 13.0-systemd §8.3 Man-pages-6.17
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.3.1 Installation of Man-pages 的命令序列（全部；本节无补丁、无 configure、
# 无编译步骤、无测试套件）：
#   rm -v man3/crypt*
#   make -R GIT=false prefix=/usr install
set -euo pipefail

PKG=man-pages
VER=6.17
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §8.3 Man-pages-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Man-pages package contains over 2,400 man pages."
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 54 MB"
echo "本节是第 8 章（Installing Basic System Software）的第一个软件包；"
echo "  §8.1 Introduction 与 §8.2 Package Management 是纯说明性小节，不含任何命令，"
echo "  按任务要求本次只处理 §8.3。"
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
  *) echo "OK        : /tools/bin 不在 PATH" ;;
esac
echo "可用空间（手册本节要求 54 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 54 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 54MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§7.13 Cleaning up and Saving the Temporary System）产物必须可用 -----"
rc=0
echo "1) §7.13.1 Cleaning 的结果（临时工具已并入 /usr，/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在（§7.13.1 未完成？）"; rc=1
else echo "   OK   /tools 已不存在（§7.13.1 的 rm -rf /tools 已执行）"; fi
if [ -e /usr/lib/libstdc++.la ] || [ -e /usr/lib/libz.la ]; then
  echo "   INFO 仍有 .la 文件残留（§7.13.1 应已删除，不影响本节）"
else
  echo "   OK   §7.13.1 要求删除的 .la 文件未见残留"
fi
echo "2) 本节 make install 直接依赖的工具（man-pages 的 GNUmakefile 以 SHELL := bash 运行）："
for t in make bash install find sed grep awk xargs cat rm mkdir tar xz; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   bash 版本：$(bash --version | sed -n 1p)"
echo "   man-pages 的 GNUmakefile 在 make < 4.4.999 时强制要求 -R 选项，手册命令已带 -R。"
echo "3) 安装目标目录（§7.5 建立的 /usr/share/man 层次）："
for d in /usr/share/man /usr/share/man/man1 /usr/share/man/man2 /usr/share/man/man3 \
         /usr/share/man/man4 /usr/share/man/man5 /usr/share/man/man6 /usr/share/man/man7 \
         /usr/share/man/man8; do
  if [ -d "$d" ]; then printf '   OK   %-24s（现有 %s 个文件）\n' "$d" "$(find "$d" -maxdepth 1 -type f | wc -l)"
  else printf '   FAIL %s 缺失\n' "$d"; rc=1; fi
done
echo "4) 源码目录（§7.13.2 之后 /sources 仍是宿主机 bind mount）："
if [ -d /sources ]; then echo "   OK   /sources 存在，共 $(find /sources -maxdepth 1 -type f | wc -l) 个文件"
else echo "   FAIL /sources 缺失"; rc=1; fi
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "5) §7.3 虚拟内核文件系统与 §7.6 基础文件："
for f in /dev/null /proc/self /sys /etc/passwd /etc/group; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "6) 本节安装前 /usr/share/man 下 man-pages 相关文件的状态："
for f in /usr/share/man/man2/open.2 /usr/share/man/man3/printf.3 /usr/share/man/man7/man-pages.7 \
         /usr/share/man/man3/crypt.3; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在\n' "$f"; else printf '   OK   %s 尚未安装\n' "$f"; fi
done
echo "   安装前 /usr/share/man 下文件总数：$(find /usr/share/man -type f | wc -l)"
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：Unpack the tarball ... using the tar command. ... In Chapters 5 and 6,"
echo "  ... In Chapter 8, ... the packages are unpacked as root."
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "包自报版本（RELEASE / Changes 首行）："
sed -n 1,3p RELEASE 2>/dev/null | sed 's/^/  RELEASE: /' || true
head -n 3 Changes 2>/dev/null | sed 's/^/  Changes: /' || true
echo "顶层内容：$(ls | tr '\n' ' ')"
echo "本节无补丁：手册 §8.3 只有 rm -v man3/crypt* 与 make -R GIT=false prefix=/usr install"
echo "  两条命令，没有任何 patch；/sources 下也没有 man-pages 相关补丁文件"
echo "  （匹配数：$(ls /sources | grep -ci 'man-pages.*patch')）。"
echo

echo "================= 8.3.1. Installation of Man-pages ================="
echo "----- 删除 crypt 相关手册页（手册第一条命令） -----"
echo "手册原文：Remove two man pages for password hashing functions. Libxcrypt will"
echo "  provide a better version of these man pages:"
echo "手册命令：rm -v man3/crypt*"
echo "删除前 man3/crypt* 的实际内容："
ls -l man3/crypt* | sed 's/^/  /'
rm -v man3/crypt*
echo "删除后确认（应无匹配）："
if ls man3/crypt* >/dev/null 2>&1; then
  echo "  FAIL man3/crypt* 仍存在"; exit 1
else
  echo "  OK   man3/crypt* 已全部删除（手册所说的 two man pages）"
fi
echo

echo "----- 本节无 configure、无编译步骤 -----"
echo "手册 §8.3.1 在删除 crypt 手册页之后直接进入安装：Install Man-pages by running:"
echo "  make -R GIT=false prefix=/usr install"
echo "  man-pages 是纯文档包，不含需要编译的源代码，因此本节没有 ./configure，"
echo "  也没有单独的 make 编译步骤。"
echo

echo "================= 本节测试 ================="
echo "手册 §8.3 未规定任何测试：该节命令只有 rm -v man3/crypt* 和"
echo "  make -R GIT=false prefix=/usr install，没有 make check / make test，"
echo "  §8.3 页面上也没有测试相关的说明或已知失败项。"
echo "  （man-pages 的 GNUmakefile 自带 check/lint 目标，但手册没有要求执行，"
echo "  它依赖 checkpatch、shellcheck 等 LFS 系统里不存在的外部 lint 工具，"
echo "  因此按「严格照手册」的要求不予执行。）"
echo "结论：本节无手册规定的测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装（手册原文：Install Man-pages by running） -----"
echo "手册命令：make -R GIT=false prefix=/usr install"
echo "手册对选项的说明："
echo "  -R        This prevents make from setting any built-in variables. The building"
echo "            system of man-pages does not work well with built-in variables, but"
echo "            currently there is no way to disable them except passing -R explicitly"
echo "            via the command line."
echo "  GIT=false This prevents the building system from emitting many \"git: command not"
echo "            found\" warnings lines."
echo "（MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境提供）"
time make -R GIT=false prefix=/usr install
echo
echo "make install 退出码 0"
echo

echo "----- 安装结果检查（对照手册 §8.3.2 Contents of Man-pages） -----"
echo "手册 §8.3.2：Installed files: various man pages"
echo "手册简介：The Man-pages package contains over 2,400 man pages. ... Describe C"
echo "  programming language functions, important device files, and significant"
echo "  configuration files."
rc=0
echo "1) 标准 man 分节（man1..man8）安装数量："
total=0
for s in 1 2 3 4 5 6 7 8; do
  n=$(find /usr/share/man/man$s -maxdepth 1 -type f 2>/dev/null | wc -l)
  total=$((total+n))
  printf '   man%-2s %6s 个文件\n' "$s" "$n"
done
echo "   man1..man8 合计：$total 个普通文件"
echo "   man-pages 自有的子分节目录（上游把 manNconst/manNtype 这类页面装到"
echo "   /usr/share/man 下的同名独立目录，而不是并入 manN）："
sub=0
for d in man2const man2type man3attr man3const man3head man3type; do
  if [ -d "/usr/share/man/$d" ]; then
    n=$(find "/usr/share/man/$d" -maxdepth 1 -type f | wc -l)
    sub=$((sub+n))
    printf '   %-10s %6s 个文件\n' "$d" "$n"
  else
    printf '   %-10s 不存在\n' "$d"
  fi
done
echo "   子分节合计：$sub 个普通文件"
echo "   /usr/share/man 下条目总数（普通文件 + 符号链接，递归）：$(find /usr/share/man -type f -o -type l | wc -l)"
if [ "$total" -ge 2400 ]; then
  echo "   OK   >= 2400，与手册「over 2,400 man pages」一致"
else
  echo "   FAIL 仅 $total 个，少于手册所说的 2,400"; rc=1
fi
echo "2) 抽样确认各类手册页（C 函数、设备文件、配置文件，即手册 §8.3.2 的三类描述）："
for f in /usr/share/man/man2/open.2 /usr/share/man/man2/write.2 \
         /usr/share/man/man3/printf.3 /usr/share/man/man3/malloc.3 /usr/share/man/man3/strcpy.3 \
         /usr/share/man/man4/null.4 /usr/share/man/man4/random.4 \
         /usr/share/man/man5/passwd.5 /usr/share/man/man5/proc.5 \
         /usr/share/man/man7/man-pages.7 /usr/share/man/man7/glibc.7 \
         /usr/share/man/man8/ld.so.8; do
  if [ -e "$f" ]; then printf '   OK   %-38s %s 字节\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "3) 确认手册要求删除的 crypt 手册页未被安装（Libxcrypt 将在 §8.28 提供更好的版本）："
if ls /usr/share/man/man3/crypt* >/dev/null 2>&1; then
  echo "   FAIL /usr/share/man/man3/crypt* 存在："; ls -l /usr/share/man/man3/crypt* | sed 's/^/     /'; rc=1
else
  echo "   OK   /usr/share/man/man3/crypt*（crypt.3 / crypt_r.3）未安装"
fi
echo "4) 手册页内容与格式抽查（确认是可读的 roff 源文件而非空文件）："
echo "   /usr/share/man/man7/man-pages.7 前 6 行："
sed -n 1,6p /usr/share/man/man7/man-pages.7 | sed 's/^/     /'
sed -n 1,20p /usr/share/man/man7/man-pages.7 > /tmp/.mp-head.txt
if grep -q '^\.TH' /tmp/.mp-head.txt; then
  echo "   OK   含 .TH 头，是标准 man(7) roff 源"
else
  echo "   FAIL 未找到 .TH 头"; rc=1
fi
rm -f /tmp/.mp-head.txt
echo "   符号链接形式的手册页抽查（若上游以链接提供别名）："
# 注意：本脚本开了 pipefail，`find ... | head -nN` 会让 find 收到 SIGPIPE 而把整条
# 管道判为失败，与命令本身无关；因此一律先写临时文件再取前几行。
find /usr/share/man -type l > /tmp/.mp-links.txt || true
nlink=$(wc -l < /tmp/.mp-links.txt)
if [ "$nlink" -gt 0 ]; then
  sed -n 1,5p /tmp/.mp-links.txt | while read -r l; do
    printf '     %s -> %s\n' "$l" "$(readlink "$l")"
  done
fi
echo "     （共 $nlink 个符号链接；man-pages 6.17 的归档内 man/manN* 下全部是普通"
echo "     文件，其 install 目标逐个 INSTALL 过去，不生成符号链接，因此为 0 属正常。"
echo "     归档顶层的 man1/man2/... 只是指向 man/man1、man/man2 的兼容符号链接，"
echo "     手册的 rm -v man3/crypt* 正是经由 man3 -> man/man3 删除了 man/man3 下的"
echo "     crypt.3 与 crypt_r.3 这两个文件，它们不会被安装。）"
rm -f /tmp/.mp-links.txt
echo "5) 安装位置确认（prefix=/usr，不应写到 /usr/local 或其他前缀）："
if [ -d /usr/local/share/man ] && [ "$(find /usr/local/share/man -type f -o -type l | wc -l)" -gt 0 ]; then
  echo "   FAIL /usr/local/share/man 下出现文件，prefix 未生效"; rc=1
else
  echo "   OK   /usr/local/share/man 下无 man-pages 文件"
fi
echo "   /usr/share/man 磁盘占用：$(du -sh /usr/share/man | cut -f1)"
echo "6) 权限抽查（应为 root:root 0644，无可执行位）："
ls -l /usr/share/man/man2/open.2 /usr/share/man/man3/printf.3 | sed 's/^/     /'
find /usr/share/man -type f -perm /111 > /tmp/.mp-perm.txt || true
badperm=$(sed -n 1,3p /tmp/.mp-perm.txt); rm -f /tmp/.mp-perm.txt
if [ -n "$badperm" ]; then
  echo "   INFO 存在带可执行位的文件："; echo "$badperm" | sed 's/^/     /'
else
  echo "   OK   /usr/share/man 下无带可执行位的普通文件"
fi
find /usr/share/man \( ! -user root -o ! -group root \) > /tmp/.mp-owner.txt 2>/dev/null || true
badowner=$(sed -n 1,3p /tmp/.mp-owner.txt); rm -f /tmp/.mp-owner.txt
if [ -n "$badowner" ]; then
  echo "   INFO 存在非 root:root 的条目："; echo "$badowner" | sed 's/^/     /'
else
  echo "   OK   /usr/share/man 下全部为 root:root"
fi
echo "7) 说明：man 命令本身由 §8.66 Man-DB 提供，本节只安装手册页文件，"
echo "   因此此处不做 man(1) 渲染验证（$(command -v man >/dev/null 2>&1 && echo '当前系统已有 man' || echo '当前系统尚无 man，属预期')）。"
[ $rc -eq 0 ] || { echo "错误：Man-pages 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd /sources
rm -rf "$SRCDIR"
[ -d "/sources/$SRCDIR" ] && { echo "错误：源码目录未清理" >&2; exit 1; }
echo "已删除 /sources/$SRCDIR"
echo "/sources 下的解包残留（应为空）："
find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.3 完成，结束时间：$(date -Is) ====="
