#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

echo "===== LFS 13.0-systemd §8.77 Jinja2-3.1.6 ====="
echo "start: $(date -Iseconds)"
cd /sources

echo "===== 前置产物与源码校验 ====="
python3 - <<'PY'
import importlib.metadata
import markupsafe

version = importlib.metadata.version("MarkupSafe")
print(f"MarkupSafe metadata version: {version}")
print(f"MarkupSafe module: {markupsafe.__file__}")
assert version == "3.0.3"
assert markupsafe.escape("<tag>") == "&lt;tag&gt;"
PY
test -s /usr/lib/python3.14/site-packages/markupsafe/_speedups.cpython-314-x86_64-linux-gnu.so
test "$(md5sum jinja2-3.1.6.tar.gz | awk '{print $1}')" = "66d4c25ff43d1deaf9637ccda523dec8"
test ! -e jinja2-3.1.6
echo "OK: 上一节 MarkupSafe-3.0.3 产物可用，Jinja2 源码校验通过。"

echo "===== 解包 ====="
tar -xf jinja2-3.1.6.tar.gz
cd jinja2-3.1.6

echo "===== 补丁与配置 ====="
echo "INFO: §8.77 未规定补丁或独立配置命令。"

echo "===== 编译 ====="
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"

echo "===== 测试 ====="
echo "TEST_RESULT: NOT_APPLICABLE (§8.77 未规定测试命令。)"

echo "===== 安装 ====="
pip3 install --no-index --find-links dist Jinja2

echo "===== 安装结果验证 ====="
python3 - <<'PY'
import importlib.metadata
import jinja2

version = importlib.metadata.version("Jinja2")
print(f"Jinja2 metadata version: {version}")
print(f"Jinja2 module: {jinja2.__file__}")
assert version == "3.1.6"
assert jinja2.Template("Hello {{ name }}!").render(name="LFS") == "Hello LFS!"
PY
test -d /usr/lib/python3.14/site-packages/jinja2
test -d /usr/lib/python3.14/site-packages/jinja2-3.1.6.dist-info
echo "OK: Jinja2-3.1.6 元数据、模块及基本模板渲染验证通过。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf -- jinja2-3.1.6
test ! -e jinja2-3.1.6
echo "OK: /sources/jinja2-3.1.6 已删除，源码包保留。"
echo "finish: $(date -Iseconds)"
echo "FINAL_RESULT: SUCCESS"
