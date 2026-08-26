#!/usr/bin/env bash
# LFS 13.0-systemd §8.9 Lz4-1.10.0
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.9.1 Installation of Lz4 的命令序列（全部，一条不多一条不少）：
#   make BUILD_STATIC=no PREFIX=/usr
#   make -j1 check
#   make BUILD_STATIC=no PREFIX=/usr install
# 本节没有 configure、没有补丁、没有 sed 改写、没有 rm。§8.9.2 只是 Contents 说明。
set -euo pipefail

PKG=lz4
VER=1.10.0
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
CHECKLOG=/sources/.lz4-make-check.log

echo "===== LFS 13.0-systemd §8.9 Lz4-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：Lz4 is a lossless compression algorithm, providing compression speed"
echo "  greater than 500 MB/s per core. It features an extremely fast decoder, with"
echo "  speed in multiple GB/s per core. Lz4 can work with Zstandard to allow both"
echo "  algorithms to compress data faster."
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 4.2 MB"
echo "手册存档：/workspace/docs/book/chapter08-lz4.html（宿主机 $LFS_ROOT/docs/book/）"
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
echo "注意：手册本节的测试命令是 make -j1 check —— 命令行上的 -j1 优先于环境变量"
echo "  MAKEFLAGS 里的 -j$(nproc)，测试因此串行执行，这正是手册要求的。"
echo "可用空间（手册本节要求 4.2 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 5 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 4.2MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.8 Xz-5.8.2）产物必须可用 -----"
rc=0
echo "1) §8.8.2 Contents of Xz 的关键产物："
for f in /usr/bin/xz /usr/bin/xzcat /usr/bin/unxz /usr/bin/lzma \
         /usr/lib/liblzma.so /usr/lib/liblzma.so.5 /usr/lib/liblzma.so.5.8.2 \
         /usr/include/lzma.h /usr/lib/pkgconfig/liblzma.pc; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.8 未完成？）\n' "$f"; rc=1; fi
done
xz_ver=$(xz --version | sed -n '1s/.*xz (XZ Utils) //p')
if [ "$xz_ver" = "5.8.2" ]; then echo "   OK   xz 自述版本 $xz_ver（§8.8 原生重建版本）"
else echo "   FAIL xz 自述版本为 '$xz_ver'，应为 5.8.2"; rc=1; fi
echo "   xz 往返自检："
if [ "$(printf 'lfs 8.9 precheck\n' | xz -c | xzcat)" = 'lfs 8.9 precheck' ]; then
  echo "     OK   xz -> xzcat 往返正常"
else echo "     FAIL xz 往返失败"; rc=1; fi
echo "2) §8.7 Bzip2 / §8.6 Zlib 产物仍可用："
for f in /usr/bin/bzip2 /usr/lib/libbz2.so.1.0.8 /usr/lib/libz.so.1.3.2 /usr/include/zlib.h; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "3) §8.5 Glibc-2.43 的 C 库可用（本节要编译 C 代码并跑测试）："
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
echo "5) 本节直接依赖的工具（解包 + make + 测试 + 安装）："
for t in tar gzip make gcc ld ar ranlib sed grep awk cmp diff cp install ln rm mkdir \
         md5sum readelf objdump find stat bash od dd; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "6) 安装目标目录："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/lib/pkgconfig; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo "7) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "8) §7.3 虚拟内核文件系统与 §7.6 基础文件："
for f in /dev/null /dev/urandom /proc/self /sys /etc/passwd /etc/group; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "9) 本节安装前系统中不应存在 Lz4（第 5~7 章从未构建过 lz4，本节是首次安装）："
for f in /usr/bin/lz4 /usr/lib/liblz4.so /usr/include/lz4.h /usr/lib/liblz4.a; do
  if [ -e "$f" ]; then printf '   INFO %-24s 已存在（%s 字节，%s）\n' "$f" "$(stat -Lc %s "$f")" "$(stat -Lc %y "$f" | cut -d. -f1)"
  else printf '   OK   %-24s 不存在（预期，本节首次安装）\n' "$f"; fi
