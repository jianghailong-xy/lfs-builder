#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C

cd /sources

echo "start: $(date -Is)"
echo "===== 前置产物检查 ====="
test -f /var/lib/lfs/chapter-08-finalized
test -x /usr/bin/gcc
test -x /usr/bin/make
test -e /usr/lib/libext2fs.so
/usr/bin/gcc --version | head -n1
/usr/bin/make --version | head -n1
/usr/sbin/mke2fs -V 2>&1 | head -n2
echo "OK: 第 8 章检查点和上一包 E2fsprogs 产物可用。"

echo "===== 源码解包与补丁检查 ====="
test -f linux-6.18.10.tar.xz
rm -rf /sources/linux-6.18.10
tar -xf linux-6.18.10.tar.xz
cd linux-6.18.10
echo "本节手册未规定补丁；不应用补丁。"

echo "===== 清理并配置内核 ====="
make mrproper
make defconfig

# 非交互地落实 LFS 13.0-systemd §10.3 明列的配置项。其结果与在
# menuconfig 中选择相同，随后由 olddefconfig 解析依赖并补齐新选项。
scripts/config --disable WERROR
scripts/config --enable PSI
scripts/config --disable PSI_DEFAULT_DISABLED
scripts/config --disable IKHEADERS
scripts/config --enable CGROUPS
scripts/config --enable MEMCG
scripts/config --enable CGROUP_SCHED
scripts/config --disable RT_GROUP_SCHED
scripts/config --disable EXPERT
scripts/config --enable RELOCATABLE
scripts/config --enable RANDOMIZE_BASE
scripts/config --enable STACKPROTECTOR
scripts/config --enable STACKPROTECTOR_STRONG
scripts/config --enable NET
scripts/config --enable INET
scripts/config --enable IPV6
scripts/config --disable UEVENT_HELPER
scripts/config --enable DEVTMPFS
scripts/config --enable DEVTMPFS_MOUNT
scripts/config --enable FW_LOADER
scripts/config --disable FW_LOADER_USER_HELPER
scripts/config --enable DMIID
scripts/config --enable SYSFB_SIMPLEFB
scripts/config --enable DRM
scripts/config --enable DRM_PANIC
scripts/config --set-str DRM_PANIC_SCREEN kmsg
scripts/config --enable DRM_FBDEV_EMULATION
scripts/config --enable DRM_SIMPLEDRM
scripts/config --enable FRAMEBUFFER_CONSOLE
scripts/config --enable INOTIFY_USER
scripts/config --enable TMPFS
scripts/config --enable TMPFS_POSIX_ACL
scripts/config --enable PCI
scripts/config --enable PCI_MSI
scripts/config --enable IOMMU_SUPPORT
scripts/config --enable IRQ_REMAP
scripts/config --enable X86_X2APIC

# 本项目目标是 BIOS 启动的 x86_64 QEMU raw 镜像，根盘使用 VirtIO；无
# initramfs，因此根文件系统、VirtIO 块设备和控制台驱动必须内建。
scripts/config --enable EXT4_FS
scripts/config --enable VIRTIO
scripts/config --enable VIRTIO_PCI
scripts/config --enable VIRTIO_BLK
scripts/config --enable SERIAL_8250
scripts/config --enable SERIAL_8250_CONSOLE
scripts/config --enable TTY
scripts/config --enable VT
make olddefconfig

echo "===== 配置核验 ====="
required_y='PSI CGROUPS MEMCG CGROUP_SCHED RELOCATABLE RANDOMIZE_BASE STACKPROTECTOR STACKPROTECTOR_STRONG NET INET IPV6 DEVTMPFS DEVTMPFS_MOUNT FW_LOADER DMIID SYSFB_SIMPLEFB DRM DRM_PANIC DRM_FBDEV_EMULATION DRM_SIMPLEDRM FRAMEBUFFER_CONSOLE INOTIFY_USER TMPFS TMPFS_POSIX_ACL PCI PCI_MSI IOMMU_SUPPORT IRQ_REMAP X86_X2APIC EXT4_FS VIRTIO VIRTIO_PCI VIRTIO_BLK SERIAL_8250 SERIAL_8250_CONSOLE'
for opt in $required_y; do
  grep -q "^CONFIG_${opt}=y$" .config || { echo "FAIL: CONFIG_${opt} 不是 y"; exit 1; }
done
required_n='WERROR PSI_DEFAULT_DISABLED IKHEADERS RT_GROUP_SCHED EXPERT UEVENT_HELPER FW_LOADER_USER_HELPER'
for opt in $required_n; do
  grep -q "^# CONFIG_${opt} is not set$" .config || { echo "FAIL: CONFIG_${opt} 未禁用"; exit 1; }
done
grep -q '^CONFIG_DRM_PANIC_SCREEN="kmsg"$' .config
echo "OK: 手册必需项及目标镜像启动所需内建项均已落实。"

echo "===== 编译 ====="
make

echo "===== 手册规定测试 ====="
echo "本节没有规定测试套件；已完成 make 编译并将在安装后核验产物。"

echo "===== 安装模块和内核文件 ====="
make modules_install
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-6.18.10-lfs-13.0-systemd
cp -iv System.map /boot/System.map-6.18.10
cp -iv .config /boot/config-6.18.10
rm -rf /usr/share/doc/linux-6.18.10
cp -r Documentation -T /usr/share/doc/linux-6.18.10

echo "===== 配置 Linux 模块加载顺序 ====="
install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << "EOF"
# Begin /etc/modprobe.d/usb.conf

install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true

# End /etc/modprobe.d/usb.conf
EOF

echo "===== 安装结果验证 ====="
test -s /boot/vmlinuz-6.18.10-lfs-13.0-systemd
test -s /boot/System.map-6.18.10
test -s /boot/config-6.18.10
test -d /lib/modules/6.18.10
test -f /usr/share/doc/linux-6.18.10/index.rst
test -f /etc/modprobe.d/usb.conf
file /boot/vmlinuz-6.18.10-lfs-13.0-systemd
du -h /boot/vmlinuz-6.18.10-lfs-13.0-systemd /boot/System.map-6.18.10 /boot/config-6.18.10
grep -E '^CONFIG_(EXT4_FS|VIRTIO_BLK|VIRTIO_PCI|DEVTMPFS|DEVTMPFS_MOUNT)=y$' /boot/config-6.18.10
echo "OK: 内核、映射、配置、模块、文档和 usb.conf 均已安装并核验。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf /sources/linux-6.18.10
test ! -e /sources/linux-6.18.10
echo "OK: /sources/linux-6.18.10 已删除，源码包保留。"
echo "finish: $(date -Is)"
echo "FINAL_RESULT: SUCCESS"
