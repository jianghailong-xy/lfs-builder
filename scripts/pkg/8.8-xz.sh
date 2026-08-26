#!/usr/bin/env bash
# LFS 13.0-systemd §8.8 Xz-5.8.2
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.8.1 Installation of Xz 的命令序列（全部，一条不多一条不少）：
#   ./configure --prefix=/usr    \
#       --disable-static \
#       --docdir=/usr/share/doc/xz-5.8.2
#   make
#   make check
#   make install
# 本节没有补丁、没有 sed 改写、没有 rm（第 6 章的 rm -v $LFS/usr/lib/liblzma.la
# 是 §6.16 的命令，不属于 §8.8）。§8.8.2 只是 Contents 说明。
set -euo pipefail

PKG=xz
VER=5.8.2
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
CHECKLOG=/sources/.xz-make-check.log

echo "===== LFS 13.0-systemd §8.8 Xz-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Xz package contains programs for compressing and decompressing files."
echo "  It provides capabilities for the lzma and the newer xz compression formats."
echo "  Compressing text files with xz yields a better compression percentage than with"
echo "  the traditional gzip or bzip2 commands."
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 24 MB"
echo "手册存档：/workspace/docs/book/chapter08-xz.html（宿主机 $LFS_ROOT/docs/book/）"
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
echo "可用空间（手册本节要求 24 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 24 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 24MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.7 Bzip2-1.0.8）产物必须可用 -----"
rc=0
echo "1) §8.7.2 Contents of Bzip2 列出的产物："
for f in /usr/bin/bzip2 /usr/bin/bunzip2 /usr/bin/bzcat /usr/bin/bzip2recover \
         /usr/bin/bzdiff /usr/bin/bzgrep /usr/bin/bzmore \
         /usr/lib/libbz2.so /usr/lib/libbz2.so.1 /usr/lib/libbz2.so.1.0 \
         /usr/lib/libbz2.so.1.0.8 /usr/include/bzlib.h; do
  if [ -e "$f" ]; then printf '   OK   %-28s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.7 未完成？）\n' "$f"; rc=1; fi
done
if [ -e /usr/lib/libbz2.a ]; then echo "   FAIL /usr/lib/libbz2.a 仍存在（§8.7 要求 rm -fv）"; rc=1
else echo "   OK   /usr/lib/libbz2.a 已按 §8.7 删除"; fi
echo "   bzip2 自述版本：$(bzip2 --help 2>&1 | sed -n 1p)"
echo "   bzip2 往返自检："
if [ "$(printf 'lfs 8.8 precheck\n' | bzip2 -c | bunzip2 -c)" = 'lfs 8.8 precheck' ]; then
  echo "     OK   bzip2 -> bunzip2 往返正常"
else echo "     FAIL bzip2 往返失败"; rc=1; fi
echo "2) §8.6 Zlib-1.3.2 产物仍可用："
for f in /usr/lib/libz.so.1.3.2 /usr/include/zlib.h; do
  if [ -e "$f" ]; then printf '   OK   %-28s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "3) §8.5 Glibc-2.43 的 C 库可用（本节要编译 C 代码并跑测试套件）："
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
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo "5) 本节直接依赖的工具（解包 + configure + make + 测试 + 安装）："
for t in tar xz make gcc ld ar ranlib sed grep awk cmp diff cp install ln rm mkdir \
         md5sum readelf objdump find stat bash perl; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   perl 版本：$(perl -e 'print "$^V\n"')"
echo "6) 安装目标目录："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/lib/pkgconfig; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo "7) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "8) §7.3 虚拟内核文件系统与 §7.6 基础文件："
for f in /dev/null /proc/self /sys /etc/passwd /etc/group; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "9) 本节安装前系统中已有的 Xz（第 6 章 §6.16 交叉编译装入 \$LFS 的临时版本，"
echo "   本节将用 chroot 内原生编译的版本覆盖它——这正是第 8 章重建的目的）："
for f in /usr/bin/xz /usr/lib/liblzma.so.$VER /usr/include/lzma.h; do
  if [ -e "$f" ]; then printf '   INFO %-30s（%s 字节，%s）\n' "$f" "$(stat -Lc %s "$f")" "$(stat -Lc %y "$f" | cut -d. -f1)"
  else printf '   INFO %s 不存在\n' "$f"; fi
