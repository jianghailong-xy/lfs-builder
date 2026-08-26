#!/usr/bin/env bash
set -euo pipefail

LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}" 
LOGS="$LFS_ROOT/logs/packages"
mkdir -p "$LOGS"

docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true \
  || { echo "错误：容器 $CONTAINER 未运行" >&2; exit 1; }

# chroot preparation is required after Chapter 8, but it recreates the tester
# account.  The Chapter 9 script is deliberately run after every prep so the
# finished image never retains that temporary account.
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep \
  >> "$LOGS/8.84-8.86-finalize.log" 2>&1
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run \
  /workspace/scripts/pkg/8.84-8.86-finalize.sh \
  >> "$LOGS/8.84-8.86-finalize.log" 2>&1
echo '##### 退出码：0' >> "$LOGS/8.84-8.86-finalize.log"

configure_system() {
  docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run \
    /workspace/scripts/configure-ch9-10.2.sh \
    >> "$LOGS/9.1-10.2-system-config.log" 2>&1
}

configure_system
CONTAINER="$CONTAINER" bash "$LFS_ROOT/scripts/build-packages.sh" 10
configure_system
echo '##### 退出码：0' >> "$LOGS/9.1-10.2-system-config.log"
