#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.56 Wheel-0.46.3 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.55 Packaging-26.0 产物 -----"
test -d /usr/lib/python3.14/site-packages/packaging
test -d /usr/lib/python3.14/site-packages/packaging-26.0.dist-info
test ! -e /sources/packaging-26.0
(cd /tmp && python3 - <<'PY')
import packaging
assert packaging.__version__ == "26.0", packaging.__version__
assert packaging.__file__.startswith("/usr/lib/python3.14/site-packages/"), packaging.__file__
print("Packaging 前置验证：", packaging.__version__, packaging.__file__)
PY
echo "OK   Packaging 26.0 产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum wheel-0.46.3.tar.gz
echo '61fb0c9633fe7492933a8f338db23508  wheel-0.46.3.tar.gz' | md5sum -c -
test ! -e /sources/wheel-0.46.3
tar -xvf wheel-0.46.3.tar.gz
cd wheel-0.46.3
echo "源码目录：$PWD"
echo "补丁：LFS 13.0-systemd 正式版 §8.56 无补丁。"
echo "配置：本节使用 PEP 517 wheel 构建，无单独 configure 步骤。"
echo

echo "----- 编译（手册命令） -----"
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
echo

echo "----- 测试 -----"
echo "本节手册未规定测试套件。"
echo

echo "----- 安装（手册命令） -----"
pip3 install --no-index --find-links dist wheel
echo

echo "----- 安装结果验证 -----"
(cd /tmp && python3 - <<'PY')
import importlib.metadata
import wheel
assert wheel.__version__ == "0.46.3", wheel.__version__
assert importlib.metadata.version("wheel") == "0.46.3"
assert wheel.__file__.startswith("/usr/lib/python3.14/site-packages/"), wheel.__file__
print("Wheel 模块：", wheel.__file__)
print("Wheel 版本：", wheel.__version__)
PY
test -x /usr/bin/wheel
test -d /usr/lib/python3.14/site-packages/wheel
test -d /usr/lib/python3.14/site-packages/wheel-0.46.3.dist-info
/usr/bin/wheel version
ls -ld /usr/bin/wheel /usr/lib/python3.14/site-packages/wheel \
       /usr/lib/python3.14/site-packages/wheel-0.46.3.dist-info
echo "OK   Wheel 0.46.3 及 wheel 程序已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/wheel-0.46.3
test ! -e /sources/wheel-0.46.3
test -f /sources/wheel-0.46.3.tar.gz
echo "OK   已删除 /sources/wheel-0.46.3；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
(cd /tmp && python3 - <<'PY')
import wheel
assert wheel.__version__ == "0.46.3", wheel.__version__
assert wheel.__file__.startswith("/usr/lib/python3.14/site-packages/"), wheel.__file__
print("installed module:", wheel.__file__)
print("installed version:", wheel.__version__)
PY
echo "OK   清理后从 /tmp 导入的是 /usr 下已安装的 Wheel-0.46.3。"
echo "===== §8.56 Wheel-0.46.3 完成：$(date -Is) ====="
