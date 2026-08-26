#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.57 Setuptools-82.0.0 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.56 Wheel-0.46.3 产物 -----"
test -x /usr/bin/wheel
test -d /usr/lib/python3.14/site-packages/wheel
test -d /usr/lib/python3.14/site-packages/wheel-0.46.3.dist-info
test ! -e /sources/wheel-0.46.3
(cd /tmp && python3 - <<'PY')
import importlib.metadata
import wheel
assert wheel.__version__ == "0.46.3", wheel.__version__
assert importlib.metadata.version("wheel") == "0.46.3"
assert wheel.__file__.startswith("/usr/lib/python3.14/site-packages/"), wheel.__file__
print("Wheel 前置验证：", wheel.__version__, wheel.__file__)
PY
echo "OK   Wheel 0.46.3 产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum setuptools-82.0.0.tar.gz
echo '6e65b88d2466b35e86e5187b99502b1c  setuptools-82.0.0.tar.gz' | md5sum -c -
test ! -e /sources/setuptools-82.0.0
tar -xvf setuptools-82.0.0.tar.gz
cd setuptools-82.0.0
echo "源码目录：$PWD"
echo "补丁：LFS 13.0-systemd 正式版 §8.57 无补丁。"
echo "配置：本节使用 PEP 517 wheel 构建，无单独 configure 步骤。"
echo

echo "----- 编译（手册命令） -----"
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
echo

echo "----- 测试 -----"
echo "本节手册未规定测试套件。"
echo

echo "----- 安装（手册命令） -----"
pip3 install --no-index --find-links dist setuptools
echo

echo "----- 安装结果验证 -----"
(cd /tmp && python3 - <<'PY')
import importlib.metadata
import setuptools
assert setuptools.__version__ == "82.0.0", setuptools.__version__
assert importlib.metadata.version("setuptools") == "82.0.0"
assert setuptools.__file__.startswith("/usr/lib/python3.14/site-packages/"), setuptools.__file__
print("Setuptools 模块：", setuptools.__file__)
print("Setuptools 版本：", setuptools.__version__)
PY
test -d /usr/lib/python3.14/site-packages/setuptools
test -d /usr/lib/python3.14/site-packages/setuptools-82.0.0.dist-info
ls -ld /usr/lib/python3.14/site-packages/setuptools \
       /usr/lib/python3.14/site-packages/setuptools-82.0.0.dist-info
echo "OK   Setuptools 82.0.0 已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/setuptools-82.0.0
test ! -e /sources/setuptools-82.0.0
test -f /sources/setuptools-82.0.0.tar.gz
echo "OK   已删除 /sources/setuptools-82.0.0；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
(cd /tmp && python3 - <<'PY')
import setuptools
assert setuptools.__version__ == "82.0.0", setuptools.__version__
assert setuptools.__file__.startswith("/usr/lib/python3.14/site-packages/"), setuptools.__file__
print("installed module:", setuptools.__file__)
print("installed version:", setuptools.__version__)
PY
echo "OK   清理后从 /tmp 导入的是 /usr 下已安装的 Setuptools-82.0.0。"
echo "===== §8.57 Setuptools-82.0.0 完成：$(date -Is) ====="
