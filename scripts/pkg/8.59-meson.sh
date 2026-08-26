#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.59 Meson-1.10.1 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.58 Ninja-1.13.2 产物 -----"
test -x /usr/bin/ninja
test "$(ninja --version)" = "1.13.2"
test ! -e /sources/ninja-1.13.2
python3 - <<'PY'
import importlib.metadata
assert importlib.metadata.version("setuptools") == "82.0.0"
assert importlib.metadata.version("wheel") == "0.46.3"
print("Python 构建依赖：setuptools", importlib.metadata.version("setuptools"),
      "/ wheel", importlib.metadata.version("wheel"))
PY
echo "OK   Ninja 1.13.2 可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum meson-1.10.1.tar.gz
echo 'e1c12d275f8aae9fae71dff3d6891746  meson-1.10.1.tar.gz' | md5sum -c -
if [ -e /sources/meson-1.10.1 ]; then
  echo "发现上次失败保留的源码目录；重试前清理该目录。"
  rm -rf /sources/meson-1.10.1
fi
test ! -e /sources/meson-1.10.1
tar -xvf meson-1.10.1.tar.gz
cd meson-1.10.1
echo "源码目录：$PWD"
echo "本节无补丁。"
echo

echo "----- 编译（手册命令） -----"
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
ls -l dist/
echo

echo "----- 测试 -----"
echo "手册说明：测试套件需要 LFS 范围之外的软件包，因此本节不运行测试套件。"
echo

echo "----- 安装（手册命令） -----"
pip3 install --no-index --find-links dist meson
install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/meson
test "$(meson --version)" = "1.10.1"
test -d /usr/lib/python3.14/site-packages/mesonbuild
test -d /usr/lib/python3.14/site-packages/meson-1.10.1.dist-info
test -f /usr/share/bash-completion/completions/meson
test -f /usr/share/zsh/site-functions/_meson
(cd /tmp && python3 - <<'PY'
import importlib.metadata
import mesonbuild
assert importlib.metadata.version("meson") == "1.10.1"
assert mesonbuild.__file__.startswith("/usr/lib/python3.14/site-packages/"), mesonbuild.__file__
print("Meson Python 模块：", mesonbuild.__file__)
PY
)
ls -ld /usr/bin/meson /usr/lib/python3.14/site-packages/mesonbuild \
  /usr/lib/python3.14/site-packages/meson-1.10.1.dist-info \
  /usr/share/bash-completion/completions/meson /usr/share/zsh/site-functions/_meson
echo "OK   Meson 1.10.1、Python 模块及 Bash/Zsh 补全文件已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/meson-1.10.1
test ! -e /sources/meson-1.10.1
test -f /sources/meson-1.10.1.tar.gz
echo "OK   已删除 /sources/meson-1.10.1；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
test "$(meson --version)" = "1.10.1"
echo "installed program: $(command -v meson)"
echo "installed version: $(meson --version)"
echo "OK   清理后 /usr/bin/meson 可用。"
echo "===== §8.59 Meson-1.10.1 完成：$(date -Is) ====="
