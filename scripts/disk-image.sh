#!/usr/bin/env bash
# LFS raw 磁盘镜像的创建 / 挂载 / 卸载。由 `make image|mount|umount|status` 调用。
#
#   disk-image.sh create   建立 raw 镜像 -> msdos 分区表 -> 单一 ext4 根分区
#   disk-image.sh mount    losetup -P 关联镜像，并把根分区挂到 $LFS_MNT
#   disk-image.sh umount   先卸载 $LFS_MNT，再解除 loop 关联（顺序不可颠倒）
#   disk-image.sh info     只读打印镜像 / loop / 分区 / 挂载信息
#
# 安全边界（docs/conventions.md §3）：本脚本只允许操作 $IMAGES_DIR 下的镜像文件
# 及其 loop 设备，挂载点只允许是 $LFS_MNT。任何要动的 loop 设备都先核对其
# backing file 位于 $IMAGES_DIR 内，否则立即中止，绝不触碰宿主机真实磁盘。
set -u -o pipefail

LFS_ROOT="${LFS_ROOT:-/root/lfs}"
IMAGES_DIR="${IMAGES_DIR:-$LFS_ROOT/images}"
IMAGE="${IMAGE:-$IMAGES_DIR/lfs.img}"
IMAGE_SIZE_GB="${IMAGE_SIZE_GB:-30}"
MIN_FREE_GB="${MIN_FREE_GB:-60}"
LFS_MNT="${LFS_MNT:-$LFS_ROOT/mnt/lfs}"
HOST_LOGS_DIR="${HOST_LOGS_DIR:-$LFS_ROOT/logs/host}"
IMAGE_LABEL="${IMAGE_LABEL:-LFS}"
IMAGE_UUID="${IMAGE_UUID:-e0292aee-a40c-414b-a00b-d3d2685b6b0d}"
# 镜像元信息（设备无关的部分：分区布局、UUID），供后续 fstab / GRUB 任务读取
INFO_FILE="${INFO_FILE:-$IMAGE.info}"

RED=''; GRN=''; YLW=''; BLD=''; RST=''
if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'; fi

