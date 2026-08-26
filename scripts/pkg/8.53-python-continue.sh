#!/usr/bin/env bash
set -euo pipefail

cd /sources/Python-3.14.3

echo
echo "===== §8.53 安装续行：$(date -Is) ====="
echo "原因：完整测试仅有手册允许的 test_urllib2/test_urllibnet DNS 失败；make test 返回 2 后严格停止，现经日志核验继续。"
echo "测试结论：461 tests OK；26 tests skipped；3 resource denied；仅 2 tests failed: test_urllib2 test_urllibnet。"
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
for program in idle3 pip3 pydoc3 python3 python3-config; do command -v "$program"; done
test -e /usr/lib/libpython3.14.so
test -e /usr/lib/libpython3.so
test -d /usr/include/python3.14
test -d /usr/lib/python3.14
test -d /usr/share/doc/python-3.14.3/html
python3 --version
pip3 --version
python3 - <<'PY'
import ctypes, sqlite3, sys
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
