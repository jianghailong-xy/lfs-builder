#!/usr/bin/env bash
# LFS 13.0-systemd §6.4 Bash-5.3
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.4.1 的命令序列（全部，无补丁、无测试套件）：
#   ./configure --prefix=/usr                      \
#               --build=$(sh support/config.guess) \
#               --host=$LFS_TGT                    \
#               --without-bash-malloc
#   make
#   make DESTDIR=$LFS install
#   ln -sv bash $LFS/bin/sh
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=bash
VER=5.3
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.4 Bash-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 72 MB"
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
echo "可用空间（手册本节要求 72 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2/§6.3 产物必须可用 -----"
for t in ld as ar ranlib gcc g++; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少前置产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS_TGT-gcc --version | head -n1
echo "§5.5 Glibc / §5.6 Libstdc++ 产物（本节交叉编译与链接所必需）："
for f in usr/lib/libc.so.6 usr/lib/ld-linux-x86-64.so.2 usr/lib/crt1.o \
         usr/include/stdio.h usr/lib/libstdc++.so.6; do
  [ -e "$LFS/$f" ] || { echo "错误：前置产物缺失：\$LFS/$f" >&2; exit 1; }
  printf 'OK   $LFS/%s\n' "$f"
done
echo "上一任务（§6.3 Ncurses）产物："
for f in usr/lib/libncursesw.so usr/lib/libncursesw.so.6 usr/include/curses.h; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.3 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%s\n' "$f"
done
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
echo "手册 §4.2 的目录布局：\$LFS/bin 必须是指向 usr/bin 的符号链接（本节最后的 ln 依赖它）："
ls -ld $LFS/bin | sed 's/^/  /'
[ "$(readlink $LFS/bin)" = "usr/bin" ] || { echo "错误：\$LFS/bin 不是 usr/bin 的符号链接" >&2; exit 1; }
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
echo "Bash 自报版本：$(grep -m1 '^AC_INIT' configure.ac | tr -d '\n')  /  $(cat _distribution 2>/dev/null).$(cat _patchlevel 2>/dev/null)"
echo "本节无补丁（手册 §6.4 未规定任何 patch）"
echo

echo "----- 6.4.1 configure（交叉编译到 /usr） -----"
echo "build 三元组（sh support/config.guess）：$(sh support/config.guess)"
echo "--without-bash-malloc：关闭 Bash 自带 malloc（已知会导致段错误），改用 Glibc 的 malloc"
time ./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build)[a-z_]* *=' Makefile | head -n8 | sed 's/^/  /' || true
grep -E '^(prefix|CC|CROSS_COMPILE) *=' Makefile | sed 's/^/  /' || true
echo "--without-bash-malloc 是否生效（MALLOC_LIB/MALLOC_SRC 应为空）："
grep -E '^(MALLOC_LIB|MALLOC_SRC|MALLOC_TARGET|MALLOC_LDFLAGS) *=' Makefile | sed 's/^/  /' || true
echo "config.h 中不应定义 USING_BASH_MALLOC："
if grep -q '^#define USING_BASH_MALLOC' config.h 2>/dev/null; then
  echo "  警告：config.h 仍定义了 USING_BASH_MALLOC"; grep -n 'USING_BASH_MALLOC' config.h | sed 's/^/  /'
else
  echo "  未定义，符合 --without-bash-malloc"
fi
echo

echo "----- 6.4.1 编译：make -----"
time make
echo

echo "----- 6.4.1 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 6.4.1 安装后处理：ln -sv bash \$LFS/bin/sh -----"
echo "（手册：为使用 sh 作为 shell 的程序建立链接；\$LFS/bin 是 usr/bin 的符号链接）"
ln -sfv bash $LFS/bin/sh
ls -l $LFS/bin/sh $LFS/usr/bin/sh
echo

echo "================= 本节测试 ================="
echo "手册 §6.4 未规定任何测试：本节命令只有 configure、make、make DESTDIR=\$LFS install"
echo "以及安装后的 ln，没有 make check / make test（Bash 的测试套件由第 8 章 §8.37 执行）。"
echo "原因见手册 §6.1：本章的程序与库是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.37.2 Contents of Bash） -----"
rc=0
echo "1) 程序（bash、bashbug，以及本节 ln 建立的 sh -> bash）："
for f in bash bashbug; do
  if [ -f "$LFS/usr/bin/$f" ]; then printf 'OK   $LFS/usr/bin/%-8s %s\n' "$f" "$(file -b $LFS/usr/bin/$f | cut -d, -f1-2)"
  else printf 'FAIL $LFS/usr/bin/%s 缺失\n' "$f"; rc=1; fi
done
if [ -L "$LFS/usr/bin/sh" ] && [ "$(readlink $LFS/usr/bin/sh)" = "bash" ]; then
  printf 'OK   $LFS/usr/bin/sh -> %s\n' "$(readlink $LFS/usr/bin/sh)"
else
  printf 'FAIL $LFS/usr/bin/sh 不是指向 bash 的符号链接\n'; rc=1
fi
echo
echo "2) 目录（手册 §8.37.2：/usr/include/bash、/usr/lib/bash；/usr/share/doc/bash-$VER 由第 8 章的额外命令安装，本节不产生）："
for d in usr/include/bash usr/lib/bash; do
  if [ -d "$LFS/$d" ]; then printf 'OK   $LFS/%-20s（%s 项）\n' "$d" "$(ls $LFS/$d | wc -l)"
  else printf 'FAIL $LFS/%s 缺失\n' "$d"; rc=1; fi
done
if [ -e "$LFS/usr/share/doc/bash-$VER" ]; then
  printf 'INFO 已存在（非本节所建）：$LFS/usr/share/doc/bash-%s\n' "$VER"
else
  printf 'INFO 不存在，符合 §6.4 预期（第 8 章 §8.37 才安装文档）：$LFS/usr/share/doc/bash-%s\n' "$VER"
fi
echo
echo "3) 手册页与其它安装物："
for f in usr/share/man/man1/bash.1 usr/share/man/man1/bashbug.1 usr/share/info/bash.info; do
  if [ -e "$LFS/$f" ]; then printf 'OK   $LFS/%s\n' "$f"
  else printf 'INFO $LFS/%s 未安装\n' "$f"; fi
done
[ $rc -eq 0 ] || { echo "错误：Bash 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo
echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
file $LFS/usr/bin/bash
readelf -h $LFS/usr/bin/bash | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应链接 §6.3 的 libtinfo/libncursesw 与 §5.5 的 libc）："
$LFS_TGT-readelf -d $LFS/usr/bin/bash | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/bash | grep 'interpreter' | sed 's/^/  /'
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/bash --version）"
echo "bash 二进制中的版本字符串（应为 5.3，MACHTYPE 应为 $LFS_TGT）："
strings -a $LFS/usr/bin/bash | grep -m1 -E '@\(#\)Bash version' | sed 's/^/  /' || true
strings -a $LFS/usr/bin/bash | grep -m1 -E '^x86_64-lfs-linux-gnu$' | sed 's/^/  MACHTYPE: /' || true
echo "$LFS/usr/lib/bash 中的可加载内建（loadables）示例："
ls $LFS/usr/lib/bash 2>/dev/null | head -n 12 | tr '\n' ' '; echo
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
[ -d "$LFS/sources/$SRCDIR" ] && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"
echo "$LFS 占用：$(du -sh $LFS 2>/dev/null | cut -f1)"

echo
echo "===== §6.4 完成，结束时间：$(date -Is) ====="
