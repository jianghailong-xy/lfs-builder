#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.19 DejaGNU-1.6.3，完整输出落到
# logs/packages/8.19-dejagnu-1.6.3.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.19-dejagnu-1.6.3.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载。§8.19 与 §8.18 一样"
echo "  对 devpts 敏感 —— DejaGNU 的每条用例都由 expect 经真实 PTY 驱动。）"
{
  echo "##### chroot 准备（§8.19 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.19；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.19 DejaGNU-1.6.3"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.18 Expect-5.45.4 已完成（日志 8.18-expect-5.45.4.log），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认（DejaGNU 的 runtest 就是定位 expect"
  echo "#####   解释器的包装脚本，make check 完全依赖它）。"
  echo "##### 手册原文快照：docs/book/chapter08-dejagnu.html"
  echo "##### 本节命令序列（手册 §8.19.1 全部命令）："
  echo "#####   mkdir -v build"
  echo "#####   cd       build"
  echo "#####   ../configure --prefix=/usr"
  echo "#####   makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi"
  echo "#####   makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi"
  echo "#####   make check"
  echo "#####   make install"
  echo "#####   install -v -dm755  /usr/share/doc/dejagnu-1.6.3"
  echo "#####   install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3"
  echo "##### 注：本节没有 make —— DejaGNU 是纯脚本包，唯一被编译的是测试用的"
  echo "#####   check_PROGRAMS = unit（testsuite/libdejagnu/unit.cc），由 make check 带出。"
  echo "##### 测试：手册原文 —— To test the results, issue: make check"
  echo "#####   本节没有任何关于允许失败的 Note / Caution。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.19-dejagnu.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / makeinfo / make check / make install 的完整输出，以及
# runtest 产出的 4 份 .sum，留在 /sources（= 宿主 sources/），这里把它们移进
# logs/packages 作为留档，避免污染源码目录。
for pair in ".dejagnu-configure.log:8.19-dejagnu-1.6.3.configure.log" \
            ".dejagnu-makeinfo.log:8.19-dejagnu-1.6.3.makeinfo.log" \
            ".dejagnu-make-check.log:8.19-dejagnu-1.6.3.check.log" \
            ".dejagnu-make-install.log:8.19-dejagnu-1.6.3.install.log" \
            ".dejagnu-launcher.sum:8.19-dejagnu-1.6.3.launcher.sum" \
            ".dejagnu-libdejagnu.sum:8.19-dejagnu-1.6.3.libdejagnu.sum" \
            ".dejagnu-report-card.sum:8.19-dejagnu-1.6.3.report-card.sum" \
            ".dejagnu-runtest.sum:8.19-dejagnu-1.6.3.runtest.sum"; do
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
