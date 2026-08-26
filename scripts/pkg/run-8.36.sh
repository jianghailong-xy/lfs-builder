#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.36-grep-3.12.log
CONTAINER=${CONTAINER:-lfs-build}
mkdir -p "$LFS_ROOT/logs/packages"

{
  if [ -s "$LOG" ]; then
    echo
    echo "##### 重试分隔：保留此前完整失败输出，追加本次执行：$(date -Is)"
  fi
  echo "##### LFS 13.0-systemd §8.36 Grep-3.12"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 完整输出；容器：$CONTAINER；chroot 根：/mnt/lfs"
  echo "##### 官方手册：https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/grep.html"
  echo '##### 手册命令：sed -i "s/echo/#echo/" src/egrep.sh；./configure --prefix=/usr；make；make check；make install'
  echo
  echo "===== chroot 环境准备 ====="
} >> "$LOG"

docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.36-grep.sh >> "$LOG" 2>&1
  rc=$?
fi
echo "##### 最终退出码：$rc" >> "$LOG"
exit "$rc"
