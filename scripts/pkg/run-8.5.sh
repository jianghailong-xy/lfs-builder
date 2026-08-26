#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.5 Glibc-2.43，完整输出落到
# logs/packages/8.5-glibc-2.43.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.5-glibc-2.43.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载）"
{
  echo "##### chroot 准备（§8.5 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.5；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.5 Glibc-2.43"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.4 Iana-Etc-20260202 已完成（日志 8.4-iana-etc-20260202.log），"
  echo "#####   其产物在下方「前置检查」中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-glibc.html"
  echo "##### 本节含补丁（glibc-fhs-1.patch）、configure、make、make check（手册"
  echo "#####   Important：critical，不得跳过）、make install、locale 安装，以及"
  echo "#####   §8.5.2 的 nsswitch.conf / 时区数据 / 动态装载器配置。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.5-glibc.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 glibc 的 tests.sum 放在 /sources（= 宿主 sources/），
# 这里取回到 logs/packages 并让 sources/ 保持只有源码包与补丁。
if [ -f "$LFS_ROOT/sources/8.5-glibc-2.43.tests.sum" ]; then
  mv "$LFS_ROOT/sources/8.5-glibc-2.43.tests.sum" \
     "$LFS_ROOT/logs/packages/8.5-glibc-2.43.tests.sum"
  echo "测试摘要：$LFS_ROOT/logs/packages/8.5-glibc-2.43.tests.sum"
fi

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc（日志：$LOG）"
exit $rc
