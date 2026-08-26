#!/usr/bin/env bash
# LFS 13.0-systemd §8.10 Zstd-1.5.7
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.10.1 Installation of Zstd 的命令序列（全部，一条不多一条不少）：
#   make prefix=/usr
#   make check
#   make prefix=/usr install
#   rm -v /usr/lib/libzstd.a
# 本节没有 configure、没有补丁、没有 sed 改写。§8.10.2 只是 Contents 说明。
set -euo pipefail

PKG=zstd
VER=1.5.7
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
CHECKLOG=/sources/.zstd-make-check.log

echo "===== LFS 13.0-systemd §8.10 Zstd-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：Zstandard is a real-time compression algorithm, providing high"
echo "  compression ratios. It offers a very wide range of compression / speed"
echo "  trade-offs, while being backed by a very fast decoder."
echo "手册数据：Approximate build time 0.4 SBU，Required disk space 86 MB"
echo "手册存档：/workspace/docs/book/chapter08-zstd.html（宿主机 /root/lfs/docs/book/）"
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
echo "说明：手册本节的测试命令就是 make check（不带 -j1），因此沿用 §7.4 环境里的"
echo "  MAKEFLAGS=-j$(nproc)。zstd 的 check 目标本身是一条 shell 脚本（tests/playTests.sh），"
echo "  并行度只作用于它所依赖的测试程序的编译。"
echo "可用空间（手册本节要求 86 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 90 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 86MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.9 Lz4-1.10.0）产物必须可用 -----"
rc=0
echo "1) §8.9.2 Contents of Lz4 的关键产物："
for f in /usr/bin/lz4 /usr/bin/lz4c /usr/bin/lz4cat /usr/bin/unlz4 \
         /usr/lib/liblz4.so /usr/lib/liblz4.so.1 /usr/lib/liblz4.so.1.10.0 \
         /usr/include/lz4.h /usr/include/lz4frame.h /usr/lib/pkgconfig/liblz4.pc; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.9 未完成？）\n' "$f"; rc=1; fi
done
lz4_ver=$(lz4 --version 2>&1 | sed -n '1s/.*v\([0-9.]*\).*/\1/p')
if [ "$lz4_ver" = "1.10.0" ]; then echo "   OK   lz4 自述版本 $lz4_ver"
else echo "   FAIL lz4 自述版本为 '$lz4_ver'，应为 1.10.0"; rc=1; fi
echo "   lz4 往返自检："
if [ "$(printf 'lfs 8.10 precheck\n' | lz4 -q -c | lz4cat)" = 'lfs 8.10 precheck' ]; then
  echo "     OK   lz4 -> lz4cat 往返正常"
else echo "     FAIL lz4 往返失败"; rc=1; fi
echo "2) §8.8 Xz / §8.7 Bzip2 / §8.6 Zlib 产物仍可用："
for f in /usr/bin/xz /usr/lib/liblzma.so /usr/include/lzma.h \
         /usr/bin/bzip2 /usr/lib/libbz2.so.1.0.8 \
         /usr/lib/libz.so /usr/lib/libz.so.1.3.2 /usr/include/zlib.h; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   说明：zstd 的 programs/Makefile 会自动探测 zlib / liblzma / liblz4（分别用"
