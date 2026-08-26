#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内以 lfs 用户执行 §5.2，完整输出落到日志。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/5.2-binutils-2.46.0-pass-1.log
mkdir -p "$LFS_ROOT/logs/packages"

{
  echo "##### LFS 13.0-systemd §5.2 Binutils-2.46.0 (Pass 1)"
  echo "##### 宿主机时间：$(date -Is)"
  echo '##### 容器内以 lfs 用户和手册 §4.4 环境执行'
  echo
} > "$LOG"

"$LFS_ROOT/scripts/lfs-container.sh" exec-lfs \
  'bash /workspace/scripts/pkg/5.2-binutils-pass1.sh' >> "$LOG" 2>&1
rc=$?
echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc"
exit "$rc"
