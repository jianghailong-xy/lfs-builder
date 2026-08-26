#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.13 Pcre2-10.47，完整输出落到
# logs/packages/8.13-pcre2-10.47.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.13-pcre2-10.47.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载）"
{
  echo "##### chroot 准备（§8.13 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.13；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.13 Pcre2-10.47"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.12 Readline-8.3 已完成（日志 8.12-readline-8.3.log），其产物在"
  echo "#####   下方「前置检查」中逐项确认（本节的 --enable-pcre2test-libreadline 直接依赖它）。"
  echo "##### 手册原文快照：docs/book/chapter08-pcre2.html"
  echo "##### 本节命令序列共 4 条，无 sed、无 patch、无可选命令："
  echo "#####   ./configure --prefix=/usr --docdir=/usr/share/doc/pcre2-10.47 \\"
  echo "#####               --enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 \\"
  echo "#####               --enable-pcre2grep-libz --enable-pcre2grep-libbz2 \\"
  echo "#####               --enable-pcre2test-libreadline --disable-static"
  echo "#####   make"
  echo "#####   make check"
  echo "#####   make install"
  echo "##### 测试：手册原文 —— To test the results, issue: make check（本节无任何"
  echo "#####   关于允许失败的 Note/Caution，故判定标准是全部通过）。结论记在日志的"
  echo "#####   「make check 结论」一节。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.13-pcre2.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / make / make check / make install 的完整输出留在 /sources
# （= 宿主 sources/），这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".pcre2-configure.log:8.13-pcre2-10.47.configure.log" \
            ".pcre2-make.log:8.13-pcre2-10.47.make.log" \
            ".pcre2-make-check.log:8.13-pcre2-10.47.check.log" \
            ".pcre2-make-install.log:8.13-pcre2-10.47.install.log"; do
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