done
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
echo "上游版本自述（lib/lz4.h 的 LZ4_VERSION_* 宏）："
grep -E '^#define LZ4_VERSION_(MAJOR|MINOR|RELEASE) ' lib/lz4.h | sed 's/^/  /'
h_major=$(awk '/^#define LZ4_VERSION_MAJOR /{print $3}'   lib/lz4.h)
h_minor=$(awk '/^#define LZ4_VERSION_MINOR /{print $3}'   lib/lz4.h)
h_patch=$(awk '/^#define LZ4_VERSION_RELEASE /{print $3}' lib/lz4.h)
src_ver="$h_major.$h_minor.$h_patch"
if [ "$src_ver" = "$VER" ]; then echo "  OK   源码自述版本 $src_ver 与手册 §8.9 的 Lz4-$VER 一致"
else echo "  FAIL 源码自述版本为 $src_ver，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁：手册 §8.9 的命令序列里没有 patch，/sources 下也没有 lz4 补丁"
lz4_patches=$(ls /sources | grep -Ei 'lz4.*patch' || true)
echo "  （/sources 中匹配 lz4*patch 的文件：${lz4_patches:-无}）"
echo "本节无 configure：lz4 用纯 Makefile 构建，前缀由命令行 PREFIX=/usr 传入。"
echo

echo "================= 8.9.1. Installation of Lz4 ================="
echo "手册原文：Compile the package:"
echo "手册命令：make BUILD_STATIC=no PREFIX=/usr"
make BUILD_STATIC=no PREFIX=/usr
echo
echo "----- 编译结果确认 -----"
for f in programs/lz4 lib/liblz4.so.$VER lib/liblz4.pc; do
  if [ -e "$f" ]; then printf '  OK   %-28s %s 字节\n' "$f" "$(stat -Lc %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; exit 1; fi
done
echo "  构建目录内的库文件："
ls -l lib/liblz4* | sed 's/^/    /'
echo "  说明：BUILD_STATIC=no 只影响 install 阶段是否安装 liblz4.a（见 lib/Makefile 的"
echo "  install 规则 ifeq \$(BUILD_STATIC),yes）；顶层 default 目标仍会在构建目录里生成"
echo "  liblz4.a，它不会被安装——安装后会在下面确认 /usr/lib/liblz4.a 不存在。"
echo "  共享库 SONAME："
objdump -p lib/liblz4.so.$VER | awk '/SONAME/{print "    "$0}'
echo "  生成的 liblz4.pc（PREFIX=/usr 是否生效）："
sed 's/^/    /' lib/liblz4.pc
pc_prefix=$(sed -n 's/^prefix=//p' lib/liblz4.pc | head -n1)
if [ "$pc_prefix" = "/usr" ]; then echo "    OK   liblz4.pc 中 prefix=/usr，PREFIX=/usr 生效"
else echo "    FAIL liblz4.pc 中 prefix 为 '$pc_prefix'，应为 /usr"; exit 1; fi
echo "  刚编译出的 lz4 自述版本："
./programs/lz4 --version | sed 's/^/    /'
echo

echo "手册原文：To test the results, issue:"
echo "手册命令：make -j1 check"
echo "（lz4 的 check = tests/ 目录的 test-lz4-essentials，是一组 shell 驱动的功能测试，"
echo "  没有 automake 的 Testsuite summary 汇总；手册未给出任何“允许失败”的说明，故判定"
echo "  依据就是 make 的退出码，不使用泛化关键字扫描——测试脚本正常输出里本来就带有"
echo "  compression/decompression error 之类的字样。）"
set +e
make -j1 check 2>&1 | tee "$CHECKLOG"
check_rc=${PIPESTATUS[0]}
set -e
echo
echo "----- make -j1 check 结论 -----"
echo "make -j1 check 退出码：$check_rc"
echo "输出行数：$(wc -l < "$CHECKLOG")"
echo "测试阶段标题（tests/Makefile 中各 test-lz4-* 目标打印的 ---- xxx ---- 行；"
echo "  这些 echo 里带字面量 \\n，bash 的 echo 不展开，故行首可能有 \\n）："
grep -F -- ' ---- ' "$CHECKLOG" | sed 's/^/  /' || true
stages=$(grep -Fc -- ' ---- ' "$CHECKLOG" || true)
echo "阶段标题行数：${stages:-0}"
echo "输出末尾 20 行："
tail -n 20 "$CHECKLOG" | sed 's/^/  /'
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make -j1 check 退出码非 0（$check_rc），手册未允许本节存在失败" >&2
  exit "$check_rc"
fi
# 判定只依据 make 的退出码 + 测试确实产生了输出；阶段标题数量仅作参考，
# 不作为失败判据（上游用 echo "\n ----" 打印标题，其展开与否取决于 shell）。
log_lines=$(wc -l < "$CHECKLOG")
if [ "$log_lines" -lt 5 ]; then
  echo "错误：make -j1 check 只产生了 $log_lines 行输出，测试可能没有真正运行" >&2
  exit 1
