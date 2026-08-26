#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C

echo "===== 核验修正与继续（$(date -Is)） ====="
echo "说明：首次安装后核验误假定 Documentation 顶层含 README；Linux 6.18.10"
echo "实际顶层索引为 index.rst。编译及手册安装命令此前均已成功，现按实际文档树复核。"
test -s /boot/vmlinuz-6.18.10-lfs-13.0-systemd
test -s /boot/System.map-6.18.10
test -s /boot/config-6.18.10
test -d /lib/modules/6.18.10
test -f /usr/share/doc/linux-6.18.10/index.rst
test -f /etc/modprobe.d/usb.conf
file /boot/vmlinuz-6.18.10-lfs-13.0-systemd
du -h /boot/vmlinuz-6.18.10-lfs-13.0-systemd /boot/System.map-6.18.10 /boot/config-6.18.10
grep -E '^CONFIG_(EXT4_FS|VIRTIO_BLK|VIRTIO_PCI|DEVTMPFS|DEVTMPFS_MOUNT|SERIAL_8250|SERIAL_8250_CONSOLE)=y$' /boot/config-6.18.10
echo "OK: 内核、映射、配置、模块、文档和 usb.conf 均已安装并核验。"

echo "===== 清理源码构建目录 ====="
rm -rf /sources/linux-6.18.10
test ! -e /sources/linux-6.18.10
test -f /sources/linux-6.18.10.tar.xz
echo "OK: /sources/linux-6.18.10 已删除，源码包保留。"
echo "finish: $(date -Is)"
echo "FINAL_RESULT: SUCCESS"
