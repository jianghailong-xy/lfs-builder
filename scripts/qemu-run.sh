#!/bin/bash
set -euo pipefail

ROOT=/root/lfs
IMAGE=${IMAGE:-$ROOT/images/lfs.img}
LOG=${QEMU_LOG:-$ROOT/logs/host/qemu-serial.log}
MEMORY=${QEMU_MEMORY:-2048}
CPUS=${QEMU_CPUS:-2}
SNAPSHOT=${QEMU_SNAPSHOT:-0}

[[ -f "$IMAGE" ]] || { echo "错误：镜像不存在：$IMAGE" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "错误：未安装 qemu-system-x86_64" >&2; exit 1; }
if losetup -j "$IMAGE" | grep -q .; then
    echo "错误：镜像仍关联到 loop 设备；请先执行 make umount" >&2
    exit 1
fi
if command -v fuser >/dev/null 2>&1; then
    holders=$(fuser "$IMAGE" 2>/dev/null || true)
    if [[ -n "$holders" ]]; then
        echo "错误：镜像正被其他进程占用，无法取得 QEMU 写锁：$IMAGE" >&2
        for pid in $holders; do
            ps -p "$pid" -o pid=,etime=,cmd= >&2 || true
        done
        echo "请先在已有虚拟机中执行 poweroff，或等待其退出后重试。" >&2
        exit 1
    fi
fi

mkdir -p "$(dirname "$LOG")"
accel=tcg
cpu=max
if [[ -r /dev/kvm && -w /dev/kvm ]] && qemu-system-x86_64 -accel help 2>/dev/null | grep -qx kvm; then
    accel=kvm
    cpu=host
fi

drive="file=$IMAGE,format=raw,if=none,id=lfsdisk"
[[ "$SNAPSHOT" == 1 ]] && drive+=",snapshot=on"

echo "QEMU: accel=$accel, disk=virtio-blk-pci, console=ttyS0, log=$LOG"
echo "退出 QEMU：按 Ctrl-a 后按 x"
exec qemu-system-x86_64 \
    -name lfs \
    -machine "pc,accel=$accel" -cpu "$cpu" -m "$MEMORY" -smp "$CPUS" \
    -drive "$drive" -device virtio-blk-pci,drive=lfsdisk \
    -display none \
    -chardev "stdio,mux=on,id=console,signal=off,logfile=$LOG" \
    -serial chardev:console -mon chardev=console,mode=readline \
    -no-reboot