fi
echo "结论：make -j1 check 退出码 0，测试全程无失败（lz4 的 check = tests/ 的"
echo "  test-lz4-essentials，含 test-lz4-basic / -multiple / -multiple-legacy /"
echo "  -frame-concatenation / -testmode / -contentSize / -dict）。任何一步失败都会让"
echo "  make 立即以非 0 退出，因此退出码 0 即表示本节测试全部通过，符合手册预期"
echo "  （手册对本节未列出任何允许失败的项）。"
echo

echo "手册原文：Install the package:"
echo "手册命令：make BUILD_STATIC=no PREFIX=/usr install"
make BUILD_STATIC=no PREFIX=/usr install
echo

echo "----- 安装后检查（手册 §8.9.2 Contents of Lz4） -----"
rc=0
echo "1) Installed programs：lz4、lz4c（link to lz4）、lz4cat（link to lz4）、unlz4（link to lz4）"
if [ -f /usr/bin/lz4 ] && [ ! -L /usr/bin/lz4 ]; then
  printf '   OK   %-8s（%s 字节，实体文件）%s\n' lz4 "$(stat -Lc %s /usr/bin/lz4)" "$(file -b /usr/bin/lz4 | cut -c1-50)"
else printf '   FAIL /usr/bin/lz4 缺失或不是实体文件\n'; rc=1; fi
for p in lz4c lz4cat unlz4; do
  got=$(readlink /usr/bin/$p 2>/dev/null || true)
  if [ "$got" = lz4 ]; then printf '   OK   %-8s -> lz4（符合手册 link to lz4）\n' "$p"
  else printf '   FAIL /usr/bin/%s 应为指向 lz4 的符号链接，实为 %s\n' "$p" "${got:-不存在或非符号链接}"; rc=1; fi
done
ls -l /usr/bin/lz4 /usr/bin/lz4c /usr/bin/lz4cat /usr/bin/unlz4 2>/dev/null | sed 's/^/     /'
echo "2) Installed library：liblz4.so"
for f in /usr/lib/liblz4.so /usr/lib/liblz4.so.1 /usr/lib/liblz4.so.$VER; do
  if [ -e "$f" ]; then printf '   OK   %-28s -> %s（%s 字节）\n' "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
ls -l /usr/lib/liblz4* | sed 's/^/     /'
echo "   SONAME 必须是 liblz4.so.1："
soname=$(objdump -p /usr/lib/liblz4.so.$VER | awk '/SONAME/{print $2}')
echo "     SONAME = $soname"
if [ "$soname" = "liblz4.so.1" ]; then echo "     OK   SONAME 正确"
else echo "     FAIL SONAME 应为 liblz4.so.1"; rc=1; fi
echo "   BUILD_STATIC=no 的效果：/usr/lib/liblz4.a 不应被安装"
if [ -e /usr/lib/liblz4.a ]; then echo "     FAIL /usr/lib/liblz4.a 存在，BUILD_STATIC=no 未生效"; rc=1
else echo "     OK   /usr/lib/liblz4.a 不存在"; fi
echo "   BUILD_STATIC=no 的效果：静态构建才安装的头文件不应出现"
for f in /usr/include/lz4frame_static.h /usr/include/lz4file.h; do
  if [ -e "$f" ]; then echo "     FAIL $f 存在（只有 BUILD_STATIC=yes 才会安装）"; rc=1
  else echo "     OK   $f 不存在"; fi
done
echo "   动态符号抽查（先落盘再匹配，避免管道 SIGPIPE 误判）："
dynsyms=$(mktemp /tmp/liblz4-dynsyms-XXXXXX)
readelf --dyn-syms -W /usr/lib/liblz4.so.$VER > "$dynsyms"
for s in LZ4_versionNumber LZ4_versionString LZ4_compress_default LZ4_decompress_safe \
         LZ4_compress_HC LZ4F_compressFrame LZ4F_decompress; do
  if grep -E "[[:space:]]$s\$|[[:space:]]$s@" "$dynsyms" > /dev/null; then
    printf '     OK   %s\n' "$s"
  else printf '     FAIL 动态符号 %s 缺失\n' "$s"; rc=1; fi
done
rm -f "$dynsyms"
echo "3) 头文件与 pkg-config 描述文件（lib/Makefile 的 install 规则）："
for f in /usr/include/lz4.h /usr/include/lz4hc.h /usr/include/lz4frame.h; do
  if [ -e "$f" ]; then printf '   OK   %-28s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
