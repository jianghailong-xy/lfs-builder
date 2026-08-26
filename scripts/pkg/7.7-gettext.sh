#!/usr/bin/env bash
# LFS 13.0-systemd §7.7 Gettext-1.0（临时工具）
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §7.7.1 的命令序列（全部；本节无补丁、无测试套件）：
#   ./configure --disable-shared
#   make
#   cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
set -euo pipefail

PKG=gettext
VER=1.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §7.7 Gettext-$VER（临时工具） ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 1.5 SBU，Required disk space 526 MB"
echo "手册简介：The Gettext package contains utilities for internationalization and"
echo "          localization. These allow programs to be compiled with NLS (Native"
echo "          Language Support), enabling them to output messages in the user's"
echo "          native language."
echo "手册 §7.7.1 原文：For our temporary set of tools, we only need to install three"
echo "          programs from Gettext."
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
  *) echo "OK        : /tools/bin 不在 PATH（交叉工具链已停用）" ;;
esac
echo "可用空间（手册本节要求 526 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 526 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 526MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§6.18 GCC-15.2.0 Pass 2）及第 6 章产物必须可用 -----"
echo "手册 §7.1：Now that all circular dependencies have been resolved, a chroot"
echo "  environment, completely isolated from the host operating system (except for the"
echo "  running kernel), can be used for the build."
rc=0
echo "1) 编译器（§6.18 装入 \$LFS/usr，现在是 chroot 内的 /usr/bin/gcc）："
for t in gcc cc g++ cpp; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-4s -> %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
gcc --version | sed -n '1s/^/   /p'
echo "   gcc -dumpmachine : $(gcc -dumpmachine)"
echo "   编译器自检（chroot 内首次真正运行本地 GCC）："
printf 'int main(void){return 0;}\n' > /tmp/.cc-selftest.c
gcc -o /tmp/.cc-selftest /tmp/.cc-selftest.c
/tmp/.cc-selftest && echo "   OK   gcc 可编译并运行本地程序"
echo "   链接器使用的解释器："
readelf -l /tmp/.cc-selftest | grep -m1 'interpreter' | sed 's/^/   /'
rm -f /tmp/.cc-selftest /tmp/.cc-selftest.c
echo "2) §6.17 Binutils Pass 2 / 第 6 章其余工具："
for t in ld as ar ranlib make sed grep gawk m4 tar xz patch find diff file bash; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "3) §7.6 建立的基础文件（本节 configure 需要能解析用户名/主机名）："
for f in /etc/passwd /etc/group /etc/hosts /etc/mtab; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "4) §7.3 虚拟内核文件系统（configure 的测试程序需要 /dev/null 等）："
for f in /dev/null /dev/zero /dev/urandom /proc/self /sys; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "5) 本节安装前 /usr/bin 下不应已有 msgfmt/msgmerge/xgettext："
for f in msgfmt msgmerge xgettext; do
  if [ -e "/usr/bin/$f" ]; then printf '   INFO /usr/bin/%s 已存在（将被 cp 覆盖）\n' "$f"
  else printf '   OK   /usr/bin/%s 尚未安装\n' "$f"; fi
done
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "包自报版本：$(grep -m1 -E "^PACKAGE_VERSION=" configure | sed "s/^PACKAGE_VERSION=//; s/'//g" || true)"
echo "本节无补丁：手册 §7.7 只有 ./configure --disable-shared、make 和一条 cp 命令，"
echo "  没有任何 patch/sed 前置改动。"
echo

echo "================= 7.7.1. Installation of Gettext ================="
echo "----- configure（手册原文：Prepare Gettext for compilation） -----"
echo "手册命令：./configure --disable-shared"
echo "手册对该选项的说明："
echo "  --disable-shared  We do not need to install any of the shared Gettext libraries"
echo "      at this time, therefore there is no need to build them."
time ./configure --disable-shared
echo
echo "configure 结果确认："
echo "  实际参数：$(grep -m1 '^  \$ \./configure' config.log | sed 's/^ *\$ *//')"
if grep -qE '^\s*\$ \./configure --disable-shared\s*$' config.log; then
  echo "  OK   configure 只带 --disable-shared，与手册一致"
else
  grep -m1 '\$ \./configure' config.log | sed 's/^/  实际：/'
fi
echo "  共享库确实被禁用（libtool 的 build_libtool_libs 应为 no）："
for lt in gettext-runtime/libtool gettext-tools/libtool libtextstyle/libtool; do
  if [ -f "$lt" ]; then grep -m1 '^build_libtool_libs=' "$lt" | sed "s|^|  $lt: |"; fi
done
echo

echo "----- 编译（手册原文：Compile the package） -----"
echo "手册命令：make"
echo "（MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境提供）"
time make
echo

