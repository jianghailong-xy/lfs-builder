#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.28 Libxcrypt-4.5.2，完整输出落到
# logs/packages/8.28-libxcrypt-4.5.2.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.28-libxcrypt-4.5.2.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.28 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.28；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.28 Libxcrypt-4.5.2"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.27 Libcap-2.77 已完成（日志 8.27-libcap-2.77.*）。与 §8.27 一样，"
  echo "#####   本节在**构建层面并不依赖**上一节：libxcrypt 只用 libc，产出的"
  echo "#####   libcrypt.so.2 的 NEEDED 里只有 libc.so.6。下方「前置检查」第 1 项仍逐项"
  echo "#####   确认 §8.27 产物可用（任务书要求），但那不是编译依赖。"
  echo "##### 手册原文快照：docs/book/chapter08-libxcrypt.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/libxcrypt.html 抓取）"
  echo "##### 本节命令序列（手册 §8.28.1 的必需部分，全部 5 条）："
  echo "#####   sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c"
  echo "#####   ./configure --prefix=/usr --enable-hashes=strong,glibc \\"
  echo "#####               --enable-obsolete-api=no --disable-static --disable-failure-tokens"
  echo "#####   make"
  echo "#####   make check"
  echo "#####   make install"
  echo "##### 提示框：本节有**一个 Note**，在 §8.28.1 末尾，给出 obsolete API 的重建步骤"
  echo "#####   （make distclean → --enable-obsolete-api=glibc 重新 configure/make →"
  echo "#####   cp -av --remove-destination .libs/libcrypt.so.1* /usr/lib）。它是**条件性**的："
  echo "#####   「If you must have such functions because of some binary-only application"
  echo "#####     or to be compliant with LSB」。本系统全部源码构建、无 binary-only 应用、"
  echo "#####   不追求 LSB，故按手册默认路径**不执行**；脚本会实测「已装的任何文件都不"
  echo "#####   NEEDED libcrypt.so.1」把这一判断落成证据。"
  echo "##### 测试判定方式：本节手册**没有任何关于测试的提示框**，也没有 known-to-fail 的"
  echo "#####   说法，只有一句「To test the results, issue: make check」。故 **make check"
  echo "#####   的退出码就是判据，必须为 0**（与 §8.26 Acl 相反，那节因有 Note 才不能用退出码）。"
  echo "#####   逐项结论一律取 automake 的 .trs 文件，不看 -j8 下顺序错乱的 PASS:/SKIP: 行。"
  echo "##### 自检断言的校准方式：本包只有 0.1 SBU / 14 MB，故正式开工前先在 chroot 的"
  echo "#####   /tmp 里做了**完整**试建（sed + configure + make + make check + DESTDIR"
  echo "#####   install，不写系统），把本脚本每一条断言在试建产物上逐条验过后才重新开工，"
  echo "#####   试建目录随后已删除。校准出的关键事实（都不是猜的）："
  echo "#####     - 共享库实体 **libcrypt.so.2.0.0**、SONAME **libcrypt.so.2**，来自 Makefile"
  echo "#####       的 -version-info 2:0:0（current-age = 2-0 = 2），**与包版本 4.5.2 无关**；"
  echo "#####     - --enable-hashes=strong,glibc 展开成 11 个算法（bcrypt bcrypt_a bcrypt_y"
  echo "#####       descrypt gost_yescrypt md5crypt scrypt sha256crypt sha512crypt"
  echo "#####       sm3_yescrypt yescrypt），另 7 个（bcrypt_x bigcrypt bsdicrypt nt"
  echo "#####       sha1crypt sm3crypt sunmd5）关闭；这正是 14 个 SKIP 里 13 个的来源；"
  echo "#####     - 第 14 个 SKIP 是 getrandom-fallbacks：其源码守卫为"
  echo "#####       #if defined HAVE_ARC4RANDOM_BUF || !defined HAVE_LD_WRAP → return 77，"
  echo "#####       本机 HAVE_ARC4RANDOM_BUF=1（glibc 2.36 起提供 arc4random_buf），"
  echo "#####       回退链根本没编译，与权限/内核/文件系统无关；"
  echo "#####     - 测试规模 TOTAL=52 PASS=38 SKIP=14 FAIL=0，试建与正式两次应完全一致，"
  echo "#####       故判据写成**等号**而非「不小于」；"
  echo "#####     - --disable-static 的硬判据是生成的 libtool 里**首个** build_old_libs=no"
  echo "#####       （该文件里出现 3 次，后两处是另一段 case 重算）+ 源码树内 0 个 .a"
  echo "#####       （本包没有 §8.25 Attr 那种 noinst_LTLIBRARIES 便利库，所以「一个都没有」"
  echo "#####       是正确断言）；但 **/usr/lib/libcrypt.la 仍会被装上**（libtool 惯例，"
  echo "#####       其 old_library='' 表明确无静态库），手册没要求删除，属正常；"
  echo "#####     - --enable-obsolete-api=no 的硬判据取 nm -D --defined-only：恰好 12 个"
  echo "#####       导出符号（9 函数 + 3 版本节点 XCRYPT_2.0/4.3/4.4），无 fcrypt/encrypt/"
  echo "#####       setkey。**不要**拿 readelf --version-info 当判据 —— 它会列出 GLIBC_2.x，"
  echo "#####       那是从 libc **需要**的版本（verneed），不是本库定义的；"
  echo "#####     - 安装产物固定为 14 个普通文件 + 3 个符号链接，其中"
  echo "#####       /usr/lib/pkgconfig/libcrypt.pc 是指向 libxcrypt.pc 的**符号链接**；"
  echo "#####     - man 页 9 个 man3 + 1 个 man5，数字由 find|wc -l 现算，不人工数。"
  echo "##### 另按本项目既往教训（memory 中的 pipefail 记录）：所有用于**展示**的"
  echo "#####   diff/grep/ls/find 都包成 { … || true; }；不用 'cmd | grep -q'；"
  echo "#####   grep 的文件名列表先落盘判空再用（列表为空时 grep 会转读 stdin 卡死）；"
  echo "#####   计数一律 wc -l 现算并复用同一变量；日志里不写入任何二进制字节。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.28-libxcrypt.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".libxcrypt-sed.log:8.28-libxcrypt-4.5.2.sed.log" \
            ".libxcrypt-configure.log:8.28-libxcrypt-4.5.2.configure.log" \
            ".libxcrypt-make.log:8.28-libxcrypt-4.5.2.make.log" \
            ".libxcrypt-make-check.log:8.28-libxcrypt-4.5.2.check.log" \
            ".libxcrypt-make-install.log:8.28-libxcrypt-4.5.2.install.log" \
            ".libxcrypt-test-summary.log:8.28-libxcrypt-4.5.2.tests.summary"; do
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