echo "     -lz / -llzma / -llz4 试编译一个最小程序）。上面这三个包在手册里正好排在"
echo "     §8.10 之前，因此本节编译出的 zstd 会带 .gz / .xz|.lzma / .lz4 格式支持——"
echo "     编译阶段会打印三行 \"==> building zstd with ... support\"，下面会核对。"
echo "3) §8.5 Glibc-2.43 的 C 库可用（本节要编译 C 代码并跑测试）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
#include <pthread.h>
static void *f(void *p){ return p; }
int main(void){ pthread_t t; pthread_create(&t,0,f,0); pthread_join(t,0);
                printf("glibc+pthread sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" -pthread >/dev/null 2>&1 && \
   [ "$("${tmpc%.c}")" = "glibc+pthread sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C+pthread 程序成功（zstd 需要 pthread 才有多线程支持）"
else echo "   FAIL 无法用 gcc 编译/运行最小 C+pthread 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo "5) 本节直接依赖的工具（解包 + make + 测试 + 安装）："
for t in tar gzip make gcc ld ar ranlib sed grep awk cmp diff cp install ln rm mkdir \
         md5sum readelf objdump file find stat bash od dd printf touch chmod sort head tail; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   （tests/playTests.sh 会调用 file、diff、md5sum、od、dd 等；上面逐一确认过）"
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
for f in /dev/null /dev/zero /dev/urandom /proc/self /sys /etc/passwd /etc/group /tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "9) 本节安装前系统中不应存在 Zstd（第 5~7 章从未构建过 zstd，本节是首次安装）："
for f in /usr/bin/zstd /usr/lib/libzstd.so /usr/lib/libzstd.a /usr/include/zstd.h; do
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
echo "上游版本自述（lib/zstd.h 的 ZSTD_VERSION_* 宏）："
grep -E '^#define ZSTD_VERSION_(MAJOR|MINOR|RELEASE) ' lib/zstd.h | sed 's/^/  /'
h_major=$(awk '$1=="#define" && $2=="ZSTD_VERSION_MAJOR"   {print $3}' lib/zstd.h)
h_minor=$(awk '$1=="#define" && $2=="ZSTD_VERSION_MINOR"   {print $3}' lib/zstd.h)
h_patch=$(awk '$1=="#define" && $2=="ZSTD_VERSION_RELEASE" {print $3}' lib/zstd.h)
src_ver="$h_major.$h_minor.$h_patch"
if [ "$src_ver" = "$VER" ]; then echo "  OK   源码自述版本 $src_ver 与手册 §8.10 的 Zstd-$VER 一致"
else echo "  FAIL 源码自述版本为 $src_ver，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁：手册 §8.10 的命令序列里没有 patch，/sources 下也没有 zstd 补丁"
zstd_patches=$(ls /sources | grep -Ei 'zstd.*patch' || true)
echo "  （/sources 中匹配 zstd*patch 的文件：${zstd_patches:-无}）"
echo "本节无 configure：zstd 用纯 Makefile 构建，安装前缀由命令行 prefix=/usr 传入"
echo "  （lib/Makefile 第 281 行 prefix ?= /usr/local，命令行赋值优先级最高）。"
echo

echo "================= 8.10.1. Installation of Zstd ================="
echo "手册原文：Compile the package:"
echo "手册命令：make prefix=/usr"
make prefix=/usr
echo
echo "----- 编译结果确认 -----"
for f in programs/zstd lib/libzstd.so.$VER lib/libzstd.pc; do
  if [ -e "$f" ]; then printf '  OK   %-28s %s 字节\n' "$f" "$(stat -Lc %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; exit 1; fi
done
echo "  构建目录内的库文件："
ls -l lib/libzstd* 2>/dev/null | sed 's/^/    /'
echo "  说明：顶层 default 目标 = lib-release + zstd-release。lib-release 同时产出"
echo "  静态库 libzstd.a 与共享库 libzstd.so.$VER；手册随后用 rm -v /usr/lib/libzstd.a"
echo "  在安装之后删掉静态库（zstd 的 Makefile 没有类似 lz4 的 BUILD_STATIC 开关）。"
echo "  共享库 SONAME："
objdump -p lib/libzstd.so.$VER | awk '/SONAME/{print "    "$0}'
echo "  生成的 libzstd.pc（prefix=/usr 是否生效）："
sed 's/^/    /' lib/libzstd.pc
pc_prefix=$(sed -n 's/^prefix=//p' lib/libzstd.pc | head -n1)
if [ "$pc_prefix" = "/usr" ]; then echo "    OK   libzstd.pc 中 prefix=/usr，prefix=/usr 生效"
else echo "    FAIL libzstd.pc 中 prefix 为 '$pc_prefix'，应为 /usr"; exit 1; fi
echo "  刚编译出的 zstd 自述版本与已启用的格式支持："
./programs/zstd --version | sed 's/^/    /'
echo "  zstd 可执行文件链接到的共享库（应含 §8.6/§8.8/§8.9 装好的 libz/liblzma/liblz4）："
ldd ./programs/zstd | sed 's/^/    /'
build_ldd=$(ldd ./programs/zstd)
for want in libz.so liblzma.so liblz4.so libc.so.6; do
  case "$build_ldd" in
    *"$want"*) printf '    OK   链接到 %s\n' "$want" ;;
    *) printf '    FAIL 未链接到 %s（对应格式支持未编入）\n' "$want"; exit 1 ;;
  esac
