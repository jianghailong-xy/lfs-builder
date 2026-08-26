#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.55 Packaging-26.0 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.54 Flit-Core-3.12.0 产物 -----"
test -d /usr/lib/python3.14/site-packages/flit_core
test -d /usr/lib/python3.14/site-packages/flit_core-3.12.0.dist-info
test ! -e /sources/flit_core-3.12.0
(cd /tmp && python3 - <<'PY')
import flit_core
assert flit_core.__version__ == "3.12.0", flit_core.__version__
assert flit_core.__file__.startswith("/usr/lib/python3.14/site-packages/"), flit_core.__file__
print("Flit-Core 前置验证：", flit_core.__version__, flit_core.__file__)
PY
echo "OK   Flit-Core 3.12.0 产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum packaging-26.0.tar.gz
echo '2cbdbb5754f038736c3c361826c6872a  packaging-26.0.tar.gz' | md5sum -c -
test ! -e /sources/packaging-26.0
tar -xvf packaging-26.0.tar.gz
cd packaging-26.0
echo "源码目录：$PWD"
echo "补丁：LFS 13.0-systemd 正式版 §8.55 无补丁。"
echo "配置：本节使用 PEP 517 wheel 构建，无单独 configure 步骤。"
echo

echo "----- 编译（手册命令） -----"
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
echo

echo "----- 测试 -----"
echo "本节手册未规定测试套件。"
echo

echo "----- 安装（手册命令） -----"
pip3 install --no-index --find-links dist packaging
echo

echo "----- 安装结果验证 -----"
(cd /tmp && python3 - <<'PY')
import importlib.metadata
import packaging
assert packaging.__version__ == "26.0", packaging.__version__
assert importlib.metadata.version("packaging") == "26.0"
assert packaging.__file__.startswith("/usr/lib/python3.14/site-packages/"), packaging.__file__
print("Packaging 模块：", packaging.__file__)
print("Packaging 版本：", packaging.__version__)
PY
test -d /usr/lib/python3.14/site-packages/packaging
test -d /usr/lib/python3.14/site-packages/packaging-26.0.dist-info
ls -ld /usr/lib/python3.14/site-packages/packaging \
       /usr/lib/python3.14/site-packages/packaging-26.0.dist-info
echo "OK   Packaging 26.0 已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/packaging-26.0
test ! -e /sources/packaging-26.0
test -f /sources/packaging-26.0.tar.gz
echo "OK   已删除 /sources/packaging-26.0；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
(cd /tmp && python3 - <<'PY')
import packaging
assert packaging.__version__ == "26.0", packaging.__version__
assert packaging.__file__.startswith("/usr/lib/python3.14/site-packages/"), packaging.__file__
print("installed module:", packaging.__file__)
print("installed version:", packaging.__version__)
PY
echo "OK   清理后从 /tmp 导入的是 /usr 下已安装的 Packaging-26.0。"
echo "===== §8.55 Packaging-26.0 完成：$(date -Is) ====="
