#!/usr/bin/env bash
set -euo pipefail

echo "===== LFS 13.0-systemd §8.71 Make-4.4.1 ====="
echo "开始：$(date -Is)"
echo "用户：$(id)"
echo "PATH=$PATH"
echo "MAKEFLAGS=${MAKEFLAGS:-}"
cd /sources

echo "----- 前置产物验证（§8.70 Libpipeline-1.5.8）-----"
test -L /usr/lib/libpipeline.so
test -f /usr/lib/libpipeline.so.1.5.8
test -f /usr/include/pipeline.h
test -f /usr/lib/pkgconfig/libpipeline.pc
test "$(pkg-config --modversion libpipeline)" = 1.5.8
echo "OK   上一任务 Libpipeline-1.5.8 关键产物可用。"

echo "----- 源码包检查与解包（本节无补丁）-----"
test -s make-4.4.1.tar.gz
sha256sum make-4.4.1.tar.gz
test ! -e make-4.4.1 || { echo "错误：构建目录 /sources/make-4.4.1 已存在，为避免覆盖现场而停止。" >&2; exit 1; }
tar -xvf make-4.4.1.tar.gz
cd make-4.4.1

echo "----- 配置：./configure --prefix=/usr -----"
./configure --prefix=/usr

echo "----- 编译：make -----"
make

echo "----- 测试：chown -R tester .；su tester -c PATH=... make check -----"
chown -R tester .
su tester -c "PATH=$PATH make check"

echo "----- 安装：make install -----"
make install

echo "----- 安装结果验证 -----"
test -x /usr/bin/make
test "$(make --version | awk 'NR==1 {print $3}')" = 4.4.1
make --version | head -1
echo "OK   /usr/bin/make 可执行，安装版本为 4.4.1。"

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf make-4.4.1
test ! -e make-4.4.1
echo "OK   已删除 /sources/make-4.4.1；源码包保留。"
echo "===== §8.71 Make-4.4.1 完成：$(date -Is) ====="
