#!/usr/bin/env bash
# LFS 13.0-systemd §8.11 File-5.46
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.11.1 Installation of File 的命令序列（全部，一条不多一条不少）：
#   ./configure --prefix=/usr
#   make
#   make check
#   make install
# 本节没有补丁、没有 sed 改写、没有额外的 rm（§6.7 里那条 rm $LFS/usr/lib/libmagic.la
# 只属于交叉编译阶段，本节手册未要求）。§8.11.2 只是 Contents 说明。
set -euo pipefail

PKG=file
VER=5.46
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
CHECKLOG=/sources/.file-make-check.log
CONFLOG=/sources/.file-configure.log

echo "===== LFS 13.0-systemd §8.11 File-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The File package contains a utility for determining the type of a"
echo "  given file or files."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 19 MB"
echo "手册存档：/workspace/docs/book/chapter08-file.html（宿主机 \$LFS_ROOT/docs/book/）"
echo

echo "----- 环境（手册 §7.4 进入 chroot 后的环境） -----"
echo "id        : $(id)"
echo "whoami    : $(whoami)"
echo "PATH      : $PATH"
echo "HOME      : $HOME"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "TESTSUITEFLAGS: ${TESTSUITEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
  *) echo "OK        : /tools/bin 不在 PATH" ;;
esac
echo "说明：手册本节的测试命令是 make check（不带 -j1），沿用 §7.4 环境里的 MAKEFLAGS。"
echo "  File 的 check 由 tests/Makefile.am 的 check-local 目标实现——一个 set -e 的 shell"
echo "  循环，对 tests/*.testfile 逐个跑 ./test，并行度只作用于 check 程序的编译。"
echo "可用空间（手册本节要求 19 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 25 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 19MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.10 Zstd-1.5.7）产物必须可用 -----"
rc=0
echo "1) §8.10.2 Contents of Zstd 的关键产物："
for f in /usr/bin/zstd /usr/bin/zstdcat /usr/bin/unzstd /usr/bin/zstdmt \
         /usr/bin/zstdgrep /usr/bin/zstdless \
         /usr/lib/libzstd.so /usr/lib/libzstd.so.1 /usr/lib/libzstd.so.1.5.7 \
         /usr/include/zstd.h /usr/include/zstd_errors.h /usr/include/zdict.h \
         /usr/lib/pkgconfig/libzstd.pc /usr/share/man/man1/zstd.1; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.10 未完成？）\n' "$f"; rc=1; fi
done
if [ -e /usr/lib/libzstd.a ]; then
  echo "   FAIL /usr/lib/libzstd.a 仍存在（§8.10 最后一条 rm -v /usr/lib/libzstd.a 未生效）"; rc=1
else echo "   OK   /usr/lib/libzstd.a 已按 §8.10 删除"; fi
zstd_ver=$(zstd --version 2>&1 | sed -n '1s/.*v\([0-9][0-9.]*\).*/\1/p')
if [ "$zstd_ver" = "1.5.7" ]; then echo "   OK   zstd 自述版本 $zstd_ver"
else echo "   FAIL zstd 自述版本为 '$zstd_ver'，应为 1.5.7"; rc=1; fi
echo "   zstd 往返自检："
if [ "$(printf 'lfs 8.11 precheck\n' | zstd -q -c | zstdcat)" = 'lfs 8.11 precheck' ]; then
  echo "     OK   zstd -> zstdcat 往返正常"
else echo "     FAIL zstd 往返失败"; rc=1; fi
echo "2) 本节 configure 会自动探测的压缩库（configure.ac 的 Final sanity checks：zlib /"
echo "   bzlib / xzlib / zstdlib 各自要求「头文件 + 库里的探针函数」同时存在）："
for f in /usr/include/zlib.h  /usr/lib/libz.so \
         /usr/include/bzlib.h /usr/lib/libbz2.so \
         /usr/include/lzma.h  /usr/lib/liblzma.so \
         /usr/include/zstd.h  /usr/lib/libzstd.so; do
  if [ -e "$f" ]; then printf '   OK   %-24s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   说明：这四个包分别是 §8.6 Zlib / §8.7 Bzip2 / §8.8 Xz / §8.10 Zstd，在手册里"
