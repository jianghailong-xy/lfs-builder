#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.10 Zstd-1.5.7，完整输出落到
# logs/packages/8.10-zstd-1.5.7.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.10-zstd-1.5.7.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载）"
{
  echo "##### chroot 准备（§8.10 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.10；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.10 Zstd-1.5.7"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.9 Lz4-1.10.0 已完成（日志 8.9-lz4-1.10.0.log），其产物在"
  echo "#####   下方「前置检查」中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-zstd.html"
  echo "##### 本节无 configure、无补丁、无 sed 改写；命令序列共 4 条："
  echo "#####   make prefix=/usr"
  echo "#####   make check"
  echo "#####   make prefix=/usr install"
  echo "#####   rm -v /usr/lib/libzstd.a"
  echo "##### 测试：本节有 make check（= tests/Makefile 的 test-zstd，即 shell 驱动的"
  echo "#####   tests/playTests.sh，无 automake 汇总）。手册 Note：输出中多处出现的"
  echo "#####   'failed' 是预期的，只有 'FAIL' 才是真正的测试失败，且不应有任何失败。"
  echo "#####   故判定标准是：make 退出码 0 + 出现收尾横幅 All tests completed"
  echo "#####   successfully + 输出中无大写 FAIL。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.10-zstd.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 make check 的完整输出留在 /sources（= 宿主 sources/），
# 这里把它移进 logs/packages 作为测试留档，避免污染源码目录。
CHECK_SRC=$LFS_ROOT/sources/.zstd-make-check.log
CHECK_DST=$LFS_ROOT/logs/packages/8.10-zstd-1.5.7.check.log
if [ -f "$CHECK_SRC" ]; then
  mv -f "$CHECK_SRC" "$CHECK_DST"
  echo "##### make check 完整输出留档：logs/packages/$(basename "$CHECK_DST")" >> "$LOG"
fi

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc（日志：$LOG）"
exit $rc
