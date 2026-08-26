#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.16 Flex-2.6.4，完整输出落到
# logs/packages/8.16-flex-2.6.4.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.16-flex-2.6.4.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载）"
{
  echo "##### chroot 准备（§8.16 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.16；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.16 Flex-2.6.4"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.15 Bc-7.0.3 已完成（日志 8.15-bc-7.0.3.log），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-flex.html"
  echo "##### 本节命令序列共 6 条，无 sed、无 patch、无可选命令："
  echo "#####   ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/flex-2.6.4"
  echo "#####   make"
  echo "#####   make check"
  echo "#####   make install"
  echo "#####   ln -sv flex   /usr/bin/lex"
  echo "#####   ln -sv flex.1 /usr/share/man/man1/lex.1"
  echo "##### 测试：手册原文 —— To test the results, issue: make check（本节无任何关于"
  echo "#####   允许失败的 Note/Caution，故判定标准是全部通过：退出码 0 且 automake 的"
  echo "#####   测试汇总满足 '# FAIL: 0'、'# ERROR: 0'、'# XPASS: 0'、PASS == TOTAL）。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.16-flex.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / make / make check / make install 的完整输出留在 /sources
# （= 宿主 sources/），这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".flex-configure.log:8.16-flex-2.6.4.configure.log" \
            ".flex-make.log:8.16-flex-2.6.4.make.log" \
            ".flex-make-check.log:8.16-flex-2.6.4.check.log" \
            ".flex-make-install.log:8.16-flex-2.6.4.install.log"; do
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
