#!/usr/bin/env bash
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.51-libffi-3.5.2.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"
mkdir -p "$LFS_ROOT/logs/packages"

{
  if [ -s "$LOG" ]; then
    echo
    echo "##### 重试分隔：保留此前完整失败输出，追加本次执行：$(date -Is)"
  fi
  echo "##### LFS 13.0-systemd §8.51 Libffi-3.5.2"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 完整输出；容器：$CONTAINER；chroot 根：/mnt/lfs"
  echo "##### 官方手册：https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/libffi.html"
  echo "##### 执行前置验证、源码校验与解包、配置、编译、测试、安装、安装验证及清理"
  echo
  echo "===== chroot 环境准备 ====="
} >> "$LOG"

docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.51-libffi.sh >> "$LOG" 2>&1
  rc=$?
fi
echo "##### 最终退出码：$rc" >> "$LOG"
exit "$rc"
