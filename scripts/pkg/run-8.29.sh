#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.29 Shadow-4.19.3，完整输出落到
# logs/packages/8.29-shadow-4.19.3.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.29-shadow-4.19.3.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.29 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.29；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.29 Shadow-4.19.3"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.28 Libxcrypt-4.5.2 已完成（日志 8.28-libxcrypt-4.5.2.*）。与前几节不同，"
  echo "#####   本节**真的**依赖上一节：手册的 --with-{b,yes}crypt 让 shadow 使用 Libxcrypt"
  echo "#####   实现的 bcrypt/yescrypt 做口令散列，装出的 passwd/login/su/chpasswd 的 NEEDED"
  echo "#####   里都会出现 libcrypt.so.2。下方「前置检查」第 1 项逐项确认 §8.28 产物可用。"
  echo "##### 手册原文快照：docs/book/chapter08-shadow.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/shadow.html 抓取）"
  echo "##### 本节命令序列（§8.29.1 + §8.29.2 + §8.29.3 的全部必需命令）："
  echo "#####   sed -i 's/groups\$(EXEEXT) //' src/Makefile.in"
  echo "#####   find man -name Makefile.in -exec sed -i 's/groups\\.1 / /'   {} \;"
  echo "#####   find man -name Makefile.in -exec sed -i 's/getspnam\\.3 / /' {} \;"
  echo "#####   find man -name Makefile.in -exec sed -i 's/passwd\\.5 / /'   {} \;"
  echo "#####   sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' -e 's:/var/spool/mail:/var/mail:' \\"
  echo "#####       -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' -i etc/login.defs"
  echo "#####   touch /usr/bin/passwd"
  echo "#####   ./configure --sysconfdir=/etc --disable-static --with-{b,yes}crypt \\"
  echo "#####               --without-libbsd --disable-logind --with-group-name-max-length=32"
  echo "#####   make"
  echo "#####   （手册原文：This package does not come with a test suite.——本节无测试）"
  echo "#####   make exec_prefix=/usr install"
  echo "#####   make -C man install-man"
  echo "#####   pwconv / grpconv / mkdir -p /etc/default / useradd -D --gid 999   （§8.29.2）"
  echo "#####   passwd root                                                        （§8.29.3）"
  echo "##### 两处与手册字面不同、且都在日志里写明理由的地方："
  echo "#####   1) §8.29.3 的 passwd root 是交互式命令，本项目 chroot 执行无 tty，改用同一个"
  echo "#####      程序的 stdin 入口 passwd --stdin root（shadow 4.19.3 原生选项）。root 口令"
  echo "#####      明文写在日志里，供后续 QEMU 验收登录。"
  echo "#####   2) §8.29.2 末尾的 sed -i '/MAIL/s/yes/no/' /etc/default/useradd 手册标注为**可选**"
  echo "#####      （If you would rather not create these files），本项目保留手册默认的"
  echo "#####      CREATE_MAIL_SPOOL=yes，故不执行。"
  echo "##### 自检断言的校准方式：本包 0.1 SBU / 115 MB，故正式开工前先在 chroot 的 /tmp 里做了"
  echo "#####   **完整**试建（四条 sed/find + login.defs sed + configure + make + DESTDIR 安装，"
  echo "#####   不写系统），把本脚本每一条断言在试建产物上逐条验过后才重新开工，试建目录随后已删除"
  echo "#####   （脚本 scripts/pkg/8.29-shadow-trial.sh）。校准出的关键事实（都不是猜的）："
  echo "#####     - 手册第一条 sed 's/groups\$(EXEEXT) //' 在 4.19.3 上匹配 **0** 行：这个版本"
  echo "#####       已经不再提供 groups 程序（src/Makefile.am 里没有该目标），man 树里也没有"
  echo "#####       groups.1。手册这两条命令仍原样执行，只是无可改之处——脚本把「匹配 0 行 +"
  echo "#####       md5 前后不变」作为证据打进日志，而不是假装它改了什么；"
  echo "#####     - getspnam.3 的 sed 命中 **9** 个 Makefile.in，passwd.5 命中 **16** 个；"
  echo "#####     - 手册的 sed 只删文件名不删目录前缀，man_MANS 里会留下 'man3/' 和 'man5/'"
  echo "#####       两个残 token。automake 的 install-manN 用 sed -n '/\\.N[a-z]*\$/p' 过滤条目，"
  echo "#####       残 token 不以 .3/.5 结尾会被丢弃，且它们又是真实目录，不会让 make 报错——"
  echo "#####       安装后脚本会复核 /usr/share/man/man3/man3 之类根本不存在；"
  echo "#####     - configure 后 exec_prefix 为空（configure.ac 里 'test \"X\$prefix\" = \"X/usr\""
  echo "#####       && exec_prefix=\"\"'），所以 bindir=/bin、sbindir=/sbin，手册必须用"
  echo "#####       make exec_prefix=/usr install 才装到 /usr/bin、/usr/sbin；"
  echo "#####     - man 页要单独 make -C man install-man，是因为顶层 Makefile.am 只在"
  echo "#####       ENABLE_REGENERATE_MAN 时才把 man 放进 SUBDIRS；"
  echo "#####     - 安装规模（判据写等号）：34 个程序（13 个 /usr/bin 文件 + 19 个 /usr/sbin 文件"
  echo "#####       + sg、vigr 两个符号链接）、10 个新增 setuid 程序、45 个 man 页"
  echo "#####       （man1=13 man3=1 man5=10 man8=21）、39 个 shadow.mo、3 个 /etc 配置文件"
  echo "#####       （login.defs limits login.access）、libsubid.so.5.0.0（ABI 5.0.0 来自"
  echo "#####       configure.ac 的 libsubid_abi_*，与包版本 4.19.3 无关）；"
  echo "#####     - setuid 判据写成**安装前后的差集**：本系统在 §7.12 Util-linux 之后已经有"
  echo "#####       mount/umount 两个 suid 程序，拿绝对集合硬套会假失败；"
  echo "#####     - --disable-static 的硬判据是 libtool 里**首个** build_old_libs=no +"
  echo "#####       /usr/lib 下没有 libsubid*.a/libshadow*.a。源码树内仍会有 1 个"
  echo "#####       lib/.libs/libshadow.a，那是 noinst 便利库（只在链接期用、不安装），"
  echo "#####       所以这里**不能**写「一个 .a 都没有」；"
  echo "#####     - 本包无测试套件，判据落在「装出来的东西能跑」：chage -l root、pwck -r、"
  echo "#####       grpck -r、groupadd/groupdel 往返、32/33 字符组名边界（验证"
  echo "#####       --with-group-name-max-length=32），以及 root 散列必须以 \$y\$ 开头"
  echo "#####       （yescrypt，同时证明 ENCRYPT_METHOD 与 Libxcrypt 都在真正工作）。"
  echo "##### 另按本项目既往教训（memory 中的 pipefail 记录）：所有用于**展示**的"
  echo "#####   diff/grep/ls/find 都包成 { … || true; }；不用 'cmd | grep -q'（grep -q 提前退出会"
  echo "#####   给上游 SIGPIPE，在 pipefail 下把整条判断弄成假；改为先落到变量再判空）；"
  echo "#####   grep 的文件名列表先落盘判空再用；计数一律现算并复用同一变量；"
  echo "#####   日志里不写入任何二进制字节，也不写完整口令散列。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.29-shadow.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".shadow-sed.log:8.29-shadow-4.19.3.sed.log" \
            ".shadow-configure.log:8.29-shadow-4.19.3.configure.log" \
            ".shadow-make.log:8.29-shadow-4.19.3.make.log" \
            ".shadow-make-install.log:8.29-shadow-4.19.3.install.log" \
            ".shadow-install-man.log:8.29-shadow-4.19.3.install-man.log" \
            ".shadow-configuring.log:8.29-shadow-4.19.3.configuring.log"; do
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