done
echo "   现有 xz 自述版本：$(xz --version 2>&1 | sed -n 1p)"
echo "   注意：本节要解包的就是 .tar.xz，解包用的正是这个即将被覆盖的 xz。"
echo "   （手册 §6.16 有 rm -v \$LFS/usr/lib/liblzma.la，故当前不应有 liblzma.la：$(ls /usr/lib/liblzma.la 2>/dev/null || echo '确认不存在')）"
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
echo "上游版本自述（configure 中的 PACKAGE_VERSION）："
cfg_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'$/\1/p" configure | head -n1)
echo "  PACKAGE_VERSION=$cfg_ver"
echo "上游版本自述（src/liblzma/api/lzma/version.h）："
grep -E '^#define LZMA_VERSION_(MAJOR|MINOR|PATCH) ' src/liblzma/api/lzma/version.h | sed 's/^/  /'
if [ "$cfg_ver" = "$VER" ]; then echo "  OK   与手册 §8.8 的 Xz-$VER 一致"
else echo "  FAIL configure 自述版本为 $cfg_ver，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁：手册 §8.8 的命令序列里没有 patch，/sources 下也没有 xz 补丁"
echo "  （匹配数：$(ls /sources | grep -ci 'xz.*patch')）。"
echo

echo "================= 8.8.1. Installation of Xz ================="
echo "手册原文：Prepare Xz for compilation with:"
echo "手册命令：./configure --prefix=/usr    \\"
echo "              --disable-static \\"
echo "              --docdir=/usr/share/doc/xz-$VER"
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz-$VER
echo
echo "----- configure 结果确认 -----"
[ -f Makefile ] && echo "  OK   Makefile 已生成（$(wc -l < Makefile) 行）" || { echo "  FAIL Makefile 未生成"; exit 1; }
grep -E '^(prefix|exec_prefix|libdir|includedir|bindir|docdir|mandir) *=' Makefile | sed 's/^/  /'
mk_prefix=$(sed -n 's/^prefix *= *//p' Makefile | head -n1)
mk_docdir=$(sed -n 's/^docdir *= *//p' Makefile | head -n1)
[ "$mk_prefix" = "/usr" ] && echo "  OK   prefix=/usr，符合 --prefix=/usr" \
  || { echo "  FAIL Makefile 中 prefix 为 '$mk_prefix'，应为 /usr"; exit 1; }
[ "$mk_docdir" = "/usr/share/doc/xz-$VER" ] && echo "  OK   docdir=/usr/share/doc/xz-$VER，符合 --docdir" \
  || { echo "  FAIL Makefile 中 docdir 为 '$mk_docdir'"; exit 1; }
echo "  --disable-static 生效确认（libtool 的 build_old_libs 应为 no）："
grep -m1 '^build_old_libs=' libtool | sed 's/^/    /'
if grep -q '^build_old_libs=no$' libtool; then echo "    OK   build_old_libs=no（不构建静态库）"
else echo "    FAIL libtool 仍会构建静态库，--disable-static 未生效"; exit 1; fi
echo "  configure 摘要（config.log 中的 configure 行）："
grep -m1 '  \$ ./configure' config.log | sed 's/^/    /'
echo

echo "手册原文：Compile the package:"
echo "手册命令：make"
make
echo
echo "----- 编译结果确认 -----"
for f in src/xz/xz src/xzdec/xzdec src/lzmainfo/lzmainfo src/liblzma/.libs/liblzma.so.5.8.2; do
  if [ -f "$f" ]; then printf '  OK   %-40s %s 字节\n' "$f" "$(stat -c %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; exit 1; fi
done
echo "  --disable-static 的效果：构建目录内不应出现 liblzma.a"
static_libs=$(find . -name 'liblzma.a')
if [ -n "$static_libs" ]; then
  echo "$static_libs" | sed 's/^/    /'; echo "  FAIL 出现了静态库"; exit 1