echo "     都排在 §8.11 之前，所以本节编译出的 file/libmagic 会带 .gz/.bz2/.xz/.zst 的"
echo "     解压识别能力（-z 选项）。configure 之后会核对 config.h 里的 *SUPPORT 宏。"
echo "   未安装、因而预期不会被启用的可选支持（信息性）："
for f in /usr/include/lzlib.h /usr/include/Lrzip.h /usr/include/seccomp.h; do
  if [ -e "$f" ]; then printf '   INFO %-24s 存在（对应支持会被自动启用）\n' "$f"
  else printf '   INFO %-24s 不存在（对应支持预期为 no）\n' "$f"; fi
done
echo "3) §8.5 Glibc-2.43 的 C 库与工具链可用（本节要 configure + 编译 C 代码 + 跑测试）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("glibc sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && \
   [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo "5) 本节直接依赖的工具（解包 + configure + make + 测试 + 安装）："
for t in tar gzip make gcc ld ar ranlib sed grep awk cmp diff cp install ln rm mkdir \
         md5sum readelf objdump find stat bash sort head tail expr basename dirname; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-9s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc     版本：$(gcc --version | sed -n 1p)"
echo "   make    版本：$(make --version | sed -n 1p)"
echo "   sed     版本：$(sed --version | sed -n 1p)"
echo "   libtool：本包自带 ltmain.sh，无需系统 libtool"
echo "6) 安装目标目录："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/share/man/man3 \
         /usr/share/man/man4 /usr/share/misc /usr/lib/pkgconfig; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo "7) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "8) §7.3 虚拟内核文件系统与 §7.6 基础文件："
for f in /dev/null /dev/zero /dev/urandom /proc/self /sys /etc/passwd /etc/group /tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "9) 安装前系统中已有的 File（来自 §6.7 的交叉编译版本，本节要用原生编译的覆盖它）："
for f in /usr/bin/file /usr/lib/libmagic.so.1.0.0 /usr/share/misc/magic.mgc /usr/include/magic.h; do
  if [ -e "$f" ]; then printf '   INFO %-30s 已存在（%s 字节，mtime %s）\n' \
       "$f" "$(stat -Lc %s "$f")" "$(stat -Lc %y "$f" | cut -d. -f1)"
  else printf '   INFO %-30s 不存在\n' "$f"; fi
