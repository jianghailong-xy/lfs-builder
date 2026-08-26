#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.17 Tcl-8.6.17，完整输出落到
# logs/packages/8.17-tcl-8.6.17.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.17-tcl-8.6.17.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
echo "（手册 §7.13.2 Important：进入第 8 章前须确认 \$LFS/dev、\$LFS/proc、\$LFS/sys"
echo "  等虚拟文件系统仍处于挂载状态，未挂载则按 §7.3 重新挂载）"
{
  echo "##### chroot 准备（§8.17 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.17；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.17 Tcl-8.6.17"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.16 Flex-2.6.4 已完成（日志 8.16-flex-2.6.4.log），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-tcl.html"
  echo "##### 本节命令序列（手册 §8.17.1 全部命令，含末尾标注 Optionally 的文档安装）："
  echo "#####   SRCDIR=\$(pwd)"
  echo "#####   cd unix"
  echo "#####   ./configure --prefix=/usr --mandir=/usr/share/man --disable-rpath"
  echo "#####   make"
  echo "#####   sed ... -i tclConfig.sh"
  echo "#####   sed ... -i pkgs/tdbc1.1.12/tdbcConfig.sh"
  echo "#####   sed ... -i pkgs/itcl4.3.4/itclConfig.sh"
  echo "#####   unset SRCDIR"
  echo "#####   LC_ALL=C.UTF-8 make test"
  echo "#####   make install"
  echo "#####   chmod 644 /usr/lib/libtclstub8.6.a"
  echo "#####   chmod -v u+w /usr/lib/libtcl8.6.so"
  echo "#####   make install-private-headers"
  echo "#####   ln -sfv tclsh8.6 /usr/bin/tclsh"
  echo "#####   mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3"
  echo "#####   cd .. && tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1"
  echo "#####   mkdir -v -p /usr/share/doc/tcl-8.6.17"
  echo "#####   cp -v -r ./html/* /usr/share/doc/tcl-8.6.17"
  echo "##### 测试：手册原文 —— To test the results, issue: LC_ALL=C.UTF-8 make test"
  echo "#####   本节没有任何关于允许失败的 Note / Caution。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.17-tcl.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把 configure / make / make test / make install 的完整输出留在 /sources
# （= 宿主 sources/），这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".tcl-configure.log:8.17-tcl-8.6.17.configure.log" \
            ".tcl-make.log:8.17-tcl-8.6.17.make.log" \
            ".tcl-make-test.log:8.17-tcl-8.6.17.test.log" \
            ".tcl-make-install.log:8.17-tcl-8.6.17.install.log"; do
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
