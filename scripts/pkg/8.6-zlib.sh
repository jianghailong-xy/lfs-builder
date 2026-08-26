#!/usr/bin/env bash
# LFS 13.0-systemd §8.6 Zlib-1.3.2
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.6.1 Installation of Zlib 的命令序列（全部，一条不多一条不少）：
#   ./configure --prefix=/usr
#   make
#   make check
#   make install
#   rm -fv /usr/lib/libz.a
# 本节没有补丁、没有 sed 修正、没有额外配置小节（§8.6.2 只是 Contents 说明）。
set -euo pipefail

PKG=zlib
VER=1.3.2
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
CHECKLOG=/sources/.zlib-make-check.log

echo "===== LFS 13.0-systemd §8.6 Zlib-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Zlib package contains compression and decompression routines used"
echo "  by some programs."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 6.4 MB"
echo "手册存档：/workspace/docs/book/chapter08-zlib.html（宿主机 \$LFS_ROOT/docs/book/）"
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
echo "可用空间（手册本节要求 6.4 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 7 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 6.4MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.5 Glibc-2.43）产物必须可用 -----"
rc=0
echo "1) §8.5 安装的 C 库本体（手册 §8.5.4 Contents 中的核心文件）："
for f in /usr/lib/libc.so.6 /usr/lib/libm.so.6 /usr/lib/libpthread.so.0 \
         /usr/lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2 \
         /usr/bin/ldd /usr/bin/localedef; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.5 未完成？）\n' "$f"; rc=1; fi
done
echo "   （手册 §7.5.1 Warning 明确 /usr/lib64 不得存在；x86_64 的动态装载器实体在"
echo "     /usr/lib/ld-linux-x86-64.so.2，ABI 要求的路径 /lib64/ld-linux-x86-64.so.2"
echo "     是指向它的符号链接：$(ls -l /lib64/ld-linux-x86-64.so.2 | sed 's/.*-> //')）"
if [ -e /usr/lib64 ]; then echo "   FAIL /usr/lib64 存在，违反手册 §7.5.1 Warning"; rc=1
else echo "   OK   /usr/lib64 不存在，符合手册 §7.5.1 Warning"; fi
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
echo "2) §8.5.2 的配置文件（nsswitch.conf / 动态装载器 / 时区）："
for f in /etc/nsswitch.conf /etc/ld.so.conf /etc/localtime; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"
  else printf '   FAIL %s 缺失（§8.5.2 未完成？）\n' "$f"; rc=1; fi
done
if [ -e /usr/lib/locale/locale-archive ]; then
  echo "   OK   /usr/lib/locale/locale-archive（$(stat -c %s /usr/lib/locale/locale-archive) 字节）"
else
  echo "   FAIL /usr/lib/locale/locale-archive 缺失"; rc=1
