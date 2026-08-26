#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.24 MPC-1.3.1，完整输出落到
# logs/packages/8.24-mpc-1.3.1.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.24-mpc-1.3.1.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.24 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.24；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.24 MPC-1.3.1"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.23 MPFR-4.2.2 已完成（日志 8.23-mpfr-4.2.2.*），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认（MPC 直接建在 MPFR 之上）；"
  echo "#####   §8.22 GMP-6.3.0 的产物在第 2 项中确认。"
  echo "##### 手册原文快照：docs/book/chapter08-mpc.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/mpc.html 抓取）"
  echo "##### 本节命令序列（手册 §8.24.1 全部 6 条）："
  echo "#####   ./configure --prefix=/usr    \\"
  echo "#####               --disable-static \\"
  echo "#####               --docdir=/usr/share/doc/mpc-1.3.1"
  echo "#####   make"
  echo "#####   make html"
  echo "#####   make check"
  echo "#####   make install"
  echo "#####   make install-html"
  echo "##### 本节没有 sed、没有补丁、也没有 mkdir build —— MPC 按手册在源码目录内"
  echo "#####   直接 configure（in-tree build）。"
  echo "##### 提示框：本节**一个都没有**（无 Note / Important / Caution / Warning）。"
  echo "##### 判据：手册对测试的全部原文只有一句「To test the results, issue: make check」，"
  echo "#####   既没有 §8.23 MPFR 那样的 critical Important，也**没有给出任何数字**。"
  echo "#####   因此除「make check 退出码为 0」直接来自手册外，TOTAL/PASS 的数字判据"
  echo "#####   均为本项目自加，取自开工前的完整试建实测（见下）。"
  echo "##### 自检断言的校准方式：本包只有 0.1 SBU / 22 MB，故在正式开工前先在 chroot 的"
  echo "#####   /tmp 里做了一次**完整**试建（configure + make + make html + make check +"
  echo "#####   make DESTDIR=/tmp/mpc-dest install install-html，不写系统），把本脚本的"
  echo "#####   每一条自检断言在试建产物上逐条验过后才重新开工，试建目录随后已删除。"
  echo "#####   校准的结论里有三条与紧邻的 §8.23 MPFR **正好相反**，照抄上一节必然扑空："
  echo "#####     - MPC **有** config.h（configure.ac 第 26 行 AC_CONFIG_HEADERS([config.h])），"
  echo "#####       而 MPFR 那一行是被 dnl 注释掉的。所以本节 src/Makefile 的 DEFS 只有"
  echo "#####       -DHAVE_CONFIG_H，探测结论（如 HAVE_COMPLEX_H）要去 config.h 里看；"
  echo "#####     - MPC **不装** pkg-config 文件 —— 源码树里没有 mpc.pc/.pc.in，而 §8.22 GMP"
  echo "#####       与 §8.23 MPFR 都装 .pc。去查 /usr/lib/pkgconfig/mpc.pc 必然扑空，"
  echo "#####       本脚本据此把它写成「确认不存在」而不是「确认存在」；"
  echo "#####     - config.status 里的 ac_cs_config 格式不同：本包是"
  echo "#####       ac_cs_config=\"'--prefix=/usr' '--disable-static' '--docdir=…'\""
  echo "#####       （双引号包外层、各选项各自单引号），MPFR 是单引号整串，取值 sed 不通用。"
  echo "#####   其余校准落点（都不是猜的）："
  echo "#####     - 库实体是 libmpc.so.3.3.1、SONAME libmpc.so.3 —— 来自 src/Makefile.am 的"
  echo "#####       libtool '-version-info 6:1:3'（CURRENT-AGE = 6-3 = 3），**不是**包版本号 1.3.1；"
  echo "#####     - make html 产出的是目录 doc/mpc.html/（27 个文件，入口 index.html），"
  echo "#####       不是单个文件，故 find/ls 必须按目录处理；"
  echo "#####     - 安装产物只有 5 个文件/链接（/usr/include/mpc.h、/usr/lib/libmpc.la、"
  echo "#####       libmpc.so、libmpc.so.3、libmpc.so.3.3.1）+ /usr/share/info/mpc.info"
  echo "#####       + docdir 下 27 个 HTML；docdir 里**只有** mpc.html/ 一个子目录，"
  echo "#####       AUTHORS/NEWS/COPYING.LESSER 不会被装进去（MPC 的 Makefile.am 无 doc_DATA），"
  echo "#####       这点也与 §8.23 MPFR 不同，故写成 INFO 而非 FAIL；"
  echo "#####     - doc/mpc.info 是 tarball 里自带的预生成文件，不由 make html 产出；"
  echo "#####     - 功能断言里 sqrt(i)/exp(i) 的 40 位小数直接取试建产物的实测输出"
  echo "#####       （0.7071067811865475244008443621048490392848 等），不从数学表抄，"
  echo "#####       因此不存在末位进位歧义；"
  echo "#####     - 试建的 make check 实测 TOTAL=74 PASS=74 SKIP=0 FAIL=0，"
  echo "#####       故 TOTAL/PASS 写成 =74 的硬判据（手册本身未给数字）；"
  echo "#####     - 本包的 tarball 是 .tar.gz（不是 .tar.xz），前置检查里查的是 gzip。"
  echo "##### 另按本项目既往教训（logs/host/ 与 memory 中的 pipefail 记录）："
  echo "#####   脚本中所有只为截断显示的 head 都已换成 sed -n '1,Np'，所有用于展示的"
  echo "#####   grep/diff/ls/find 都包成 { ... || true; }，避免 SIGPIPE/非零退出在 pipefail 下误判。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.24-mpc.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".mpc-configure.log:8.24-mpc-1.3.1.configure.log" \
            ".mpc-make.log:8.24-mpc-1.3.1.make.log" \
            ".mpc-make-html.log:8.24-mpc-1.3.1.make-html.log" \
            ".mpc-make-check.log:8.24-mpc-1.3.1.check.log" \
            ".mpc-make-install.log:8.24-mpc-1.3.1.install.log" \
            ".mpc-make-install-html.log:8.24-mpc-1.3.1.install-html.log" \
            ".mpc-test-summary.log:8.24-mpc-1.3.1.tests.summary"; do
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
