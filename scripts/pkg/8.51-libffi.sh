#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.51 Libffi-3.5.2 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.50 Libelf from Elfutils-0.194 产物 -----"
test -e /usr/lib/libelf.so
test -f /usr/include/libelf.h
test -f /usr/include/gelf.h
test -f /usr/lib/pkgconfig/libelf.pc
test ! -e /usr/lib/libelf.a
test ! -e /sources/elfutils-0.194
pkg-config --modversion libelf
test "$(pkg-config --modversion libelf)" = 0.194
echo "OK   Libelf 0.194 共享库、头文件和 pkg-config 元数据可用，静态库及上一节构建目录均不存在。"
echo

echo "----- 源码校验与解包 -----"
md5sum libffi-3.5.2.tar.gz
echo '92af9efad4ba398995abf44835c5d9e9  libffi-3.5.2.tar.gz' | md5sum -c -
test ! -e /sources/libffi-3.5.2
tar -xvf libffi-3.5.2.tar.gz
cd libffi-3.5.2
echo "源码目录：$PWD"
echo "补丁：本节无补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr    \
            --disable-static \
            --with-gcc-arch=native
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试（手册命令） -----"
make check
echo

echo "----- 测试结果摘要 -----"
find . -name '*.log' -o -name '*.sum' | sort
if test -f x86_64-pc-linux-gnu/testsuite/libffi.sum; then
  grep -E '^# of (expected passes|unexpected failures|unexpected successes|expected failures|unresolved testcases|unsupported tests)' x86_64-pc-linux-gnu/testsuite/libffi.sum || true
fi
echo "OK   make check 退出码为 0。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 安装结果验证 -----"
test -e /usr/lib/libffi.so
test ! -e /usr/lib/libffi.a
test -f /usr/include/ffi.h
test -f /usr/include/ffitarget.h
test -f /usr/lib/pkgconfig/libffi.pc
pkg-config --modversion libffi
test "$(pkg-config --modversion libffi)" = 3.5.2
ls -l /usr/lib/libffi.so* /usr/include/ffi.h /usr/include/ffitarget.h /usr/lib/pkgconfig/libffi.pc
echo "OK   Libffi 3.5.2 共享库、头文件和 pkg-config 元数据已安装；静态库未安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/libffi-3.5.2
test ! -e /sources/libffi-3.5.2
test -f /sources/libffi-3.5.2.tar.gz
echo "OK   已删除 /sources/libffi-3.5.2；tarball 保留。"
echo
echo "===== §8.51 Libffi-3.5.2 完成：$(date -Is) ====="
