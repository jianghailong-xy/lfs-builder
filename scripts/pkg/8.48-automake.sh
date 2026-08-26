#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.48 Automake-1.18.1 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.47 Autoconf-2.72 产物 -----"
test -x /usr/bin/autoconf
test -x /usr/bin/autom4te
test ! -e /sources/autoconf-2.72
/usr/bin/autoconf --version
test "$(/usr/bin/autoconf --version | sed -n '1s/.* //p')" = 2.72
test -d /usr/share/autoconf
echo "OK   Autoconf 2.72 可用，且上一节源码构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum automake-1.18.1.tar.xz
echo 'cea31dbf1120f890cbf2a3032cfb9a68  automake-1.18.1.tar.xz' | md5sum -c -
test ! -e /sources/automake-1.18.1
tar -xvf automake-1.18.1.tar.xz
cd automake-1.18.1
echo "源码目录：$PWD"
echo "补丁：本节无补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
echo

echo "----- 编译（手册命令：make） -----"
make
echo

echo "----- 测试（手册命令：make -j\$((\$(nproc)>4?\$(nproc):4)) check） -----"
test_jobs=$(( $(nproc) > 4 ? $(nproc) : 4 ))
make -j"$test_jobs" check
echo "OK   make -j${test_jobs} check 退出码为 0。"
echo

echo "----- 安装（手册命令：make install） -----"
make install
echo

echo "----- 安装结果验证 -----"
for program in aclocal aclocal-1.18 automake automake-1.18; do
    test -x "/usr/bin/$program"
    echo "OK   /usr/bin/$program"
done
test -d /usr/share/automake-1.18
test -d /usr/share/doc/automake-1.18.1
/usr/bin/automake --version
test "$(/usr/bin/automake --version | sed -n '1s/.* //p')" = 1.18.1
ls -ld /usr/share/automake-1.18 /usr/share/doc/automake-1.18.1
echo "OK   手册列出的程序、共享数据及文档目录均已安装，版本为 1.18.1。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/automake-1.18.1
test ! -e /sources/automake-1.18.1
test -f /sources/automake-1.18.1.tar.xz
echo "OK   已删除 /sources/automake-1.18.1；tarball 保留。"
echo
echo "===== §8.48 Automake-1.18.1 完成：$(date -Is) ====="
