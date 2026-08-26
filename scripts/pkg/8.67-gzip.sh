#!/usr/bin/env bash
set -euo pipefail

echo "===== LFS 13.0-systemd §8.67 Gzip-1.14 ====="
echo "开始：$(date -Is)"
echo "用户：$(id)"
echo "PATH=$PATH"
echo "MAKEFLAGS=${MAKEFLAGS:-} TESTSUITEFLAGS=${TESTSUITEFLAGS:-}"
cd /sources

echo "----- 前置产物验证（§8.66 GRUB-2.14）-----"
grub-install --version
test "$(grub-install --version | awk 'NR==1 {print $NF}')" = 2.14
test -x /usr/sbin/grub-install
test -s /usr/lib/grub/i386-pc/modinfo.sh
echo "OK   上一任务 GRUB-2.14 关键产物可用。"

echo "----- 源码包检查、解包 -----"
test -s gzip-1.14.tar.xz
sha256sum gzip-1.14.tar.xz
test ! -e gzip-1.14 || { echo "错误：构建目录 /sources/gzip-1.14 已存在，为避免覆盖现场而停止。" >&2; exit 1; }
tar -xvf gzip-1.14.tar.xz
cd gzip-1.14
echo "手册本节未规定补丁。"

echo "----- 配置：./configure --prefix=/usr -----"
./configure --prefix=/usr

echo "----- 编译：make -----"
make

echo "----- 测试：make check -----"
make check
echo "OK   make check 退出码为 0。"

echo "----- 安装：make install -----"
make install

echo "----- 安装结果验证 -----"
gzip --version | head -n 1
test "$(gzip --version | awk 'NR==1 {print $2}')" = 1.14
for p in gunzip gzexe gzip uncompress zcat zcmp zdiff zegrep zfgrep zforce zgrep zless zmore znew; do
  command -v "$p"
done
test /usr/bin/uncompress -ef /usr/bin/gunzip
tmp=$(mktemp -d /tmp/gzip-verify.XXXXXX)
printf 'LFS Gzip 1.14 verification\n' > "$tmp/input"
gzip -c "$tmp/input" > "$tmp/input.gz"
gzip -cd "$tmp/input.gz" > "$tmp/output"
cmp "$tmp/input" "$tmp/output"
rm -rf "$tmp"
echo "OK   Gzip 1.14 程序、硬链接及压缩往返验证通过。"

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf gzip-1.14
test ! -e gzip-1.14
echo "OK   已删除 /sources/gzip-1.14；源码包保留。"
gzip --version | head -n 1
echo "===== §8.67 Gzip-1.14 完成：$(date -Is) ====="
