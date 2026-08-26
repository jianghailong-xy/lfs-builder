#!/usr/bin/env bash
# LFS 13.0-systemd 构建容器的生命周期管理（宿主机侧执行）
#
#   lfs-container.sh build    构建 lfs-build:13.0-systemd 镜像
#   lfs-container.sh up       启动（或复用）常驻容器 lfs-build
#   lfs-container.sh prepare  容器内执行手册 §4.2/§4.3/§4.4 的准备（幂等）
#   lfs-container.sh check    容器内跑手册 §2.2 的 version-check.sh
#   lfs-container.sh shell    进入容器 root shell
#   lfs-container.sh lfs-sh   以 lfs 用户、手册规定的干净环境进入 shell
#   lfs-container.sh exec-lfs <命令...>  以 lfs 用户在 $LFS/sources 下执行命令
#   lfs-container.sh down     停止并删除容器（不动镜像与产物）
#   lfs-container.sh status   只读状态
#
# 挂载点约定见 docs/conventions.md：宿主 $LFS_ROOT -> /workspace，
# 宿主 $LFS_ROOT/mnt/lfs -> /mnt/lfs（=$LFS），宿主 sources -> $LFS/sources。
set -euo pipefail
export LC_ALL=C LANG=C

LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LFS_MNT="${LFS_MNT:-$LFS_ROOT/mnt/lfs}"
SOURCES_DIR="${SOURCES_DIR:-$LFS_ROOT/sources}"
DOCKER_DIR="${DOCKER_DIR:-$LFS_ROOT/docker}"
DOCKER_IMAGE="${DOCKER_IMAGE:-lfs-build-$(basename "$LFS_ROOT"):13.0-systemd}"
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"
C_LFS="${C_LFS:-/mnt/lfs}"

die() { echo "错误：$*" >&2; exit 1; }

# 安全边界：只认本项目 images/ 下镜像关联出来的 loop 设备
require_mount() {
  findmnt -no SOURCE,TARGET "$LFS_MNT" >/dev/null 2>&1 \
    || die "$LFS_MNT 未挂载，请先在宿主机执行 make mount"
  local src; src=$(findmnt -no SOURCE "$LFS_MNT")
  case "$src" in
    /dev/loop*) ;;
    *) die "$LFS_MNT 的来源是 $src，不是本项目的 loop 设备，拒绝继续" ;;
  esac
  losetup -a | grep -qF "$LFS_ROOT/images/" || die "loop 设备未指向本项目镜像"
}

require_container() {
  docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true \
    || die "容器 $CONTAINER 未运行，请先执行 make container-up"
}

cmd_build() { docker build -t "$DOCKER_IMAGE" "$DOCKER_DIR"; }

cmd_up() {
  require_mount
  if docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
    echo "容器 $CONTAINER 已在运行"; return 0
  fi
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" \
    --privileged \
    -v "$LFS_ROOT:/workspace" \
    --mount type=bind,source="$LFS_MNT",target="$C_LFS",bind-propagation=rshared \
    -v "$SOURCES_DIR:$C_LFS/sources" \
    -w /workspace \
    -e LFS="$C_LFS" \
    "$DOCKER_IMAGE" sleep infinity >/dev/null
  echo "容器 $CONTAINER 已启动"
}

cmd_prepare() { require_container; docker exec "$CONTAINER" bash /workspace/scripts/prepare-chapter4.sh; }
cmd_check()   { require_container; docker exec -w /tmp "$CONTAINER" bash /workspace/docker/version-check.sh; }

# 以 lfs 用户、手册 §4.4 规定的干净环境（env -i + .bashrc）执行命令
run_as_lfs() {
  require_container
  docker exec -u lfs -w "$C_LFS/sources" "$CONTAINER" \
    env -i HOME=/home/lfs TERM="${TERM:-xterm}" PS1='\u:\w\$ ' \
    /bin/bash -c "source /home/lfs/.bashrc; $*"
}

case "${1:-status}" in
  build)    cmd_build ;;
  up)       cmd_up ;;
  prepare)  cmd_prepare ;;
  check)    cmd_check ;;
  shell)    require_container; docker exec -it "$CONTAINER" /bin/bash ;;
  lfs-sh)   require_container; docker exec -it -u lfs "$CONTAINER" /bin/bash --login ;;
  exec-lfs) shift; [ $# -ge 1 ] || die "用法：exec-lfs <命令...>"; run_as_lfs "$@" ;;
  down)     docker rm -f "$CONTAINER" >/dev/null 2>&1 && echo "容器已删除" || echo "容器不存在" ;;
  status)
    echo "== 镜像 =="; docker images "$DOCKER_IMAGE"
    echo "== 容器 =="; docker ps -a --filter "name=^/$CONTAINER$"
    echo "== 容器内 \$LFS =="
    docker exec "$CONTAINER" sh -c 'echo $LFS; ls -la $LFS' 2>/dev/null || echo "  (容器未运行)"
    ;;
  *) die "未知子命令：$1" ;;
esac
