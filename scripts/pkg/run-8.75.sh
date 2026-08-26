#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT=/root/lfs; LOG=$LFS_ROOT/logs/packages/8.75-vim-9.2.0078.log; CONTAINER=${CONTAINER:-lfs-build}; mkdir -p "$LFS_ROOT/logs/packages"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.75-vim.sh >> "$LOG" 2>&1; rc=$?; fi
echo "##### 最终退出码：$rc" >> "$LOG"; exit "$rc"