if [ -s /usr/lib/pkgconfig/liblz4.pc ]; then
  echo "   OK   /usr/lib/pkgconfig/liblz4.pc"
  sed 's/^/        /' /usr/lib/pkgconfig/liblz4.pc
else echo "   FAIL /usr/lib/pkgconfig/liblz4.pc 缺失"; rc=1; fi
echo "4) 手册页（programs/Makefile 的 install 规则）："
if [ -f /usr/share/man/man1/lz4.1 ]; then echo "   OK   /usr/share/man/man1/lz4.1（$(stat -Lc %s /usr/share/man/man1/lz4.1) 字节）"
else echo "   FAIL /usr/share/man/man1/lz4.1 缺失"; rc=1; fi
for m in lz4c.1 lz4cat.1 unlz4.1; do
  got=$(readlink "/usr/share/man/man1/$m" 2>/dev/null || true)
  if [ "$got" = "lz4.1" ]; then printf '   OK   %-10s -> lz4.1\n' "$m"
  else printf '   FAIL /usr/share/man/man1/%s 应指向 lz4.1，实为 %s\n' "$m" "${got:-不存在}"; rc=1; fi
done
echo "5) 版本与运行验证（安装后的 /usr/bin/lz4 必须是本节刚编译的 $VER）："
echo "   lz4 --version："
lz4 --version 2>&1 | sed 's/^/     /'
inst_ver=$(lz4 --version 2>&1 | sed -n '1s/.*v\([0-9.]*\).*/\1/p')
if [ "$inst_ver" = "$VER" ]; then echo "   OK   lz4 版本 $inst_ver"
else echo "   FAIL lz4 版本为 '$inst_ver'"; rc=1; fi
echo "   lz4 链接到的共享库："
ldd /usr/bin/lz4 | sed 's/^/     /'
ldd_out=$(ldd /usr/bin/lz4)
echo "     INFO 上游设计：programs/Makefile 的 lz4 目标直接把 lib/*.c 编进可执行文件"
echo "          （SRCFILES = LIBFILES + programs/*.c），并不去链接 liblz4.so；链接"
echo "          -llz4 的是另一个目标 lz4-wlib，手册本节不使用它。因此 /usr/bin/lz4 的"
echo "          ldd 中没有 liblz4.so.1 属于预期，不是缺陷。liblz4.so 的可用性由下面"
echo "          第 6 项的 -llz4 编译/运行验证覆盖。"
case "$ldd_out" in
  *libc.so.6*) echo "     OK   动态链接到 §8.5 装好的 libc.so.6" ;;
  *) echo "     FAIL 未链接到 libc.so.6"; rc=1 ;;
esac
echo "6) 功能验证（自加检查，非手册命令）：压缩-解压往返 + 各命令别名"
tmpd=$(mktemp -d /tmp/lz4-verify-XXXXXX)
head -c 300000 /usr/share/man/man1/lz4.1 > "$tmpd/plain" 2>/dev/null || true
if [ ! -s "$tmpd/plain" ]; then
  for i in $(seq 1 5000); do echo "LFS 13.0-systemd lz4 round trip line $i"; done > "$tmpd/plain"
fi
orig_sum=$(md5sum < "$tmpd/plain" | cut -d' ' -f1)
orig_size=$(stat -c %s "$tmpd/plain")
lz4 -q -f "$tmpd/plain" "$tmpd/t.lz4"
csize=$(stat -c %s "$tmpd/t.lz4")
new_sum=$(lz4cat "$tmpd/t.lz4" | md5sum | cut -d' ' -f1)
if [ "$new_sum" = "$orig_sum" ]; then
  printf '   OK   lz4 压缩 %s -> %s 字节，lz4cat 解压后 md5 与原文一致（%s）\n' "$orig_size" "$csize" "$orig_sum"
