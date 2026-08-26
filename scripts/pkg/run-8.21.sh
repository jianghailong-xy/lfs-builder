#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.21 Binutils-2.46.0，完整输出落到
# logs/packages/8.21-binutils-2.46.0.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.21-binutils-2.46.0.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.21 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.21；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.21 Binutils-2.46.0"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.20 Pkgconf-2.5.1 已完成（日志 8.20-pkgconf-2.5.1.*），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-binutils.html"
  echo "##### 本节命令序列（手册 §8.21.1 全部 7 条命令）："
  echo "#####   mkdir -v build"
  echo "#####   cd       build"
  echo "#####   ../configure --prefix=/usr       \\"
  echo "#####                --sysconfdir=/etc   \\"
  echo "#####                --enable-ld=default \\"
  echo "#####                --enable-plugins    \\"
  echo "#####                --enable-shared     \\"
  echo "#####                --disable-werror    \\"
  echo "#####                --enable-64-bit-bfd \\"
  echo "#####                --enable-new-dtags  \\"
  echo "#####                --with-system-zlib  \\"
  echo "#####                --enable-default-hash-style=gnu"
  echo "#####   make tooldir=/usr"
  echo "#####   make -k check"
  echo "#####   grep '^FAIL:' \$(find -name '*.log')"
  echo "#####   make tooldir=/usr install"
  echo "#####   rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \\"
  echo "#####           /usr/share/doc/gprofng/"
  echo "##### 测试：手册 §8.21 有唯一的 Important 提示框 ——「The test suite for Binutils"
  echo "#####   in this section is considered critical. Do not skip it under any"
  echo "#####   circumstances.」，因此 make -k check 必跑。手册同时给出允许的例外："
  echo "#####   「One test related to gprofng is known to fail.」"
  echo "#####   判据不用 make 的退出码（-k 下非 0 属预期），而用 DejaGNU 自己的 *.sum"
  echo "#####   汇总计数，并要求「非 gprofng 的 FAIL 数为 0」。"
  echo "##### 自检断言的校准方式：本包 1.7 SBU / 835 MB，做一次 /tmp 试建代价过高；"
  echo "#####   改为拿系统里**已安装的同版本** §6.17 binutils-pass2（同为 2.46.0）把全部"
  echo "#####   功能断言先跑了一遍，据此纠正了 3 处："
  echo "#####     a) 版本自述是 \"2.46.0.20260210\" 而非 \"2.46.0\"，断言必须用子串包含；"
  echo "#####     b) ld/ar/nm 的 --plugin 在未加 --enable-plugins 时也存在，不能当"
  echo "#####        --enable-plugins 的判据 —— 改用 bfd/config.h 的"
  echo "#####        \"#define BFD_SUPPORTS_PLUGINS 1\" 作硬判据；"
  echo "#####     c) 手册 §8.21.2 Contents 里的 dwp 在 2.46.0 中不存在（tar -t 确认源码包"
  echo "#####        已无 gold/ 子目录），故不把它写成硬性断言，而是在日志里给出证据说明。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.21-binutils.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".binutils-configure.log:8.21-binutils-2.46.0.configure.log" \
            ".binutils-make.log:8.21-binutils-2.46.0.make.log" \
            ".binutils-make-check.log:8.21-binutils-2.46.0.check.log" \
            ".binutils-make-install.log:8.21-binutils-2.46.0.install.log" \
            ".binutils-test-summary.log:8.21-binutils-2.46.0.tests.summary"; do
  src=$LFS_ROOT/sources/${pair%%:*}
  dst=$LFS_ROOT/logs/packages/${pair#*:}
  if [ -f "$src" ]; then
    mv -f "$src" "$dst"
    echo "##### 留档：logs/packages/$(basename "$dst")" >> "$LOG"
  fi
done

# DejaGNU 的 .sum 原件（每个测试套件一份）
for f in "$LFS_ROOT"/sources/.binutils-sum-*.sum; do
  [ -e "$f" ] || continue
  base=$(basename "$f"); base=${base#.binutils-sum-}; base=${base%.sum}
  mv -f "$f" "$LFS_ROOT/logs/packages/8.21-binutils-2.46.0.$base.sum"
  echo "##### 留档：logs/packages/8.21-binutils-2.46.0.$base.sum" >> "$LOG"
done

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc（日志：$LOG）"
exit $rc
