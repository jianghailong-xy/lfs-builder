#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.81-procps-ng-4.0.6.log
CONTAINER=${CONTAINER:-lfs-build}
mkdir -p "$LFS_ROOT/logs/packages"

{
  if [ -s "$LOG" ]; then
    echo
    echo "##### 环境纠正后重试分隔：保留此前宿主机误执行输出，追加实际 chroot 执行：$(date -Is)"
  fi
  echo "##### LFS 13.0-systemd §8.81 Procps-ng-4.0.6"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 完整输出；容器：$CONTAINER；chroot 根：/mnt/lfs"
  echo
  echo "===== chroot 环境准备 ====="
} >> "$LOG"

docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run \
    /workspace/scripts/pkg/8.81-procps-ng.sh >> "$LOG" 2>&1
  rc=$?
fi
echo "##### 退出码：$rc" >> "$LOG"
exit "$rc"