done
echo "  注意：zstd 可执行文件不链接自家的 libzstd.so —— programs/Makefile 的 zstd 目标"
echo "  把 lib/ 的源码（ZSTDLIB_LOCAL_SRC）直接编进 CLI；链接 -lzstd 的是另一个目标"
echo "  zstd-dll，手册本节不使用它。故 ldd 中没有 libzstd.so.1 属于预期，不是缺陷。"
echo "  libzstd.so 的可用性由安装后第 6 项的 -lzstd 编译/运行验证覆盖。"
echo

echo "手册原文：To test the results, issue:"
echo "手册命令：make check"
echo "手册 Note 原文：In the test output there are several places that indicate 'failed'."
echo "  These are expected and only 'FAIL' is an actual test failure. There should be no"
echo "  test failures."
echo "（zstd 的 check = tests/Makefile 的 test-zstd，即 tests/playTests.sh，是一组 shell"
echo "  驱动的 CLI 功能测试。playTests.sh 以 set -e 运行，任何一步出错立即以非 0 退出，"
echo "  没有 automake 那样的汇总计数。因此判定依据是：make 的退出码为 0，且输出中出现"
echo "  tests/Makefile check 目标最后打印的 \"All tests completed successfully\"。"
echo "  按手册 Note，输出里的小写 'failed' 属预期（负向用例里 zstd 自己打印的错误信息），"
echo "  不作为失败判据；下面仍会把大小写两种计数打出来供人工核对。）"
set +e
make check 2>&1 | tee "$CHECKLOG"
check_rc=${PIPESTATUS[0]}
set -e
echo
echo "----- make check 结论 -----"
echo "make check 退出码：$check_rc"
echo "输出行数：$(wc -l < "$CHECKLOG")"
echo "输出末尾 25 行："
tail -n 25 "$CHECKLOG" | sed 's/^/  /'
echo
echo "手册 Note 相关的计数（信息性，非判据）："
lower_failed=$(grep -c 'failed' "$CHECKLOG" || true)
upper_fail=$(grep -c 'FAIL' "$CHECKLOG" || true)
echo "  含小写 'failed' 的行数：${lower_failed:-0}（手册：These are expected）"
echo "  含大写 'FAIL'   的行数：${upper_fail:-0}（手册：only 'FAIL' is an actual test failure）"
if [ "${upper_fail:-0}" -gt 0 ]; then
  echo "  以下是含大写 FAIL 的行（需人工确认）："
  grep -n 'FAIL' "$CHECKLOG" | sed 's/^/    /'
fi
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make check 退出码非 0（$check_rc），手册明确要求 There should be no test failures" >&2
  exit "$check_rc"
fi
if grep -F 'All tests completed successfully' "$CHECKLOG" > /dev/null; then
  echo "  OK   输出中出现 tests/Makefile check 目标的收尾横幅 All tests completed successfully"
else
  echo "错误：make check 退出码为 0，但输出中没有 'All tests completed successfully'，" >&2
  echo "  测试可能没有跑到底" >&2
  exit 1
fi
if [ "${upper_fail:-0}" -ne 0 ]; then
  echo "错误：输出中出现 ${upper_fail} 行大写 FAIL，按手册 Note 这才是真正的测试失败" >&2
  exit 1
fi
echo "结论：make check 退出码 0，收尾横幅出现，无大写 FAIL —— 本节测试全部通过，"
echo "  符合手册「There should be no test failures」的要求。"
echo

echo "手册原文：Install the package:"
echo "手册命令：make prefix=/usr install"
make prefix=/usr install
echo
echo "手册原文：Remove the static library:"
echo "手册命令：rm -v /usr/lib/libzstd.a"
if [ -e /usr/lib/libzstd.a ]; then
  rm -v /usr/lib/libzstd.a
