#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.26 Acl-2.3.2，完整输出落到
# logs/packages/8.26-acl-2.3.2.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.26-acl-2.3.2.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.26 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.26；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.26 Acl-2.3.2"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.25 Attr-2.5.2 已完成（日志 8.25-attr-2.5.2.*）。与前几节不同，"
  echo "#####   本节**真的依赖**上一节：POSIX ACL 在内核里就是 system.posix_acl_access/"
  echo "#####   default 两个扩展属性，libacl 经 libattr 读写它们，configure 也要靠"
  echo "#####   libattr.pc 找到它。故下方「前置检查」第 1 项不只看文件在不在，还用"
  echo "#####   -lattr 链接并运行了一个最小程序。"
  echo "##### 手册原文快照：docs/book/chapter08-acl.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/acl.html 抓取）"
  echo "##### 本节命令序列（手册 §8.26.1 全部 4 条）："
  echo "#####   ./configure --prefix=/usr    \\"
  echo "#####               --disable-static \\"
  echo "#####               --docdir=/usr/share/doc/acl-2.3.2"
  echo "#####   make"
  echo "#####   make check"
  echo "#####   make install"
  echo "##### 本节没有 sed、没有补丁、没有 mkdir build（in-tree build），也没有"
  echo "#####   make html / make install-html。与紧邻的 §8.25 Attr 相比少一个"
  echo "#####   --sysconfdir=/etc（Acl 不装任何 /etc 下的文件），故只有 3 个选项。"
  echo "##### 提示框：本节有**一个 Note** ——"
  echo "#####   「One test named test/cp.test is known to fail because Coreutils is not"
  echo "#####     built with the Acl support yet.」"
  echo "#####   它直接决定测试判定方式：既然手册明说有一项已知失败，make check 必然以"
  echo "#####   非零退出码结束，**退出码不能作判据**，判据是「失败项有且只有 test/cp」。"
  echo "##### 手册正文另有前置条件：「The Acl tests must be run on a filesystem that"
  echo "#####   supports access controls.」故脚本在开工前直接往构建目录所在的 /sources"
  echo "#####   写入并读回一条真实的 POSIX ACL（此刻 setfacl 还没有，用上一节装好的"
  echo "#####   setfattr/getfattr 按内核 xattr 格式手工构造 system.posix_acl_access，"
  echo "#####   写后以 ls -l 出现 '+' 为准）。"
  echo "##### 自检断言的校准方式：本包只有 <0.1 SBU / 6.5 MB，故正式开工前先在 chroot 的"
  echo "#####   /tmp 里做了一次**完整**试建（configure + make + make check +"
  echo "#####   make DESTDIR=/tmp/acl-trial/dest install，不写系统），把本脚本每一条自检"
  echo "#####   断言在试建产物上逐条验过后才重新开工，试建目录随后已删除。"
  echo "#####   校准结论里几条照抄 §8.25 必然扑空的点："
  echo "#####     - 共享库实体是 libacl.so.1.1.2302、SONAME libacl.so.1。三段数字都不是"
  echo "#####       包版本：libacl/Makemodule.am 里 LT_CURRENT=2、LT_AGE=1，LT_REVISION"
  echo "#####       由 configure.ac 用 printf \"%d%d%02d\" 2 3 2 算成 2302，"
  echo "#####       -version-info 2:2302:1 → 主号 = CURRENT-AGE = 1，实体名 1.1.2302；"
  echo "#####     - 头文件装到**两个**地方：/usr/include/acl/libacl.h 与"
  echo "#####       /usr/include/sys/acl.h，手册 Contents 只列了目录 /usr/include/acl；"
  echo "#####     - 本节装 pkg-config 文件 libacl.pc；"
  echo "#####     - 测试共 15 项 = Makefile 里 TESTS 13 项 + XFAIL_TESTS 2 项"
  echo "#####       （test/nfs/nfsacl.test 与 test/nfs/nfs-dir.test 明写为预期失败）；"
  echo "#####       试建实测 TOTAL=15 PASS=8 FAIL=1(test/cp) SKIP=4 XFAIL=2 XPASS=0 ERROR=0；"
  echo "#####     - test/root/ 下 4 项**永远** SKIP（exit 77），原因与「是不是 root」无关："
  echo "#####       测试由 test/runwrapper 预载 .libs/libtestlookup.so 接管 getpwnam 等，"
  echo "#####       该库的 getpwnam_r 在 buflen<170000 时**故意**返回 ERANGE（考验调用方"
  echo "#####       是否扩大缓冲区重试），而同库的 getpwnam() 包装只给 16384 字节静态缓冲区，"
  echo "#####       于是预载后 getpwnam(\"root\") 恒为 NULL，test/run 的 su() 报"
  echo "#####       \"su: user root does not exist\"，require_root 随即 exit 77。这是上游"
  echo "#####       测试套件的固有行为，在任何系统上都一样，不是本环境缺陷"
  echo "#####       （本环境此刻确实也没有 su —— §7.8 util-linux 带 --disable-su，"
  echo "#####        Shadow 要到 §8.36 才装，但那不是这 4 项 SKIP 的原因）；"
  echo "#####     - 测试日志开头的 \"Possible precedence issue with control flow operator"
  echo "#####       (exit) at ./test/run line 147\" 是 test/run 这个 perl 脚本自身的写法"
  echo "#####       告警，不是测试失败；"
  echo "#####     - 本包 tarball 是 .tar.xz（上一节 attr 是 .tar.gz），前置检查里查 xz。"
  echo "##### 另按本项目既往教训（logs/host/ 与 memory 中的 pipefail 记录）："
  echo "#####   脚本中所有只为截断显示的 head 都已换成 tail -n N <文件> 或 sed -n '1,Np'，"
  echo "#####   所有用于展示的 grep/ls/find 都包成 { ... || true; }，避免 SIGPIPE/非零退出"
  echo "#####   在 pipefail 下误判；for 循环里也不用 '[ ] && cmd' 作最后一条命令。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.26-acl.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".acl-configure.log:8.26-acl-2.3.2.configure.log" \
            ".acl-make.log:8.26-acl-2.3.2.make.log" \
            ".acl-make-check.log:8.26-acl-2.3.2.check.log" \
            ".acl-make-install.log:8.26-acl-2.3.2.install.log" \
            ".acl-test-suite.log:8.26-acl-2.3.2.test-suite.log" \
            ".acl-test-summary.log:8.26-acl-2.3.2.tests.summary"; do
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