ok()   { printf '  %s[ OK ]%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s[WARN]%s %s\n' "$YLW" "$RST" "$*"; }
info() { printf '  %s\n' "$*"; }
head_(){ printf '\n%s== %s ==%s\n' "$BLD" "$1" "$RST"; }
die()  { printf '  %s[FAIL]%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
run()  { printf '  %s$%s %s\n' "$BLD" "$RST" "$*"; "$@" || die "命令失败：$*"; }

# ---------------------------------------------------------------- 安全断言
# 镜像路径必须落在 $IMAGES_DIR 内
assert_image_path() {
    local dir; dir="$(cd "$(dirname "$IMAGE")" 2>/dev/null && pwd -P)" \
        || die "镜像目录不存在：$(dirname "$IMAGE")"
    local base; base="$(cd "$IMAGES_DIR" 2>/dev/null && pwd -P)" \
        || die "IMAGES_DIR 不存在：$IMAGES_DIR"
    [ "$dir" = "$base" ] || die "拒绝操作 $IMAGES_DIR 之外的镜像：$IMAGE"
}

# 挂载点必须恰好是 $LFS_MNT
assert_mount_target() {
    [ -d "$LFS_MNT" ] || die "挂载点不存在：$LFS_MNT（执行 make dirs）"
    local t; t="$(cd "$LFS_MNT" && pwd -P)"
    [ "$t" = "$LFS_MNT" ] || die "挂载点解析异常：$LFS_MNT -> $t"
}

# 该 loop 设备的 backing file 必须在 $IMAGES_DIR 内，否则不许碰
assert_project_loop() {
    local dev="$1" back
    case "$dev" in /dev/loop[0-9]*) ;; *) die "不是 loop 设备，拒绝操作：$dev" ;; esac
    back="$(losetup -n -O BACK-FILE "$dev" 2>/dev/null)"
    [ -n "$back" ] || die "无法读取 $dev 的 backing file，拒绝操作"
    case "$back" in
        "$IMAGES_DIR"/*) ;;
        *) die "$dev 的 backing file 为 $back，不在 $IMAGES_DIR 内，拒绝操作" ;;
    esac
}

# 已关联本镜像的 loop 设备（可能为空）
loop_of_image() { losetup -n -O NAME -j "$IMAGE" 2>/dev/null | head -1; }

part_of_loop()  { printf '%sp1' "$1"; }
# /dev/loopNp1 -> /dev/loopN
loop_base_of() { printf '%s' "${1%p[0-9]*}"; }

log_to() { # log_to <日志名>：把本次全部输出同时写入 logs/host/<名>.log
    mkdir -p "$HOST_LOGS_DIR"
    exec > >(tee -a "$HOST_LOGS_DIR/$1") 2>&1
    printf '\n----- %s  %s -----\n' "$(date '+%F %T')" "$*"
}

# ---------------------------------------------------------------- create
cmd_create() {
    log_to image.log
    assert_image_path
    head_ "创建 raw 镜像"

    if [ -e "$IMAGE" ]; then
        if [ "${FORCE:-0}" = "1" ]; then
            local dev; dev="$(loop_of_image)"
            [ -n "$dev" ] && die "镜像已关联 $dev，请先 make umount 再用 FORCE=1 重建"
            warn "FORCE=1：删除已存在的镜像 $IMAGE"
            run rm -f "$IMAGE"
        else
            die "镜像已存在：$IMAGE（如需重建：make umount && make image FORCE=1）"
        fi
    fi

    local avail_gb; avail_gb="$(df -BG --output=avail "$IMAGES_DIR" | tail -1 | tr -dc '0-9')"
    [ -n "$avail_gb" ] || die "无法读取 $IMAGES_DIR 的可用空间"
    [ "$avail_gb" -ge "$MIN_FREE_GB" ] \
        || die "可用空间 ${avail_gb}G 低于下限 ${MIN_FREE_GB}G，拒绝创建 ${IMAGE_SIZE_GB}G 镜像"
    ok "可用空间 ${avail_gb}G（下限 ${MIN_FREE_GB}G）"

    # 稀疏 raw 文件：逻辑 ${IMAGE_SIZE_GB}G，实际按写入增长；qemu 可直接使用
    run qemu-img create -f raw "$IMAGE" "${IMAGE_SIZE_GB}G"
    run chmod 0600 "$IMAGE"
    ok "镜像已创建：$IMAGE（逻辑 ${IMAGE_SIZE_GB}G，稀疏）"

    head_ "写入分区表（msdos / BIOS + GRUB）"
    # 直接在镜像文件上分区，避免在未格式化阶段占用 loop 设备。
    # start=2048 扇区（1 MiB）：既满足对齐，也给 GRUB core.img 留出 MBR gap。
    # 单一主分区 p1，type=83（Linux），bootable，占满镜像剩余空间。
    sfdisk "$IMAGE" <<'EOF' || die "sfdisk 分区失败"
label: dos
unit: sectors
start=2048, type=83, bootable
EOF
    ok "分区表写入完成"
    sfdisk -l "$IMAGE" | sed 's/^/    /'

    head_ "关联 loop 并格式化 ext4"
    local dev part
    dev="$(losetup -P -f --show "$IMAGE")" || die "losetup 关联失败"
    [ -n "$dev" ] || die "losetup 未返回设备名"
    assert_project_loop "$dev"
    ok "loop 关联：$dev -> $IMAGE"
    part="$(part_of_loop "$dev")"

    # 分区节点由内核异步创建，等待其出现
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -b "$part" ] && break; sleep 0.3; done
    if [ ! -b "$part" ]; then
        partx -a "$dev" 2>/dev/null || true
        for i in 1 2 3 4 5; do [ -b "$part" ] && break; sleep 0.3; done
    fi
    [ -b "$part" ] || { losetup -d "$dev"; die "分区节点未出现：$part"; }
    ok "分区节点：$part"

    if ! mkfs.ext4 -q -F -L "$IMAGE_LABEL" -U "$IMAGE_UUID" -m 1 "$part"; then
        losetup -d "$dev"; die "mkfs.ext4 失败：$part"
    fi
    ok "ext4 格式化完成（label=$IMAGE_LABEL，UUID=$IMAGE_UUID，保留块 1%）"

    local uuid ptuuid
    uuid="$(blkid -s UUID -o value "$part")"
    ptuuid="$(blkid -s PTUUID -o value "$dev" 2>/dev/null)"

    head_ "记录镜像信息"
    cat > "$INFO_FILE" <<EOF
# LFS raw 磁盘镜像信息（由 scripts/disk-image.sh create 生成，勿手工编辑）
# 生成时间: $(date '+%F %T %z')
IMAGE=$IMAGE
IMAGE_SIZE_GB=$IMAGE_SIZE_GB
PART_TABLE=msdos
PART_COUNT=1
PART1_NUM=1
PART1_TYPE=83
PART1_BOOTABLE=yes
PART1_START_SECTOR=2048
PART1_FSTYPE=ext4
PART1_LABEL=$IMAGE_LABEL
PART1_UUID=$uuid
PTUUID=$ptuuid
MOUNTPOINT=$LFS_MNT
EOF
    ok "已写入 $INFO_FILE"
    sed 's/^/    /' "$INFO_FILE"

    head_ "释放 loop（创建阶段不保持关联）"
    run losetup -d "$dev"
    ok "已解除 $dev 关联；执行 make mount 挂载到 $LFS_MNT"
}

# ---------------------------------------------------------------- mount
cmd_mount() {
    log_to mount.log
    assert_image_path
    assert_mount_target
    [ -f "$IMAGE" ] || die "镜像不存在：$IMAGE（先执行 make image）"

    head_ "挂载镜像根分区"

    # 已挂载则核对来源后幂等返回
    if findmnt -n "$LFS_MNT" >/dev/null 2>&1; then
        local cur; cur="$(findmnt -n -o SOURCE "$LFS_MNT" | head -1)"
        assert_project_loop "$(loop_base_of "$cur")"
        ok "$LFS_MNT 已挂载自 $cur，无需重复挂载"
        cmd_info
        return 0
    fi

    local dev part
    dev="$(loop_of_image)"
    if [ -n "$dev" ]; then
        assert_project_loop "$dev"
        ok "复用已有 loop 关联：$dev"
    else
        dev="$(losetup -P -f --show "$IMAGE")" || die "losetup 关联失败"
        assert_project_loop "$dev"
        ok "loop 关联：$dev -> $IMAGE"
    fi
    part="$(part_of_loop "$dev")"

    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -b "$part" ] && break; sleep 0.3; done
    if [ ! -b "$part" ]; then
        partx -a "$dev" 2>/dev/null || true
        for i in 1 2 3 4 5; do [ -b "$part" ] && break; sleep 0.3; done
    fi
    [ -b "$part" ] || die "分区节点未出现：$part"

    local fstype; fstype="$(blkid -s TYPE -o value "$part" 2>/dev/null)"
    [ "$fstype" = "ext4" ] || die "$part 文件系统为 '${fstype:-未知}'，不是 ext4，拒绝挂载"

    # 挂载点必须为空，避免覆盖已有内容
    if [ -n "$(ls -A "$LFS_MNT" 2>/dev/null)" ]; then
        warn "$LFS_MNT 非空，挂载后其原有内容将被遮蔽"
    fi

    run mount "$part" "$LFS_MNT"
    ok "已挂载 $part -> $LFS_MNT"
    cmd_info
}

# ---------------------------------------------------------------- umount
cmd_umount() {
    log_to mount.log
    assert_image_path
    head_ "卸载并解除 loop 关联"

    # 先卸载，再解除关联（docs/conventions.md §3，顺序不可颠倒）
    if findmnt -n "$LFS_MNT" >/dev/null 2>&1; then
        local cur; cur="$(findmnt -n -o SOURCE "$LFS_MNT" | head -1)"
        assert_project_loop "$(loop_base_of "$cur")"
        # chroot 准备会在根挂载下留下 dev/proc/sys/run/sources；只在上面的
        # project-loop 断言通过后，按最深路径优先卸载这些精确子挂载。
        local target
        while IFS= read -r target; do
            [ "$target" = "$LFS_MNT" ] && continue
            case "$target" in "$LFS_MNT"/*) run umount "$target" ;; *) die "发现项目外子挂载：$target" ;; esac
        done < <(findmnt -Rnl -o TARGET "$LFS_MNT" | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
        run umount "$LFS_MNT"
        ok "已卸载 $LFS_MNT（来自 $cur）"
    else
        info "$LFS_MNT 未挂载，跳过 umount"
    fi

    local dev; dev="$(loop_of_image)"
    if [ -n "$dev" ]; then
        assert_project_loop "$dev"
        run losetup -d "$dev"
        ok "已解除 loop 关联：$dev"
    else
        info "本镜像无 loop 关联，跳过 losetup -d"
    fi
}

# ---------------------------------------------------------------- info
cmd_info() {
    head_ "当前镜像 / 设备状态"
    if [ -f "$IMAGE" ]; then
        info "镜像    : $IMAGE  逻辑 $(du -h --apparent-size "$IMAGE" | cut -f1)  实占 $(du -h "$IMAGE" | cut -f1)"
    else
        info "镜像    : (未创建) $IMAGE"
        return 0
    fi
    local dev; dev="$(loop_of_image)"
    if [ -n "$dev" ]; then
        info "loop    : $dev -> $IMAGE"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT "$dev" 2>/dev/null | sed 's/^/    /'
    else
        info "loop    : (未关联)"
    fi
    if findmnt -n "$LFS_MNT" >/dev/null 2>&1; then
        findmnt -o SOURCE,TARGET,FSTYPE,SIZE,AVAIL,OPTIONS "$LFS_MNT" | sed 's/^/    /'
    else
        info "挂载    : (未挂载) $LFS_MNT"
    fi
    [ -f "$INFO_FILE" ] && { info "元信息  : $INFO_FILE"; }
    return 0
}

case "${1-}" in
    create) cmd_create ;;
    mount)  cmd_mount ;;
    umount) cmd_umount ;;
    info)   cmd_info ;;
    *) printf '用法: %s {create|mount|umount|info}\n' "$0" >&2; exit 2 ;;
esac
