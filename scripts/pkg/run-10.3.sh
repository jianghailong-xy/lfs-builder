#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/10.3-linux-6.18.10.log
CONTAINER=${CONTAINER:-lfs-build}
mkdir -p "$LFS_ROOT/logs/packages"

{
  echo "##### LFS 13.0-systemd §10.3 Linux-6.18.10"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 完整输出；容器：$CONTAINER；chroot 根：/mnt/lfs"
  echo
  echo "===== chroot 环境准备 ====="
} > "$LOG"

docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run \
    /workspace/scripts/pkg/10.3-linux.sh >> "$LOG" 2>&1
  rc=$?
fi
echo "##### 退出码：$rc" >> "$LOG"
exit "$rc"