else echo "    OK   构建目录内没有 liblzma.a"; fi
echo "  共享库 SONAME："
objdump -p src/liblzma/.libs/liblzma.so.5.8.2 | grep -m1 SONAME | sed 's/^/    /'
echo "  刚编译出的 xz 自述版本："
./src/xz/xz --version | sed 's/^/    /'
echo

echo "手册原文：To test the results, issue:"
echo "手册命令：make check"
echo "（本节手册未给出任何“允许失败”的说明，故期望全部测试通过；判定依据是"
echo "  automake 并行测试框架输出的 Testsuite summary 中 FAIL/ERROR 计数与 make 退出码，"
echo "  不使用泛化的关键字匹配。）"
set +e
make check 2>&1 | tee "$CHECKLOG"
check_rc=${PIPESTATUS[0]}
set -e
echo
echo "----- make check 结论 -----"
echo "make check 退出码：$check_rc"
echo "automake 测试汇总（Testsuite summary 区块）："
awk '/^Testsuite summary/{p=1} p{print "  "$0} /^====+$/{if(p&&++n%2==0)p=0}' "$CHECKLOG" || true
sum_total=$(awk '/^# TOTAL:/{s+=$3} END{print s+0}' "$CHECKLOG")
sum_pass=$(awk  '/^# PASS:/{s+=$3}  END{print s+0}' "$CHECKLOG")
sum_skip=$(awk  '/^# SKIP:/{s+=$3}  END{print s+0}' "$CHECKLOG")
sum_xfail=$(awk '/^# XFAIL:/{s+=$3} END{print s+0}' "$CHECKLOG")
sum_fail=$(awk  '/^# FAIL:/{s+=$3}  END{print s+0}' "$CHECKLOG")
sum_xpass=$(awk '/^# XPASS:/{s+=$3} END{print s+0}' "$CHECKLOG")
sum_err=$(awk   '/^# ERROR:/{s+=$3} END{print s+0}' "$CHECKLOG")
echo "合计：TOTAL=$sum_total PASS=$sum_pass SKIP=$sum_skip XFAIL=$sum_xfail FAIL=$sum_fail XPASS=$sum_xpass ERROR=$sum_err"
echo "逐条测试结果（PASS/FAIL/SKIP 行）："
grep -E '^(PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):' "$CHECKLOG" | sed 's/^/  /' || true
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make check 退出码非 0（$check_rc），手册未允许本节存在失败" >&2
  exit "$check_rc"
fi
if [ "$sum_total" -lt 1 ]; then
  echo "错误：没有解析到任何 Testsuite summary 计数，测试可能未真正运行" >&2
  exit 1
fi
if [ "$sum_fail" -ne 0 ] || [ "$sum_err" -ne 0 ] || [ "$sum_xpass" -ne 0 ]; then
  echo "错误：测试存在 FAIL=$sum_fail ERROR=$sum_err XPASS=$sum_xpass" >&2
  exit 1
fi
echo "结论：本节测试全部通过（$sum_pass/$sum_total 通过，SKIP=$sum_skip，0 失败 0 错误），符合手册预期。"
echo

echo "手册原文：Install the package:"
echo "手册命令：make install"
make install
echo

echo "----- 安装后检查（手册 §8.8.2 Contents of Xz） -----"
rc=0
echo "1) Installed programs（手册列出 23 个）："
for p in lzcat lzcmp lzdiff lzegrep lzfgrep lzgrep lzless lzma lzmadec lzmainfo \
         lzmore unlzma unxz xz xzcat xzcmp xzdec xzdiff xzegrep xzfgrep xzgrep \
         xzless xzmore; do
  if [ -e "/usr/bin/$p" ]; then
    if [ -L "/usr/bin/$p" ]; then printf '   OK   %-10s -> %s\n' "$p" "$(readlink "/usr/bin/$p")"
    else printf '   OK   %-10s（%s 字节，实体文件）\n' "$p" "$(stat -Lc %s "/usr/bin/$p")"; fi
  else printf '   FAIL /usr/bin/%s 缺失\n' "$p"; rc=1; fi
