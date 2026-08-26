#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.58 Ninja-1.13.2 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.57 Setuptools-82.0.0 产物 -----"
test -d /usr/lib/python3.14/site-packages/setuptools
test -d /usr/lib/python3.14/site-packages/setuptools-82.0.0.dist-info
test ! -e /sources/setuptools-82.0.0
(cd /tmp && python3 - <<'PY')
import importlib.metadata
import setuptools
assert setuptools.__version__ == "82.0.0", setuptools.__version__
assert importlib.metadata.version("setuptools") == "82.0.0"
assert setuptools.__file__.startswith("/usr/lib/python3.14/site-packages/"), setuptools.__file__
print("Setuptools 前置验证：", setuptools.__version__, setuptools.__file__)
PY
echo "OK   Setuptools 82.0.0 产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum ninja-1.13.2.tar.gz
echo '76c00637fde44909cd7d56f8d73f2042  ninja-1.13.2.tar.gz' | md5sum -c -
test ! -e /sources/ninja-1.13.2
tar -xvf ninja-1.13.2.tar.gz
cd ninja-1.13.2
echo "源码目录：$PWD"
echo

echo "----- 可选并行度补丁（手册 sed） -----"
sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
grep -A5 'int Guess' src/ninja.cc
echo "OK   Ninja 将识别 NINJAJOBS 环境变量。"
echo

echo "----- 配置与编译（手册命令） -----"
python3 configure.py --bootstrap --verbose
echo

echo "----- 测试 -----"
echo "手册说明：测试套件依赖 CMake，不能在当前 chroot 中运行；--bootstrap 自举重建已测试基本功能。"
test -x ./ninja
./ninja --version
test "$(./ninja --version)" = "1.13.2"
echo "OK   自举构建成功，生成的 Ninja 版本为 1.13.2。"
echo

echo "----- 安装（手册命令） -----"
install -vm755 ninja /usr/bin/
install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/ninja
test "$(/usr/bin/ninja --version)" = "1.13.2"
test -f /usr/share/bash-completion/completions/ninja
test -f /usr/share/zsh/site-functions/_ninja
ls -l /usr/bin/ninja /usr/share/bash-completion/completions/ninja /usr/share/zsh/site-functions/_ninja
echo "安装版本：$(/usr/bin/ninja --version)"
echo "OK   Ninja 1.13.2 及 Bash/Zsh 补全文件已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/ninja-1.13.2
test ! -e /sources/ninja-1.13.2
test -f /sources/ninja-1.13.2.tar.gz
echo "OK   已删除 /sources/ninja-1.13.2；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
test "$(ninja --version)" = "1.13.2"
echo "installed program: $(command -v ninja)"
echo "installed version: $(ninja --version)"
echo "OK   清理后 /usr/bin/ninja 可用。"
echo "===== §8.58 Ninja-1.13.2 完成：$(date -Is) ====="
