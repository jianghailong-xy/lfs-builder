#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.42 Inetutils-2.7 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.41 Expat-2.7.4 产物 -----"
test -x /usr/bin/xmlwf
test -e /usr/lib/libexpat.so
test -f /usr/include/expat.h
test -d /usr/share/doc/expat-2.7.4
test ! -e /sources/expat-2.7.4
/usr/bin/xmlwf -h 2>&1 | head -n3 || true
echo "OK   Expat-2.7.4 程序、共享库、头文件与文档可用，上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum inetutils-2.7.tar.gz
echo 'eed294e7b170cbbb0ff86493ef4c1273  inetutils-2.7.tar.gz' | md5sum -c -
test ! -e /sources/inetutils-2.7
tar -xvf inetutils-2.7.tar.gz
cd inetutils-2.7
echo "源码目录：$PWD"
echo

echo "----- GCC 14.1+ 兼容性修改（手册命令） -----"
sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
test "$(grep -c 'def HAVE_TERMCAP_TGETENT' telnet/telnet.c)" -eq 0
echo "OK   HAVE_TERMCAP_TGETENT 条件宏已按手册替换。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr        \
            --bindir=/usr/bin    \
            --localstatedir=/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers
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

echo "----- 移动 ifconfig 到正确位置（手册命令） -----"
mv -v /usr/{,s}bin/ifconfig
echo

echo "----- 安装结果验证 -----"
for p in dnsdomainname ftp hostname ping ping6 talk telnet tftp traceroute; do
  test -x "/usr/bin/$p"
done
test -x /usr/sbin/ifconfig
test ! -e /usr/bin/ifconfig
ls -l /usr/bin/{dnsdomainname,ftp,hostname,ping,ping6,talk,telnet,tftp,traceroute} /usr/sbin/ifconfig
/usr/bin/hostname --version 2>&1 | head -n2 || true
/usr/sbin/ifconfig --version 2>&1 | head -n2 || true
echo "OK   手册列出的 10 个程序均已安装，ifconfig 位于 /usr/sbin。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/inetutils-2.7
test ! -e /sources/inetutils-2.7
test -f /sources/inetutils-2.7.tar.gz
echo "OK   已删除 /sources/inetutils-2.7；tarball 保留。"
echo
echo "===== §8.42 Inetutils-2.7 完成：$(date -Is) ====="
