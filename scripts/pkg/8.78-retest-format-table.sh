#!/usr/bin/env bash
set -euo pipefail
cd /sources/systemd-259.1/build
echo "===== 针对 test-format-table 的 locale 诊断复测 ====="
echo "INFO: 全套测试继承 LC_ALL=POSIX，使期望的 Unicode 省略号降级为 ASCII 三点。"
echo "INFO: 按测试自身要求改用 C.UTF-8，单独复测该用例。"
LC_ALL=C.UTF-8 meson test test-format-table --print-errorlogs
echo "RETEST_RESULT: PASS (test-format-table under LC_ALL=C.UTF-8)"
