#!/usr/bin/env bash
# LFS 13.0-systemd §6.3 Ncurses-6.6
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.3.1 的命令序列（全部，无补丁、无测试套件）：
#   mkdir build
#   pushd build
#     ../configure --prefix=$LFS/tools AWK=gawk
#     make -C include
#     make -C progs tic
#     install progs/tic $LFS/tools/bin
#   popd
#   ./configure --prefix=/usr                \
#       --host=$LFS_TGT              \
#       --build=$(./config.guess)    \
#       --mandir=/usr/share/man      \
#       --with-manpage-format=normal \
#       --with-shared                \
#       --without-normal             \
#       --with-cxx-shared            \
#       --without-debug              \
#       --without-ada                \
#       --disable-stripping          \
#       AWK=gawk
#   make
#   make DESTDIR=$LFS install
#   ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
#   sed -e 's/^#if.*XOPEN.*$/#if 1/' -i $LFS/usr/include/curses.h
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=ncurses
VER=6.6
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.3 Ncurses-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.4 SBU，Required disk space 54 MB"
echo
echo "----- 环境（手册 §4.4 / iii. General Compilation Instructions） -----"
echo "whoami   : $(whoami)"
echo "LFS      : $LFS"
echo "LFS_TGT  : $LFS_TGT"
echo "PATH     : $PATH"
echo "LC_ALL   : $LC_ALL"
echo "CONFIG_SITE: $CONFIG_SITE"
echo "MAKEFLAGS: ${MAKEFLAGS:-（未设置）}"
echo "umask    : $(umask)"
echo "hash 关闭: $(set -o | grep hashall)"
echo "uname -m : $(uname -m)"
[ "$(whoami)" = "lfs" ] || { echo "错误：必须以 lfs 用户构建（手册 §6.1 警告：以 root 构建会毁掉宿主系统）" >&2; exit 1; }
[ "$LFS" = "/mnt/lfs" ] || { echo "错误：LFS 不是 /mnt/lfs" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点" >&2; exit 1; }
echo "可用空间（手册本节要求 54 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2 M4 产物必须可用 -----"
for t in ld as ar ranlib gcc g++; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少前置产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS_TGT-gcc --version | head -n1
echo "§5.5 Glibc / §5.6 Libstdc++ 产物："
for f in usr/lib/libc.so.6 usr/lib/ld-linux-x86-64.so.2 usr/lib/crt1.o \
         usr/include/stdio.h usr/lib/libstdc++.so.6; do
  [ -e "$LFS/$f" ] || { echo "错误：前置产物缺失：\$LFS/$f" >&2; exit 1; }
  printf 'OK   $LFS/%s\n' "$f"
done
echo "上一任务（§6.2 M4）产物："
[ -x "$LFS/usr/bin/m4" ] || { echo "错误：\$LFS/usr/bin/m4 缺失，§6.2 未完成" >&2; exit 1; }
printf 'OK   $LFS/usr/bin/m4  (%s)\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
echo "本节 tic 需要在宿主上编译运行，检查宿主工具链与 gawk："
gcc --version | head -n1
g++ --version | head -n1
gawk --version | head -n1
echo

cd $LFS/sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii：以 lfs 用户在 \$LFS/sources 下解包） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "Ncurses 自报版本：$(grep -m1 '^NCURSES_VERSION' dist.mk || grep -m1 'VERSION=' VERSION 2>/dev/null || cat VERSION)"
echo "本节无补丁（手册 §6.3 未规定任何 patch）"
echo

echo "----- 6.3.1 第一步：在宿主上构建 tic 并装入 \$LFS/tools/bin -----"
echo "（手册：先用宿主编译器构建 tic，安装到 \$LFS/tools，使后面交叉编译时能在 PATH 中找到它）"
mkdir build
pushd build
  time ../configure --prefix=$LFS/tools AWK=gawk
  echo
  echo "--- make -C include ---"
  time make -C include
  echo
  echo "--- make -C progs tic ---"
  time make -C progs tic
  echo
  echo "--- install progs/tic \$LFS/tools/bin ---"
  install progs/tic $LFS/tools/bin
popd
echo
echo "确认 tic 已就位且是宿主可执行的程序（供交叉编译阶段调用）："
ls -l $LFS/tools/bin/tic
file $LFS/tools/bin/tic
command -v tic
tic -V
echo

echo "----- 6.3.1 configure（交叉编译到 /usr） -----"
echo "build 三元组（./config.guess）：$(./config.guess)"
time ./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping          \
            AWK=gawk
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT，cross_compiling=yes）："
grep -E '^(host|build)[a-z_]* *=' Makefile | head -n6 | sed 's/^/  /' || true
grep -E '^(prefix|CC|CXX|cross_compiling|AWK) *=' Makefile | sed 's/^/  /' || true
echo "手册要求的开关是否生效（宽字符/共享库/无静态库/无 debug/无 ada/不 strip/手册页不压缩）："
grep -E '^(DFT_ARG_SUFFIX|LIB_SUFFIX|MANPAGE_FORMAT|cf_cv_abi_default)' Makefile 2>/dev/null | sed 's/^/  /' || true
echo

echo "----- 6.3.1 编译：make -----"
time make
echo

echo "----- 6.3.1 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 6.3.1 安装后处理（手册规定的两条命令） -----"
echo "1) ln -sv libncursesw.so \$LFS/usr/lib/libncurses.so"
ln -sfv libncursesw.so $LFS/usr/lib/libncurses.so
echo "2) sed -e 's/^#if.*XOPEN.*\$/#if 1/' -i \$LFS/usr/include/curses.h"
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i $LFS/usr/include/curses.h
echo "curses.h 中受影响的行（应全部变成 #if 1，不再有 #if ...XOPEN...）："
grep -n '^#if 1$' $LFS/usr/include/curses.h | sed 's/^/  /' || true
if grep -qE '^#if.*XOPEN' $LFS/usr/include/curses.h; then
  echo "错误：curses.h 仍存在未被替换的 ^#if ...XOPEN... 行" >&2; exit 1
fi
echo

echo "================= 本节测试 ================="
echo "手册 §6.3 未规定任何测试：本节命令只有 build/ 内的 tic 构建、configure、make、"
echo "make DESTDIR=\$LFS install 以及安装后的 ln 与 sed，没有 make check / make test。"
echo "原因见手册 §6.1：本章的程序与库是用交叉工具链为目标平台编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查 -----"
echo "对照手册 §8.31.2 Contents of Ncurses；注意其中的非 w 符号链接（libcurses.so /"
echo "libform.so / libmenu.so / libpanel.so）与 /usr/share/doc/ncurses-6.6 是第 8 章"
echo "§8.31 自己的额外命令（for lib in ... ln -sfv、cp -R doc）产生的，§6.3 不含这些命令，"
echo "因此本节不应、也不会安装它们；下面按 §6.3 实际规定的命令逐项核对。"
rc=0
echo
echo "1) 程序（make DESTDIR=\$LFS install 安装到 \$LFS/usr/bin；captoinfo/infotocap 为 tic 的链接，reset 为 tset 的链接）："
for f in captoinfo clear infocmp infotocap ncursesw6-config reset tabs tic toe tput tset; do
  if [ -e "$LFS/usr/bin/$f" ]; then printf 'OK   $LFS/usr/bin/%s\n' "$f"
  else printf 'FAIL $LFS/usr/bin/%s 缺失\n' "$f"; rc=1; fi
done
echo
echo "2) 共享库（--with-shared / --with-cxx-shared，宽字符版为实体）："
for f in libncursesw.so libncursesw.so.6 libncursesw.so.6.6 \
         libformw.so libmenuw.so libpanelw.so \
         libncurses++w.so libncurses++w.so.6 libncurses++w.so.6.6; do
  if [ -e "$LFS/usr/lib/$f" ]; then printf 'OK   $LFS/usr/lib/%-22s -> %s\n' "$f" "$(readlink -f $LFS/usr/lib/$f | sed "s|^$LFS||")"
  else printf 'FAIL $LFS/usr/lib/%s 缺失\n' "$f"; rc=1; fi
done
echo
echo "3) 手册本节安装后处理生成的 libncurses.so 符号链接（必须指向 libncursesw.so）："
if [ -L "$LFS/usr/lib/libncurses.so" ] && [ "$(readlink $LFS/usr/lib/libncurses.so)" = "libncursesw.so" ]; then
  printf 'OK   $LFS/usr/lib/libncurses.so -> %s\n' "$(readlink $LFS/usr/lib/libncurses.so)"
else
  printf 'FAIL $LFS/usr/lib/libncurses.so 不是指向 libncursesw.so 的符号链接\n'; rc=1
fi
echo
echo "4) 手册本节安装后处理的 curses.h（^#if ...XOPEN... 必须全部变为 #if 1，使其始终用宽字符结构体）："
if grep -qE '^#if.*XOPEN' $LFS/usr/include/curses.h; then
  printf 'FAIL curses.h 仍有未替换的 ^#if ...XOPEN... 行\n'; rc=1
else
  printf 'OK   $LFS/usr/include/curses.h 已无 ^#if ...XOPEN... 行，替换后的 #if 1 行：%s\n' "$(grep -c '^#if 1$' $LFS/usr/include/curses.h)"
fi
echo
echo "5) 目录与头文件："
for d in usr/share/tabset usr/share/terminfo usr/share/man; do
  if [ -d "$LFS/$d" ]; then printf 'OK   $LFS/%s\n' "$d"
  else printf 'FAIL $LFS/%s 缺失\n' "$d"; rc=1; fi
done
for f in usr/include/curses.h usr/include/ncurses.h usr/include/term.h \
         usr/include/form.h usr/include/menu.h usr/include/panel.h usr/include/cursesw.h; do
  if [ -e "$LFS/$f" ]; then printf 'OK   $LFS/%s\n' "$f"
  else printf 'FAIL $LFS/%s 缺失\n' "$f"; rc=1; fi
done
echo
echo "6) 手册第 8 章才会创建、本节按手册不应存在的项（仅提示，不判失败）："
for f in usr/lib/libcurses.so usr/lib/libform.so usr/lib/libmenu.so usr/lib/libpanel.so \
         usr/share/doc/ncurses-$VER; do
  if [ -e "$LFS/$f" ]; then printf 'INFO 已存在（非本节所建）：$LFS/%s\n' "$f"
  else printf 'INFO 不存在，符合 §6.3 预期（第 8 章 §8.31 才创建）：$LFS/%s\n' "$f"; fi
done
[ $rc -eq 0 ] || { echo "错误：Ncurses 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo
echo "----- configure 开关的实际效果核对 -----"
echo "--without-normal（不装静态 C 库）：以下应为空"
find $LFS/usr/lib -maxdepth 1 \( -name 'lib*curses*.a' -o -name 'libform*.a' \
     -o -name 'libmenu*.a' -o -name 'libpanel*.a' \) | sed 's/^/  /'
echo "--without-debug（不装 _g 调试库）：以下应为空"
find $LFS/usr/lib -maxdepth 1 -name 'lib*_g.*' | sed 's/^/  /'
echo "--without-ada（不装 Ada 绑定）：以下应为空"
find $LFS/usr -maxdepth 4 \( -iname '*AdaCurses*' -o -iname 'terminal_interface*' \) 2>/dev/null | sed 's/^/  /'
echo "--with-manpage-format=normal（手册页不压缩）：\$LFS/usr/share/man 下的 .gz 数量应为 0"
echo "  .gz 文件数：$(find $LFS/usr/share/man -name '*.gz' 2>/dev/null | wc -l)"
echo "  已装 ncurses 手册页数（.3ncurses 为 6.6 的后缀）：$(find $LFS/usr/share/man -name '*.3ncurses' 2>/dev/null | wc -l)"
echo "  本节安装的 man1 手册页：$(cd $LFS/usr/share/man/man1 && ls captoinfo.1 clear.1 infocmp.1 infotocap.1 ncursesw6-config.1 reset.1 tabs.1 tic.1 toe.1 tput.1 tset.1 2>/dev/null | tr '\n' ' ')"
echo "--disable-stripping（不用宿主 strip）：目标二进制应为 not stripped"
file -b $LFS/usr/bin/tic | sed 's/^/  /'
echo
echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
file $LFS/usr/lib/libncursesw.so.6.6 $LFS/usr/bin/tic 2>/dev/null || true
readelf -h $LFS/usr/lib/libncursesw.so.6.6 | grep -E 'Class|Machine|Type' | sed 's/^/  /'
$LFS_TGT-readelf -d $LFS/usr/bin/tic | grep -E 'NEEDED' | sed 's/^/  /'
echo "\$LFS/usr/bin/tic 的解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/tic | grep 'interpreter' | sed 's/^/  /'
echo "对比：\$LFS/tools/bin/tic 是本节第一步在宿主上构建、供交叉编译期间使用的宿主程序："
file -b $LFS/tools/bin/tic | sed 's/^/  /'
echo
echo "----- terminfo 数据 -----"
ls -l $LFS/usr/lib/libncursesw.so*
echo "terminfo 条目数：$(find $LFS/usr/share/terminfo -type f | wc -l)"
echo "terminfo 一级目录：$(ls $LFS/usr/share/terminfo | tr '\n' ' ')"
echo "关键条目检查："
for t in x/xterm x/xterm-256color l/linux v/vt100 d/dumb; do
  [ -e "$LFS/usr/share/terminfo/$t" ] && printf '  OK   %s\n' "$t" || printf '  WARN %s 不存在\n' "$t"
done
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
[ -d "$LFS/sources/$SRCDIR" ] && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR（含其中的 build/ 子目录）"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"
echo "$LFS 占用：$(du -sh $LFS 2>/dev/null | cut -f1)"

echo
echo "===== §6.3 完成，结束时间：$(date -Is) ====="