else
  echo "错误：/usr/lib/libzstd.a 不存在，make install 未按预期安装静态库" >&2
  exit 1
fi
echo

echo "----- 安装后检查（手册 §8.10.2 Contents of Zstd） -----"
rc=0
echo "1) Installed programs：zstd、zstdcat (link to zstd)、zstdgrep、zstdless、"
echo "   zstdmt (link to zstd)、unzstd (link to zstd)"
if [ -f /usr/bin/zstd ] && [ ! -L /usr/bin/zstd ]; then
  printf '   OK   %-9s（%s 字节，实体文件）%s\n' zstd "$(stat -Lc %s /usr/bin/zstd)" "$(file -b /usr/bin/zstd | cut -c1-46)"
else printf '   FAIL /usr/bin/zstd 缺失或不是实体文件\n'; rc=1; fi
for p in zstdcat unzstd zstdmt; do
  got=$(readlink /usr/bin/$p 2>/dev/null || true)
  if [ "$got" = zstd ]; then printf '   OK   %-9s -> zstd（符合手册 link to zstd）\n' "$p"
  else printf '   FAIL /usr/bin/%s 应为指向 zstd 的符号链接，实为 %s\n' "$p" "${got:-不存在或非符号链接}"; rc=1; fi
done
for p in zstdgrep zstdless; do
  if [ -f /usr/bin/$p ] && [ ! -L /usr/bin/$p ] && [ -x /usr/bin/$p ]; then
    printf '   OK   %-9s（%s 字节，可执行 shell 脚本：%s）\n' "$p" "$(stat -Lc %s /usr/bin/$p)" "$(head -n1 /usr/bin/$p)"
  else printf '   FAIL /usr/bin/%s 缺失或不可执行\n' "$p"; rc=1; fi
done
ls -l /usr/bin/zstd /usr/bin/zstdcat /usr/bin/unzstd /usr/bin/zstdmt \
      /usr/bin/zstdgrep /usr/bin/zstdless 2>/dev/null | sed 's/^/     /'
echo "2) Installed library：libzstd.so"
for f in /usr/lib/libzstd.so /usr/lib/libzstd.so.1 /usr/lib/libzstd.so.$VER; do
  if [ -e "$f" ]; then printf '   OK   %-30s -> %s（%s 字节）\n' "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
ls -l /usr/lib/libzstd* | sed 's/^/     /'
echo "   SONAME 必须是 libzstd.so.1："
soname=$(objdump -p /usr/lib/libzstd.so.$VER | awk '/SONAME/{print $2}')
echo "     SONAME = $soname"
if [ "$soname" = "libzstd.so.1" ]; then echo "     OK   SONAME 正确"
else echo "     FAIL SONAME 应为 libzstd.so.1"; rc=1; fi
echo "   手册 rm -v /usr/lib/libzstd.a 的效果："
if [ -e /usr/lib/libzstd.a ]; then echo "     FAIL /usr/lib/libzstd.a 仍存在"; rc=1
else echo "     OK   /usr/lib/libzstd.a 已删除"; fi
echo "   动态符号抽查（先落盘再匹配，避免管道 SIGPIPE 误判）："
dynsyms=$(mktemp /tmp/libzstd-dynsyms-XXXXXX)
readelf --dyn-syms -W /usr/lib/libzstd.so.$VER > "$dynsyms"
for s in ZSTD_versionNumber ZSTD_versionString ZSTD_compress ZSTD_decompress \
         ZSTD_createCCtx ZSTD_createDCtx ZSTD_getFrameContentSize ZDICT_trainFromBuffer; do
  if grep -E "[[:space:]]$s\$|[[:space:]]$s@" "$dynsyms" > /dev/null; then
    printf '     OK   %s\n' "$s"
  else printf '     FAIL 动态符号 %s 缺失\n' "$s"; rc=1; fi
done
rm -f "$dynsyms"
echo "3) 头文件与 pkg-config 描述文件（lib/Makefile 的 install-includes / install-pc）："
for f in /usr/include/zstd.h /usr/include/zstd_errors.h /usr/include/zdict.h; do
  if [ -e "$f" ]; then printf '   OK   %-30s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
