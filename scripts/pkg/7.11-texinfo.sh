#!/usr/bin/env bash
# LFS 13.0-systemd §7.11 Texinfo-7.2（临时工具）
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §7.11.1 的命令序列（全部；本节无补丁、无测试套件）：
#   ./configure --prefix=/usr
#   make
#   make install
set -euo pipefail

PKG=texinfo
VER=7.2
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §7.11 Texinfo-$VER（临时工具） ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 152 MB"
echo "手册简介：The Texinfo package contains programs for reading, writing, and"
echo "  converting info pages."
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
echo "可用空间（手册本节要求 152 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 152 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 152MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§7.10 Python-3.14.3）产物及 chroot 基础必须可用 -----"
rc=0
echo "1) §7.10 装入 /usr 的 Python 产物（确认上一任务产物完好）："
if command -v python3 >/dev/null 2>&1; then
  printf '   OK   %-9s %-20s %s\n' python3 "$(command -v python3)" "$(python3 --version 2>&1)"
else
  echo "   FAIL python3 不可用（§7.10 未完成？）"; rc=1
fi
for f in /usr/bin/python3 /usr/bin/pydoc3 /usr/lib/libpython3.so; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "2) §7.9 Perl（Texinfo 的 texi2any/pod2texi 是 Perl 程序，构建与安装都必需）："
if command -v perl >/dev/null 2>&1; then
  printf '   OK   %-9s %-16s %s\n' perl "$(command -v perl)" "$(perl -e 'print "v$]"')"
  echo "   perl -V:version：$(perl -V:version 2>/dev/null | tr -d '\n')"
  echo "   Perl 模块（Texinfo 的 XS 模块与安装脚本会用到）："
  for m in ExtUtils::MakeMaker Encode Data::Dumper File::Basename Getopt::Long POSIX Storable Text::Tabs Unicode::Normalize; do
    if perl -M"$m" -e1 >/dev/null 2>&1; then printf '     OK   %s\n' "$m"
    else printf '     FAIL %s 不可用\n' "$m"; rc=1; fi
  done
else
  echo "   FAIL perl 不可用（§7.9 未完成？）"; rc=1
fi
echo "3) §7.7/§7.8 产物（configure 会探测 gettext/bison 相关能力）："
for t in msgfmt xgettext bison yacc; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-9s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "4) 编译器与第 6 章工具（Texinfo 的 configure 是 autoconf 脚本）："
for t in gcc cc g++ ld as ar ranlib make sed grep gawk m4 tar xz patch find diff file bash install-info; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-11s %s\n' "$t" "$(command -v $t)"
  else printf '   INFO %-11s 不可用\n' "$t"; fi
done
for t in gcc cc ld ar make sed grep gawk tar xz find bash; do
  command -v $t >/dev/null 2>&1 || { printf '   FAIL 必需工具 %s 不可用\n' "$t"; rc=1; }
done
gcc --version | sed -n '1s/^/   gcc: /p'
echo "5) C 库头文件与 ncurses（info 程序需要 terminfo/curses 支持）："
for h in /usr/include/stdio.h /usr/include/locale.h /usr/include/langinfo.h /usr/include/curses.h; do
  if [ -f "$h" ]; then printf '   OK   %s\n' "$h"; else printf '   INFO %s 缺失\n' "$h"; fi
done
for h in /usr/include/stdio.h /usr/include/locale.h; do
  [ -f "$h" ] || { printf '   FAIL 必需头文件 %s 缺失\n' "$h"; rc=1; }
done
for l in /usr/lib/libc.so /usr/lib/libncursesw.so; do
  if [ -e "$l" ]; then printf '   OK   %s\n' "$l"; else printf '   INFO %s 缺失\n' "$l"; fi
done
echo "6) §7.6 建立的基础文件："
for f in /etc/passwd /etc/group /etc/hosts /etc/mtab; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "7) §7.3 虚拟内核文件系统："
for f in /dev/null /dev/zero /dev/urandom /dev/pts /proc/self /sys; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "8) §7.5 建立的安装目标目录："
for d in /usr/share/info /usr/share/man/man1 /usr/share/man/man5; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"; else printf '   FAIL %s 缺失\n' "$d"; rc=1; fi
done
echo "9) 本节安装前 texinfo 相关文件的状态："
for f in /usr/bin/makeinfo /usr/bin/texi2any /usr/bin/info /usr/bin/install-info /usr/lib/texinfo; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在（将被 make install 覆盖）\n' "$f"
  else printf '   OK   %s 尚未安装\n' "$f"; fi
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
echo "包自报版本：$(grep -m1 -E '^PACKAGE_STRING=' configure | sed "s/^PACKAGE_STRING=//; s/'//g")"
echo "本节无补丁：手册 §7.11 只有 ./configure --prefix=/usr、make、make install 三条命令，"
echo "  没有任何 patch/sed 前置改动（sources 目录下也没有 texinfo 相关补丁文件：$(ls /sources | grep -ci 'texinfo.*patch') 个）。"
echo

