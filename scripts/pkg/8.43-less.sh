#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.43 Less-692 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.42 Inetutils-2.7 产物 -----"
test -x /usr/bin/hostname
test -x /usr/bin/ping
test -x /usr/sbin/ifconfig
test ! -e /sources/inetutils-2.7
/usr/bin/hostname --version 2>&1 | head -n2
/usr/sbin/ifconfig --version 2>&1 | head -n2
echo "OK   Inetutils-2.7 的 hostname、ping、ifconfig 可用，上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum less-692.tar.gz
echo '4efd31e34ecf7682a6c62a3c53007600  less-692.tar.gz' | md5sum -c -
test ! -e /sources/less-692
tar -xvf less-692.tar.gz
cd less-692
echo "源码目录：$PWD"
echo "补丁：本节无补丁命令。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr --sysconfdir=/etc
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
for p in less lessecho lesskey; do
  test -x "/usr/bin/$p"
done
ls -l /usr/bin/{less,lessecho,lesskey}
/usr/bin/less --version | head -n2
/usr/bin/less --version | head -n1 | grep -Eq '^less 692 \(.+ regular expressions\)$'
echo "OK   手册列出的 less、lessecho、lesskey 均已安装，less 版本为 692。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/less-692
test ! -e /sources/less-692
test -f /sources/less-692.tar.gz
echo "OK   已删除 /sources/less-692；tarball 保留。"
echo
echo "===== §8.43 Less-692 完成：$(date -Is) ====="
