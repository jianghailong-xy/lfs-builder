#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.23 MPFR-4.2.2，完整输出落到
# logs/packages/8.23-mpfr-4.2.2.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.23-mpfr-4.2.2.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.23 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.23；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.23 MPFR-4.2.2"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.22 GMP-6.3.0 已完成（日志 8.22-gmp-6.3.0.*），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认（MPFR 是 GMP 的直接使用者）。"
  echo "##### 手册原文快照：docs/book/chapter08-mpfr.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/mpfr.html 抓取）"
  echo "##### 本节命令序列（手册 §8.23.1 全部 6 条）："
  echo "#####   ./configure --prefix=/usr        \\"
  echo "#####               --disable-static     \\"
  echo "#####               --enable-thread-safe \\"
  echo "#####               --docdir=/usr/share/doc/mpfr-4.2.2"
  echo "#####   make"
  echo "#####   make html"
  echo "#####   make check"
  echo "#####   make install"
  echo "#####   make install-html"
  echo "##### 本节没有 sed、没有补丁、也没有 mkdir build —— MPFR 按手册在源码目录内"
  echo "#####   直接 configure（in-tree build）。"
  echo "##### 提示框只有 1 个："
  echo "#####   Important  The test suite for MPFR in this section is considered critical."
  echo "#####              Do not skip it under any circumstances. —— make check 必跑。"
  echo "##### 判据：手册给出的量化标准是「Test the results and ensure that all 198 tests"
  echo "#####   passed」，用 automake 汇总块的 '# TOTAL:' / '# PASS:' 核对；"
  echo "#####   另加 make check 退出码为 0、FAIL/XPASS/ERROR 全为 0、各项之和 = TOTAL"
  echo "#####   作为一致性互校。"
  echo "##### 自检断言的校准方式：本包只有 0.2 SBU / 43 MB，故在正式开工前先在 chroot 的"
  echo "#####   /tmp 里做了一次**完整**试建（configure + make + make html + make check +"
  echo "#####   make DESTDIR=/tmp/mpfr-dest install install-html，不写系统），把本脚本的"
  echo "#####   每一条自检断言在试建产物上逐条验过后才重新开工，试建目录随后已删除。"
  echo "#####   校准据此定下了这些落点（都不是猜的）："
  echo "#####     - 本包**没有 config.h** —— configure.ac 第 93 行的 AC_CONFIG_HEADERS 被"
  echo "#####       dnl 注释掉了，所有 -D 宏进入生成 Makefile 的 DEFS 变量。因此"
  echo "#####       --enable-thread-safe 的核对点是 src/Makefile 的 DEFS 里的"
  echo "#####       -DMPFR_USE_THREAD_SAFE=1 / -DMPFR_USE_C11_THREAD_SAFE=1，去找 config.h 必然扑空；"
  echo "#####     - --enable-thread-safe 做三重核对：configure 日志的"
  echo "#####       'checking for TLS support using C11... yes' + 上面的 DEFS +"
  echo "#####       运行期 mpfr_buildopt_tls_p()==1（另有测试套件 tversion 打印的 'TLS = yes' 佐证）；"
  echo "#####     - --disable-static 的硬判据仍是生成的 libtool 里**首个** build_old_libs=no"
  echo "#####       （该文件里 build_old_libs 出现 3 次，第 2/3 处是另一段默认值与 case 重算），"
  echo "#####       辅以安装后无 .a、.la 里 old_library=''；"
  echo "#####     - 库实体是 libmpfr.so.6.2.2、SONAME libmpfr.so.6 —— 来自 src/Makefile.am 的"
  echo "#####       libtool '-version-info 8:2:2'（CURRENT-AGE = 8-2 = 6），**不是**包版本号 4.2.2；"
  echo "#####     - make html 产出的是目录 doc/mpfr.html/（48 个文件，入口 index.html），"
  echo "#####       不是单个文件，故 find 必须带 -type f；"
  echo "#####     - 安装产物共 7 个文件/链接 + 文档目录 62 个文件 + /usr/share/info/mpfr.info；"
  echo "#####       doc/mpfr.info 是 tarball 里自带的预生成文件，不由 make html 产出；"
  echo "#####     - 功能断言里 pi/sqrt(2)/e 的 40 位小数直接取试建产物的实测输出"
  echo "#####       （3.1415926535897932384626433832795028841972 等），不从十进制展开表抄，"
  echo "#####       因此不存在末位进位歧义；"
  echo "#####     - 试建的 make check 实测 TOTAL=198 PASS=198 SKIP=0 FAIL=0，与手册的"
  echo "#####       「all 198 tests passed」完全吻合，故 TOTAL/PASS 都可以写成 =198 的硬判据。"
  echo "##### 另按本项目既往教训（logs/host/ 与 memory 中的 pipefail 记录）："
  echo "#####   脚本中所有只为截断显示的 head 都已换成 sed -n '1,Np'，所有用于展示的"
  echo "#####   grep/diff/ls 都包成 { ... || true; }，避免 SIGPIPE/非零退出在 pipefail 下误判。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.23-mpfr.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".mpfr-configure.log:8.23-mpfr-4.2.2.configure.log" \
            ".mpfr-make.log:8.23-mpfr-4.2.2.make.log" \
            ".mpfr-make-html.log:8.23-mpfr-4.2.2.make-html.log" \
            ".mpfr-make-check.log:8.23-mpfr-4.2.2.check.log" \
            ".mpfr-make-install.log:8.23-mpfr-4.2.2.install.log" \
            ".mpfr-make-install-html.log:8.23-mpfr-4.2.2.install-html.log" \
            ".mpfr-test-summary.log:8.23-mpfr-4.2.2.tests.summary"; do
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