if [ -s /usr/lib/pkgconfig/libzstd.pc ]; then
  echo "   OK   /usr/lib/pkgconfig/libzstd.pc"
  sed 's/^/        /' /usr/lib/pkgconfig/libzstd.pc
else echo "   FAIL /usr/lib/pkgconfig/libzstd.pc 缺失"; rc=1; fi
echo "4) 手册页（programs/Makefile 的 install 规则）："
for m in zstd.1 zstdgrep.1 zstdless.1; do
  if [ -f "/usr/share/man/man1/$m" ] && [ ! -L "/usr/share/man/man1/$m" ]; then
    printf '   OK   %-12s（%s 字节）\n' "$m" "$(stat -Lc %s "/usr/share/man/man1/$m")"
  else printf '   FAIL /usr/share/man/man1/%s 缺失\n' "$m"; rc=1; fi
done
for m in zstdcat.1 unzstd.1; do
  got=$(readlink "/usr/share/man/man1/$m" 2>/dev/null || true)
  if [ "$got" = "zstd.1" ]; then printf '   OK   %-12s -> zstd.1\n' "$m"
  else printf '   FAIL /usr/share/man/man1/%s 应指向 zstd.1，实为 %s\n' "$m" "${got:-不存在}"; rc=1; fi
done
echo "   INFO zstdmt 没有对应的 man 页（programs/Makefile 的 install 规则只为 zstdcat 和"
echo "        unzstd 建 man 链接），这是上游设计，不是缺陷。"
echo "5) 版本与运行验证（安装后的 /usr/bin/zstd 必须是本节刚编译的 $VER）："
echo "   zstd --version："
zstd --version 2>&1 | sed 's/^/     /'
inst_ver=$(zstd --version 2>&1 | sed -n '1s/.*v\([0-9][0-9.]*\).*/\1/p')
if [ "$inst_ver" = "$VER" ]; then echo "   OK   zstd 版本 $inst_ver"
else echo "   FAIL zstd 版本为 '$inst_ver'"; rc=1; fi
echo "   zstd 链接到的共享库："
ldd /usr/bin/zstd | sed 's/^/     /'
inst_ldd=$(ldd /usr/bin/zstd)
for want in libz.so liblzma.so liblz4.so libc.so.6; do
  case "$inst_ldd" in
    *"$want"*) printf '     OK   链接到 %s\n' "$want" ;;
    *) printf '     FAIL 未链接到 %s\n' "$want"; rc=1 ;;
  esac
done
echo "6) 功能验证（自加检查，非手册命令）："
tmpd=$(mktemp -d /tmp/zstd-verify-XXXXXX)
head -c 400000 /usr/share/man/man1/zstd.1 > "$tmpd/plain" 2>/dev/null || true
if [ ! -s "$tmpd/plain" ]; then
  for i in $(seq 1 8000); do echo "LFS 13.0-systemd zstd round trip line $i"; done > "$tmpd/plain"
fi
orig_sum=$(md5sum < "$tmpd/plain" | cut -d' ' -f1)
orig_size=$(stat -c %s "$tmpd/plain")
zstd -q -f "$tmpd/plain" -o "$tmpd/t.zst"
csize=$(stat -c %s "$tmpd/t.zst")
new_sum=$(zstdcat "$tmpd/t.zst" | md5sum | cut -d' ' -f1)
if [ "$new_sum" = "$orig_sum" ]; then
  printf '   OK   zstd 压缩 %s -> %s 字节，zstdcat 解压后 md5 与原文一致（%s）\n' "$orig_size" "$csize" "$orig_sum"
