#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.20 Pkgconf-2.5.1，完整输出落到
# logs/packages/8.20-pkgconf-2.5.1.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.20-pkgconf-2.5.1.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.20 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.20；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.20 Pkgconf-2.5.1"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.19 DejaGNU-1.6.3 已完成（日志 8.19-dejagnu-1.6.3.*），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-pkgconf.html"
  echo "##### 本节命令序列（手册 §8.20.1 全部命令）："
  echo "#####   ./configure --prefix=/usr    \\"
  echo "#####               --disable-static \\"
  echo "#####               --docdir=/usr/share/doc/pkgconf-2.5.1"
  echo "#####   make"
  echo "#####   make install"
  echo "#####   ln -sv pkgconf   /usr/bin/pkg-config"
  echo "#####   ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1"
  echo "##### 测试：手册 §8.20 全节**没有**测试命令（不含 \"To test the results\" 一句）。"
  echo "#####   上游 Makefile.am 的 check 目标依赖 kyua 测试框架，LFS 不安装 kyua，"
  echo "#####   故本节按手册「无测试」处理，改以安装后功能验证（对照 §8.20.2 Contents）覆盖。"
  echo "##### 自检断言已先在 chroot 的 /tmp 里做过一次完整试建（configure/make/"
  echo "#####   make DESTDIR=… install）校准，纠正了 3 处：pkgconf --cflags/--libs 的"
  echo "#####   实际输出顺序，以及 libpkgconf 的 client 必须用 pkgconf_client_new()"
  echo "#####   而非栈上 pkgconf_client_init()（后者会段错误）。试建目录已删除。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.20-pkgconf.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / make / make install 的完整输出留在 /sources
# （= 宿主 sources/），这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".pkgconf-configure.log:8.20-pkgconf-2.5.1.configure.log" \
            ".pkgconf-make.log:8.20-pkgconf-2.5.1.make.log" \
            ".pkgconf-make-install.log:8.20-pkgconf-2.5.1.install.log"; do
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
