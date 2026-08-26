#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.15 Bc-7.0.3，完整输出落到
# logs/packages/8.15-bc-7.0.3.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.15-bc-7.0.3.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载）"
{
  echo "##### chroot 准备（§8.15 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.15；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.15 Bc-7.0.3"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.14 M4-1.4.21 已完成（日志 8.14-m4-1.4.21.log），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-bc.html"
  echo "##### 本节命令序列共 4 条，无 sed、无 patch、无可选命令："
  echo "#####   CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r"
  echo "#####   make"
  echo "#####   make test"
  echo "#####   make install"
  echo "##### 测试：手册原文 —— To test bc, run: make test（本节无任何关于允许失败的"
  echo "#####   Note/Caution，故判定标准是全部通过：退出码 0 且 bc/dc 两套测试都打印"
  echo "#####   'All <x> tests passed.'）。手册的 -G 选项本身就会跳过一部分用例"
  echo "#####   （Omit parts of the test suite that won't work until the bc program"
  echo "#####   has been installed），这些 'Skipping ...' 属手册规定的正常结果，"
  echo "#####   在日志的「make test 结论」一节逐条列出。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.15-bc.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / make / make test / make install 的完整输出留在 /sources
# （= 宿主 sources/），这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".bc-configure.log:8.15-bc-7.0.3.configure.log" \
            ".bc-make.log:8.15-bc-7.0.3.make.log" \
            ".bc-make-test.log:8.15-bc-7.0.3.test.log" \
            ".bc-make-install.log:8.15-bc-7.0.3.install.log"; do
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
