#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.38 Libtool-2.5.4 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.37 Bash-5.3 产物 -----"
test -x /usr/bin/bash
test -x /usr/bin/bashbug
test -L /usr/bin/sh
test "$(readlink /usr/bin/sh)" = bash
/usr/bin/bash --version | head -n1
test ! -e /sources/bash-5.3
echo "OK   Bash-5.3 关键产物可用，且上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum libtool-2.5.4.tar.xz
echo '22e0a29df8af5fdde276ea3a7d351d30  libtool-2.5.4.tar.xz' | md5sum -c -
test ! -e /sources/libtool-2.5.4
tar -xvf libtool-2.5.4.tar.xz
cd libtool-2.5.4
echo "源码目录：$PWD"
echo "INFO 本节手册没有要求应用补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试（手册命令：make check） -----"
make check
echo "OK   make check 退出码为 0。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 删除仅供测试套件使用的静态库（手册命令） -----"
rm -fv /usr/lib/libltdl.a
test ! -e /usr/lib/libltdl.a
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/libtool
test -x /usr/bin/libtoolize
test -e /usr/lib/libltdl.so
test -d /usr/include/libltdl
test -d /usr/share/libtool
/usr/bin/libtool --version | head -n1
/usr/bin/libtoolize --version | head -n1
ls -l /usr/bin/libtool /usr/bin/libtoolize /usr/lib/libltdl.so*
echo "OK   libtool、libtoolize、共享库和本节安装目录均已验证；libltdl.a 不存在。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/libtool-2.5.4
test ! -e /sources/libtool-2.5.4
test -f /sources/libtool-2.5.4.tar.xz
echo "OK   已删除 /sources/libtool-2.5.4；tarball 保留。"
echo
echo "===== §8.38 Libtool-2.5.4 完成：$(date -Is) ====="