echo "================= 7.11.1. Installation of Texinfo ================="
echo "----- configure（手册原文：Prepare Texinfo for compilation） -----"
echo "手册命令：./configure --prefix=/usr"
echo "  说明：本节手册未给出任何 configure 选项说明，只有 --prefix=/usr 一个参数。"
time ./configure --prefix=/usr
echo
echo "configure 结果确认："
grep -m1 '\$ \./configure' config.log | sed 's/^ *\$ */  实际参数：/' || true
if grep -qE '^\s*\$ \./configure --prefix=/usr\s*$' config.log; then
  echo "  OK   configure 参数与手册 §7.11 完全一致"
else
  echo "  注意：configure 参数与手册字面不一致，见上一行"
fi
echo "  生成的构建参数："
grep -m1 '^prefix = ' Makefile  | sed 's/^/    Makefile: /' || true
grep -m1 '^PACKAGE_VERSION = ' Makefile | sed 's/^/    Makefile: /' || true
echo "  子目录 configure 状态（gnulib/tp/info/install-info 等）："
ls -d */Makefile 2>/dev/null | sed 's/^/    /' || true
echo "  Perl 探测结果（texi2any 依赖）："
grep -m1 '^PERL = ' tp/Makefile 2>/dev/null | sed 's/^/    tp/Makefile: /' || true
echo

echo "----- 编译（手册原文：Compile the package） -----"
echo "手册命令：make"
echo "（MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境提供）"
time make
echo
echo "顶层 make 退出码 0"
echo "构建产物（安装前，在源码树内）："
for b in info/ginfo install-info/ginstall-info tp/texi2any texindex/texindex; do
  if [ -e "$b" ]; then printf '  OK   %-28s %s\n' "$b" "$(file -b "$b" | cut -d, -f1-2)"
  else printf '  INFO %s 不存在（可能路径不同）\n' "$b"; fi
done
echo

echo "================= 本节测试 ================="
echo "手册 §7.11 未规定任何测试：该节命令只有 ./configure --prefix=/usr、make 和"
echo "  make install，没有 make check / make test。"
echo "  手册第 7 章的临时工具一律不跑测试套件（Texinfo 的测试套件在第 8 章 §8.74"
echo "  才可选运行）。"
echo "结论：本节无手册规定的测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装（手册原文：Install the package） -----"
echo "手册命令：make install"
time make install
echo

echo "----- 安装结果检查（对照手册 §8.74.2 Contents of Texinfo） -----"
echo "手册 §8.74.2：Installed programs: info, install-info, makeinfo (link to texi2any),"
echo "  pdftexi2dvi, pod2texi, texi2any, texi2dvi, texi2pdf, and texindex；"
echo "  Installed libraries: MiscXS.so, Parsetexi.so, and XSParagraph.so"
echo "  (all in /usr/lib/texinfo)；"
echo "  Installed directories: /usr/share/texinfo and /usr/lib/texinfo"
rc=0
echo "1) 程序："
for p in info install-info makeinfo pdftexi2dvi pod2texi texi2any texi2dvi texi2pdf texindex; do
  if [ -e "/usr/bin/$p" ]; then printf '   OK   %-24s %s\n' "/usr/bin/$p" "$(file -b "/usr/bin/$p" | cut -d, -f1-2)"
  else printf '   FAIL /usr/bin/%s 缺失\n' "$p"; rc=1; fi
done
echo "   手册指出 makeinfo 是 texi2any 的链接："
ls -l /usr/bin/makeinfo | sed 's/^/     /'
if [ -L /usr/bin/makeinfo ]; then
  echo "     OK   makeinfo -> $(readlink /usr/bin/makeinfo)"
else
  echo "     INFO makeinfo 不是符号链接（本版本以脚本形式安装）"
fi
echo "2) 库（手册 §8.74.2 写作 /usr/lib/texinfo 下的 XS 模块）："
echo "   说明：手册 §8.74.2 的 Contents 列表沿用旧版路径 /usr/lib/texinfo；Texinfo 7.2"
echo "   实际把这些 Perl XS 模块装到 /usr/lib/texi2any（见构建日志中 libtool 的"
echo "   -rpath /usr/lib/texi2any）。本节命令与手册完全一致，仅上游布局变更，"
echo "   因此按实际存在的那个目录校验。"
if [ -d /usr/lib/texi2any ]; then XSDIR=/usr/lib/texi2any
elif [ -d /usr/lib/texinfo ]; then XSDIR=/usr/lib/texinfo
else echo "   FAIL /usr/lib/texi2any 与 /usr/lib/texinfo 均不存在"; XSDIR=/usr/lib/texinfo; rc=1; fi
echo "   XS 模块目录：$XSDIR"
for l in MiscXS.so Parsetexi.so XSParagraph.so; do
  if [ -e "$XSDIR/$l" ]; then printf '   OK   %-34s %s\n' "$XSDIR/$l" "$(file -b "$XSDIR/$l" | cut -d, -f1-3)"
  else printf '   FAIL %s/%s 缺失\n' "$XSDIR" "$l"; rc=1; fi
