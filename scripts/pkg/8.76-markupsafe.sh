#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

echo "===== LFS 13.0-systemd §8.76 MarkupSafe-3.0.3 ====="
echo "start: $(date -Iseconds)"
cd /sources

echo "===== 前置产物与源码校验 ====="
vim --version | head -n3
test "$(vim --version | head -n1)" = "VIM - Vi IMproved 9.2 (2026 Feb 14, compiled Aug 25 2026 18:21:28)"
test -x /usr/bin/vim
test -L /usr/bin/vi
test -s /etc/vimrc
test "$(md5sum markupsafe-3.0.3.tar.gz | awk '{print $1}')" = "13a73126d25afa72a1ff0daed072f5fe"
test ! -e markupsafe-3.0.3
echo "OK: 上一节 Vim-9.2.0078 产物可用，MarkupSafe 源码校验通过。"

echo "===== 解包 ====="
tar -xf markupsafe-3.0.3.tar.gz
cd markupsafe-3.0.3

echo "===== 补丁与配置 ====="
echo "INFO: §8.76 未规定补丁或独立配置命令。"

echo "===== 编译 ====="
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"

echo "===== 测试 ====="
echo "TEST_RESULT: NOT_APPLICABLE (§8.76: This package does not come with a test suite.)"

echo "===== 安装 ====="
pip3 install --no-index --find-links dist Markupsafe

echo "===== 安装结果验证 ====="
python3 - <<'PY'
import importlib.metadata
import markupsafe

version = importlib.metadata.version("MarkupSafe")
print(f"MarkupSafe metadata version: {version}")
print(f"MarkupSafe module: {markupsafe.__file__}")
assert version == "3.0.3"
assert markupsafe.escape("<tag>") == "&lt;tag&gt;"
PY
test -d /usr/lib/python3.14/site-packages/markupsafe
test -d /usr/lib/python3.14/site-packages/markupsafe-3.0.3.dist-info
test -s /usr/lib/python3.14/site-packages/markupsafe/_speedups.cpython-314-x86_64-linux-gnu.so
echo "OK: MarkupSafe-3.0.3 元数据、模块、C 扩展及基本转义行为验证通过。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf -- markupsafe-3.0.3
test ! -e markupsafe-3.0.3
echo "OK: /sources/markupsafe-3.0.3 已删除，源码包保留。"
echo "finish: $(date -Iseconds)"
echo "FINAL_RESULT: SUCCESS"
