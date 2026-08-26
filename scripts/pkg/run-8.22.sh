#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.22 GMP-6.3.0，完整输出落到
# logs/packages/8.22-gmp-6.3.0.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.22-gmp-6.3.0.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.22 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.22；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.22 GMP-6.3.0"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.21 Binutils-2.46.0 已完成（日志 8.21-binutils-2.46.0.*），其产物在"
  echo "#####   下方「前置检查」第 1 项中逐项确认。"
  echo "##### 手册原文快照：docs/book/chapter08-gmp.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/gmp.html 抓取）"
  echo "##### 本节命令序列（手册 §8.22.1 全部 8 条命令）："
  echo "#####   sed -i '/long long t1;/,+1s/()/(...)/' configure"
  echo "#####   ./configure --prefix=/usr    \\"
  echo "#####               --enable-cxx     \\"
  echo "#####               --disable-static \\"
  echo "#####               --docdir=/usr/share/doc/gmp-6.3.0"
  echo "#####   make"
  echo "#####   make html"
  echo "#####   make check 2>&1 | tee gmp-check-log"
  echo "#####   awk '/# PASS:/{total+=\$3} ; END{print total}' gmp-check-log"
  echo "#####   make install"
  echo "#####   make install-html"
  echo "##### 本节没有 mkdir build —— GMP 按手册在源码目录内直接 configure（in-tree build）。"
  echo "##### 提示框共 4 个，逐个处置（详见日志正文）："
  echo "#####   Note①  32 位 x86 + 已设 CFLAGS 才需 ABI=32 —— 本机 x86_64 且 env -i 无 CFLAGS，不适用；"
  echo "#####   Note②  --host=none-linux-gnu 生成通用库是可选项 —— 手册正文未加，本节不加；"
  echo "#####   Important  测试 critical，不得跳过 —— make check 必跑；"
  echo "#####   Caution    处理器探测误判会导致 Illegal instruction —— 脚本在 make 与 check 的"
  echo "#####              输出里显式搜索该字样，命中即报错，不静默放过。"
  echo "##### 判据：手册给出的唯一量化标准是「Ensure that at least 199 tests in the test"
  echo "#####   suite passed」，用手册自己的 awk 命令在 gmp-check-log 上求 '# PASS:' 之和；"
  echo "#####   另加 make check 退出码为 0、汇总 FAIL/XPASS/ERROR 全为 0 作为一致性互校。"
  echo "##### 自检断言的校准方式：本包只有 0.3 SBU / 54 MB，故在正式开工前先在 chroot 的"
  echo "#####   /tmp 里做了一次完整试建（sed + configure + make + make html +"
  echo "#####   make DESTDIR=/tmp/gmp-dest install install-html，不跑 make check、不写系统），"
  echo "#####   把本脚本的每一条自检断言在试建产物上逐条验过后才重新开工。校准记录见"
  echo "#####   logs/host/gmp-calib.log。校准据此定下了这些落点（都不是猜的）："
  echo "#####     - sed 恰好改写 2 行（configure 里两处 'void g(){}' -> 'void g(...){}'）；"
  echo "#####     - --disable-static 的硬判据是 libtool 里首个 build_old_libs=no"
  echo "#####       （该文件里 build_old_libs 出现 3 次，只有第一次是本次配置的结论），"
  echo "#####       Makefile 中并没有 enable_static/enable_shared 变量，不能拿它当判据；"
  echo "#####     - --enable-cxx 的硬判据是 Makefile 的 GMPXX_LTLIBRARIES_OPTION = libgmpxx.la"
  echo "#####       与 GMPXX_HEADERS_OPTION = gmpxx.h；"
  echo "#####     - make html 产出的是目录 doc/gmp.html/（146 个文件，入口 index.html），"
  echo "#####       不是单个文件，故 find 必须带 -type f 才不会把目录当文件去 head；"
  echo "#####     - 库实体为 libgmp.so.10.5.0 / libgmpxx.so.4.7.0（SONAME libgmp.so.10 /"
  echo "#####       libgmpxx.so.4），/usr/lib/libgmp.so 与 libgmpxx.so 是指向它们的符号链接；"
  echo "#####     - 位数断言改用 mpz_get_str + strlen 而不是 mpz_sizeinbase —— 后者在非 2 的"
  echo "#####       幂进制下可能大 1，不能作精确判据；"
  echo "#####     - mpf 的 sqrt(2) 只断言前 20 位小数（1.41421356237309504880），避开"
  echo "#####       gmp_printf 在第 40 位上的进位边界。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.22-gmp.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".gmp-configure.log:8.22-gmp-6.3.0.configure.log" \
            ".gmp-make.log:8.22-gmp-6.3.0.make.log" \
            ".gmp-make-html.log:8.22-gmp-6.3.0.make-html.log" \
            ".gmp-make-check.log:8.22-gmp-6.3.0.check.log" \
            ".gmp-make-install.log:8.22-gmp-6.3.0.install.log" \
            ".gmp-make-install-html.log:8.22-gmp-6.3.0.install-html.log" \
            ".gmp-test-summary.log:8.22-gmp-6.3.0.tests.summary"; do
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
