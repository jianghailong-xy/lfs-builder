#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.39 GDBM-1.26 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.38 Libtool-2.5.4 产物 -----"
test -x /usr/bin/libtool
test -x /usr/bin/libtoolize
test -e /usr/lib/libltdl.so
test ! -e /usr/lib/libltdl.a
test ! -e /sources/libtool-2.5.4
/usr/bin/libtool --version | head -n1
/usr/bin/libtoolize --version | head -n1
echo "OK   Libtool-2.5.4 关键产物可用，静态测试库已删除，且上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum gdbm-1.26.tar.gz
echo 'aaa600665bc89e2febb3c7bd90679115  gdbm-1.26.tar.gz' | md5sum -c -
test ! -e /sources/gdbm-1.26
tar -xvf gdbm-1.26.tar.gz
cd gdbm-1.26
echo "源码目录：$PWD"
echo "INFO 本节手册没有要求应用补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr    \
            --disable-static \
            --enable-libgdbm-compat
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

echo "----- 安装结果验证 -----"
test -x /usr/bin/gdbm_dump
test -x /usr/bin/gdbm_load
test -x /usr/bin/gdbmtool
test -e /usr/lib/libgdbm.so
test -e /usr/lib/libgdbm_compat.so
test ! -e /usr/lib/libgdbm.a
test ! -e /usr/lib/libgdbm_compat.a
/usr/bin/gdbmtool --version | head -n1
ls -l /usr/bin/gdbm_dump /usr/bin/gdbm_load /usr/bin/gdbmtool \
      /usr/lib/libgdbm.so* /usr/lib/libgdbm_compat.so*
echo "OK   三个程序及两个共享库均已验证；--disable-static 生效。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/gdbm-1.26
test ! -e /sources/gdbm-1.26
test -f /sources/gdbm-1.26.tar.gz
echo "OK   已删除 /sources/gdbm-1.26；tarball 保留。"
echo
echo "===== §8.39 GDBM-1.26 完成：$(date -Is) ====="
