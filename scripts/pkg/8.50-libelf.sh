#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.50 Libelf from Elfutils-0.194 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.49 OpenSSL-3.6.1 产物 -----"
test -x /usr/bin/openssl
test -e /usr/lib/libssl.so
test -e /usr/lib/libcrypto.so
test ! -e /sources/openssl-3.6.1
/usr/bin/openssl version
/usr/bin/openssl version | grep -F 'OpenSSL 3.6.1'
echo "OK   OpenSSL 3.6.1 程序和共享库可用，且上一节源码构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum elfutils-0.194.tar.bz2
echo '1137792ea10e9194637d7344439a5955  elfutils-0.194.tar.bz2' | md5sum -c -
test ! -e /sources/elfutils-0.194
tar -xvf elfutils-0.194.tar.bz2
cd elfutils-0.194
echo "源码目录：$PWD"
echo "补丁：本节无补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr        \
            --disable-debuginfod \
            --enable-libdebuginfod=dummy
echo

echo "----- 编译（手册命令：仅编译 lib 和 libelf） -----"
make -C lib
make -C libelf
echo

echo "----- 测试 -----"
echo "SKIP 手册明确说明：The test suite fails to build with glibc-2.43 or newer."
echo "当前 glibc：$(getconf GNU_LIBC_VERSION)；因此本节没有执行测试命令。"
echo

echo "----- 安装（手册命令：仅安装 Libelf） -----"
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm /usr/lib/libelf.a
echo

echo "----- 安装结果验证 -----"
test -e /usr/lib/libelf.so
test ! -e /usr/lib/libelf.a
test -f /usr/lib/pkgconfig/libelf.pc
test -d /usr/include/elfutils
test -f /usr/include/libelf.h
test -f /usr/include/gelf.h
pkg-config --modversion libelf
test "$(pkg-config --modversion libelf)" = 0.194
ls -l /usr/lib/libelf.so* /usr/lib/pkgconfig/libelf.pc
ls -ld /usr/include/elfutils
echo "OK   libelf.so、头文件目录和 libelf.pc 已安装；静态库 libelf.a 已按手册删除。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/elfutils-0.194
test ! -e /sources/elfutils-0.194
test -f /sources/elfutils-0.194.tar.bz2
echo "OK   已删除 /sources/elfutils-0.194；tarball 保留。"
echo
echo "===== §8.50 Libelf from Elfutils-0.194 完成：$(date -Is) ====="
