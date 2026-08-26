#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.40 Gperf-3.3 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.39 GDBM-1.26 产物 -----"
test -x /usr/bin/gdbm_dump
test -x /usr/bin/gdbm_load
test -x /usr/bin/gdbmtool
test -e /usr/lib/libgdbm.so
test -e /usr/lib/libgdbm_compat.so
test ! -e /usr/lib/libgdbm.a
test ! -e /usr/lib/libgdbm_compat.a
test ! -e /sources/gdbm-1.26
/usr/bin/gdbmtool --version | head -n1
echo "OK   GDBM-1.26 关键产物可用，静态库不存在，且上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum gperf-3.3.tar.gz
echo '31753b021ea78a21f154bf9eecb8b079  gperf-3.3.tar.gz' | md5sum -c -
test ! -e /sources/gperf-3.3
tar -xvf gperf-3.3.tar.gz
cd gperf-3.3
echo "源码目录：$PWD"
echo "INFO 本节手册没有要求应用补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
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
test -x /usr/bin/gperf
test -d /usr/share/doc/gperf-3.3
/usr/bin/gperf --version | head -n1
ls -ld /usr/bin/gperf /usr/share/doc/gperf-3.3
find /usr/share/doc/gperf-3.3 -maxdepth 1 -type f -printf '%f\n' | sort
echo "OK   gperf 程序与版本化文档目录均已验证。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/gperf-3.3
test ! -e /sources/gperf-3.3
test -f /sources/gperf-3.3.tar.gz
echo "OK   已删除 /sources/gperf-3.3；tarball 保留。"
echo
echo "===== §8.40 Gperf-3.3 完成：$(date -Is) ====="
