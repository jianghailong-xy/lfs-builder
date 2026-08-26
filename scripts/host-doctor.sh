#!/usr/bin/env bash
# 宿主机构建环境体检。由 `make doctor` 调用。
# 退出码：0 = 所有强制检查通过（可选项可能仍有 WARN）；1 = 存在强制项失败。
set -u -o pipefail

LFS_ROOT="${LFS_ROOT:-/root/lfs}"
MIN_FREE_GB="${MIN_FREE_GB:-60}"
IMAGE_SIZE_GB="${IMAGE_SIZE_GB:-30}"

RED=''; GRN=''; YLW=''; BLD=''; RST=''
if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'; fi

fail_count=0
warn_count=0
missing_pkgs=()

ok()   { printf '  %s[ OK ]%s %-28s %s\n' "$GRN" "$RST" "$1" "${2-}"; }
warn() { printf '  %s[WARN]%s %-28s %s\n' "$YLW" "$RST" "$1" "${2-}"; warn_count=$((warn_count+1)); }
bad()  { printf '  %s[FAIL]%s %-28s %s\n' "$RED" "$RST" "$1" "${2-}"; fail_count=$((fail_count+1)); }
head_() { printf '\n%s== %s ==%s\n' "$BLD" "$1" "$RST"; }

note_pkg() {
    local p="$1" e
    [ -z "$p" ] && return 0
    for e in ${missing_pkgs[@]+"${missing_pkgs[@]}"}; do [ "$e" = "$p" ] && return 0; done
    missing_pkgs+=("$p")
}

# require_cmd <命令> <apt包> [说明]
require_cmd() {
    local cmd="$1" pkg="$2" desc="${3-}" path
    if path="$(command -v "$cmd" 2>/dev/null)"; then
        ok "$cmd" "$path${desc:+  ($desc)}"
    else
        bad "$cmd" "未找到，需安装 ${pkg}${desc:+  ($desc)}"
        note_pkg "$pkg"
    fi
}

# optional_cmd <命令> <apt包> [说明]
optional_cmd() {
    local cmd="$1" pkg="$2" desc="${3-}" path
    if path="$(command -v "$cmd" 2>/dev/null)"; then
        ok "$cmd" "$path${desc:+  ($desc)}"
    else
        warn "$cmd" "可选，未找到（${pkg}）${desc:+  $desc}"
    fi
}

printf '%sLFS 宿主机构建环境体检%s  —  LFS_ROOT=%s\n' "$BLD" "$RST" "$LFS_ROOT"
printf '主机: %s   内核: %s   架构: %s\n' "$(uname -n)" "$(uname -r)" "$(uname -m)"

# ---------------------------------------------------------------- 基础
head_ "基础环境"
if [ "$(id -u)" -eq 0 ]; then
    ok "root 权限" "uid=0"
else
    bad "root 权限" "loop/mount/chroot 操作需要 root（当前 uid=$(id -u)）"
fi
if [ "$(uname -m)" = "x86_64" ]; then
    ok "宿主架构" "x86_64"
else
    bad "宿主架构" "需要 x86_64，当前为 $(uname -m)"
fi
require_cmd make      make        "构建入口"
require_cmd bash      bash
require_cmd tar       tar         "解包源码"
require_cmd xz        xz-utils
require_cmd gzip      gzip
require_cmd cpio      cpio        "生成 UUID 根文件系统所需的最小 initramfs"
require_cmd bzip2     bzip2
require_cmd patch     patch
require_cmd wget      wget        "下载源码包"
require_cmd sha256sum coreutils   "校验源码包"
optional_cmd curl     curl
optional_cmd git      git
optional_cmd rsync    rsync

# ---------------------------------------------------------------- Docker
head_ "Docker 构建环境"
require_cmd docker docker.io "容器化构建环境"
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        ok "docker 守护进程" "版本 $(docker version --format '{{.Server.Version}}' 2>/dev/null)  存储驱动 $(docker info --format '{{.Driver}}' 2>/dev/null)"
    else
        bad "docker 守护进程" "docker info 失败，守护进程未运行或当前用户无权访问"
    fi
    if docker info --format '{{.MemTotal}}' >/dev/null 2>&1; then
        :
    fi
fi

# ---------------------------------------------------------------- QEMU
head_ "QEMU x86_64"
require_cmd qemu-system-x86_64 qemu-system-x86 "启动最终镜像"
require_cmd qemu-img           qemu-utils      "创建/检查 raw 镜像"
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    ok "qemu 版本" "$(qemu-system-x86_64 --version | head -1)"
    if qemu-system-x86_64 -accel help 2>/dev/null | grep -qx 'kvm'; then
        ok "qemu 支持 kvm 加速器" "已编入二进制"
    else
        warn "qemu 支持 kvm 加速器" "该 qemu 未编入 kvm，将只能使用 tcg 软件模拟"
    fi
fi

