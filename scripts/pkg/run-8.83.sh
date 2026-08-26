#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.83-e2fsprogs-1.47.3.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"
mkdir -p "$LFS_ROOT/logs/packages"

{
  echo "##### LFS 13.0-systemd §8.83 E2fsprogs-1.47.3"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 完整输出；容器：$CONTAINER；chroot 根：/mnt/lfs"
  echo
  echo "===== chroot 环境准备 ====="
} > "$LOG"

docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run \
    /workspace/scripts/pkg/8.83-e2fsprogs.sh >> "$LOG" 2>&1
  rc=$?
fi
echo "##### 退出码：$rc" >> "$LOG"
exit "$rc"
