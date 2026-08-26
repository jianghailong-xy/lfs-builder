#!/usr/bin/env bash
# 仅在 LFS chroot 内执行。
set -euo pipefail
part="$(findmnt -n -o SOURCE /)"
case "$part" in /dev/loop[0-9]*p1) ;; *) echo "根文件系统不在 loop 第 1 分区上：$part" >&2; exit 1 ;; esac
loop="${part%p1}"
case "$loop" in /dev/loop[0-9]*) ;; *) echo "根文件系统不在 loop 设备上：$loop" >&2; exit 1 ;; esac
partuuid="$(blkid -s PARTUUID -o value "$part")"
[ -n "$partuuid" ] || { echo "无法读取 $part 的 PARTUUID" >&2; exit 1; }
grep -q "^PARTUUID=$partuuid[[:space:]]\+/[[:space:]]" /etc/fstab \
  || { echo "/etc/fstab 与实际 PARTUUID 不一致" >&2; exit 1; }
grub-install --target=i386-pc "$loop"
kernel="$(basename "$(find /boot -maxdepth 1 -name 'vmlinuz-*-lfs-13.0-systemd' -type f | sort -V | tail -1)")"
[ -n "$kernel" ] || { echo '找不到 LFS 内核' >&2; exit 1; }

install -d -m 0755 /boot/grub
printf '%s\n' \
  'set default=0' \
  'set timeout=5' \
  '' \
  'serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1' \
  'terminal_input serial' \
  'terminal_output serial' \
  '' \
  "menuentry \"GNU/Linux, Linux ${kernel#vmlinuz-}\" {" \
  '    insmod part_msdos' \
  '    insmod ext2' \
  "    linux /boot/$kernel root=PARTUUID=$partuuid ro console=ttyS0,115200n8" \
  '}' > /boot/grub/grub.cfg
grub-script-check /boot/grub/grub.cfg
