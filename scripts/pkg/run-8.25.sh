#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.25 Attr-2.5.2，完整输出落到
# logs/packages/8.25-attr-2.5.2.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.25-attr-2.5.2.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.25 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.25；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.25 Attr-2.5.2"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.24 MPC-1.3.1 已完成（日志 8.24-mpc-1.3.1.*）。Attr 本身不依赖"
  echo "#####   MPC，故下方「前置检查」第 1 项查 MPC 是为了确认上一任务产物确实可用、"
  echo "#####   系统状态连续（不只看文件在不在，还用 libmpc 链接运行了一个最小程序）；"
  echo "#####   本节真正的依赖只有 glibc（xattr 系统调用封装）与 §7 章的工具链。"
  echo "##### 手册原文快照：docs/book/chapter08-attr.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/attr.html 抓取）"
  echo "##### 本节命令序列（手册 §8.25.1 全部 4 条）："
  echo "#####   ./configure --prefix=/usr     \\"
  echo "#####               --disable-static  \\"
  echo "#####               --sysconfdir=/etc \\"
  echo "#####               --docdir=/usr/share/doc/attr-2.5.2"
  echo "#####   make"
  echo "#####   make check"
  echo "#####   make install"
  echo "##### 本节没有 sed、没有补丁、没有 mkdir build（in-tree build），也**没有**"
  echo "#####   make html / make install-html —— 那两条是 §8.22 GMP / §8.23 MPFR /"
  echo "#####   §8.24 MPC 才有的，本节只有 4 条命令。"
  echo "##### 提示框：本节**一个都没有**（无 Note / Important / Caution / Warning）。"
  echo "##### 判据：手册对测试的全部原文是正文里的两句 ——"
  echo "#####   「The tests must be run on a filesystem that supports extended attributes"
  echo "#####     such as the ext2, ext3, or ext4 filesystems.」"
  echo "#####   「To test the results, issue: make check」"
  echo "#####   前一句是本节独有的**前置条件**（前三节都没有），故脚本在开工前专门用一个"
  echo "#####     直接调 setxattr/getxattr/removexattr 的 C 程序实测了 /sources 与 /tmp"
  echo "#####     两个文件系统的 user.* 扩展属性读写（此刻系统里还没有 setfattr 可用）。"
  echo "#####   后一句之外手册**没有给出任何数字**，因此除「make check 退出码为 0」直接"
  echo "#####     来自手册外，TOTAL/PASS 的数字判据均为本项目自加。"
  echo "##### 自检断言的校准方式：本包只有 <0.1 SBU / 4.1 MB，故在正式开工前先在 chroot 的"
  echo "#####   /tmp 里做了一次**完整**试建（configure + make + make check +"
  echo "#####   make DESTDIR=/tmp/attr-dest install，不写系统），把本脚本的每一条自检断言"
  echo "#####   在试建产物上逐条验过后才重新开工，试建目录随后已删除。"
  echo "#####   校准的结论里有几条与紧邻的 §8.22–§8.24 三个数学库都不同，照抄必然扑空："
  echo "#####     - 共享库实体是 libattr.so.1.1.2502、SONAME libattr.so.1。三段数字都不是"
  echo "#####       包版本 2.5.2：libattr/Makemodule.am 里 LT_CURRENT=2、LT_AGE=1，"
  echo "#####       LT_REVISION 由 configure.ac 用 printf \"%d%d%02d\" 2 5 2 算成 2502，"
  echo "#####       -version-info 2:2502:1 → 主号 = CURRENT-AGE = 1，实体名 = 1.1.2502；"
  echo "#####     - 本节**有** --sysconfdir=/etc（前三节都没有），它唯一的落点是"
  echo "#####       Makefile.am 的 dist_sysconf_DATA = xattr.conf，故「该选项是否生效」的"
  echo "#####       可观测判据就是 /etc/xattr.conf 装出来、且 /usr/etc/xattr.conf 不存在；"
  echo "#####     - 本节**装** pkg-config 文件 libattr.pc（与 §8.24 MPC 相反，与 GMP/MPFR"
  echo "#####       相同），下一节 §8.26 Acl 的 configure 要靠它找 libattr；"
  echo "#####     - 源码树里的 include/attr 是 configure 用 AC_CONFIG_COMMANDS 建的**符号"
  echo "#####       链接**，而装到系统的 /usr/include/attr 是**真目录**（3 个头文件），"
  echo "#####       检查时要区分这两者；"
  echo "#####     - make check 的 TESTS 只有 2 项（test/Makemodule.am 里明写 test/attr.test"
  echo "#####       与 test/root/getfattr.test），试建实测 TOTAL=2 PASS=2 SKIP=0 FAIL=0，"
  echo "#####       故 TOTAL/PASS 写成 =2 的硬判据，且 SKIP 也写成 =0 —— 本包唯一会导致"
  echo "#####       跳过的原因就是文件系统不支持 xattr，跳过即等于测试没真跑；"
  echo "#####     - 测试日志开头的 \"Possible precedence issue with control flow operator"
  echo "#####       (exit) at ./test/run line 150\" 是 test/run 这个 perl 脚本自身的写法"
  echo "#####       告警，不是测试失败，automake 也不据此判定结果；"
  echo "#####     - attributes.h 里 attr_get/attr_set/attr_list/attr_remove 全部带"
  echo "#####       __attribute__((deprecated))，功能验证程序编译时必然出 deprecated 告警，"
  echo "#####       属预期，故脚本只对「非 deprecated 告警」作提示；"
  echo "#####     - 本包的 tarball 是 .tar.gz（不是 .tar.xz），前置检查里查的是 gzip；"
  echo "#####     - make check 由 perl 写的 test/run 驱动（TEST_LOG_COMPILER），故 perl"
  echo "#####       是本节硬依赖；po/ 下 10 种语言的 .mo 由 §7.7 装的 msgfmt 生成。"
  echo "##### 另按本项目既往教训（logs/host/ 与 memory 中的 pipefail 记录）："
  echo "#####   脚本中所有只为截断显示的 head 都已换成 sed -n '1,Np'，所有用于展示的"
  echo "#####   grep/diff/ls/find 都包成 { ... || true; }，grep -q 前先把内容取进变量，"
  echo "#####   避免 SIGPIPE/非零退出在 pipefail 下误判。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.25-attr.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".attr-configure.log:8.25-attr-2.5.2.configure.log" \
            ".attr-make.log:8.25-attr-2.5.2.make.log" \
            ".attr-make-check.log:8.25-attr-2.5.2.check.log" \
            ".attr-make-install.log:8.25-attr-2.5.2.install.log" \
            ".attr-test-summary.log:8.25-attr-2.5.2.tests.summary"; do
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