else printf '   FAIL zstd/zstdcat 往返后内容不一致\n'; rc=1; fi
echo "   zstd -t 完整性校验："
if zstd -t "$tmpd/t.zst" >/dev/null 2>&1; then echo "     OK   zstd -t 通过"
else echo "     FAIL zstd -t 失败"; rc=1; fi
echo "   unzstd 解压："
unzstd -q -f "$tmpd/t.zst" -o "$tmpd/unzstd.out"
if [ "$(md5sum < "$tmpd/unzstd.out" | cut -d' ' -f1)" = "$orig_sum" ]; then echo "     OK   unzstd 输出与原文一致"
else echo "     FAIL unzstd 输出不一致"; rc=1; fi
echo "   zstdmt（多线程别名，等价于 zstd -T0）："
zstdmt -q -f "$tmpd/plain" -o "$tmpd/tmt.zst"
if [ "$(zstdcat "$tmpd/tmt.zst" | md5sum | cut -d' ' -f1)" = "$orig_sum" ]; then echo "     OK   zstdmt 压缩结果可正确解压"
else echo "     FAIL zstdmt 往返失败"; rc=1; fi
echo "   最高压缩比 zstd --ultra -22："
zstd -q -f --ultra -22 "$tmpd/plain" -o "$tmpd/t22.zst"
printf '     --ultra -22 压缩后 %s 字节（默认级别 %s 字节）\n' "$(stat -c %s "$tmpd/t22.zst")" "$csize"
if [ "$(zstdcat "$tmpd/t22.zst" | md5sum | cut -d' ' -f1)" = "$orig_sum" ]; then echo "     OK   -22 往返一致"
else echo "     FAIL -22 往返失败"; rc=1; fi
echo "   跨格式支持（前置的 §8.6 zlib / §8.8 xz / §8.9 lz4 被编进了 zstd）："
echo "     判据：zstd --format=X 压出来的文件，能被该格式的原生工具解开且内容一致。"
for spec in "gzip:gzip -cdq" "xz:xz -cdq" "lzma:xz -cdq" "lz4:lz4 -cdq"; do
  fmt=${spec%%:*}; dec=${spec#*:}
  out="$tmpd/x.$fmt"
  if ! zstd -q -f --format=$fmt "$tmpd/plain" -o "$out" 2>"$tmpd/err.$fmt"; then
    printf '     FAIL zstd --format=%s 压缩失败：%s\n' "$fmt" "$(cat "$tmpd/err.$fmt")"; rc=1; continue
  fi
  if [ "$($dec < "$out" | md5sum | cut -d" " -f1)" = "$orig_sum" ]; then
    printf '     OK   --format=%-4s -> %8s 字节，原生工具「%s」解开后与原文一致\n' \
           "$fmt" "$(stat -c %s "$out")" "$dec"
  else
    printf '     FAIL --format=%s 的输出无法被「%s」正确解开\n' "$fmt" "$dec"; rc=1
  fi
  # zstd 自身能否回读这些格式：作为信息记录（不同格式的魔数识别强弱不同，
  # 手册对此无要求，故不作为失败判据）
  if [ "$(zstd -dcq "$out" 2>/dev/null | md5sum | cut -d" " -f1)" = "$orig_sum" ]; then
    printf '          INFO zstd -dc 也能直接回读 .%s\n' "$fmt"
  else
    printf '          INFO zstd -dc 未直接回读 .%s（仅信息，非判据）\n' "$fmt"
  fi
done
echo "   zstdgrep（手册：Runs grep on ZSTD compressed files）："
printf 'alpha\nLFS-ZSTDGREP-MARKER\nomega\n' > "$tmpd/g.txt"
zstd -q -f "$tmpd/g.txt" -o "$tmpd/g.txt.zst"
zg_out=$(zstdgrep LFS-ZSTDGREP-MARKER "$tmpd/g.txt.zst" 2>&1 || true)
echo "     zstdgrep 输出：$zg_out"
case "$zg_out" in
  *LFS-ZSTDGREP-MARKER*) echo "     OK   zstdgrep 在 .zst 文件中匹配到目标行" ;;
  *) echo "     FAIL zstdgrep 未匹配到目标行"; rc=1 ;;