done
echo "   该目录下的全部内容："
ls -1 "$XSDIR" 2>/dev/null | sed 's/^/     /'
echo "3) 目录："
for d in /usr/share/texinfo "$XSDIR"; do
  if [ -d "$d" ]; then echo "   OK   $d（$(find "$d" -type f | wc -l) 个文件）"
  else echo "   FAIL $d 缺失"; rc=1; fi
done
echo "   /usr/share/texinfo 内容：$(ls /usr/share/texinfo | tr '\n' ' ')"
echo "4) 运行冒烟测试："
# 注意：本脚本开了 pipefail，`cmd | head -n1` 会让 cmd 收到 SIGPIPE 而把整条管道
# 判为失败，与命令本身无关；因此一律先写临时文件再取首行。
vout=/tmp/.texinfo-version.out
for c in "info --version" "install-info --version" "makeinfo --version" "texi2any --version" "texindex --version" "pod2texi --version"; do
  if $c >"$vout" 2>&1; then
    printf '   OK   %-24s %s\n' "$c" "$(sed -n 1p "$vout")"
  else
    echo "   FAIL $c 执行失败"; sed -n '1,3p' "$vout" | sed 's/^/        /'; rc=1
  fi
done
makeinfo --version >"$vout" 2>&1 || true
ver_line=$(sed -n 1p "$vout"); rm -f "$vout"
case "$ver_line" in *"$VER"*) echo "   OK   makeinfo 版本号含 $VER" ;;
  *) echo "   FAIL makeinfo 报告的版本不含 $VER：$ver_line"; rc=1 ;; esac
echo "   makeinfo 实际转换一个最小 Texinfo 文档（验证 Perl XS 模块可加载）："
work=$(mktemp -d /tmp/texinfo-smoke-XXXXXX)
cat > "$work/hello.texi" <<'TEXI'
\input texinfo
@setfilename hello.info
@settitle Hello LFS
@node Top
@top Hello LFS
This is a minimal Texinfo document built during LFS 7.11.
@bye
TEXI
if (cd "$work" && makeinfo hello.texi) && [ -s "$work/hello.info" ]; then
  echo "     OK   生成 hello.info（$(wc -l < "$work/hello.info") 行）"
  sed -n '1,4p' "$work/hello.info" | sed 's/^/       /'
else
  echo "     FAIL makeinfo 无法转换文档"; rc=1
fi
if (cd "$work" && makeinfo --html --no-split -o hello.html hello.texi) && [ -s "$work/hello.html" ]; then
  echo "     OK   makeinfo --html 输出 hello.html（$(wc -c < "$work/hello.html") 字节）"
else
  echo "     FAIL makeinfo --html 失败"; rc=1
fi
if (cd "$work" && makeinfo --plaintext -o hello.txt hello.texi) && [ -s "$work/hello.txt" ]; then
  echo "     OK   makeinfo --plaintext 输出 hello.txt"
else
  echo "     FAIL makeinfo --plaintext 失败"; rc=1
fi
echo "   install-info 维护 info 索引（第 8 章多个包的 make install 依赖它）："
cp "$work/hello.info" /usr/share/info/hello.info
if install-info --info-dir=/usr/share/info /usr/share/info/hello.info 2>/dev/null || \
   install-info /usr/share/info/hello.info /usr/share/info/dir 2>/dev/null; then
  echo "     OK   install-info 执行成功"
else
  echo "     INFO install-info 未创建条目（该 .texi 无 @dircategory/@direntry，属正常）"
fi
install-info --delete --info-dir=/usr/share/info /usr/share/info/hello.info >/dev/null 2>&1 || true
rm -f /usr/share/info/hello.info
echo "   info 读取已安装的 info 页（texinfo 自身安装了 info.info 等）："
ls /usr/share/info/ > /tmp/.texinfo-infolist.txt || true
sed -n '1,20p' /tmp/.texinfo-infolist.txt | sed 's/^/     /'
echo "     （/usr/share/info 共 $(wc -l < /tmp/.texinfo-infolist.txt) 项）"
rm -f /tmp/.texinfo-infolist.txt
info_out=$(info --output=- --subnodes texinfo 2>/dev/null | head -n 3) || true
if [ -n "$info_out" ]; then
  echo "     OK   info 可读出 texinfo 手册，前 3 行："
  echo "$info_out" | sed 's/^/       /'
else
  echo "     INFO info 未能读出 texinfo 手册（本节未必安装该 info 文件）"
fi
echo "   texindex 排序 info 索引文件："
printf '\\entry{alpha}{2}{alpha}\n\\entry{beta}{1}{beta}\n' > "$work/t.cp"
if (cd "$work" && texindex t.cp) && [ -s "$work/t.cps" ]; then
  echo "     OK   texindex 生成 t.cps："
  sed 's/^/       /' "$work/t.cps"
else
  echo "     FAIL texindex 排序失败"; rc=1
fi
rm -rf "$work"
[ $rc -eq 0 ] || { echo "错误：Texinfo 关键文件缺失或不符合手册要求" >&2; exit 1; }
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
echo "===== §7.11 完成，结束时间：$(date -Is) ====="
