#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.11 File-5.46，完整输出落到
# logs/packages/8.11-file-5.46.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.11-file-5.46.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载）"
{
  echo "##### chroot 准备（§8.11 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.11；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.11 File-5.46"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.10 Zstd-1.5.7 已完成（日志 8.10-zstd-1.5.7.log），其产物在"
  echo "#####   下方「前置检查」中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-file.html"
  echo "##### 本节无补丁、无 sed 改写；命令序列共 4 条："
  echo "#####   ./configure --prefix=/usr"
  echo "#####   make"
  echo "#####   make check"
  echo "#####   make install"
  echo "##### 测试：本节有 make check（= tests/Makefile.am 的 check-local，一个 set -e 的"
  echo "#####   shell 循环，对 tests/*.testfile 逐个跑 ./test 与 .result 比对；不是"
  echo "#####   automake 的 TESTS 机制，故无 '# TOTAL:/# PASS:/# FAIL:' 汇总行）。"
  echo "#####   手册本节没有任何关于测试结果的 Note/Caution，即要求全部通过。判定标准："
  echo "#####   make 退出码 0 + 输出里 'Running test:' 行数 == tests/*.testfile 个数。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.11-file.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / make check 的完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".file-configure.log:8.11-file-5.46.configure.log" \
            ".file-make-check.log:8.11-file-5.46.check.log"; do
  src=$LFS_ROOT/sources/${pair%%:*}
  dst=$LFS_ROOT/logs/packages/${pair#*:}
  if [ -f "$src" ]; then
    mv -f "$src" "$dst"
    echo "##### 留档：logs/packages/$(basename "$dst")" >> "$LOG"
  fi
done

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc（日志：$LOG）"
exit $rc