esac
echo "   zstdless（手册：Runs less on ZSTD compressed files）："
echo "     INFO zstdless 只是 'export LESSOPEN=...; exec less \"\$@\"' 的两行封装，需要"
echo "          Less —— 它在手册里排在本节之后（§8.x Less-*），此刻尚未安装，故这里只"
echo "          检查脚本本身已正确安装，不做功能调用。"
sed 's/^/       | /' /usr/bin/zstdless
echo "   liblzstd 直接链接验证（-lzstd 编译并运行）："
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zstd.h>
#include <zdict.h>
int main(void) {
    const char *src = "LFS 13.0-systemd libzstd round trip -- "
                      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    size_t slen = strlen(src) + 1;
    size_t bound = ZSTD_compressBound(slen);
    char *cbuf = malloc(bound), *dbuf = malloc(slen);
    size_t clen, dlen;
    unsigned long long fsize;
    if (!cbuf || !dbuf) return 4;
    printf("ZSTD_VERSION_STRING(header)=%s ZSTD_versionString(lib)=%s ZSTD_versionNumber=%u\n",
           ZSTD_VERSION_STRING, ZSTD_versionString(), ZSTD_versionNumber());
    clen = ZSTD_compress(cbuf, bound, src, slen, 3);
    if (ZSTD_isError(clen)) { printf("compress error: %s\n", ZSTD_getErrorName(clen)); return 1; }
    fsize = ZSTD_getFrameContentSize(cbuf, clen);
    dlen = ZSTD_decompress(dbuf, slen, cbuf, clen);
    if (ZSTD_isError(dlen)) { printf("decompress error: %s\n", ZSTD_getErrorName(dlen)); return 2; }
    printf("simple API: %zu -> %zu -> %zu bytes (frame says %llu), round trip %s\n",
           slen, clen, dlen, fsize,
           (dlen == slen && memcmp(dbuf, src, slen) == 0) ? "OK" : "MISMATCH");
    if (dlen != slen || memcmp(dbuf, src, slen) != 0) return 3;
    {   /* 上下文 API，验证 ZSTD_createCCtx / ZSTD_createDCtx 等符号可用 */
        ZSTD_CCtx *cctx = ZSTD_createCCtx();
        ZSTD_DCtx *dctx = ZSTD_createDCtx();
        size_t c2, d2;
        if (!cctx || !dctx) return 5;
        c2 = ZSTD_compressCCtx(cctx, cbuf, bound, src, slen, 9);
        if (ZSTD_isError(c2)) return 6;
        d2 = ZSTD_decompressDCtx(dctx, dbuf, slen, cbuf, c2);
        if (ZSTD_isError(d2) || d2 != slen || memcmp(dbuf, src, slen) != 0) return 7;
        printf("context API: %zu -> %zu -> %zu bytes, round trip OK\n", slen, c2, d2);
        ZSTD_freeCCtx(cctx); ZSTD_freeDCtx(dctx);
    }
    printf("zdict.h usable: ZDICT_isError(0)=%u\n", ZDICT_isError(0));
    free(cbuf); free(dbuf);
    return 0;
}
EOF
if gcc -o "$tmpd/t" "$tmpd/t.c" -lzstd && "$tmpd/t"; then
  echo "     OK   -lzstd 链接、运行、简单 API 与上下文 API 往返均正常"
  ldd "$tmpd/t" | sed -n 's/.*\(libzstd[^ ]*\)/        \1/p'
else echo "     FAIL 无法用 -lzstd 编译或运行 libzstd 测试程序"; rc=1; fi
echo "   libzstd.pc 内容可被 gcc 直接使用（手工展开 Libs/Cflags）："
pc_libs=$(sed -n 's/^Libs: //p' /usr/lib/pkgconfig/libzstd.pc)
echo "     Libs = $pc_libs"
rm -rf "$tmpd"
echo "7) 本节写入系统的文件清单："
ls -l /usr/bin/zstd /usr/bin/zstdcat /usr/bin/unzstd /usr/bin/zstdmt \
      /usr/bin/zstdgrep /usr/bin/zstdless \
      /usr/lib/libzstd* /usr/lib/pkgconfig/libzstd.pc \
      /usr/include/zstd.h /usr/include/zstd_errors.h /usr/include/zdict.h \
      /usr/share/man/man1/zstd.1 /usr/share/man/man1/zstdcat.1 \
      /usr/share/man/man1/unzstd.1 /usr/share/man/man1/zstdgrep.1 \
      /usr/share/man/man1/zstdless.1 2>/dev/null | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Zstd 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留测试摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.10.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  make check 完整输出已在 $CHECKLOG（= 宿主 /root/lfs/sources/.zstd-make-check.log）"
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
echo "===== §8.10 完成，结束时间：$(date -Is) ====="