done
echo "   手册标注的链接关系逐条核对（link to X）："
check_link() { # <名字> <应指向>
  local n=$1 want=$2 got
  got=$(readlink "/usr/bin/$n" 2>/dev/null || true)
  if [ "$got" = "$want" ]; then printf '     OK   %-10s link to %s\n' "$n" "$want"
  else printf '     FAIL %-10s 应 link to %s，实为 %s\n' "$n" "$want" "${got:-非符号链接}"; rc=1; fi
}
check_link lzcat   xz
check_link lzcmp   xzdiff
check_link lzdiff  xzdiff
check_link lzegrep xzgrep
check_link lzfgrep xzgrep
check_link lzgrep  xzgrep
check_link lzless  xzless
check_link lzma    xz
check_link lzmore  xzmore
check_link unlzma  xz
check_link unxz    xz
check_link xzcat   xz
check_link xzcmp   xzdiff
check_link xzegrep xzgrep
check_link xzfgrep xzgrep
echo "   实体程序（手册未标 link to 的：lzmadec lzmainfo xz xzdec xzdiff xzgrep xzless xzmore）："
for p in lzmadec lzmainfo xz xzdec xzdiff xzgrep xzless xzmore; do
  if [ -L "/usr/bin/$p" ]; then printf '     FAIL %s 不应是符号链接\n' "$p"; rc=1
  else printf '     OK   %-10s %s\n' "$p" "$(file -b "/usr/bin/$p" 2>/dev/null | cut -c1-60)"; fi
done
echo "2) Installed libraries：liblzma.so"
for f in /usr/lib/liblzma.so /usr/lib/liblzma.so.5 /usr/lib/liblzma.so.$VER; do
  if [ -e "$f" ]; then printf '   OK   %-30s -> %s（%s 字节）\n' "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
ls -l /usr/lib/liblzma* | sed 's/^/     /'
echo "   libtool 归档 /usr/lib/liblzma.la：手册 §8.8 的 4 条命令里没有删除它的步骤"
echo "   （删除 liblzma.la 是 §6.16 对 \$LFS 临时系统的命令，不属于本节），故 make"
echo "   install 装出的 .la 按手册保留："
if [ -e /usr/lib/liblzma.la ]; then ls -l /usr/lib/liblzma.la | sed 's/^/     /'
else echo "     INFO /usr/lib/liblzma.la 不存在"; fi
echo "   --disable-static 的效果：/usr/lib/liblzma.a 不应存在"
if [ -e /usr/lib/liblzma.a ]; then echo "     FAIL /usr/lib/liblzma.a 存在"; rc=1
else echo "     OK   /usr/lib/liblzma.a 不存在"; fi
echo "   SONAME 必须是 liblzma.so.5："
soname=$(objdump -p /usr/lib/liblzma.so.$VER | awk '/SONAME/{print $2}')
echo "     SONAME = $soname"
[ "$soname" = "liblzma.so.5" ] && echo "     OK   SONAME 正确" || { echo "     FAIL SONAME 应为 liblzma.so.5"; rc=1; }
echo "   动态符号抽查："
dynsyms=$(mktemp /tmp/liblzma-dynsyms-XXXXXX)
readelf --dyn-syms -W /usr/lib/liblzma.so.$VER > "$dynsyms"
for s in lzma_version_string lzma_easy_buffer_encode lzma_stream_buffer_decode \
         lzma_code lzma_end lzma_stream_decoder; do
  if grep -qE "[[:space:]]$s\$|[[:space:]]$s@" "$dynsyms"; then
    printf '     OK   %s\n' "$s"
  else printf '     FAIL 动态符号 %s 缺失\n' "$s"; rc=1; fi
done
rm -f "$dynsyms"
echo "3) Installed directories：/usr/include/lzma 和 /usr/share/doc/xz-$VER"
for d in /usr/include/lzma /usr/share/doc/xz-$VER; do
  if [ -d "$d" ]; then printf '   OK   %-30s（%s 个条目）\n' "$d" "$(ls -A "$d" | wc -l)"
  else printf '   FAIL 目录 %s 缺失\n' "$d"; rc=1; fi
