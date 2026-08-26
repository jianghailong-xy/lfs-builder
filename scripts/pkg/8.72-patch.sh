#!/usr/bin/env bash
set -euo pipefail

echo "===== LFS 13.0-systemd §8.72 Patch-2.8 ====="
echo "开始：$(date -Is)"
echo "用户：$(id)"
echo "PATH=$PATH"
echo "MAKEFLAGS=${MAKEFLAGS:-}"
cd /sources

echo "----- 前置产物验证（§8.71 Make-4.4.1）-----"
test -x /usr/bin/make
test "$(make --version | awk 'NR==1 {print $3}')" = 4.4.1
echo "OK   上一任务 Make-4.4.1 关键产物可用。"

echo "----- 源码包检查与解包（本节无额外补丁）-----"
test -s patch-2.8.tar.xz
echo "149327a021d41c8f88d034eab41c039f  patch-2.8.tar.xz" | md5sum -c -
test ! -e patch-2.8 || { echo "错误：构建目录 /sources/patch-2.8 已存在，为避免覆盖失败现场而停止。" >&2; exit 1; }
tar -xvf patch-2.8.tar.xz
cd patch-2.8

echo "----- 配置：./configure --prefix=/usr -----"
./configure --prefix=/usr

echo "----- 编译：make -----"
make

echo "----- 测试：make check -----"
make check

echo "----- 安装：make install -----"
make install

echo "----- 安装结果验证 -----"
test -x /usr/bin/patch
test "$(patch --version | awk 'NR==1 {print $3}')" = 2.8
test -f /usr/share/man/man1/patch.1
patch --version | head -1
echo "OK   /usr/bin/patch 可执行，安装版本为 2.8，手册页存在。"

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf patch-2.8
test ! -e patch-2.8
echo "OK   已删除 /sources/patch-2.8；源码包保留。"
echo "===== §8.72 Patch-2.8 完成：$(date -Is) ====="
