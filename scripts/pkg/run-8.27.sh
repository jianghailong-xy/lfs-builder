#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.27 Libcap-2.77，完整输出落到
# logs/packages/8.27-libcap-2.77.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.27-libcap-2.77.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.27 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.27；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.27 Libcap-2.77"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.26 Acl-2.3.2 已完成（日志 8.26-acl-2.3.2.*）。与 §8.26 不同，"
  echo "#####   本节在**构建层面并不依赖**上一节：libcap 只用内核头文件 + libc(+pthread)，"
  echo "#####   构建出的 libcap.so/libpsx.so 的 NEEDED 里只有 libc.so.6。下方「前置检查」"
  echo "#####   第 1 项仍逐项确认 §8.26 产物可用（任务书要求），但那不是编译依赖。"
  echo "##### 手册原文快照：docs/book/chapter08-libcap.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/libcap.html 抓取）"
  echo "##### 本节命令序列（手册 §8.27.1 全部 4 条）："
  echo "#####   sed -i '/install -m.*STA/d' libcap/Makefile"
  echo "#####   make prefix=/usr lib=lib"
  echo "#####   make test"
  echo "#####   make prefix=/usr lib=lib install"
  echo "##### 本节的形态与 §8.25/§8.26 差别极大，照抄那两节的写法会全线扑空："
  echo "#####   - **没有 configure**：libcap 是手写 Makefile + Make.Rules，不用 autotools。"
  echo "#####     没有 --prefix/--disable-static/--docdir，也没有 config.log 或生成的 libtool"
  echo "#####     脚本可供核对；「选项是否生效」只能靠 make 求值 Make.Rules 变量来验证，"
  echo "#####     本脚本就是这么做的（临时 makefile include Make.Rules 后打印 LIBDIR 等）。"
  echo "#####   - **禁止静态库靠的是那条 sed，不是 --disable-static**。sed 删掉的是"
  echo "#####     libcap/Makefile 里 install-static-cap / install-static-psx 两个目标下的"
  echo "#####     两条 install 命令（试建实测命中第 194、205 行，恰好 2 行）。注意静态库"
  echo "#####     libcap.a / libpsx.a **仍会被编译出来**留在构建目录，sed 只是不让它们被"
  echo "#####     装进系统。试建对照：不做 sed 会多装出 /usr/lib/libcap.a 与 libpsx.a。"
  echo "#####   - **没有 docdir**，本节不装 /usr/share/doc/libcap-2.77。"
  echo "#####   - **程序装到 /usr/sbin 而不是 /usr/bin**（SBINDIR=\$(exec_prefix)/sbin）。"
  echo "#####     手册 Contents 只写了程序名没写路径，去 /usr/bin 找必然扑空。"
  echo "#####   - make 与 make install 都带 prefix=/usr lib=lib，而 **make test 不带**"
  echo "#####     （手册原文就是光秃秃一条 make test）。"
  echo "##### 提示框：本节有**一个 Note**，在 §8.27.1 开头 ——"
  echo "#####   「If updating this package on an existing system and the go compiler is"
  echo "#####     installed, prevent a build error by using export GOLANG=no before running"
  echo "#####     the commands below. Be sure to unset GOLANG after installation is complete.」"
  echo "#####   它的两个前提在本环境都不成立：(a) 这是首次安装（安装前 /usr/sbin/capsh 等"
  echo "#####   全部不存在，脚本逐项查过）；(b) 没有 go 编译器（go/gccgo 均未安装，且"
  echo "#####   Make.Rules 自算的 GOLANG=no）。故本次**未**设置 GOLANG，也不存在事后 unset。"
  echo "##### 手册对 lib=lib 的说明（The meaning of the make option）："
  echo "#####   「lib=lib —— This parameter sets the library directory to /usr/lib rather"
  echo "#####     than /usr/lib64 on x86_64. It has no effect on x86.」"
  echo "#####   这条在本机是实打实起作用的：Make.Rules:21 把 lib 的默认值定义为"
  echo "#####     lib=\$(shell ldd /usr/bin/ld|grep -E \"ld-linux|ld.so\"|cut -d/ -f2)"
  echo "#####   本机 ldd /usr/bin/ld 的解释器行是 /lib64/ld-linux-x86-64.so.2，故默认值"
  echo "#####   真的算成 lib64。不给 lib=lib 就会把库装进 /lib64、程序装进 /sbin，"
  echo "#####   直接撞上手册 §7.5.1 的「/usr/lib64 ... it is imperative that this directory"
  echo "#####   be non-existent」。脚本把默认与手册两种取值下的 LIBDIR/SBINDIR 都打出来对照。"
  echo "##### 测试判定方式（与 §8.26 相反）：本节手册**没有任何关于测试的提示框**，"
  echo "#####   也没有 known-to-fail 的说法，只有一句「To test the results, issue: make test」。"
  echo "#####   故 **make test 的退出码就是判据，必须为 0**（§8.26 因有 Note 才不能用退出码）。"
  echo "#####   另需说明：make test 里 progs/ 会打印 \"no program tests without privilege,"
  echo "#####   try 'make sudotest'\" —— 这是 progs/Makefile 第 53 行写死的 echo，**不是**"
  echo "#####   权限检测，任何环境下都会原样打印；需要特权的测试在 make sudotest 里，"
  echo "#####   而手册没有要求执行它。doc/ 同理打印 \"no doc tests available\"。"
  echo "##### 自检断言的校准方式：本包只有 <0.1 SBU / 3.1 MB，故正式开工前先在 chroot 的"
  echo "#####   /tmp 里做了**完整**试建（sed + make + make test + make prefix=/usr lib=lib"
  echo "#####   DESTDIR=... install，不写系统），把本脚本每一条自检断言在试建产物上逐条"
  echo "#####   验过后才重新开工，试建目录随后已删除。校准出的关键事实："
  echo "#####     - 共享库实体 libcap.so.2.77 / libpsx.so.2.77，SONAME libcap.so.2 /"
  echo "#####       libpsx.so.2 —— 这里的 2 与 77 就是包版本 2.77，与 §8.26 那种"
  echo "#####       libacl.so.1.1.2302（与版本无关的 libtool 编号）完全不同；"
  echo "#####     - libpsx.so 的 NEEDED 里没有 libpthread.so.0 —— glibc 2.34 起 pthread"
  echo "#####       已并入 libc.so.6，属预期，不是 PTHREADS 没生效（PTHREADS=yes 已核对）；"
  echo "#####     - pam_cap.so **不会**被构建：Make.Rules:123 让 PAM_CAP 取决于"
  echo "#####       /usr/include/security/pam_modules.h，本系统尚无 Linux-PAM，故 PAM_CAP=no；"
  echo "#####       但 doc 目录仍会无条件装上 pam_cap.8 这一页 man（man 页在、模块不在，"
  echo "#####       手册 Contents 也没列 pam_cap.so，属正常）；"
  echo "#####     - RAISE_SETFCAP 默认 no（Make.Rules:185），故 progs/Makefile:48-49 那条"
  echo "#####       「给装好的 setcap 自己打上 cap_setfcap=i」不会执行，装出的 setcap"
  echo "#####       不带文件 capability；"
  echo "#####     - make test 以默认 lib=lib64 运行**不会**污染安装结果：libcap.pc /"
  echo "#####       libpsx.pc 是上一步 make（带 lib=lib）由 .pc.in 生成的，make test 不会"
  echo "#####       重新生成（.pc 比 .pc.in 新）。脚本在 make test 前后各 cat 一次这两个"
  echo "#####       文件作实证，装出后再查一次 libdir 是否为 /usr/lib。"
  echo "##### 另按本项目既往教训（logs/host/ 与 memory 中的 pipefail 记录）："
  echo "#####   脚本中所有只为截断显示的 head 都已换成 tail -n N <文件> 或 sed -n '1,Np'，"
  echo "#####   所有用于展示的 grep/ls/find 都包成 { ... || true; }，避免 SIGPIPE/非零退出"
  echo "#####   在 pipefail 下误判；for 循环里也不用 '[ ] && cmd' 作最后一条命令。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.27-libcap.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".libcap-sed.log:8.27-libcap-2.77.sed.log" \
            ".libcap-make.log:8.27-libcap-2.77.make.log" \
            ".libcap-make-test.log:8.27-libcap-2.77.test.log" \
            ".libcap-make-install.log:8.27-libcap-2.77.install.log" \
            ".libcap-test-summary.log:8.27-libcap-2.77.tests.summary"; do
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
