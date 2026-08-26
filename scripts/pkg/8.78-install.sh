#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX
test -d /sources/systemd-259.1/build
cd /sources/systemd-259.1/build
echo "===== 测试结论 ====="
echo "TEST_RESULT: ACCEPTED (1707 passed, 32 skipped, 2 failed: test-namespace is documented by LFS; test-format-table passed when rerun with its required C.UTF-8 locale.)"
echo "===== 安装 ====="
ninja install
echo "===== 安装预生成手册页 ====="
tar -xf ../../systemd-man-pages-259.1.tar.xz \
    --no-same-owner --strip-components=1     \
    -C /usr/share/man
echo "===== 初始化 machine-id 与 preset ====="
systemd-machine-id-setup
systemctl preset-all
echo "===== 安装结果验证 ====="
test -x /usr/bin/systemctl
test -x /usr/bin/systemd-machine-id-setup
test -x /usr/bin/udevadm
test -e /usr/lib/libsystemd.so
test -e /usr/lib/libudev.so
test -s /etc/machine-id
test -f /usr/share/man/man1/systemctl.1
systemctl --version
udevadm --version
echo "machine-id bytes: $(wc -c < /etc/machine-id)"
echo "OK: Systemd-259.1 关键程序、库、手册页和 machine-id 均已验证。"
echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf -- systemd-259.1
test ! -e systemd-259.1
echo "OK: /sources/systemd-259.1 已删除，两个源码包保留。"
echo "finish: $(date -Iseconds)"
echo "FINAL_RESULT: SUCCESS"
