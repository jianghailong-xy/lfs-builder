#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.53 Python-3.14.3 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.52 Sqlite-3510200 产物 -----"
test -x /usr/bin/sqlite3
test -e /usr/lib/libsqlite3.so
test -f /usr/include/sqlite3.h
test -f /usr/lib/pkgconfig/sqlite3.pc
test ! -e /usr/lib/libsqlite3.a
test ! -e /sources/sqlite-autoconf-3510200
test "$(pkg-config --modversion sqlite3)" = 3.51.2
echo "OK   Sqlite 3.51.2 产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum Python-3.14.3.tar.xz python-3.14.3-docs-html.tar.bz2
echo 'ef513dcb836d219ae0e2b16ac9c87d0f  Python-3.14.3.tar.xz' | md5sum -c -
echo '005159be74cf46222d6399fbc0fb0ada  python-3.14.3-docs-html.tar.bz2' | md5sum -c -
test ! -e /sources/Python-3.14.3
tar -xvf Python-3.14.3.tar.xz
cd Python-3.14.3
echo "源码目录：$PWD"
echo "补丁：LFS 13.0-systemd 正式版 §8.53 无补丁。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr          \
            --enable-shared        \
            --with-system-expat    \
            --enable-optimizations \
            --without-static-libpython
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试（手册命令） -----"
set +e
make test TESTOPTS="--timeout 120"
test_rc=$?
set -e
if [ "$test_rc" -ne 0 ]; then
  echo "INFO make test 退出码：$test_rc；核对是否仅为手册允许的 DNS 失败。"
  test "$test_rc" -eq 2
  test "$(grep -Ec '^    test_urllib2 test_urllibnet$' /workspace/logs/packages/8.53-python-3.14.3.log 2>/dev/null || true)" -ge 1
fi
echo "OK   Python 测试达到手册允许结果。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 安装预格式化文档（手册可选命令；本次执行） -----"
install -v -dm755 /usr/share/doc/python-3.14.3/html
tar --strip-components=1  \
    --no-same-owner       \
    --no-same-permissions \
    -C /usr/share/doc/python-3.14.3/html \
    -xvf ../python-3.14.3-docs-html.tar.bz2
echo

echo "----- 安装结果验证 -----"
for program in idle3 pip3 pydoc3 python3 python3-config; do
  command -v "$program"
done
test -e /usr/lib/libpython3.14.so
test -e /usr/lib/libpython3.so
test -d /usr/include/python3.14
test -d /usr/lib/python3.14
test -d /usr/share/doc/python-3.14.3/html
python3 --version
pip3 --version
python3 - <<'PY'
import ctypes
import sqlite3
import sys
from xml.parsers import expat
assert sys.version_info[:3] == (3, 14, 3), sys.version
assert sqlite3.sqlite_version == "3.51.2", sqlite3.sqlite_version
ctypes.CDLL("libpython3.14.so")
print("Python 模块验证：sqlite=", sqlite3.sqlite_version, "expat=", expat.EXPAT_VERSION)
PY
ls -ld /usr/include/python3.14 /usr/lib/python3.14 /usr/share/doc/python-3.14.3/html
ls -l /usr/bin/idle3 /usr/bin/pip3 /usr/bin/pydoc3 /usr/bin/python3 /usr/bin/python3-config /usr/lib/libpython3.so /usr/lib/libpython3.14.so
echo "OK   Python 3.14.3 程序、共享库、头文件、标准库和 HTML 文档已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/Python-3.14.3
test ! -e /sources/Python-3.14.3
test -f /sources/Python-3.14.3.tar.xz
test -f /sources/python-3.14.3-docs-html.tar.bz2
echo "OK   已删除 /sources/Python-3.14.3；源码包和文档包保留。"
echo
echo "===== §8.53 Python-3.14.3 完成：$(date -Is) ====="
