#!/usr/bin/env bash
set -euo pipefail

echo "===== LFS 13.0-systemd §8.70 Libpipeline-1.5.8 ====="
echo "开始：$(date -Is)"
echo "用户：$(id)"
echo "PATH=$PATH"
echo "MAKEFLAGS=${MAKEFLAGS:-}"
cd /sources

echo "----- 前置产物验证（§8.69 Kbd-2.9.0）-----"
test -x /usr/bin/loadkeys
loadkeys --version
test "$(loadkeys --version | awk 'NR==1 {print $NF}')" = 2.9.0
test -d /usr/share/keymaps
test -d /usr/share/consolefonts
echo "OK   上一任务 Kbd-2.9.0 关键产物可用。"

echo "----- 源码包检查与解包（本节无补丁）-----"
test -s libpipeline-1.5.8.tar.gz
sha256sum libpipeline-1.5.8.tar.gz
test ! -e libpipeline-1.5.8 || { echo "错误：构建目录 /sources/libpipeline-1.5.8 已存在，为避免覆盖现场而停止。" >&2; exit 1; }
tar -xvf libpipeline-1.5.8.tar.gz
cd libpipeline-1.5.8

echo "----- 配置：./configure --prefix=/usr -----"
./configure --prefix=/usr

echo "----- 编译：make -----"
make

echo "----- 测试 -----"
echo "SKIP 手册说明测试需要已从 LFS 移除的 Check 库；按 §8.70 不运行测试。"

echo "----- 安装：make install -----"
make install

echo "----- 安装结果验证 -----"
test -L /usr/lib/libpipeline.so
test -f /usr/lib/libpipeline.so.1.5.8
test "$(readlink /usr/lib/libpipeline.so)" = libpipeline.so.1.5.8
test -f /usr/include/pipeline.h
test -f /usr/lib/pkgconfig/libpipeline.pc
test "$(pkg-config --modversion libpipeline)" = 1.5.8
ldconfig
ldconfig -p | grep -F 'libpipeline.so.1'
echo "OK   libpipeline.so、头文件与 pkg-config 元数据验证通过，版本为 1.5.8。"

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf libpipeline-1.5.8
test ! -e libpipeline-1.5.8
echo "OK   已删除 /sources/libpipeline-1.5.8；源码包保留。"
echo "===== §8.70 Libpipeline-1.5.8 完成：$(date -Is) ====="