# ---------------------------------------------------------------- loop / 分区 / 文件系统
head_ "loop 设备 / 分区 / 文件系统工具"
require_cmd losetup   util-linux  "关联 raw 镜像到 loop 设备"
require_cmd sfdisk    fdisk       "创建分区表"
require_cmd fdisk     fdisk
require_cmd partx     util-linux  "刷新 loop 分区"
require_cmd blkid     util-linux  "读取 UUID"
require_cmd lsblk     util-linux
require_cmd mount     mount
require_cmd umount    mount
require_cmd mkfs.ext4 e2fsprogs   "格式化根分区"
require_cmd e2fsck    e2fsprogs
require_cmd tune2fs   e2fsprogs
optional_cmd parted   parted      "分区表交互检查"
optional_cmd kpartx   kpartx      "partx 的备选方案"

if [ -e /dev/loop-control ]; then
    ok "/dev/loop-control" "loop 子系统可用（已用 loop: $(losetup -a 2>/dev/null | wc -l)）"
else
    if modprobe loop 2>/dev/null && [ -e /dev/loop-control ]; then
        ok "/dev/loop-control" "已通过 modprobe loop 加载"
    else
        bad "/dev/loop-control" "loop 子系统不可用，无法挂载 raw 镜像"
    fi
fi
if [ -r /proc/filesystems ] && grep -qw ext4 /proc/filesystems; then
    ok "内核 ext4 支持" "/proc/filesystems 含 ext4"
elif modprobe ext4 2>/dev/null; then
    ok "内核 ext4 支持" "已通过 modprobe ext4 加载"
else
    bad "内核 ext4 支持" "内核无 ext4，无法挂载根分区"
fi

# ---------------------------------------------------------------- GRUB
head_ "GRUB（BIOS 引导）"
require_cmd grub-install  grub-pc-bin   "向镜像写入 BIOS 引导代码"
optional_cmd grub-mkconfig grub-common  "生成 grub.cfg（最终以 chroot 内 GRUB 为准）"
optional_cmd grub-mkimage  grub-common
if [ -d /usr/lib/grub/i386-pc ]; then
    ok "grub i386-pc 模块" "/usr/lib/grub/i386-pc ($(ls /usr/lib/grub/i386-pc | wc -l) 个文件)"
else
    bad "grub i386-pc 模块" "缺少 /usr/lib/grub/i386-pc，需安装 grub-pc-bin"
    note_pkg grub-pc-bin
fi

# ---------------------------------------------------------------- 磁盘空间
head_ "磁盘空间"
avail_gb="$(df -BG --output=avail "$LFS_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')"
fs_line="$(df -PhT "$LFS_ROOT" 2>/dev/null | tail -1)"
if [ -n "$avail_gb" ]; then
    if [ "$avail_gb" -ge "$MIN_FREE_GB" ]; then
        ok "可用空间" "${avail_gb}G 可用（下限 ${MIN_FREE_GB}G，计划镜像 ${IMAGE_SIZE_GB}G）"
    else
        bad "可用空间" "仅 ${avail_gb}G 可用，低于下限 ${MIN_FREE_GB}G（计划镜像 ${IMAGE_SIZE_GB}G + 源码 + 构建中间产物）"
    fi
    printf '        %s\n' "$fs_line"
else
    bad "可用空间" "无法读取 $LFS_ROOT 的 df 信息"
fi
mem_gb="$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null)"
if [ -n "$mem_gb" ] && [ "$mem_gb" -ge 4 ]; then
    ok "内存" "${mem_gb}G，逻辑核心 $(nproc)"
else
    warn "内存" "${mem_gb:-?}G 偏小，构建 GCC/Glibc 时建议 >= 4G 并配置交换分区"
fi

# ---------------------------------------------------------------- KVM（可选）
head_ "KVM 加速（可选）"
if [ -c /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        if command -v qemu-system-x86_64 >/dev/null 2>&1 &&
           echo quit | timeout 20 qemu-system-x86_64 -accel kvm -display none -m 64 \
                -nodefaults -no-user-config -monitor stdio >/dev/null 2>&1; then
            ok "/dev/kvm" "可用，qemu -accel kvm 冒烟测试通过（启动镜像可用硬件加速）"
        else
            warn "/dev/kvm" "设备存在但 qemu -accel kvm 冒烟测试未通过，启动时回退 -accel tcg"
        fi
    else
        warn "/dev/kvm" "存在但当前用户无读写权限，启动时回退 -accel tcg"
    fi
else
    warn "/dev/kvm" "不存在（未开启嵌套虚拟化？），启动时回退 -accel tcg，速度较慢但不影响正确性"
fi

# ---------------------------------------------------------------- 项目骨架
head_ "项目骨架"
for d in sources scripts docs docker images logs logs/packages logs/host mnt/lfs; do
    if [ -d "$LFS_ROOT/$d" ]; then
        ok "$d/" ""
    else
        bad "$d/" "缺失，执行 make dirs 创建"
    fi
done

# ---------------------------------------------------------------- 汇总
head_ "汇总"
if [ "$fail_count" -eq 0 ]; then
    printf '  %s强制检查全部通过%s（%d 项可选警告）\n' "$GRN" "$RST" "$warn_count"
    exit 0
else
    printf '  %s%d 项强制检查失败%s，%d 项可选警告\n' "$RED" "$fail_count" "$RST" "$warn_count"
    if [ "${#missing_pkgs[@]}" -gt 0 ] 2>/dev/null; then
        printf '  建议安装：apt-get install -y %s\n' "${missing_pkgs[*]}"
    fi
    exit 1
fi