done
echo "   /usr/include/lzma 内容："
ls /usr/include/lzma | sed 's/^/     /'
echo "   /usr/share/doc/xz-$VER 内容（--docdir 指向此处，验证该选项确实生效）："
ls -A /usr/share/doc/xz-$VER | sed 's/^/     /'
if [ -e /usr/include/lzma.h ]; then echo "   OK   /usr/include/lzma.h（$(stat -c %s /usr/include/lzma.h) 字节）"
else echo "   FAIL /usr/include/lzma.h 缺失"; rc=1; fi
echo "4) pkg-config 描述文件与手册页："
if [ -s /usr/lib/pkgconfig/liblzma.pc ]; then
  echo "   OK   /usr/lib/pkgconfig/liblzma.pc"
  sed 's/^/        /' /usr/lib/pkgconfig/liblzma.pc
else echo "   FAIL /usr/lib/pkgconfig/liblzma.pc 缺失"; rc=1; fi
for m in xz.1 xzdec.1 lzmainfo.1 xzdiff.1 xzgrep.1 xzless.1 xzmore.1; do
  if [ -e "/usr/share/man/man1/$m" ]; then printf '   OK   /usr/share/man/man1/%s\n' "$m"
  else printf '   FAIL /usr/share/man/man1/%s 缺失\n' "$m"; rc=1; fi
done
echo "5) 版本与运行验证（安装后的 /usr/bin/xz 必须是本节刚编译的 $VER）："
echo "   xz --version："
xz --version | sed 's/^/     /'
inst_ver=$(xz --version | sed -n '1s/.*xz (XZ Utils) //p')
[ "$inst_ver" = "$VER" ] && echo "   OK   xz 版本 $inst_ver" || { echo "   FAIL xz 版本为 '$inst_ver'"; rc=1; }
lib_ver=$(xz --version | sed -n '2s/.*liblzma //p')
[ "$lib_ver" = "$VER" ] && echo "   OK   liblzma 版本 $lib_ver" || { echo "   FAIL liblzma 版本为 '$lib_ver'"; rc=1; }
echo "   xz 链接到的共享库："
ldd /usr/bin/xz | sed 's/^/     /'
echo "6) 功能验证（自加检查，非手册命令）：xz / lzma 两种格式的压缩-解压往返"
tmpd=$(mktemp -d /tmp/xz-verify-XXXXXX)
head -c 200000 /usr/share/man/man1/xz.1 > "$tmpd/plain" 2>/dev/null || \
  { for i in $(seq 1 4000); do echo "LFS 13.0-systemd xz round trip line $i"; done > "$tmpd/plain"; }
orig_sum=$(md5sum < "$tmpd/plain" | cut -d' ' -f1)
orig_size=$(stat -c %s "$tmpd/plain")
for fmt in xz lzma; do
  cp "$tmpd/plain" "$tmpd/t.$fmt.in"
  if [ "$fmt" = xz ]; then xz -c "$tmpd/t.$fmt.in" > "$tmpd/t.$fmt"; else lzma -c "$tmpd/t.$fmt.in" > "$tmpd/t.$fmt"; fi
  csize=$(stat -c %s "$tmpd/t.$fmt")
  if [ "$fmt" = xz ]; then xzcat "$tmpd/t.$fmt" > "$tmpd/t.$fmt.out"; else lzcat "$tmpd/t.$fmt" > "$tmpd/t.$fmt.out"; fi
  new_sum=$(md5sum < "$tmpd/t.$fmt.out" | cut -d' ' -f1)
  if [ "$new_sum" = "$orig_sum" ]; then
    printf '   OK   %-5s 格式：%s -> %s 字节，解压后 md5 与原文一致\n' "$fmt" "$orig_size" "$csize"
  else printf '   FAIL %s 格式往返后内容不一致\n' "$fmt"; rc=1; fi
