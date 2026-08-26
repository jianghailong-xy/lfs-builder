#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.41 Expat-2.7.4 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.40 Gperf-3.3 产物 -----"
test -x /usr/bin/gperf
test -d /usr/share/doc/gperf-3.3
test ! -e /sources/gperf-3.3
/usr/bin/gperf --version | head -n1
echo "OK   Gperf-3.3 程序与文档可用，上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum expat-2.7.4.tar.xz
echo '5d3d1e1c829f8fb6f42b8e3e2371afa3  expat-2.7.4.tar.xz' | md5sum -c -
test ! -e /sources/expat-2.7.4
tar -xvf expat-2.7.4.tar.xz
cd expat-2.7.4
echo "源码目录：$PWD"
echo "INFO 本节手册没有要求应用补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr \
            --disable-static \
            --docdir=/usr/share/doc/expat-2.7.4
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

echo "----- 安装可选文档（手册命令） -----"
install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.7.4
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/xmlwf
test -e /usr/lib/libexpat.so
test -d /usr/share/doc/expat-2.7.4
test ! -e /usr/lib/libexpat.a
/usr/bin/xmlwf -h 2>&1 | head -n3 || true
ls -l /usr/bin/xmlwf /usr/lib/libexpat.so
find /usr/share/doc/expat-2.7.4 -maxdepth 1 -type f -printf '%f\n' | sort
echo "OK   xmlwf、libexpat.so 与版本化文档目录已验证；静态库不存在。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/expat-2.7.4
test ! -e /sources/expat-2.7.4
test -f /sources/expat-2.7.4.tar.xz
echo "OK   已删除 /sources/expat-2.7.4；tarball 保留。"
echo
echo "===== §8.41 Expat-2.7.4 完成：$(date -Is) ====="
