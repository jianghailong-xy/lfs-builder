#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.63 Gawk-5.3.2 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.62 Diffutils-3.12 产物 -----"
for program in cmp diff diff3 sdiff; do
  test -x "/usr/bin/$program"
done
test "$(diff --version | sed -n '1s/.* //p')" = "3.12"
test ! -e /sources/diffutils-3.12
diff --version | head -n 1
echo "OK   Diffutils 3.12 关键程序可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包（本节无补丁） -----"
echo 'b7014650c5f45e5d4837c31209dc0037  gawk-5.3.2.tar.xz' | md5sum -c -
if [ -e /sources/gawk-5.3.2 ]; then
  echo "发现上次失败保留的源码目录；重试前清理该目录。"
  rm -rf /sources/gawk-5.3.2
fi
tar -xvf gawk-5.3.2.tar.xz
cd gawk-5.3.2
echo "源码目录：$PWD"
echo

echo "----- 避免安装不需要的文件（手册命令） -----"
sed -i 's/extras//' Makefile.in
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr
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
echo "Gawk 测试套件退出码：$test_rc"
if [ "$test_rc" -ne 0 ]; then
  echo "错误：Gawk 测试套件存在失败；停止于安装前并保留源码目录与完整日志。" >&2
  exit "$test_rc"
fi
echo "OK   Gawk 测试套件全部通过。"
echo

echo "----- 安装（手册命令） -----"
rm -f /usr/bin/gawk-5.3.2
make install
echo

echo "----- 创建 awk 手册页链接（手册命令） -----"
ln -sv gawk.1 /usr/share/man/man1/awk.1
echo

echo "----- 安装可选文档（手册命令） -----"
install -vDm644 doc/{awkforai.txt,*.{eps,pdf,jpg}} -t /usr/share/doc/gawk-5.3.2
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/gawk
test -L /usr/bin/awk
test "$(readlink /usr/bin/awk)" = "gawk"
test -f /usr/bin/gawk-5.3.2
test "$(stat -c %i /usr/bin/gawk)" = "$(stat -c %i /usr/bin/gawk-5.3.2)"
test -L /usr/share/man/man1/awk.1
test "$(readlink /usr/share/man/man1/awk.1)" = "gawk.1"
for library in filefuncs fnmatch fork inplace intdiv ordchr readdir readfile revoutput revtwoway rwarray time; do
  test -f "/usr/lib/gawk/$library.so"
done
test -d /usr/libexec/awk
test -d /usr/share/awk
test -f /usr/share/doc/gawk-5.3.2/awkforai.txt
/usr/bin/gawk --version | head -n 1
ls -li /usr/bin/awk /usr/bin/gawk /usr/bin/gawk-5.3.2
ls -l /usr/share/man/man1/awk.1
ls -l /usr/lib/gawk/*.so
echo "OK   Gawk 5.3.2 程序、链接、扩展库、数据目录、手册页及文档均已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/gawk-5.3.2
test ! -e /sources/gawk-5.3.2
test -f /sources/gawk-5.3.2.tar.xz
echo "OK   已删除 /sources/gawk-5.3.2；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
/usr/bin/gawk --version | head -n 1
test -x /usr/bin/gawk
test -L /usr/bin/awk
test -f /usr/lib/gawk/filefuncs.so
echo "OK   清理后 Gawk 5.3.2 关键产物仍可用。"
echo "===== §8.63 Gawk-5.3.2 完成：$(date -Is) ====="
