#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.18 Expect-5.45.4，完整输出落到
# logs/packages/8.18-expect-5.45.4.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.18-expect-5.45.4.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载。§8.18 对 devpts 的"
echo "  挂载尤其敏感 —— 手册在本节开头专门要求先验证 chroot 内 PTY 可用。）"
{
  echo "##### chroot 准备（§8.18 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.18；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.18 Expect-5.45.4"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.17 Tcl-8.6.17 已完成（日志 8.17-tcl-8.6.17.log），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认（本节 configure 直接读取它的"
  echo "#####   /usr/lib/tclConfig.sh 与 install-private-headers 装出的私有头）。"
  echo "##### 手册原文快照：docs/book/chapter08-expect.html"
  echo "##### 本节命令序列（手册 §8.18.1 全部命令）："
  echo "#####   python3 -c 'from pty import spawn; spawn([\"echo\", \"ok\"])'"
  echo "#####   patch -Np1 -i ../expect-5.45.4-gcc15-1.patch"
  echo "#####   ./configure --prefix=/usr           \\"
  echo "#####               --with-tcl=/usr/lib     \\"
  echo "#####               --enable-shared         \\"
  echo "#####               --disable-rpath         \\"
  echo "#####               --mandir=/usr/share/man \\"
  echo "#####               --with-tclinclude=/usr/include"
  echo "#####   make"
  echo "#####   make test"
  echo "#####   make install"
  echo "#####   ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib"
  echo "##### 测试：手册原文 —— To test the results, issue: make test"
  echo "#####   本节没有任何关于允许失败的 Note / Caution；唯一的告诫是开头那段 ——"
  echo "#####   PTY 不可用时必须先解决再继续，否则 Expect 及后续依赖它的测试套件会"
  echo "#####   \"fail catastrophically\"。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.18-expect.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / make / make test / make install 的完整输出留在 /sources
# （= 宿主 sources/），这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".expect-configure.log:8.18-expect-5.45.4.configure.log" \
            ".expect-make.log:8.18-expect-5.45.4.make.log" \
            ".expect-make-test.log:8.18-expect-5.45.4.test.log" \
            ".expect-make-install.log:8.18-expect-5.45.4.install.log"; do
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
