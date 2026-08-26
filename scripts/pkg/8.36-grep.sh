#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.36 Grep-3.12 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.35 Bison-3.8.2 产物 -----"
test -x /usr/bin/bison
test -x /usr/bin/yacc
test -f /usr/lib/liby.a
bison --version | head -n1
test ! -e /sources/bison-3.8.2
echo "OK   Bison 3.8.2 关键产物可用，且上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum grep-3.12.tar.xz
echo '5d9301ed9d209c4a88c8d3a6fd08b9ac  grep-3.12.tar.xz' | md5sum -c -
test ! -e /sources/grep-3.12
tar -xvf grep-3.12.tar.xz
cd grep-3.12
echo "源码目录：$PWD"
echo

echo "----- 手册规定的源码修改 -----"
sed -i "s/echo/#echo/" src/egrep.sh
grep -n '#echo' src/egrep.sh
echo

echo "----- 配置 -----"
./configure --prefix=/usr
echo

echo "----- 编译 -----"
make
echo

echo "----- 测试（手册命令：make check） -----"
make check
echo "OK   make check 退出码为 0。"
echo

echo "----- 安装 -----"
make install
echo

echo "----- 安装结果验证 -----"
grep --version | head -n1
for program in grep egrep fgrep; do
  test -x "/usr/bin/$program"
  ls -l "/usr/bin/$program"
done
printf '%s\n' alpha beta gamma | grep -Fx beta
printf '%s\n' alpha beta gamma | egrep 'alpha|gamma'
printf '%s\n' alpha beta gamma | fgrep beta
echo "OK   grep、egrep、fgrep 及基本匹配功能均已验证。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/grep-3.12
test ! -e /sources/grep-3.12
test -f /sources/grep-3.12.tar.xz
echo "OK   已删除 /sources/grep-3.12；tarball 保留。"
echo
echo "===== §8.36 Grep-3.12 完成：$(date -Is) ====="
