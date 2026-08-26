#!/usr/bin/env bash
# LFS 13.0-systemd §6.7 File-5.46
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.7.1 的命令序列（全部，无补丁、无测试套件）：
#   mkdir build
#   pushd build
#     ../configure --disable-bzlib      \
#                  --disable-libseccomp \
#                  --disable-xzlib      \
#                  --disable-zlib
#     make
#   popd
#   ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
#   make FILE_COMPILE=$(pwd)/build/src/file
#   make DESTDIR=$LFS install
#   rm -v $LFS/usr/lib/libmagic.la
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=file
VER=5.46
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.7 File-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 43 MB"
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
echo "可用空间（手册本节要求 43 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2~§6.6 产物必须可用 -----"
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
echo "上一任务（§6.6 Diffutils-3.12）产物必须可用："
for f in usr/bin/cmp usr/bin/diff usr/bin/diff3 usr/bin/sdiff; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.6 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%-14s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/lib/libncursesw.so.6（§6.3）：%s\n' "$(file -b $LFS/usr/lib/libncursesw.so.6 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/bash（§6.4）：%s\n' "$(file -b $LFS/usr/bin/bash | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/ls（§6.5）：%s\n' "$(file -b $LFS/usr/bin/ls | cut -d, -f1-2)"
echo
echo "宿主机 file 版本（手册 §6.7.1 要求：宿主的 file 必须与本次构建的版本一致，"
echo "  否则无法生成签名文件 magic.mgc；本节正是为此先构建一份临时的 file 命令）："
file --version | head -n2 | sed 's/^/  /'
host_file_ver=$(file --version | head -n1)
if [ "$host_file_ver" = "file-$VER" ]; then
  echo "  → 宿主 file 为 $host_file_ver，与目标版本 file-$VER 一致。"
else
  echo "  → 注意：宿主 file 为 $host_file_ver，与目标版本 file-$VER 不同；"
  echo "    因此下面构建的 build/src/file 通过 FILE_COMPILE 使用是强制性的。"
fi
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
echo "File 自报版本：$(grep -m1 -E '^AC_INIT' configure.ac | tr -d '\n')"
echo "本节无补丁：手册 §6.7 未规定任何 patch。"
echo

echo "================= 6.7.1 第一步：为宿主构建临时的 file 命令 ================="
echo "手册原文：The file command on the build host needs to be the same version as the"
echo "one we are building in order to create the signature file. Run the following"
echo "commands to make a temporary copy of the file command."
echo "说明：这份 build/ 里的 file 是**宿主平台**的本地编译（不带 --host），只用于在"
echo "  安装阶段生成 magic.mgc 签名文件，不会被安装进 \$LFS。"
echo
echo "----- mkdir build && pushd build -----"
mkdir build
pushd build
echo "----- ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib -----"
echo "选项含义（手册）：configure 会试图使用宿主发行版里已存在的库；若库文件存在而对应的"
echo "  头文件缺失就会编译失败。这些 --disable-* 用于阻止使用宿主上这些不需要的能力。"
time ../configure --disable-bzlib      \
             --disable-libseccomp \
             --disable-xzlib      \
             --disable-zlib
echo
echo "临时构建的 configure 结果确认（应为本地编译：build == host，cross_compiling=no）："
grep -m1 -E "cross_compiling=" config.log | sed 's/^ */  /' || echo "  （config.log 未以该形式记录，见上面的 build/host 三元组）"
grep -E '^(host|build)_triplet *=' Makefile | sed 's/^/  /' || true
echo
echo "----- make（临时 file） -----"
time make
echo
echo "临时 file 已生成："
ls -l src/file
file -b src/file | sed 's/^/  /'
./src/file --version | head -n1 | sed 's/^/  自报版本：/'
popd
echo "（build/ 目录仅用于生成签名文件，最终会随源码目录一起被清理）"
echo

echo "================= 6.7.1 第二步：交叉编译并安装 File ================="
echo "----- ./configure --prefix=/usr --host=\$LFS_TGT --build=\$(./config.guess) -----"
echo "build 三元组（./config.guess）：$(./config.guess)"
time ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build)_triplet *=' Makefile | sed 's/^/  /' || true
grep -E '^(prefix|CC) *=' Makefile | head -n4 | sed 's/^/  /' || true
echo "config.log 中的 cross_compiling 判定（应为 yes）："
grep -m1 -E "cross_compiling=" config.log | sed 's/^ */  /' || echo "  （config.log 未以该形式记录，见上面的 build/host 三元组）"
echo

