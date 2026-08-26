#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.65 Groff-1.23.0 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.64 Findutils-4.10.0 产物 -----"
for program in find locate updatedb xargs; do
  test -x "/usr/bin/$program"
done
test -d /var/lib/locate
test ! -e /sources/findutils-4.10.0
find --version | head -n 1
locate --version | head -n 1
echo "OK   Findutils 4.10.0 关键产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包（本节无补丁） -----"
echo '5e4f40315a22bb8a158748e7d5094c7d  groff-1.23.0.tar.gz' | md5sum -c -
if [ -e /sources/groff-1.23.0 ]; then
  echo "发现上次失败保留的源码目录；重试前清理该目录。"
  rm -rf /sources/groff-1.23.0
fi
tar -xvf groff-1.23.0.tar.gz
cd groff-1.23.0
echo "源码目录：$PWD"
echo

echo "----- 配置（手册命令；本地区使用 A4） -----"
PAGE=A4 ./configure --prefix=/usr
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试（手册命令） -----"
set +e
make check
test_rc=$?
set -e
echo "Groff 测试套件退出码：$test_rc"
if [ "$test_rc" -ne 0 ]; then
  echo "错误：Groff 测试套件存在失败；停止于安装前并保留源码目录与完整日志。" >&2
  exit "$test_rc"
fi
echo "OK   Groff 测试套件全部通过。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 安装结果验证 -----"
for program in groff troff nroff eqn pic tbl soelim refer; do
  test -x "/usr/bin/$program"
done
test -d /usr/lib/groff
test -d /usr/share/groff
test -d /usr/share/doc/groff-1.23.0
groff --version | head -n 1
printf '.TH GROFFCHECK 1\n.SH NAME\ngroffcheck \\- smoke test\n' | groff -Tascii -man | grep -q 'smoke test'
ls -ld /usr/lib/groff /usr/share/groff /usr/share/doc/groff-1.23.0
echo "OK   Groff 1.23.0 关键程序、目录及基本格式化功能均可用。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/groff-1.23.0
test ! -e /sources/groff-1.23.0
test -f /sources/groff-1.23.0.tar.gz
echo "OK   已删除 /sources/groff-1.23.0；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
groff --version | head -n 1
test -x /usr/bin/groff
test -d /usr/share/groff
echo "OK   清理后 Groff 1.23.0 关键产物仍可用。"
echo "===== §8.65 Groff-1.23.0 完成：$(date -Is) ====="