done
echo "   xz -t 完整性校验：$(xz -t "$tmpd/t.xz" && echo OK || echo FAIL)"
echo "   xzdec 解码器：$(xzdec "$tmpd/t.xz" | md5sum | cut -d' ' -f1)（应为 $orig_sum）"
[ "$(xzdec "$tmpd/t.xz" | md5sum | cut -d' ' -f1)" = "$orig_sum" ] || { echo "   FAIL xzdec 输出不一致"; rc=1; }
echo "   lzmainfo 读取 .lzma 头："
lzmainfo "$tmpd/t.lzma" | sed 's/^/     /'
echo "   xzgrep / xzdiff / xzcmp 脚本可用性："
if xzgrep -c 'LFS\|xz' "$tmpd/t.xz" >/dev/null 2>&1 || xzgrep -q . "$tmpd/t.xz"; then echo "     OK   xzgrep 可运行"
else echo "     FAIL xzgrep 不可运行"; rc=1; fi
if xzdiff "$tmpd/t.xz" "$tmpd/t.xz" >/dev/null 2>&1; then echo "     OK   xzdiff 可运行（同文件比较无差异）"
else echo "     FAIL xzdiff 不可运行"; rc=1; fi
echo "   liblzma 直接链接验证（-llzma 编译并运行）："
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <lzma.h>
int main(void) {
    const char *src = "LFS 13.0-systemd liblzma round trip -- "
                      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    uint8_t buf[512]; char out[512];
    size_t opos = 0, ipos = 0, dpos = 0;
    printf("LZMA_VERSION_STRING(header)=%s lzma_version_string(lib)=%s\n",
           LZMA_VERSION_STRING, lzma_version_string());
    if (lzma_easy_buffer_encode(6, LZMA_CHECK_CRC64, NULL,
            (const uint8_t *)src, strlen(src) + 1, buf, &opos, sizeof buf) != LZMA_OK)
        return 1;
    uint64_t memlimit = UINT64_MAX;
    if (lzma_stream_buffer_decode(&memlimit, 0, NULL, buf, &ipos, opos,
            (uint8_t *)out, &dpos, sizeof out) != LZMA_OK)
        return 2;
    printf("encoded %zu -> %zu bytes, round trip %s\n",
           strlen(src) + 1, opos, strcmp(out, src) == 0 ? "OK" : "MISMATCH");
    return strcmp(out, src) == 0 ? 0 : 3;
}
EOF
if gcc -o "$tmpd/t" "$tmpd/t.c" -llzma && "$tmpd/t"; then
  echo "     OK   -llzma 链接、运行、压缩/解压往返均正常"
  ldd "$tmpd/t" | grep -i liblzma | sed 's/^/        /'
else echo "     FAIL 无法用 -llzma 编译或运行 liblzma 测试程序"; rc=1; fi
echo "   tar 解 .tar.xz 仍然可用（后续各节解包依赖它）："
if tar -tf "/sources/$TARBALL" >/dev/null 2>&1; then echo "     OK   tar -tf /sources/$TARBALL 正常"
else echo "     FAIL tar 无法读取 .tar.xz"; rc=1; fi
rm -rf "$tmpd"
echo "7) 本节写入 /usr 的文件清单（按安装时间筛出的 xz 相关条目）："
ls -l /usr/bin/{lzcat,lzcmp,lzdiff,lzegrep,lzfgrep,lzgrep,lzless,lzma,lzmadec,lzmainfo,lzmore,unlzma,unxz,xz,xzcat,xzcmp,xzdec,xzdiff,xzegrep,xzfgrep,xzgrep,xzless,xzmore} 2>/dev/null | sed 's/^/     /'
ls -l /usr/lib/liblzma* /usr/lib/pkgconfig/liblzma.pc /usr/include/lzma.h 2>/dev/null | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Xz 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留测试摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.8.sh"
echo "  移入 $LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  make check 完整输出已在 $CHECKLOG（= 宿主 $LFS_ROOT/sources/.xz-make-check.log）"
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
echo "===== §8.8 完成，结束时间：$(date -Is) ====="