echo "----- 编译：make FILE_COMPILE=\$(pwd)/build/src/file -----"
echo "FILE_COMPILE 指向上一步为宿主编译的 file，用它把 magic 源文件编译成 magic.mgc；"
echo "交叉编译出的 src/file 是 $LFS_TGT 的二进制，在宿主上无法运行，故必须显式指定。"
echo "FILE_COMPILE = $(pwd)/build/src/file"
time make FILE_COMPILE=$(pwd)/build/src/file
echo

echo "----- 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 删除 libtool 归档文件（手册：它对交叉编译有害） -----"
echo "命令：rm -v \$LFS/usr/lib/libmagic.la"
rm -v $LFS/usr/lib/libmagic.la
[ -e "$LFS/usr/lib/libmagic.la" ] && { echo "错误：libmagic.la 仍然存在" >&2; exit 1; }
echo "确认已删除：\$LFS/usr/lib/libmagic.la 不存在"
echo

echo "================= 本节测试 ================="
echo "手册 §6.7 未规定任何测试：本节命令只有临时 file 的 configure/make、交叉编译的"
echo "configure、make FILE_COMPILE=...、make DESTDIR=\$LFS install 和 rm libmagic.la，"
echo "没有 make check / make test（File 的测试套件由第 8 章 §8.11 在 chroot 内执行）。"
echo "原因见手册 §6.1：本章的程序与库是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.11.2 Contents of File） -----"
rc=0
echo "1) 程序 file："
if [ -f "$LFS/usr/bin/file" ]; then
  printf '   OK   $LFS/usr/bin/file   %s\n' "$(file -b $LFS/usr/bin/file | cut -d, -f1-2)"
else
  printf '   FAIL $LFS/usr/bin/file 缺失\n'; rc=1
fi
echo "2) 库 libmagic.so："
for f in usr/lib/libmagic.so usr/lib/libmagic.so.1; do
  if [ -e "$LFS/$f" ]; then printf '   OK   $LFS/%-22s -> %s\n' "$f" "$(readlink -f $LFS/$f | sed "s|^$LFS||")"
  else printf '   FAIL $LFS/%s 缺失\n' "$f"; rc=1; fi
done
ls -l $LFS/usr/lib/libmagic* | sed 's/^/     /'
echo "3) 签名文件 magic.mgc（由临时 file 生成，本节的关键产物）："
if [ -f "$LFS/usr/share/misc/magic.mgc" ]; then
  printf '   OK   $LFS/usr/share/misc/magic.mgc  %s 字节\n' "$(stat -c %s $LFS/usr/share/misc/magic.mgc)"
  printf '        类型：%s\n' "$(file -b $LFS/usr/share/misc/magic.mgc)"
else
  printf '   FAIL $LFS/usr/share/misc/magic.mgc 缺失\n'; rc=1
fi
echo "4) 头文件与手册页："
for f in usr/include/magic.h usr/share/man/man1/file.1 \
         usr/share/man/man3/libmagic.3 usr/share/man/man4/magic.4; do
  if [ -e "$LFS/$f" ]; then printf '   OK   $LFS/%s\n' "$f"
  else printf '   INFO $LFS/%s 未安装\n' "$f"; fi
done
echo "5) libtool 归档必须已被删除："
if [ -e "$LFS/usr/lib/libmagic.la" ]; then printf '   FAIL $LFS/usr/lib/libmagic.la 仍存在\n'; rc=1
else printf '   OK   $LFS/usr/lib/libmagic.la 已删除\n'; fi
[ $rc -eq 0 ] || { echo "错误：File 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
file $LFS/usr/bin/file
readelf -h $LFS/usr/bin/file | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应链接 §5.5 的 libc 与本节的 libmagic）："
$LFS_TGT-readelf -d $LFS/usr/bin/file | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/file | grep 'interpreter' | sed 's/^/  /'
echo "libmagic.so.1 的 SONAME 与依赖："
$LFS_TGT-readelf -d $LFS/usr/lib/libmagic.so.1 | grep -E 'SONAME|NEEDED' | sed 's/^/  /'
echo "file 二进制中的版本字符串（应为 5.46）："
strings -a $LFS/usr/bin/file | grep -m1 -E '^5\.46$' | sed 's/^/  版本: /' || true
strings -a $LFS/usr/bin/file | grep -m1 -E 'file-5\.46' | sed 's/^/  /' || true
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/file --version）"
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录，含临时的 build/） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
[ -d "$LFS/sources/$SRCDIR" ] && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR（临时 build/ 目录在其内部，一并删除）"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"
echo "$LFS 占用：$(du -sh $LFS 2>/dev/null | cut -f1)"

echo
echo "===== §6.7 完成，结束时间：$(date -Is) ====="
