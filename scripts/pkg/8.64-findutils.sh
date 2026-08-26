#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.64 Findutils-4.10.0 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.63 Gawk-5.3.2 产物 -----"
test -x /usr/bin/gawk
test -L /usr/bin/awk
test "$(readlink /usr/bin/awk)" = "gawk"
test -f /usr/bin/gawk-5.3.2
test -f /usr/lib/gawk/filefuncs.so
test ! -e /sources/gawk-5.3.2
gawk --version | head -n 1
echo "OK   Gawk 5.3.2 关键产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包（本节无补丁） -----"
echo '870cfd71c07d37ebe56f9f4aaf4ad872  findutils-4.10.0.tar.xz' | md5sum -c -
if [ -e /sources/findutils-4.10.0 ]; then
  echo "发现上次失败保留的源码目录；重试前清理该目录。"
  rm -rf /sources/findutils-4.10.0
fi
tar -xvf findutils-4.10.0.tar.xz
cd findutils-4.10.0
echo "源码目录：$PWD"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr --localstatedir=/var/lib/locate
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试（手册命令） -----"
chown -R tester .
set +e
su tester -c "PATH=$PATH make check" < /dev/null
test_rc=$?
set -e
echo "Findutils 测试套件退出码：$test_rc"
if [ "$test_rc" -ne 0 ]; then
  echo "错误：Findutils 测试套件存在失败；停止于安装前并保留源码目录与完整日志。" >&2
  exit "$test_rc"
fi
echo "OK   Findutils 测试套件全部通过。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 安装结果验证 -----"
for program in find locate updatedb xargs; do
  test -x "/usr/bin/$program"
done
test -d /var/lib/locate
find --version | head -n 1
locate --version | head -n 1
xargs --version | head -n 1
ls -ld /var/lib/locate
ls -l /usr/bin/{find,locate,updatedb,xargs}
echo "OK   Findutils 4.10.0 程序及 /var/lib/locate 均已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/findutils-4.10.0
test ! -e /sources/findutils-4.10.0
test -f /sources/findutils-4.10.0.tar.xz
echo "OK   已删除 /sources/findutils-4.10.0；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
find --version | head -n 1
for program in find locate updatedb xargs; do
  test -x "/usr/bin/$program"
done
test -d /var/lib/locate
echo "OK   清理后 Findutils 4.10.0 关键产物仍可用。"
echo "===== §8.64 Findutils-4.10.0 完成：$(date -Is) ====="
