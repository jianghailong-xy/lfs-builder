#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.47 Autoconf-2.72 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.46 Intltool-0.51.0 产物 -----"
test -x /usr/bin/intltoolize
test ! -e /sources/intltool-0.51.0
/usr/bin/intltoolize --version
test "$(/usr/bin/intltoolize --version | sed -n '1s/.* //p')" = 0.51.0
test -f /usr/share/intltool/Makefile.in.in
test -f /usr/share/doc/intltool-0.51.0/I18N-HOWTO
echo "OK   Intltool 0.51.0 可用，且上一节源码构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum autoconf-2.72.tar.xz
echo '1be79f7106ab6767f18391c5e22be701  autoconf-2.72.tar.xz' | md5sum -c -
test ! -e /sources/autoconf-2.72
tar -xvf autoconf-2.72.tar.xz
cd autoconf-2.72
echo "源码目录：$PWD"
echo "补丁：本节无补丁。"
echo

echo "----- 配置（手册命令：./configure --prefix=/usr） -----"
./configure --prefix=/usr
echo

echo "----- 编译（手册命令：make） -----"
make
echo

echo "----- 测试（手册命令：make check） -----"
make check
echo "OK   make check 退出码为 0。"
echo

echo "----- 安装（手册命令：make install） -----"
make install
echo

echo "----- 安装结果验证 -----"
for program in autoconf autoheader autom4te autoreconf autoscan autoupdate ifnames; do
    test -x "/usr/bin/$program"
    echo "OK   /usr/bin/$program"
done
test -d /usr/share/autoconf
/usr/bin/autoconf --version
test "$(/usr/bin/autoconf --version | sed -n '1s/.* //p')" = 2.72
ls -ld /usr/share/autoconf
echo "OK   七个手册列出的程序及 /usr/share/autoconf 均已安装，版本为 2.72。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/autoconf-2.72
test ! -e /sources/autoconf-2.72
test -f /sources/autoconf-2.72.tar.xz
echo "OK   已删除 /sources/autoconf-2.72；tarball 保留。"
echo
echo "===== §8.47 Autoconf-2.72 完成：$(date -Is) ====="