fi
echo "3) 新 glibc 能被链接使用（手册 §8.5 之后的健全性验证思路：编译并运行一个小程序）："
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("glibc sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行成功；链接的解释器与 libc："
  readelf -l "${tmpc%.c}" | grep -m1 'interpreter' | sed 's/^/        /'
  ldd "${tmpc%.c}" | sed 's/^/        /'
else
  echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1
fi
rm -f "$tmpc" "${tmpc%.c}"
echo "4) §7.13.1 Cleaning 的结果（临时工具已并入 /usr，/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在（§7.13.1 未完成？）"; rc=1
else echo "   OK   /tools 已不存在"; fi
echo "5) 本节直接依赖的工具（解包 + configure + make + 测试 + 安装）："
for t in tar gzip make gcc ld ar ranlib sed grep awk cp install rm mkdir md5sum \
         readelf objdump strip find stat diff; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   ld   版本：$(ld --version | sed -n 1p)"
echo "6) 安装目标目录（手册本节把 --prefix=/usr 的产物写入 /usr/lib、/usr/include、"
echo "   /usr/share/man/man3、/usr/lib/pkgconfig）："
for d in /usr/lib /usr/include /usr/share/man/man3 /usr/lib/pkgconfig; do
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
echo "9) 本节安装前系统中是否已有 zlib（应当没有——第 8 章首次安装它）："
found_pre=0
for f in /usr/lib/libz.so /usr/lib/libz.a /usr/include/zlib.h; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在，本节会覆盖\n' "$f"; found_pre=1; fi
done
[ $found_pre -eq 0 ] && echo "   OK   /usr 下尚无 libz.so / libz.a / zlib.h"
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
echo "上游版本自述（zlib.h 中的 ZLIB_VERSION）："
grep -m1 '#define ZLIB_VERSION' zlib.h | sed 's/^/  /'
zh_ver=$(sed -n 's/^#define ZLIB_VERSION[[:space:]]*"\(.*\)".*/\1/p' zlib.h | head -n1)
if [ "$zh_ver" = "$VER" ]; then echo "  OK   与手册 §8.6 的 Zlib-$VER 一致"
else echo "  FAIL zlib.h 自述版本为 $zh_ver，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁：手册 §8.6 的命令序列里没有 patch，/sources 下也没有 zlib 补丁"
echo "  （匹配数：$(ls /sources | grep -ci 'zlib.*patch')）。"
echo

echo "================= 8.6.1. Installation of Zlib ================="
echo "手册原文：Prepare Zlib for compilation:"
echo "手册命令：./configure --prefix=/usr"
./configure --prefix=/usr
echo
echo "----- configure 结果确认 -----"
echo "生成的 Makefile / configure.log 摘要："
[ -f Makefile ] && echo "  OK   Makefile 已生成（$(wc -l < Makefile) 行）" || { echo "  FAIL Makefile 未生成"; exit 1; }
grep -E '^(prefix|exec_prefix|libdir|includedir|sharedlibdir|mandir|SHAREDLIB|SHAREDLIBV|STATICLIB) *=' Makefile | sed 's/^/  /'
grep -m1 '^prefix *= */usr$' Makefile >/dev/null && echo "  OK   prefix=/usr，符合手册的 --prefix=/usr" \
  || { echo "  FAIL Makefile 中 prefix 不是 /usr"; exit 1; }
echo

echo "手册原文：Compile the package:"
echo "手册命令：make"
make
echo
echo "----- 编译结果确认 -----"
for f in libz.a libz.so.$VER; do
  if [ -f "$f" ]; then printf '  OK   %-16s %s 字节\n' "$f" "$(stat -c %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; exit 1; fi
done
echo "  构建目录内的 libz 相关产物："
ls -l libz* | sed 's/^/    /'
echo "  共享库 SONAME："
objdump -p libz.so.$VER | grep -m1 SONAME | sed 's/^/    /'
echo

echo "手册原文：To test the results, issue:"
echo "手册命令：make check"
echo "（本节手册未给出任何“允许失败”的说明，故期望全部测试通过）"
set +e
make check 2>&1 | tee "$CHECKLOG"
check_rc=${PIPESTATUS[0]}
set -e
echo
echo "----- make check 结论 -----"
echo "make check 退出码：$check_rc"
echo "测试输出中的 OK 行："
grep -n 'test OK' "$CHECKLOG" | sed 's/^/  /' || true
echo "测试输出中的 FAIL/Error 行（应为空）："
fail_lines=$(grep -niE 'fail|\*\*\* .*error|Error [0-9]' "$CHECKLOG" || true)
if [ -n "$fail_lines" ]; then echo "$fail_lines" | sed 's/^/  /'; else echo "  （无）"; fi
ok_cnt=$(grep -c 'test OK' "$CHECKLOG" || true)
echo "通过标记（'*** ... test OK ***'）计数：$ok_cnt"
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make check 退出码非 0（$check_rc），手册未允许本节存在失败" >&2
  exit "$check_rc"
fi
if [ -n "$fail_lines" ]; then
  echo "错误：make check 退出码为 0，但输出中出现 FAIL/Error 字样，需人工确认" >&2
  exit 1
fi
if [ "$ok_cnt" -lt 1 ]; then
  echo "错误：make check 没有输出任何 'test OK' 标记，测试可能未真正运行" >&2
  exit 1
fi
echo "结论：本节测试全部通过（$ok_cnt 项 'test OK'，0 失败），符合手册预期。"
echo

echo "手册原文：Install the package:"
echo "手册命令：make install"
make install
echo
echo "手册原文：Remove a useless static library:"
echo "手册命令：rm -fv /usr/lib/libz.a"
rm -fv /usr/lib/libz.a
echo

echo "----- 安装后检查（手册 §8.6.2 Contents of Zlib） -----"
rc=0
echo "手册 §8.6.2 Installed libraries：libz.so"
echo "1) 共享库及其符号链接："
for f in /usr/lib/libz.so /usr/lib/libz.so.1 /usr/lib/libz.so.$VER; do
  if [ -e "$f" ]; then printf '   OK   %-26s -> %s（%s 字节）\n' "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
ls -l /usr/lib/libz* | sed 's/^/     /'
echo "2) 手册要求删除的静态库 /usr/lib/libz.a（Remove a useless static library）："
if [ -e /usr/lib/libz.a ]; then echo "   FAIL /usr/lib/libz.a 仍存在"; rc=1
else echo "   OK   /usr/lib/libz.a 已删除"; fi
echo "3) 头文件（供后续包 configure 检测 zlib）："
for f in /usr/include/zlib.h /usr/include/zconf.h; do
  if [ -s "$f" ]; then printf '   OK   %-24s（%s 字节）\n' "$f" "$(stat -c %s "$f")"
  else printf '   FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
echo "   已安装 zlib.h 的版本宏：$(grep -m1 '#define ZLIB_VERSION' /usr/include/zlib.h)"
echo "4) pkg-config 描述文件与手册页："
if [ -s /usr/lib/pkgconfig/zlib.pc ]; then
  echo "   OK   /usr/lib/pkgconfig/zlib.pc"
  sed 's/^/        /' /usr/lib/pkgconfig/zlib.pc
else echo "   FAIL /usr/lib/pkgconfig/zlib.pc 缺失"; rc=1; fi
if [ -s /usr/share/man/man3/zlib.3 ]; then echo "   OK   /usr/share/man/man3/zlib.3"
else echo "   FAIL /usr/share/man/man3/zlib.3 缺失"; rc=1; fi
echo "5) 共享库元信息（SONAME 必须是 libz.so.1，否则后续包链接后运行会找不到库）："
soname=$(objdump -p /usr/lib/libz.so.$VER | awk '/SONAME/{print $2}')
echo "   SONAME = $soname"
if [ "$soname" = "libz.so.1" ]; then echo "   OK   SONAME 正确"
else echo "   FAIL SONAME 为 $soname，应为 libz.so.1"; rc=1; fi
echo "   动态符号抽查（compress/uncompress/deflate/inflate/gzopen/zlibVersion）："
for s in compress uncompress deflate inflate gzopen zlibVersion; do
  if readelf --dyn-syms -W /usr/lib/libz.so.$VER | grep -E "[[:space:]]$s\$|[[:space:]]$s@" >/dev/null; then
    printf '     OK   %s\n' "$s"
  else printf '     FAIL 动态符号 %s 缺失\n' "$s"; rc=1; fi
done
echo "6) 实际链接与运行验证（自加检查，非手册命令）：编译一个调用 zlibVersion() 与"
echo "   compress()/uncompress() 的小程序，-lz 链接后运行："
tmpd=$(mktemp -d /tmp/zlib-verify-XXXXXX)
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <zlib.h>
int main(void) {
    const char *src = "LFS 13.0-systemd zlib round trip test -- "
                      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    unsigned char buf[256]; char out[256];
    uLongf blen = sizeof buf, olen = sizeof out;
    printf("ZLIB_VERSION(header)=%s zlibVersion(lib)=%s\n", ZLIB_VERSION, zlibVersion());
    if (compress(buf, &blen, (const Bytef *)src, strlen(src) + 1) != Z_OK) return 1;
    if (uncompress((Bytef *)out, &olen, buf, blen) != Z_OK) return 2;
    printf("compressed %zu -> %lu bytes, round trip %s\n",
           strlen(src) + 1, (unsigned long)blen,
           strcmp(out, src) == 0 ? "OK" : "MISMATCH");
    return strcmp(out, src) == 0 ? 0 : 3;
}
EOF
if gcc -o "$tmpd/t" "$tmpd/t.c" -lz && "$tmpd/t"; then
  echo "   OK   -lz 链接、运行、压缩/解压往返均正常"
  echo "   该程序链接到的 libz："
  ldd "$tmpd/t" | grep -i libz | sed 's/^/        /'
else
  echo "   FAIL 无法用 -lz 编译或运行 zlib 测试程序"; rc=1
fi
rm -rf "$tmpd"
echo "7) 手册未要求安装的东西不应出现（本节只装库、头文件、pkgconfig、man3）："
for f in /usr/bin/minigzip /usr/bin/example /usr/lib/libz.la; do
  if [ -e "$f" ]; then printf '   FAIL %s 不该存在\n' "$f"; rc=1
  else printf '   OK   %s 未安装，符合手册\n' "$f"; fi
done
echo "8) 本节写入 /usr 的全部文件清单："
for f in /usr/lib/libz.so /usr/lib/libz.so.1 /usr/lib/libz.so.$VER \
         /usr/include/zlib.h /usr/include/zconf.h \
         /usr/lib/pkgconfig/zlib.pc /usr/share/man/man3/zlib.3; do
  [ -e "$f" ] && ls -ld "$f" | sed 's/^/     /'
done
[ $rc -eq 0 ] || { echo "错误：Zlib 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留测试摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.6.sh"
echo "  移入 \$LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  make check 完整输出已在 $CHECKLOG（= 宿主 \$LFS_ROOT/sources/.zlib-make-check.log）"
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
echo "===== §8.6 完成，结束时间：$(date -Is) ====="
