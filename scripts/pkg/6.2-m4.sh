#!/usr/bin/env bash
# LFS 13.0-systemd §6.2 M4-1.4.21
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.2.1 的命令序列（全部，无补丁、无测试套件）：
#   ./configure --prefix=/usr   \
#               --host=$LFS_TGT \
#               --build=$(build-aux/config.guess)
#   make
#   make DESTDIR=$LFS install
# 手册 §6.1：本章全部包用刚建好的交叉工具链交叉编译，安装到最终位置但还不能使用，
# 必须以 lfs 用户、§4.4 的环境完成。
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=m4
VER=1.4.21
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.2 M4-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 39 MB"
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
echo "可用空间（手册本节要求 39 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链（§5.2–§5.6）产物必须可用 -----"
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
echo "验证交叉工具链能编译链接可执行文件："
tmpd=$(mktemp -d); echo 'int main(){return 0;}' > "$tmpd/t.c"
$LFS_TGT-gcc "$tmpd/t.c" -o "$tmpd/t" && echo "OK   \$LFS_TGT-gcc 可正常编译链接"
readelf -h "$tmpd/t" | grep -E 'Class|Machine' | sed 's/^/  /'
rm -rf "$tmpd"
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
echo "M4 自报版本：$(grep -m1 '^PACKAGE_VERSION' configure | head -n1)"
echo "本节无补丁（手册 §6.2 未规定任何 patch）"
echo

echo "----- 6.2.1 configure -----"
echo "build 三元组（build-aux/config.guess）：$(build-aux/config.guess)"
time ./configure --prefix=/usr   \
            --host=$LFS_TGT      \
            --build=$(build-aux/config.guess)
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT，cross_compiling=yes）："
grep -E '^(host|build)_alias *=' Makefile | sed 's/^/  /' || true
grep -E '^(prefix|CC|cross_compiling) *=' Makefile | sed 's/^/  /' || true
echo

echo "----- 6.2.1 编译：make -----"
time make
echo

echo "----- 6.2.1 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "================= 本节测试 ================="
echo "手册 §6.2 未规定任何测试（本节只有 configure / make / make DESTDIR=\$LFS install 三条命令）。"
echo "原因见手册 §6.1：本章的程序是用交叉工具链为目标平台编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行 make check。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（手册 §8.14.2 Contents of M4：唯一安装的程序是 m4） -----"
rc=0
for f in usr/bin/m4; do
  if [ -e "$LFS/$f" ]; then printf 'OK   $LFS/%s\n' "$f"
  else printf 'FAIL $LFS/%s 缺失\n' "$f"; rc=1; fi
done
[ $rc -eq 0 ] || { echo "错误：M4 关键文件缺失" >&2; exit 1; }
ls -l $LFS/usr/bin/m4
echo
echo "确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制）："
file $LFS/usr/bin/m4 2>/dev/null || true
readelf -h $LFS/usr/bin/m4 | grep -E 'Class|Machine|Type' | sed 's/^/  /'
$LFS_TGT-readelf -d $LFS/usr/bin/m4 | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 \$LFS 内的 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/m4 | grep 'interpreter' | sed 's/^/  /'
echo
echo "手册说明本节不安装其它文件；本次安装写入 \$LFS 的内容："
find $LFS/usr -newer $LFS/sources/$TARBALL -name 'm4*' -maxdepth 3 2>/dev/null | sed 's/^/  /' || true
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
echo "===== §6.2 完成，结束时间：$(date -Is) ====="
