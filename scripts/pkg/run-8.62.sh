#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"; LOG=$LFS_ROOT/logs/packages/8.62-diffutils-3.12.log; CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"; mkdir -p "$LFS_ROOT/logs/packages"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.62-diffutils.sh >> "$LOG" 2>&1; rc=$?; fi
echo "##### 最终退出码：$rc" >> "$LOG"; exit "$rc"
