#!/usr/bin/env bash
# 物理整盘安装入口。check 全程只读；install 仅在全部安全闸通过并经 TTY 二次确认后写盘。
set -u -o pipefail

LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DISK_MNT="${DISK_MNT:-$LFS_ROOT/mnt/lfs}"
DISK_LABEL="${DISK_LABEL:-LFS}"
ALLOW_LOOP_TEST="${ALLOW_LOOP_TEST:-0}"
RED=''; GRN=''; YLW=''; BLD=''; RST=''
if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'; fi
ok()   { printf '  %s[ OK ]%s %s\n' "$GRN" "$RST" "$*"; }
info() { printf '  %s\n' "$*"; }
head_(){ printf '\n%s== %s ==%s\n' "$BLD" "$1" "$RST"; }
die()  { printf '  %s[FAIL]%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
run()  { printf '  %s$%s %q' "$BLD" "$RST" "$1"; printf ' %q' "${@:2}"; printf '\n'; "$@" || die "命令失败：$*"; }

declare -a NODES=() REASONS=()
add_reason() { REASONS+=("$1"); }

assert_target_syntax() {
    local target="$1" type back root
    [ "${target#/dev/}" != "$target" ] || die "目标必须是 /dev 下的设备路径：$target"
    case "$target" in
        /dev/sd[a-z]|/dev/sd[a-z][a-z]) ;;
        /dev/loop[0-9]*)
            [ "$ALLOW_LOOP_TEST" = 1 ] || die "loop 设备仅限显式 ALLOW_LOOP_TEST=1 的隔离测试"
            back="$(losetup -n -O BACK-FILE "$target" 2>/dev/null)"
            [ -n "$back" ] || die "无法读取 $target 的后备文件"
            root="$(cd "$LFS_ROOT" && pwd -P)"
            case "$(readlink -f "$back")" in "$root"/*) ;; *) die "测试 loop 后备文件不在仓库内：$back" ;; esac
            ;;
        *)
            [[ "$target" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] || \
                die "只接受整盘 /dev/sdX 或 /dev/nvmeXnY；拒绝分区及其他设备：$target"
            ;;
    esac
    [ -b "$target" ] || die "目标不是块设备：$target"
    [ "$(readlink -f "$target")" = "$target" ] || die "目标必须使用规范设备全名，不接受符号链接：$target"
    type="$(lsblk -dnro TYPE "$target" 2>/dev/null)"
    if [[ "$target" == /dev/loop* ]]; then [ "$type" = loop ] || die "$target 不是 loop 整盘";
    else [ "$type" = disk ] || die "$target 不是整盘设备（TYPE=$type）"; fi
}

collect_nodes() { mapfile -t NODES < <(lsblk -nrpo NAME "$1"); }

print_profile() {
    local target="$1" model serial size pttype
    model="$(lsblk -dno MODEL "$target" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    serial="$(lsblk -dno SERIAL "$target" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    size="$(lsblk -dnro SIZE "$target")"; pttype="$(lsblk -dnro PTTYPE "$target")"
    head_ "目标设备完整画像（只读）"
    info "设备路径      : $target"
    info "型号          : ${model:-未知}"
    info "序列号        : ${serial:-未知}"
    info "容量          : ${size:-未知}"
    info "分区表类型    : ${pttype:-无/未知}"
    info "分区 / 文件系统 / 标签 / 挂载点 / PARTTYPE："
    lsblk -o NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS,PARTTYPE "$target" | sed 's/^/    /'
    info "活动 swap     : $(awk 'NR>1 {print $1}' /proc/swaps | grep -Fx -f <(printf '%s\n' "${NODES[@]}") | paste -sd, - || true)"
    info "ZFS 池引用    : $(zpool_members "$target" | paste -sd, - || true)"
    info "MD/LVM 标记   : 见下方安全闸逐项结果"
    info "EFI 系统分区  : $(has_efi && echo 是 || echo 否)"
}

zpool_members() {
    command -v zpool >/dev/null 2>&1 || return 0
    local n base
    for n in "${NODES[@]}"; do
        base="$(basename "$n")"
        zpool status -P 2>/dev/null | awk -v p="$n" -v b="$base" '$1==p || $1==b {print $1}'
    done | sort -u
}

has_efi() {
    local n pt
    for n in "${NODES[@]:1}"; do
        pt="$(lsblk -dnro PARTTYPE "$n" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        [ "$pt" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b ] && return 0
        [ "$pt" = ef ] && return 0
    done
    return 1
}

root_or_boot_parent() {
    local target="$1" mp src top
    for mp in / /boot /boot/efi; do
        src="$(findmnt -nro SOURCE --target "$mp" 2>/dev/null | head -1)"
        [ -b "$src" ] || continue
        top="$(lsblk -snrpo NAME,TYPE "$src" | awk '$2=="disk" || $2=="loop" {print $1}' | tail -1)"
        [ "$top" = "$target" ] && { printf '%s:%s\n' "$mp" "$src"; return 0; }
    done
    return 1
}

run_gates() {
    local target="$1" n fs mp hit root_hit
    for n in "${NODES[@]}"; do
        mp="$(lsblk -dnro MOUNTPOINTS "$n" 2>/dev/null | sed '/^[[:space:]]*$/d' | paste -sd, -)"
        [ -n "$mp" ] && add_reason "已挂载：$n -> $mp"
    done
    while read -r n _; do
        [ -n "${n:-}" ] || continue
        for hit in "${NODES[@]}"; do [ "$(readlink -f "$n")" = "$hit" ] && add_reason "活动 swap：$hit"; done
    done < <(tail -n +2 /proc/swaps)
    for n in "${NODES[@]}"; do
        fs="$(blkid -s TYPE -o value "$n" 2>/dev/null || true)"
        case "$fs" in
            zfs_member) add_reason "ZFS 成员（blkid）：$n" ;;
            linux_raid_member) add_reason "MD RAID 成员（blkid）：$n" ;;
            LVM2_member) add_reason "LVM PV（blkid）：$n" ;;
        esac
        [ -d "/sys/class/block/$(basename "$n")/holders" ] && \
          find "/sys/class/block/$(basename "$n")/holders" -mindepth 1 -maxdepth 1 -print -quit | grep -q . && \
          add_reason "设备正被内核 holder 使用：$n"
    done
    hit="$(zpool_members "$target" | paste -sd, - || true)"; [ -n "$hit" ] && add_reason "ZFS 池 status 引用：$hit"
    if command -v pvs >/dev/null 2>&1; then
        while read -r n; do
            [ -n "$n" ] || continue
            for hit in "${NODES[@]}"; do [ "$(readlink -f "$n")" = "$hit" ] && add_reason "LVM PV（pvs）：$hit"; done
        done < <(pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1};1')
    fi
    has_efi && add_reason "包含 EFI 系统分区"
    root_hit="$(root_or_boot_parent "$target" || true)"
    [ -n "$root_hit" ] && add_reason "当前运行系统的根/启动盘：$root_hit"
}

check_target() {
    local target="$1"
    assert_target_syntax "$target"; collect_nodes "$target"; print_profile "$target"; run_gates "$target"
    head_ "安全闸结论"
    if ((${#REASONS[@]})); then
        printf '  [REJECT] %s\n' "${REASONS[@]}" >&2
        die "命中 ${#REASONS[@]} 条硬性拒绝规则；未进入确认环节，未执行写盘"
    fi
    ok "未命中硬性拒绝规则"
}

confirm_target() {
    local target="$1" answer phrase="清空 $target"
    [ -t 0 ] && [ -t 1 ] || die "非交互环境默认拒绝；请在真实终端中人工确认"
    head_ "破坏性操作二次确认"
    printf '  即将永久清空 %s。请输入完整短语 [%s]：' "$target" "$phrase"
    IFS= read -r answer
    [ "$answer" = "$phrase" ] || die "确认短语不匹配，拒绝写盘"
}

wait_partition() { local p="$1" i; for i in {1..20}; do [ -b "$p" ] && return 0; sleep .25; done; return 1; }
install_target() {
    local target="$1" boot root uuid
    check_target "$target"; confirm_target "$target"
    # 缩短画像/确认与破坏性命令之间的 TOCTOU 窗口：临写前重新采集并跑同一硬闸。
    REASONS=(); collect_nodes "$target"; run_gates "$target"
    ((${#REASONS[@]} == 0)) || {
        printf '  [REJECT] %s\n' "${REASONS[@]}" >&2
        die "确认后设备状态发生变化；未执行写盘"
    }
    [ ! -e "$DISK_MNT" ] || { [ -d "$DISK_MNT" ] || die "挂载点不是目录：$DISK_MNT"; }
    findmnt -n "$DISK_MNT" >/dev/null 2>&1 && die "挂载点已被占用：$DISK_MNT"
    mkdir -p "$DISK_MNT"
    [ -z "$(ls -A "$DISK_MNT")" ] || die "挂载点非空：$DISK_MNT"
    head_ "清空目标并创建 GPT/BIOS 分区"
    sfdisk --wipe always "$target" <<'EOF' || die "sfdisk 分区失败"
label: gpt
unit: sectors
start=2048, size=2048, type=21686148-6449-6E6F-744E-656564454649
start=4096, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
    partprobe "$target" 2>/dev/null || true
    if [[ "$target" == /dev/nvme* || "$target" == /dev/loop* ]]; then boot="${target}p1"; root="${target}p2"; else boot="${target}1"; root="${target}2"; fi
    wait_partition "$root" || die "分区节点未出现：$root"
    run mkfs.ext4 -q -F -L "$DISK_LABEL" -m 1 "$root"
    run mount "$root" "$DISK_MNT"
    uuid="$(blkid -s UUID -o value "$root")"
    head_ "安装结果"
    ok "BIOS boot 分区：$boot"
    ok "ext4 根分区：$root（LABEL=$DISK_LABEL UUID=$uuid）"
    ok "已挂载：$root -> $DISK_MNT"
    lsblk -o NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,PARTTYPE,MOUNTPOINTS "$target" | sed 's/^/    /'
}

case "${1-}" in
    check) [ "$#" -eq 2 ] || die "用法：$0 check /dev/sdX"; check_target "$2" ;;
    install) [ "$#" -eq 2 ] || die "用法：$0 install /dev/sdX"; install_target "$2" ;;
    *) printf '用法：%s {check|install} /dev/sdX\n' "$0" >&2; exit 2 ;;
esac
