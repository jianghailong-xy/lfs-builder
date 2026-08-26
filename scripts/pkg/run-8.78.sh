#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.78-systemd-259.1.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"
PHASE=${1:-buildtest}
mkdir -p "$LFS_ROOT/logs/packages"

{
  if [ -s "$LOG" ]; then
    echo
    echo "##### 阶段/重试分隔：保留此前完整输出，追加本次执行：$(date -Is)"
  fi
  echo "##### LFS 13.0-systemd §8.78 Systemd-259.1；阶段：$PHASE"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 完整输出；容器：$CONTAINER；chroot 根：/mnt/lfs"
  echo
  echo "===== chroot 环境准备 ====="
} >> "$LOG"

docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  case "$PHASE" in
    buildtest) target=/workspace/scripts/pkg/8.78-systemd.sh ;;
    retest-format-table) target=/workspace/scripts/pkg/8.78-retest-format-table.sh ;;
    install) target=/workspace/scripts/pkg/8.78-install.sh ;;
    *) echo "未知阶段：$PHASE" >> "$LOG"; exit 2 ;;
  esac
  docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run "$target" >> "$LOG" 2>&1
  rc=$?
fi
echo "##### 阶段 $PHASE 退出码：$rc" >> "$LOG"

# The book permits test-namespace to fail in chroot.  test-format-table also
# fails under the book's POSIX locale but must pass under C.UTF-8.  For the
# normal chapter runner, accept only that exact two-failure summary, rerun the
# locale-sensitive test, and then install.  Any additional failure still stops.
if [ "$PHASE" = buildtest ] && [ "$rc" -ne 0 ]; then
  failures=$(sed -n '/^Summary of Failures:/,/^Ok:/p' "$LOG" | tail -n 20 | grep ' FAIL ' || true)
  if [ "$(printf '%s\n' "$failures" | grep -c .)" -eq 2 ] \
     && printf '%s\n' "$failures" | grep -q 'systemd:test-namespace' \
     && printf '%s\n' "$failures" | grep -q 'systemd:test-format-table'; then
    CONTAINER="$CONTAINER" bash "$0" retest-format-table || exit $?
    CONTAINER="$CONTAINER" bash "$0" install || exit $?
    rc=0
  fi
fi
exit "$rc"