echo "================= 本节测试 ================="
echo "手册 §7.7 未规定任何测试：本节命令只有 ./configure --disable-shared、make 和"
echo "  cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin，没有 make check。"
echo "  第 7 章其余小节（Bison、Perl、Python、Texinfo、Util-linux）同样如此；Gettext 的"
echo "  完整测试套件出现在第 8 章 §8.34（make check）。"
echo "  手册 §7.7.1 的理由：For our temporary set of tools, we only need to install three"
echo "  programs from Gettext——本节甚至不执行 make install。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装（手册原文：Install the msgfmt, msgmerge, and xgettext programs） -----"
echo "手册命令：cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin"
echo "构建产物（安装前）："
ls -l gettext-tools/src/{msgfmt,msgmerge,xgettext} | sed 's/^/  /'
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
echo

echo "----- 安装结果检查（对照手册 §8.34.2 Contents of Gettext 中本节涉及的三个程序） -----"
rc=0
for f in msgfmt msgmerge xgettext; do
  p=/usr/bin/$f
  if [ -x "$p" ]; then
    printf '   OK   %-18s %s\n' "$p" "$(file -b $p | cut -d, -f1-3)"
  else
    printf '   FAIL %s 缺失或不可执行\n' "$p"; rc=1
  fi
done
echo "   手册 §8.34.2 对这三个程序的描述："
echo "     msgfmt    Translates a translation catalog into a binary message catalog"
echo "     msgmerge  Combines two raw translations into a single file"
echo "     xgettext  Extracts the translatable message lines from the given source files"
echo "   三个程序在 chroot 内实际运行（--version）："
for f in msgfmt msgmerge xgettext; do
  full=$($f --version 2>&1) || { echo "   FAIL $f --version 执行失败"; rc=1; continue; }
  out=${full%%$'\n'*}
  printf '     %-10s %s\n' "$f" "$out"
  case "$out" in
    *"$VER"*) ;;
    *) printf '   FAIL %s 报告的版本不含 %s\n' "$f" "$VER"; rc=1 ;;
  esac
done
echo "   功能性冒烟测试（msgfmt 把 .po 编译成 .mo，再由 msgunfmt 之外的手段确认）："
cat > /tmp/.gt-test.po <<'POEOF'
msgid ""
msgstr "Content-Type: text/plain; charset=UTF-8\n"

msgid "hello"
msgstr "nihao"
POEOF
msgfmt -o /tmp/.gt-test.mo /tmp/.gt-test.po
if [ -s /tmp/.gt-test.mo ]; then
  echo "     OK   msgfmt 生成 $(stat -c %s /tmp/.gt-test.mo) 字节的 .mo：$(file -b /tmp/.gt-test.mo)"
else
  echo "     FAIL msgfmt 未生成 .mo"; rc=1
fi
printf 'int main(void){ printf(gettext("hello")); }\n' > /tmp/.gt-test.c
( cd /tmp && xgettext -o /tmp/.gt-test.pot --omit-header .gt-test.c ) \
  && grep -q 'msgid "hello"' /tmp/.gt-test.pot \
  && echo "     OK   xgettext 从 C 源文件中提取出 msgid \"hello\"" \
  || { echo "     FAIL xgettext 提取失败"; rc=1; }
msgmerge -q -o /tmp/.gt-merged.po /tmp/.gt-test.po /tmp/.gt-test.pot \
  && grep -q 'msgid "hello"' /tmp/.gt-merged.po \
  && echo "     OK   msgmerge 合并 .po 与 .pot 成功" \
  || { echo "     FAIL msgmerge 失败"; rc=1; }
rm -f /tmp/.gt-test.po /tmp/.gt-test.mo /tmp/.gt-test.c /tmp/.gt-test.pot /tmp/.gt-merged.po
echo "   本节按手册只装这三个程序，不执行 make install，因此不应出现其它 gettext 文件："
for f in /usr/bin/gettext /usr/bin/msgunfmt /usr/bin/ngettext /usr/lib/libintl.so /usr/lib/preloadable_libintl.so; do
  if [ -e "$f" ]; then printf '     INFO %s 存在（非本节安装）\n' "$f"
  else printf '     OK   %s 不存在（符合本节只装 3 个程序）\n' "$f"; fi
done
echo "   --disable-shared 的效果：不应安装任何 gettext 共享库："
shopt -s nullglob
gtlibs=(/usr/lib/libintl* /usr/lib/libgettext* /usr/lib/libtextstyle*)
shopt -u nullglob
if [ ${#gtlibs[@]} -eq 0 ]; then
  echo "     OK   /usr/lib 下无 libintl/libgettext/libtextstyle"
else
  ls -l "${gtlibs[@]}" | sed 's/^/     INFO /'
fi
[ $rc -eq 0 ] || { echo "错误：Gettext 关键文件缺失或不符合手册要求" >&2; exit 1; }
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
echo "===== §7.7 完成，结束时间：$(date -Is) ====="
