#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

cd /sources

echo "===== LFS 13.0-systemd §8.79 D-Bus-1.16.2 ====="
echo "start: $(date -Iseconds)"

echo "===== 上一任务产物与源码校验 ====="
test -x /usr/bin/systemctl
test -e /usr/lib/libsystemd.so
test -s /etc/machine-id
systemctl --version | head -1
echo '97832e6f0a260936d28536e5349c22e5  dbus-1.16.2.tar.xz' | md5sum -c -
test ! -e dbus-1.16.2 || {
  echo "错误：/sources/dbus-1.16.2 已存在；保留现场并停止。" >&2
  exit 1
}
echo "OK: §8.78 Systemd 关键产物和 D-Bus 源码包可用。"

echo "===== 解包 ====="
tar -xf dbus-1.16.2.tar.xz
cd dbus-1.16.2

echo "===== 补丁 ====="
echo "INFO: LFS 13.0-systemd §8.79 未规定补丁。"

echo "===== 配置 ====="
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..

echo "===== 编译 ====="
ninja

echo "===== 测试 ====="
ninja test
echo "TEST_RESULT: PASS"

echo "===== 安装 ====="
ninja install

echo "===== 创建 machine-id 符号链接 ====="
ln -sfv /etc/machine-id /var/lib/dbus

echo "===== 安装结果验证 ====="
test -x /usr/bin/dbus-daemon
test -x /usr/bin/dbus-send
test -x /usr/bin/dbus-run-session
test -e /usr/lib/libdbus-1.so
test -L /var/lib/dbus/machine-id
test "$(readlink /var/lib/dbus/machine-id)" = /etc/machine-id
/usr/bin/dbus-daemon --version
echo "machine-id link: $(readlink /var/lib/dbus/machine-id)"
echo "OK: D-Bus-1.16.2 关键程序、库和 machine-id 链接均已验证。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf -- dbus-1.16.2
test ! -e dbus-1.16.2
echo "OK: /sources/dbus-1.16.2 已删除，源码包保留。"
echo "finish: $(date -Iseconds)"
echo "FINAL_RESULT: SUCCESS"
