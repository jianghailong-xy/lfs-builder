#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内以 lfs 用户执行 §5.4，完整输出落到日志。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/5.4-linux-6.18.10-api-headers.log

{
  echo "##### LFS 13.0-systemd §5.4 Linux-6.18.10 API Headers"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：lfs-build（镜像 lfs-build:13.0-systemd），\$LFS=/mnt/lfs（loop 挂载的镜像根分区）"
  echo
} > "$LOG"

"$LFS_ROOT/scripts/lfs-container.sh" exec-lfs \
  'bash /workspace/scripts/pkg/5.4-linux-api-headers.sh' >> "$LOG" 2>&1
rc=$?

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc"
exit $rc
