#!/usr/bin/env bash
# 安装 BIOS GRUB 到 images/lfs.img 对应的 loop 设备，并使用实际 PARTUUID。
set -euo pipefail

LFS_ROOT="${LFS_ROOT:-/root/lfs}"
IMAGES_DIR="${IMAGES_DIR:-$LFS_ROOT/images}"
IMAGE="${IMAGE:-$IMAGES_DIR/lfs.img}"
LFS_MNT="${LFS_MNT:-$LFS_ROOT/mnt/lfs}"
CONTAINER="${CONTAINER:-lfs-build}"
HOST_LOGS_DIR="${HOST_LOGS_DIR:-$LFS_ROOT/logs/host}"
EXPECTED_UUID="${EXPECTED_UUID:-e0292aee-a40c-414b-a00b-d3d2685b6b0d}"

die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

assert_image_path() {
    local dir base
    dir="$(cd "$(dirname "$IMAGE")" 2>/dev/null && pwd -P)" || die "镜像目录不存在"
    base="$(cd "$IMAGES_DIR" 2>/dev/null && pwd -P)" || die "IMAGES_DIR 不存在"
    [ "$dir" = "$base" ] || die "拒绝操作 $IMAGES_DIR 之外的镜像：$IMAGE"
}

assert_project_loop() {
    local dev="$1" back base
    case "$dev" in /dev/loop[0-9]*) ;; *) die "不是 loop 设备，拒绝操作：$dev" ;; esac
    back="$(losetup -n -O BACK-FILE "$dev" 2>/dev/null)"
    [ -n "$back" ] || die "无法读取 $dev 的 backing file，拒绝操作"
    base="$(cd "$IMAGES_DIR" && pwd -P)"
    case "$back" in "$base"/*) ;; *) die "$dev 的 backing file 为 $back，不在 $base 内，拒绝操作" ;; esac
    [ "$(readlink -f "$back")" = "$(readlink -f "$IMAGE")" ] \
        || die "$dev 指向 $back，不是目标镜像 $IMAGE"
}

mkdir -p "$HOST_LOGS_DIR"
exec > >(tee -a "$HOST_LOGS_DIR/grub-install.log") 2>&1
printf '\n----- %s  GRUB BIOS install -----\n' "$(date '+%F %T')"
assert_image_path
[ -f "$IMAGE" ] || die "镜像不存在：$IMAGE"

part="$(findmnt -n -o SOURCE "$LFS_MNT" 2>/dev/null || true)"
case "$part" in /dev/loop[0-9]*p1) ;; *) die "$LFS_MNT 必须挂载自 loop 的第 1 分区；当前：${part:-未挂载}" ;; esac
loop="${part%p1}"
assert_project_loop "$loop"
[ "$(blkid -s UUID -o value "$part")" = "$EXPECTED_UUID" ] \
    || die "$part 的 UUID 与预期 $EXPECTED_UUID 不符"
docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true \
    || die "容器 $CONTAINER 未运行；先执行 make env"

printf '[SAFE] 精确目标：%s -> %s；根分区：%s；UUID=%s\n' "$loop" "$IMAGE" "$part" "$EXPECTED_UUID"
docker exec "$CONTAINER" test -b "$loop" || die "容器内看不到 $loop"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run \
    /workspace/scripts/write-grub-config.sh
partuuid="$(blkid -s PARTUUID -o value "$part")"
grep -q "root=PARTUUID=$partuuid ro console=ttyS0,115200n8" "$LFS_MNT/boot/grub/grub.cfg" \
    || die "grub.cfg 未使用实际 PARTUUID"
! grep -Eq '^[[:space:]]*initrd|root=UUID=|root=/dev/vda1' "$LFS_MNT/boot/grub/grub.cfg" \
    || die "grub.cfg 含禁止的 initrd 或根设备写法"
! find "$LFS_MNT/boot" -maxdepth 1 -type f \( -name 'initramfs*' -o -name 'initrd*' \) -print -quit | grep -q . \
    || die "/boot 中存在 initramfs/initrd"
printf '[ OK ] GRUB 已安装到 %s；配置：%s/boot/grub/grub.cfg\n' "$loop" "$LFS_MNT"