else printf '   FAIL lz4/lz4cat 往返后内容不一致\n'; rc=1; fi
echo "   lz4 -t 完整性校验："
if lz4 -t "$tmpd/t.lz4" >/dev/null 2>&1; then echo "     OK   lz4 -t 通过"
else echo "     FAIL lz4 -t 失败"; rc=1; fi
echo "   unlz4 解压："
unlz4 -q -f "$tmpd/t.lz4" "$tmpd/unlz4.out"
if [ "$(md5sum < "$tmpd/unlz4.out" | cut -d' ' -f1)" = "$orig_sum" ]; then echo "     OK   unlz4 输出与原文一致"
else echo "     FAIL unlz4 输出不一致"; rc=1; fi
echo "   lz4c（旧版命令行别名）："
lz4c -q -f "$tmpd/plain" "$tmpd/t2.lz4"
if [ "$(lz4cat "$tmpd/t2.lz4" | md5sum | cut -d' ' -f1)" = "$orig_sum" ]; then echo "     OK   lz4c 压缩结果可正确解压"
else echo "     FAIL lz4c 往返失败"; rc=1; fi
echo "   高压缩比模式 lz4 -9："
lz4 -q -f -9 "$tmpd/plain" "$tmpd/t9.lz4"
printf '     -9 压缩后 %s 字节（默认级别 %s 字节）\n' "$(stat -c %s "$tmpd/t9.lz4")" "$csize"
if [ "$(lz4cat "$tmpd/t9.lz4" | md5sum | cut -d' ' -f1)" = "$orig_sum" ]; then echo "     OK   -9 往返一致"
else echo "     FAIL -9 往返失败"; rc=1; fi
echo "   liblz4 直接链接验证（-llz4 编译并运行）："
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lz4.h>
#include <lz4frame.h>
int main(void) {
    const char *src = "LFS 13.0-systemd liblz4 round trip -- "
                      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    char cbuf[512], dbuf[512];
    int slen = (int)strlen(src) + 1;
    int clen, dlen;
    printf("LZ4_VERSION_STRING(header)=%s LZ4_versionString(lib)=%s LZ4_versionNumber=%d\n",
           LZ4_VERSION_STRING, LZ4_versionString(), LZ4_versionNumber());
    clen = LZ4_compress_default(src, cbuf, slen, (int)sizeof cbuf);
    if (clen <= 0) return 1;
    dlen = LZ4_decompress_safe(cbuf, dbuf, clen, (int)sizeof dbuf);
    if (dlen != slen) return 2;
    printf("block: %d -> %d -> %d bytes, round trip %s\n",
           slen, clen, dlen, memcmp(dbuf, src, (size_t)slen) == 0 ? "OK" : "MISMATCH");
    if (memcmp(dbuf, src, (size_t)slen) != 0) return 3;
    {   /* frame API，验证 lz4frame.h 与 LZ4F_* 符号可用 */
        size_t fbound = LZ4F_compressFrameBound((size_t)slen, NULL);
        char *fbuf = malloc(fbound);
        if (!fbuf) return 4;
        size_t flen = LZ4F_compressFrame(fbuf, fbound, src, (size_t)slen, NULL);
        if (LZ4F_isError(flen)) { free(fbuf); return 5; }
        printf("frame: %d -> %zu bytes, LZ4F_compressFrame OK\n", slen, flen);
        free(fbuf);
    }
    return 0;
}
EOF
if gcc -o "$tmpd/t" "$tmpd/t.c" -llz4 && "$tmpd/t"; then
  echo "     OK   -llz4 链接、运行、块 API 与帧 API 往返均正常"
  ldd "$tmpd/t" | sed -n 's/.*\(liblz4[^ ]*\)/        \1/p'
else echo "     FAIL 无法用 -llz4 编译或运行 liblz4 测试程序"; rc=1; fi
echo "   pkg-config 描述文件可被 gcc 使用（手工展开 liblz4.pc 的 Libs/Cflags）："
pc_libs=$(sed -n 's/^Libs: //p' /usr/lib/pkgconfig/liblz4.pc | sed 's/\${exec_prefix}/\/usr/; s/\${libdir}/\/usr\/lib/')
echo "     Libs = $pc_libs"
rm -rf "$tmpd"
echo "7) 本节写入系统的文件清单："
ls -l /usr/bin/lz4 /usr/bin/lz4c /usr/bin/lz4cat /usr/bin/unlz4 \
      /usr/lib/liblz4* /usr/lib/pkgconfig/liblz4.pc \
      /usr/include/lz4.h /usr/include/lz4hc.h /usr/include/lz4frame.h \
      /usr/share/man/man1/lz4.1 /usr/share/man/man1/lz4c.1 \
      /usr/share/man/man1/lz4cat.1 /usr/share/man/man1/unlz4.1 2>/dev/null | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Lz4 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留测试摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.9.sh"
echo "  移入 $LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  make -j1 check 完整输出已在 $CHECKLOG（= 宿主 $LFS_ROOT/sources/.lz4-make-check.log）"
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
echo "===== §8.9 完成，结束时间：$(date -Is) ====="
