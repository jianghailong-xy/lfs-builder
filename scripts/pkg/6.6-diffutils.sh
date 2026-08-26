#!/usr/bin/env bash
# LFS 13.0-systemd §6.6 Diffutils-3.12
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.6.1 的命令序列（全部，无补丁、无测试套件）：
#   ./configure --prefix=/usr   \
#               --host=$LFS_TGT \
#               gl_cv_func_strcasecmp_works=y \
#               --build=$(./build-aux/config.guess)
#   make
#   make DESTDIR=$LFS install
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=diffutils
VER=3.12
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.6 Diffutils-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 35 MB"
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
echo "可用空间（手册本节要求 35 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2~§6.5 产物必须可用 -----"
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
echo "上一任务（§6.5 Coreutils-9.10）产物必须可用："
for f in usr/bin/ls usr/bin/hostname usr/sbin/chroot usr/libexec/coreutils/libstdbuf.so; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.5 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%-38s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/lib/libncursesw.so.6（§6.3）：%s\n' "$(file -b $LFS/usr/lib/libncursesw.so.6 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/bash（§6.4）：%s\n' "$(file -b $LFS/usr/bin/bash | cut -d, -f1-2)"
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
echo "Diffutils 自报版本：$(grep -m1 -E '^AC_INIT' configure.ac | tr -d '\n')  /  $(cat .version 2>/dev/null || echo 'N/A')"
echo "本节无补丁：手册 §6.6 未规定任何 patch。"
echo

echo "----- 6.6.1 configure（交叉编译到 /usr） -----"
echo "build 三元组（./build-aux/config.guess）：$(./build-aux/config.guess)"
echo "gl_cv_func_strcasecmp_works=y：手册说明该检查需要运行被编译的 C 程序，交叉编译时"
echo "  无法运行且上游没有给出交叉编译的回退值，configure 会直接报错；已知 Glibc-2.43 的"
echo "  strcasecmp 正常，故直接把检查结果指定为 y，让 configure 跳过该检查。"
time ./configure --prefix=/usr   \
            --host=$LFS_TGT \
            gl_cv_func_strcasecmp_works=y \
            --build=$(./build-aux/config.guess)
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build)[a-z_]* *=' Makefile | head -n8 | sed 's/^/  /' || true
grep -E '^(prefix|CC|cross_compiling) *=' Makefile | sed 's/^/  /' || true
echo "config.log 中的 cross_compiling 判定："
grep -m1 -E "^cross_compiling='" config.log | sed 's/^/  /' || true
echo "gl_cv_func_strcasecmp_works 的取值（应为手册指定的 y，未经实际运行探测）："
grep -m1 -E "^gl_cv_func_strcasecmp_works=" config.log | sed 's/^/  /' || true
echo

echo "----- 6.6.1 编译：make -----"
time make
echo

echo "----- 6.6.1 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "================= 本节测试 ================="
echo "手册 §6.6 未规定任何测试：本节命令只有 configure、make、make DESTDIR=\$LFS install，"
echo "没有 make check / make test（Diffutils 的测试套件由第 8 章 §8.62 在 chroot 内执行）。"
echo "原因见手册 §6.1：本章的程序与库是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.62.2 Contents of Diffutils） -----"
rc=0
echo "1) 手册 §8.62.2 列出的 4 个程序（cmp、diff、diff3、sdiff）："
for p in cmp diff diff3 sdiff; do
  if [ -f "$LFS/usr/bin/$p" ]; then
    printf '   OK   $LFS/usr/bin/%-6s %s\n' "$p" "$(file -b $LFS/usr/bin/$p | cut -d, -f1-2)"
  else
    printf '   FAIL $LFS/usr/bin/%s 缺失\n' "$p"; rc=1
  fi
done
echo
echo "2) 手册页与 info（本包同时安装文档）："
for f in usr/share/man/man1/cmp.1 usr/share/man/man1/diff.1 \
         usr/share/man/man1/diff3.1 usr/share/man/man1/sdiff.1 \
         usr/share/info/diffutils.info; do
  if [ -e "$LFS/$f" ]; then printf '   OK   $LFS/%s\n' "$f"
  else printf '   INFO $LFS/%s 未安装\n' "$f"; fi
done
[ $rc -eq 0 ] || { echo "错误：Diffutils 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
file $LFS/usr/bin/diff
readelf -h $LFS/usr/bin/diff | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应只链接 §5.5 的 libc）："
$LFS_TGT-readelf -d $LFS/usr/bin/diff | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/diff | grep 'interpreter' | sed 's/^/  /'
echo "diff 二进制中的版本字符串（应为 3.12）："
strings -a $LFS/usr/bin/diff | grep -m1 -E '^3\.12$' | sed 's/^/  版本: /' || true
strings -a $LFS/usr/bin/diff | grep -m1 -E 'GNU diffutils' | sed 's/^/  /' || true
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/diff --version）"
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
echo "===== §6.6 完成，结束时间：$(date -Is) ====="
