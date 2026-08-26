#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.30 GCC-15.2.0，完整输出落到
# logs/packages/8.30-gcc-15.2.0.log。
set -uo pipefail
LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG=$LFS_ROOT/logs/packages/8.30-gcc-15.2.0.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER="${CONTAINER:-lfs-build-$(basename "$LFS_ROOT")}"

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.30 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.30；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.30 GCC-15.2.0"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS_ROOT/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 $LFS_ROOT/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.29 Shadow-4.19.3 已完成（日志 8.29-shadow-4.19.3.*）。本节**真的**"
  echo "#####   用到它：手册要求 GCC 的测试套件以非特权用户身份运行"
  echo "#####   （\"Test the results as a non-privileged user\"），用的正是 Shadow 装的 su。"
  echo "#####   下方「前置检查」第 1 项逐项确认 §8.29 产物可用。"
  echo "##### 手册原文快照：docs/book/chapter08-gcc.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/gcc.html 抓取）"
  echo "##### 本节命令序列（§8.30.1 的全部命令，按手册原文顺序）："
  echo "#####   sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c"
  echo "#####   case \$(uname -m) in x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;; esac"
  echo "#####   mkdir -v build && cd build"
  echo "#####   ../configure --prefix=/usr LD=ld --enable-languages=c,c++ --enable-default-pie \\"
  echo "#####                --enable-default-ssp --enable-host-pie --disable-multilib \\"
  echo "#####                --disable-bootstrap --disable-fixincludes --with-system-zlib"
  echo "#####   make"
  echo "#####   ulimit -s -H unlimited"
  echo "#####   sed -e '/cpython/d' -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp"
  echo "#####   chown -R tester ."
  echo "#####   su tester -c \"PATH=\$PATH make -k check\""
  echo "#####   ../contrib/test_summary        （手册：pipe through 'grep -A7 Summ'）"
  echo "#####   make install"
  echo "#####   chown -v -R root:root /usr/lib/gcc/\$(gcc -dumpmachine)/15.2.0/include{,-fixed}"
  echo "#####   ln -svr /usr/bin/cpp /usr/lib"
  echo "#####   ln -sv gcc.1 /usr/share/man/man1/cc.1"
  echo "#####   ln -sfv ../../libexec/gcc/\$(gcc -dumpmachine)/15.2.0/liblto_plugin.so /usr/lib/bfd-plugins/"
  echo "#####   echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log  + 6 条 grep/readelf 核对"
  echo "#####   rm -v a.out dummy.log"
  echo "#####   mkdir -pv /usr/share/gdb/auto-load/usr/lib && mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib"
  echo "##### 与手册字面完全一致，没有增删任何一条命令。三处需要说明的执行细节："
  echo "#####   1) 手册 Important 说测试可以加 -jx 提速。本 chroot 的 MAKEFLAGS 已是 -j\$(nproc)（=-j8），"
  echo "#####      且实测它能穿过 su tester -c（脚本前置检查第 4 项有探针输出），所以**不**额外追加"
  echo "#####      -jx，命令保持与手册逐字相同；"
  echo "#####   2) 手册的 6 条工具链完整性检查（readelf/grep dummy.log）原样执行，输出与手册给出的"
  echo "#####      期望值逐条比对，比对结果写在日志里，不是只把输出打出来了事；"
  echo "#####   3) make / make -k check / make install 的**完整**输出体量在几十 MB 量级，全塞进主日志"
  echo "#####      会让主日志不可读，因此它们落到独立文件（见文末「留档」行），主日志记录起止时间、"
  echo "#####      退出码、耗时、尾部若干行，以及测试的完整汇总与全部意外结果明细。"
  echo "##### 本包不做 /tmp 试建校准（手册数据 45 SBU / 6.6 GB，试建代价过高）。因此脚本里的自检"
  echo "#####   断言只用两类来源：(a) 手册 §8.30.1 白纸黑字给出的期望输出（6 条工具链检查、"
  echo "#####   4 组已知失败）；(b) 手册 §8.30.2 Contents 列出的程序/库/目录清单。不写任何"
  echo "#####   靠猜的数量等号——这正是 memory 里那条教训（构建失败全部来自自加检查而非手册命令）。"
  echo "##### 另按同一条教训：所有用于展示的 diff/grep/ls/find 都包成 { … || true; }；不用"
  echo "#####   'cmd | grep -q'；文件名列表先落盘判空再喂给 grep/xargs；日志里不写二进制字节。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.30-gcc.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".gcc-configure.log:8.30-gcc-15.2.0.configure.log" \
            ".gcc-make.log:8.30-gcc-15.2.0.make.log" \
            ".gcc-check.log:8.30-gcc-15.2.0.check.log" \
            ".gcc-test-summary.log:8.30-gcc-15.2.0.test_summary.log" \
            ".gcc-unexpected.log:8.30-gcc-15.2.0.unexpected.log" \
            ".gcc-make-install.log:8.30-gcc-15.2.0.install.log"; do
  src=$LFS_ROOT/sources/${pair%%:*}
  dst=$LFS_ROOT/logs/packages/${pair#*:}
  if [ -f "$src" ]; then
    mv -f "$src" "$dst"
    echo "##### 留档：logs/packages/$(basename "$dst")（$(wc -l < "$dst") 行）" >> "$LOG"
  fi
done

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc（日志：$LOG）"
exit $rc
