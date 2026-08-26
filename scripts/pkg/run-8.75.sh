#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"; LOG=$LFS_ROOT/logs/packages/8.75-vim-9.2.0078.log; CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"; mkdir -p "$LFS_ROOT/logs/packages"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1; rc=$?
# Vim's terminal/FIFO tests require both a real PTY and the container's PID
# namespace (so /proc/self/fd describes the test process).  docker exec already
# enters that namespace; -t supplies the missing PTY while output is still kept
# in the package log.
if [ "$rc" -eq 0 ]; then docker exec -t "$CONTAINER" bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.75-vim.sh >> "$LOG" 2>&1; rc=$?; fi
echo "##### 最终退出码：$rc" >> "$LOG"; exit "$rc"