done
old_file_ver=$(file --version 2>&1 | sed -n 1p)
old_file_mtime=$(stat -Lc %Y /usr/bin/file 2>/dev/null || echo 0)
old_file_size=$(stat -Lc %s /usr/bin/file 2>/dev/null || echo 0)
echo "   §6.7 版本自述：$old_file_ver"
echo "   §6.7 /usr/bin/file：$old_file_size 字节，mtime 纪元秒 $old_file_mtime"
echo "   §6.7 的 file 链接到的共享库（交叉编译时用 --disable-{bzlib,libseccomp,xzlib,zlib}"
echo "     构建的只是那份临时副本；正式安装的这份是自动探测的，此刻记录以便对照）："
ldd /usr/bin/file | sed 's/^/     /'
echo "   INFO 本节结束后会核对 /usr/bin/file 的 mtime/大小确实发生了变化，"
echo "        以证明系统里的 file 已被本节原生编译的版本替换（两者版本号同为 5.46，"
echo "        仅凭 --version 无法区分）。"
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls -l | sed 's/^/  /'
echo "上游版本自述（configure 的 PACKAGE_VERSION）："
src_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'$/\1/p" configure | head -n1)
echo "  PACKAGE_VERSION=$src_ver"
if [ "$src_ver" = "$VER" ]; then echo "  OK   源码自述版本 $src_ver 与手册 §8.11 的 File-$VER 一致"
else echo "  FAIL 源码自述版本为 $src_ver，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁：手册 §8.11 的命令序列里没有 patch，/sources 下也没有 file 补丁"
file_patches=$(ls /sources | grep -Ei '^file.*patch' || true)
echo "  （/sources 中匹配 file*patch 的文件：${file_patches:-无}）"
echo "本节无 sed 改写：§8.11 只有 configure/make/make check/make install 四条命令"
echo "测试集规模（tests/*.testfile 的个数，后面用来核对 make check 是否跑全）："
expected_tests=$(ls tests/*.testfile | wc -l)
echo "  tests/*.testfile 共 $expected_tests 个"
echo "  测试机制：tests/Makefile.am 的 check-local 是一个 set -e 的 shell 循环，对每个"
echo "    testfile 打印一行 'Running test: <路径>' 后运行 ./test 比对 .result；它不是"
echo "    automake 的 TESTS 机制，因此没有 '# TOTAL:/# PASS:/# FAIL:' 汇总行。"
echo

echo "================= 8.11.1. Installation of File ================="
echo "手册原文：Prepare File for compilation:"
echo "手册命令：./configure --prefix=/usr"
set +e
./configure --prefix=/usr 2>&1 | tee "$CONFLOG"
conf_rc=${PIPESTATUS[0]}
set -e
echo "configure 退出码：$conf_rc"
[ "$conf_rc" -eq 0 ] || { echo "错误：configure 失败" >&2; exit "$conf_rc"; }
echo
echo "----- configure 结果确认 -----"
echo "  安装前缀（Makefile 里的 prefix）："
conf_prefix=$(sed -n 's/^prefix = //p' Makefile | head -n1)
echo "    prefix = $conf_prefix"
if [ "$conf_prefix" = "/usr" ]; then echo "    OK   --prefix=/usr 生效"
else echo "    FAIL prefix 为 '$conf_prefix'，应为 /usr" >&2; exit 1; fi
echo "    libdir     = $(sed -n 's/^libdir = //p' Makefile | head -n1)"
echo "    includedir = $(sed -n 's/^includedir = //p' Makefile | head -n1)"
echo "    mandir     = $(sed -n 's/^mandir = //p' Makefile | head -n1)"
echo "    pkgdatadir = $(sed -n 's/^pkgdatadir = //p' magic/Makefile | head -n1)"
echo "  压缩支持宏（config.h，由 configure.ac 的 Final sanity checks 决定）："
for m in ZLIBSUPPORT BZLIBSUPPORT XZLIBSUPPORT ZSTDLIBSUPPORT; do
  if grep -E "^#define $m 1\$" config.h > /dev/null; then
    printf '    OK   %-14s 已启用（对应 §8.6/§8.7/§8.8/§8.10 的库被探测到）\n' "$m"
  else
    printf '    FAIL %-14s 未启用，但对应的头文件与库在前置检查中都存在\n' "$m"; exit 1
  fi
done
for m in LZLIBSUPPORT LRZIPSUPPORT HAVE_LIBSECCOMP; do
  if grep -E "^#define $m 1\$" config.h > /dev/null; then
    printf '    INFO %-16s 已启用\n' "$m"
  else
    printf '    INFO %-16s 未启用（对应库未安装，预期如此）\n' "$m"
  fi
done
echo "  configure 探测到的 LIBS（会被链进 libmagic）："
conf_libs=$(sed -n 's/^LIBS = //p' src/Makefile | head -n1)
echo "    LIBS = $conf_libs"
echo "  man 页节号（doc/Makefile.am：未给 --enable-fsect-man5 时 magic 手册页是 magic.4）："
man_magic=$(sed -n 's/^man_MAGIC = //p' doc/Makefile | head -n1)
echo "    man_MAGIC = $man_magic"
echo

echo "手册原文：Compile the package:"
echo "手册命令：make"
make
echo
echo "----- 编译结果确认 -----"
for f in src/file src/.libs/libmagic.so.1.0.0 magic/magic.mgc; do
  if [ -e "$f" ]; then printf '  OK   %-30s %s 字节\n' "$f" "$(stat -Lc %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; exit 1; fi
done
echo "  说明：magic/magic.mgc 由 magic/Makefile.am 的 \${MAGIC} 规则用 *本次刚编译出的*"
echo "    \$(top_builddir)/src/file -C -m magic 生成（IS_CROSS_COMPILE 为假时 FILE_COMPILE"
echo "    = top_builddir/src/file）。这与 §6.7 交叉编译时必须先做一份 host 可执行的临时"
echo "    副本不同，本节是原生编译，无此需求。"
echo "  共享库 SONAME："
objdump -p src/.libs/libmagic.so.1.0.0 | awk '/SONAME/{print "    "$0}'
echo "  刚编译出的 file 自述版本："
./src/.libs/file --version 2>/dev/null | sed 's/^/    /' || ./src/file --version | sed 's/^/    /'
echo

echo "手册原文：To test the results, issue:"
echo "手册命令：make check"
echo "（本节手册没有关于测试结果的 Note / Caution，即要求测试全部通过。判定依据："
echo "  make 退出码为 0，且 tests 目录的 check-local 循环确实对全部 $expected_tests 个"
echo "  tests/*.testfile 各打印了一行 'Running test:'——该循环以 set -e 运行，任何一个"
echo "  用例比对失败都会立即中断并让 make 以非 0 退出。）"
set +e
make check 2>&1 | tee "$CHECKLOG"
check_rc=${PIPESTATUS[0]}
set -e
echo
echo "----- make check 结论 -----"
echo "make check 退出码：$check_rc"
echo "输出行数：$(wc -l < "$CHECKLOG")"
echo "输出末尾 20 行："
tail -n 20 "$CHECKLOG" | sed 's/^/  /'
echo
ran_tests=$(grep -c '^Running test: ' "$CHECKLOG" || true)
ran_tests=${ran_tests:-0}
echo "统计："
echo "  tests/*.testfile 用例总数        ：$expected_tests"
echo "  输出中 'Running test:' 的行数    ：$ran_tests"
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make check 退出码非 0（$check_rc）" >&2
  echo "  完整输出见 $CHECKLOG" >&2
  exit "$check_rc"
fi
if [ "$ran_tests" -ne "$expected_tests" ]; then
  echo "错误：make check 退出码为 0，但只跑了 $ran_tests / $expected_tests 个用例，" >&2
  echo "  测试没有跑到底" >&2
  exit 1
fi
echo "  OK   退出码 0 且 $ran_tests/$expected_tests 个用例全部执行完毕"
echo "  说明：check-local 的比对由 tests/test.c 完成，不匹配时它自己会打印差异并以非 0"
echo "    退出，从而使整条 set -e 循环中断——所以「退出码 0 + 用例数跑满」即等价于"
echo "    「全部用例通过」。下面把输出里出现的 'fail/error' 类字样列出来供人工核对："
susp=$(grep -niE 'fail|error|differ|mismatch' "$CHECKLOG" || true)
if [ -n "$susp" ]; then
  echo "$susp" | sed 's/^/    /'
  echo "    （注意：magic 规则与测试样本的文件名/描述里本身就可能含 error、fail 等词，"
  echo "      这里只作人工核对之用，不作为失败判据——失败判据是上面的退出码与用例数。）"
else
  echo "    （无匹配行）"
fi
echo "结论：make check 退出码 0，$ran_tests 个用例全部执行且无中断 —— 本节测试全部通过。"
echo

echo "手册原文：Install the package:"
echo "手册命令：make install"
make install
echo

echo "----- 安装后检查（手册 §8.11.2 Contents of File） -----"
rc=0
echo "1) Installed program：file"
if [ -f /usr/bin/file ] && [ -x /usr/bin/file ] && [ ! -L /usr/bin/file ]; then
  printf '   OK   /usr/bin/file（%s 字节，mtime %s）\n' \
     "$(stat -Lc %s /usr/bin/file)" "$(stat -Lc %y /usr/bin/file | cut -d. -f1)"
else printf '   FAIL /usr/bin/file 缺失或不可执行\n'; rc=1; fi
new_file_mtime=$(stat -Lc %Y /usr/bin/file)
new_file_size=$(stat -Lc %s /usr/bin/file)
echo "   与安装前（§6.7 交叉编译版本）对比："
printf '     安装前：%s 字节，mtime 纪元秒 %s\n' "$old_file_size" "$old_file_mtime"
printf '     安装后：%s 字节，mtime 纪元秒 %s\n' "$new_file_size" "$new_file_mtime"
if [ "$new_file_mtime" -gt "$old_file_mtime" ]; then
  echo "     OK   /usr/bin/file 已被本节新编译的版本覆盖（mtime 变新）"
else
  echo "     FAIL /usr/bin/file 的 mtime 未变新，make install 可能没有覆盖它"; rc=1
fi
echo "2) Installed library：libmagic.so"
for f in /usr/lib/libmagic.so /usr/lib/libmagic.so.1 /usr/lib/libmagic.so.1.0.0; do
  if [ -e "$f" ]; then printf '   OK   %-30s -> %s（%s 字节）\n' "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
ls -l /usr/lib/libmagic* | sed 's/^/     /'
soname=$(objdump -p /usr/lib/libmagic.so.1.0.0 | awk '/SONAME/{print $2}')
echo "   SONAME = $soname"
if [ "$soname" = "libmagic.so.1" ]; then echo "     OK   SONAME 正确（src/Makefile.am：-version-info 1:0:0）"
else echo "     FAIL SONAME 应为 libmagic.so.1"; rc=1; fi
echo "   INFO /usr/lib/libmagic.la：$( [ -e /usr/lib/libmagic.la ] && echo 存在 || echo 不存在 )"
echo "        §6.7 里手册要求 rm -v \$LFS/usr/lib/libmagic.la（理由：harmful for cross"
echo "        compilation），§8.11 未要求删除，故这里保留原样，不作判据。"
echo "   动态符号抽查（先落盘再匹配，避免管道 SIGPIPE 误判）："
dynsyms=$(mktemp /tmp/libmagic-dynsyms-XXXXXX)
readelf --dyn-syms -W /usr/lib/libmagic.so.1.0.0 > "$dynsyms"
for s in magic_open magic_close magic_load magic_file magic_buffer magic_error \
         magic_setflags magic_version magic_getpath; do
  if grep -E "[[:space:]]$s\$|[[:space:]]$s@" "$dynsyms" > /dev/null; then
    printf '     OK   %s\n' "$s"
  else printf '     FAIL 动态符号 %s 缺失\n' "$s"; rc=1; fi
done
rm -f "$dynsyms"
echo "   libmagic 链接到的共享库（应含 §8.6/§8.7/§8.8/§8.10 的四个压缩库）："
ldd /usr/lib/libmagic.so.1.0.0 | sed 's/^/     /'
lib_ldd=$(ldd /usr/lib/libmagic.so.1.0.0)
for want in libz.so libbz2.so liblzma.so libzstd.so libc.so.6; do
  case "$lib_ldd" in
    *"$want"*) printf '     OK   链接到 %s\n' "$want" ;;
    *) printf '     FAIL 未链接到 %s（对应解压支持未编入）\n' "$want"; rc=1 ;;
  esac
done
echo "3) 头文件、pkg-config 描述文件与 magic 数据库："
for f in /usr/include/magic.h /usr/lib/pkgconfig/libmagic.pc /usr/share/misc/magic.mgc; do
  if [ -s "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
echo "   libmagic.pc 内容："
sed 's/^/     /' /usr/lib/pkgconfig/libmagic.pc
pc_prefix=$(sed -n 's/^prefix=//p' /usr/lib/pkgconfig/libmagic.pc | head -n1)
if [ "$pc_prefix" = "/usr" ]; then echo "     OK   libmagic.pc 中 prefix=/usr"
else echo "     FAIL libmagic.pc 中 prefix 为 '$pc_prefix'"; rc=1; fi
echo "   magic.mgc 与本次构建产物一致性（应与 magic/magic.mgc 完全相同）："
if cmp -s magic/magic.mgc /usr/share/misc/magic.mgc; then
  echo "     OK   /usr/share/misc/magic.mgc 与构建目录中的 magic/magic.mgc 内容一致"
else echo "     FAIL /usr/share/misc/magic.mgc 与 magic/magic.mgc 不一致"; rc=1; fi
echo "4) 手册页（doc/Makefile.am 的 man_MANS = file.1 magic.4 libmagic.3）："
for m in man1/file.1 man3/libmagic.3 man4/magic.4; do
  if [ -f "/usr/share/man/$m" ]; then
    printf '   OK   %-18s（%s 字节）\n' "$m" "$(stat -Lc %s "/usr/share/man/$m")"
  else printf '   FAIL /usr/share/man/%s 缺失\n' "$m"; rc=1; fi
done
if [ -e /usr/share/man/man5/magic.5 ]; then
  echo "   INFO /usr/share/man/man5/magic.5 存在（本节未用 --enable-fsect-man5，非本节产物）"
else
  echo "   INFO /usr/share/man/man5/magic.5 不存在（预期：未给 --enable-fsect-man5）"
fi
echo "5) 版本与运行验证："
echo "   file --version："
file --version 2>&1 | sed 's/^/     /'
inst_ver=$(file --version 2>&1 | sed -n '1s/^file-//p')
if [ "$inst_ver" = "$VER" ]; then echo "   OK   file 版本 $inst_ver"
else echo "   FAIL file 版本为 '$inst_ver'"; rc=1; fi
echo "   file 链接到的共享库（应链接到刚装好的 libmagic.so.1）："
ldd /usr/bin/file | sed 's/^/     /'
bin_ldd=$(ldd /usr/bin/file)
case "$bin_ldd" in
  *libmagic.so.1*) echo "     OK   /usr/bin/file 链接到 libmagic.so.1" ;;
  *) echo "     FAIL /usr/bin/file 未链接到 libmagic.so.1"; rc=1 ;;
esac
echo "   file 默认使用的 magic 路径（-C/--version 的第二行）："
file --version 2>&1 | sed -n '2,4p' | sed 's/^/     /'
echo "6) 功能验证（自加检查，非手册命令）："
tmpd=$(mktemp -d /tmp/file-verify-XXXXXX)
printf '#!/bin/sh\necho hello\n' > "$tmpd/script.sh"
printf 'plain ascii text for lfs 8.11\n' > "$tmpd/plain.txt"
cp /usr/bin/file "$tmpd/elf.bin"
echo "   基本类型识别："
for spec in "elf.bin:ELF 64-bit LSB" "script.sh:POSIX shell script" "plain.txt:ASCII text" \
            "/usr/lib/libmagic.so.1.0.0:ELF 64-bit LSB shared object"; do
  tgt=${spec%%:*}; want=${spec#*:}
  case "$tgt" in /*) p=$tgt ;; *) p=$tmpd/$tgt ;; esac
  out=$(file -b "$p")
  case "$out" in
    *"$want"*) printf '     OK   %-28s -> %s\n' "$(basename "$p")" "$out" ;;
    *) printf '     FAIL %-28s -> %s（期望包含「%s」）\n' "$(basename "$p")" "$out" "$want"; rc=1 ;;
  esac
done
echo "   压缩支持验证（file -z 解开后再识别内容，逐一对应前面启用的四个 *SUPPORT 宏）："
for spec in "gz:gzip -c" "bz2:bzip2 -c" "xz:xz -c" "zst:zstd -q -c"; do
  ext=${spec%%:*}; comp=${spec#*:}
  $comp < "$tmpd/plain.txt" > "$tmpd/plain.txt.$ext"
  raw=$(file -b "$tmpd/plain.txt.$ext")
  unz=$(file -bz "$tmpd/plain.txt.$ext")
  printf '     .%-4s file    -> %s\n' "$ext" "$raw"
  printf '     .%-4s file -z -> %s\n' "$ext" "$unz"
  case "$unz" in
    *"ASCII text"*) printf '     OK   file -z 成功解开 .%s 并识别出内层 ASCII text\n' "$ext" ;;
    *) printf '     FAIL file -z 未能解开 .%s（%s 支持未生效？）\n' "$ext" "$ext"; rc=1 ;;
  esac
done
echo "   libmagic 直接链接验证（-lmagic 编译并运行）："
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
#include <magic.h>
int main(int argc, char **argv) {
    magic_t m = magic_open(MAGIC_NONE);
    const char *r;
    if (!m) { printf("magic_open failed\n"); return 1; }
    printf("magic_version() = %d\n", magic_version());
    if (magic_load(m, NULL) != 0) {
        printf("magic_load failed: %s\n", magic_error(m)); magic_close(m); return 2;
    }
    r = magic_file(m, argv[1]);
    if (!r) { printf("magic_file failed: %s\n", magic_error(m)); magic_close(m); return 3; }
    printf("magic_file(%s) = %s\n", argv[1], r);
    magic_close(m);
    return 0;
}
EOF
if gcc -o "$tmpd/t" "$tmpd/t.c" -lmagic && "$tmpd/t" "$tmpd/plain.txt"; then
  echo "     OK   -lmagic 链接、magic_open/magic_load/magic_file 调用均正常"
  ldd "$tmpd/t" | sed -n 's/.*\(libmagic[^ ]*\)/        \1/p'
else echo "     FAIL 无法用 -lmagic 编译或运行 libmagic 测试程序"; rc=1; fi
rm -rf "$tmpd"
echo "7) 本节写入系统的文件清单："
ls -l /usr/bin/file /usr/lib/libmagic* /usr/lib/pkgconfig/libmagic.pc \
      /usr/include/magic.h /usr/share/misc/magic.mgc \
      /usr/share/man/man1/file.1 /usr/share/man/man3/libmagic.3 \
      /usr/share/man/man4/magic.4 2>/dev/null | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：File 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留测试摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.11.sh"
echo "  移入 \$LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure  完整输出：$CONFLOG（= 宿主 \$LFS_ROOT/sources/.file-configure.log）"
echo "  make check 完整输出：$CHECKLOG（= 宿主 \$LFS_ROOT/sources/.file-make-check.log）"
cd /sources
rm -rf "$SRCDIR"
[ -d "/sources/$SRCDIR" ] && { echo "错误：源码目录未清理" >&2; exit 1; }
echo "已删除 /sources/$SRCDIR"
echo "/sources 下的解包残留（应为空）："
find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.11 完成，结束时间：$(date -Is) ====="
