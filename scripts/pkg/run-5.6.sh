#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内以 lfs 用户执行 §5.6，完整输出落到日志。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/5.6-libstdc-from-gcc-15.2.0.log

{
  echo "##### LFS 13.0-systemd §5.6 Libstdc++ from GCC-15.2.0"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：lfs-build（镜像 lfs-build:13.0-systemd），\$LFS=/mnt/lfs（loop 挂载的镜像根分区）"
  echo
} > "$LOG"

"$LFS_ROOT/scripts/lfs-container.sh" exec-lfs \
  'bash /workspace/scripts/pkg/5.6-libstdcpp.sh' >> "$LOG" 2>&1
rc=$?

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc"
exit $rc
