#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内以 lfs 用户执行 §6.6，完整输出落到日志。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/6.6-diffutils-3.12.log

{
  echo "##### LFS 13.0-systemd §6.6 Diffutils-3.12"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：lfs-build（镜像 lfs-build:13.0-systemd），\$LFS=/mnt/lfs（loop 挂载的镜像根分区）"
  echo
} > "$LOG"

"$LFS_ROOT/scripts/lfs-container.sh" exec-lfs \
  'bash /workspace/scripts/pkg/6.6-diffutils.sh' >> "$LOG" 2>&1
rc=$?

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc"
exit $rc
