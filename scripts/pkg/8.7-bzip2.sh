#!/usr/bin/env bash
# LFS 13.0-systemd §8.7 Bzip2-1.0.8
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.7.1 Installation of Bzip2 的命令序列（全部，一条不多一条不少）：
#   patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
#   sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
#   sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
#   make -f Makefile-libbz2_so
#   make clean
#   make
#   make PREFIX=/usr install
#   cp -av libbz2.so.* /usr/lib
#   ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
#   ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
#   cp -v bzip2-shared /usr/bin/bzip2
#   for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 $i; done
#   rm -fv /usr/lib/libbz2.a
# 本节的测试不是独立的 `make check`：手册在 `make` 处写的是
#   "Compile and test the package:"  —— bzip2 的 Makefile 中 all: ... test，
# 因此测试套件是在 `make` 里跑的，本脚本据此判定测试结论。
set -euo pipefail

PKG=bzip2
VER=1.0.8
TARBALL=$PKG-$VER.tar.gz
PATCHF=$PKG-$VER-install_docs-1.patch
SRCDIR=$PKG-$VER
MAKELOG=/sources/.bzip2-make.log

echo "===== LFS 13.0-systemd §8.7 Bzip2-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Bzip2 package contains programs for compressing and decompressing"
echo "  files. Compressing text files with bzip2 yields a much better compression"
echo "  percentage than with the traditional gzip."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 7.3 MB"
echo "手册存档：/workspace/docs/book/chapter08-bzip2.html（宿主机 /root/lfs/docs/book/）"
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
echo "可用空间（手册本节要求 7.3 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 8 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 7.3MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.6 Zlib-1.3.2）产物必须可用 -----"
rc=0
echo "1) §8.6.2 Contents of Zlib 列出的产物（Installed libraries: libz.so）："
for f in /usr/lib/libz.so /usr/lib/libz.so.1 /usr/lib/libz.so.1.3.2 \
         /usr/include/zlib.h /usr/include/zconf.h /usr/lib/pkgconfig/zlib.pc; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.6 未完成？）\n' "$f"; rc=1; fi
done
if [ -e /usr/lib/libz.a ]; then echo "   FAIL /usr/lib/libz.a 仍存在（§8.6 要求 rm -fv）"; rc=1
else echo "   OK   /usr/lib/libz.a 已按 §8.6 删除"; fi
echo "   已安装 zlib.h 的版本宏：$(grep -m1 '#define ZLIB_VERSION' /usr/include/zlib.h)"
echo "2) §8.5 Glibc-2.43 的 C 库仍然可用（本节要编译 C 代码并运行测试）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("toolchain sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && [ "$("${tmpc%.c}")" = "toolchain sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else
  echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1
fi
rm -f "$tmpc" "${tmpc%.c}"
echo "3) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1
else echo "   OK   /tools 已不存在"; fi
echo "4) 本节直接依赖的工具（解包 + 打补丁 + sed 改 Makefile + make + 测试 + 安装）："
for t in tar gzip patch sed make gcc ld ar ranlib grep awk cp ln rm mkdir md5sum \
         cmp diff readelf objdump find stat; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc   版本：$(gcc --version | sed -n 1p)"
echo "   make  版本：$(make --version | sed -n 1p)"
echo "   patch 版本：$(patch --version | sed -n 1p)"
echo "   （手册本节的测试用 cmp 比对压缩/解压结果，cmp 来自 §6.6/§8 的 Diffutils）"
echo "5) 安装目标目录（本节写入 /usr/bin、/usr/lib、/usr/include、/usr/share/man/man1、"
echo "   /usr/share/doc/bzip2-$VER）："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/share/doc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，安装过程会创建\n' "$d"; fi
done
echo "6) 源码包与补丁（/sources 是宿主机 bind mount）："
for f in "/sources/$TARBALL" "/sources/$PATCHF"; do
  if [ -f "$f" ]; then echo "   OK   $f 存在（$(stat -c %s "$f") 字节）"
  else echo "   FAIL $f 缺失"; rc=1; fi
done
echo "7) §7.3 虚拟内核文件系统与 §7.6 基础文件："
for f in /dev/null /proc/self /sys /etc/passwd /etc/group; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "8) 本节安装前系统中是否已有 bzip2（第 8 章首次安装它；第 6 章的临时系统里没有"
echo "   bzip2，手册第 6 章不含该包）："
found_pre=0
for f in /usr/bin/bzip2 /usr/lib/libbz2.so /usr/lib/libbz2.a /usr/include/bzlib.h; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在，本节会覆盖\n' "$f"; found_pre=1; fi
done
[ $found_pre -eq 0 ] && echo "   OK   /usr 下尚无 bzip2 / libbz2 / bzlib.h"
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包与补丁校验（md5sums，手册 §3.1 / §3.2） -----"
grep -E " ($TARBALL|$PATCHF)\$" md5sums
grep -E " ($TARBALL|$PATCHF)\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls -l | sed 's/^/  /'
echo "上游版本自述（bzlib.h / Makefile 中的版本）："
grep -m1 'version.*1\.0\.8' README | sed 's/^/  /' || true
mk_ver=$(sed -n 's/^DISTNAME=bzip2-\(.*\)$/\1/p' Makefile | head -n1)
so_ver=$(sed -n 's/.*libbz2\.so\.\([0-9.]*\) .*/\1/p' Makefile-libbz2_so | head -n1)
echo "  Makefile DISTNAME = bzip2-$mk_ver"
echo "  Makefile-libbz2_so 的共享库名 = libbz2.so.$so_ver"
if [ "$mk_ver" = "$VER" ]; then echo "  OK   与手册 §8.7 的 Bzip2-$VER 一致"
else echo "  FAIL Makefile 自述版本为 $mk_ver，与 $VER 不符" >&2; exit 1; fi
if [ "$so_ver" = "$VER" ]; then echo "  OK   共享库版本号与手册的 ln -sfv libbz2.so.$VER 一致"
else echo "  FAIL Makefile-libbz2_so 的库版本为 $so_ver，与手册的 libbz2.so.$VER 不符" >&2; exit 1; fi
echo

echo "================= 8.7.1. Installation of Bzip2 ================="
echo "手册原文：Apply a patch that will install the documentation for this package:"
echo "手册命令：patch -Np1 -i ../$PATCHF"
patch -Np1 -i "../$PATCHF"
echo "  打补丁后 Makefile 中新增的文档安装动作："
grep -n 'share/doc' Makefile | sed 's/^/    /'
echo

echo "手册原文：The following command ensures installation of symbolic links are relative:"
echo "手册命令：sed -i 's@\\(ln -s -f \\)\$(PREFIX)/bin/@\\1@' Makefile"
echo "  修改前 Makefile 中的 ln -s -f 行："
grep -n 'ln -s -f' Makefile | sed 's/^/    /'
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
echo "  修改后 Makefile 中的 ln -s -f 行（应不再含 \$(PREFIX)/bin/）："
grep -n 'ln -s -f' Makefile | sed 's/^/    /'
if grep -q 'ln -s -f \$(PREFIX)/bin/' Makefile; then
  echo "  FAIL 仍存在 'ln -s -f \$(PREFIX)/bin/'，sed 未生效" >&2; exit 1
else echo "  OK   符号链接已改为相对形式"; fi
echo

echo "手册原文：Ensure the man pages are installed into the correct location:"
echo "手册命令：sed -i \"s@(PREFIX)/man@(PREFIX)/share/man@g\" Makefile"
echo "  修改前 Makefile 中的 man 路径行："
grep -n '(PREFIX)/man' Makefile | sed 's/^/    /'
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
echo "  修改后 Makefile 中的 man 路径行（应全部为 \$(PREFIX)/share/man）："
grep -n '(PREFIX)/share/man' Makefile | sed 's/^/    /'
if grep -q '(PREFIX)/man[^a-z]' Makefile; then
  echo "  FAIL 仍存在 \$(PREFIX)/man 路径，sed 未生效" >&2; exit 1
else echo "  OK   手册页安装路径已改为 \$(PREFIX)/share/man"; fi
echo

echo "手册原文：Prepare Bzip2 for compilation with:"
echo "手册命令：make -f Makefile-libbz2_so"
echo "手册说明（The meaning of the make parameter）：-f Makefile-libbz2_so —— This will"
echo "  cause Bzip2 to be built using a different Makefile file, in this case the"
echo "  Makefile-libbz2_so file, which creates a dynamic libbz2.so library and links"
echo "  the Bzip2 utilities against it."
make -f Makefile-libbz2_so
echo
echo "----- 动态库构建结果确认 -----"
for f in libbz2.so.$VER bzip2-shared; do
  if [ -e "$f" ]; then printf '  OK   %-18s %s 字节\n' "$f" "$(stat -Lc %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; exit 1; fi
done
echo "  构建目录内的 libbz2.so* ："
ls -l libbz2.so* | sed 's/^/    /'
echo "  共享库 SONAME："
objdump -p libbz2.so.$VER | grep -m1 SONAME | sed 's/^/    /'
echo "  bzip2-shared 的动态依赖："
ldd bzip2-shared | sed 's/^/    /'
echo

echo "手册命令：make clean"
echo "（手册把 make clean 与 make -f Makefile-libbz2_so 列在同一段命令里；clean 只清理"
echo "  普通 Makefile 的中间产物，不会删掉上一步生成的 libbz2.so.* 与 bzip2-shared）"
make clean
echo "  make clean 后仍保留的动态库产物："
ls -l libbz2.so* bzip2-shared | sed 's/^/    /'
for f in libbz2.so.$VER bzip2-shared; do
  [ -e "$f" ] || { echo "  FAIL make clean 误删了 $f" >&2; exit 1; }
done
echo "  OK   libbz2.so.$VER 与 bzip2-shared 均保留"
echo

echo "手册原文：Compile and test the package:"
echo "手册命令：make"
echo "（本节没有单独的 make check：bzip2 的 Makefile 里 all: libbz2.a bzip2 bzip2recover"
echo "  test，test 依赖 bzip2，因此测试套件在这一步随 make 一起执行。手册对本节未给出"
echo "  任何“允许失败”的说明，故期望测试全部通过。）"
set +e
make 2>&1 | tee "$MAKELOG"
make_rc=${PIPESTATUS[0]}
set -e
echo
echo "----- make（含测试）结论 -----"
echo "make 退出码：$make_rc"
echo "测试段落输出（bzip2 Makefile 的 test 目标 —— words1/words2/words3 与 6 次 cmp）："
sed -n '/Doing 6 tests/,$p' "$MAKELOG" | sed 's/^/  /'
echo
echo "编译告警（bzip2 1.0.8 用现代 gcc 编译时的已知无害告警，手册未视其为失败）："
warn_lines=$(grep -niE 'warning:' "$MAKELOG" || true)
if [ -n "$warn_lines" ]; then
  echo "$warn_lines" | sed 's/^/  /'
  echo "  说明：blocksort.c 的 -Winline \"inlining failed in call to 'mainGtU'\" 是 bzip2"
  echo "    上游源码在新版 gcc 下的长期已知告警（Makefile 里带 -Winline，而 mainGtU 超过"
  echo "    了 max-inline-insns-single 限制），只影响内联优化，不影响正确性；下面的 6 次"
  echo "    cmp 比对即为手册要求的正确性验证。"
else echo "  （无）"; fi
echo "输出中的真实失败标志（cmp 的 \"differ:\"、编译器 error:、make 的 *** / Error N；"
echo "  已排除 warning: 行与 bzip2 自身说明文字，应为空）："
fail_lines=$(grep -nE 'differ:|[Ee]rror:|\*\*\* |Error [0-9]' "$MAKELOG" | grep -viE 'warning:' || true)
if [ -n "$fail_lines" ]; then echo "$fail_lines" | sed 's/^/  /'; else echo "  （无）"; fi
cmp_cnt=$(grep -cE '^cmp sample[0-9]+\.(bz2|tst) ' "$MAKELOG" || true)
echo "执行到的 cmp 比对次数（手册测试为 3 次压缩 + 3 次解压，共 6 次）：$cmp_cnt"
if [ "$make_rc" -ne 0 ]; then
  echo "错误：make 退出码非 0（$make_rc），本节测试未通过，手册未允许失败" >&2
  exit "$make_rc"
fi
if [ -n "$fail_lines" ]; then
  echo "错误：make 退出码为 0，但输出中出现 differ:/error:/*** 等失败标志，需人工确认" >&2
  exit 1
fi
if ! grep -q "it looks like Bzip2 is working" "$MAKELOG" && \
   ! grep -q "you're in business" "$MAKELOG"; then
  echo "错误：测试输出中没有 bzip2 的成功结语（words3），测试可能未真正运行" >&2
  exit 1
fi
if [ "$cmp_cnt" -ne 6 ]; then
  echo "错误：cmp 比对次数为 $cmp_cnt，与手册测试的 6 次不符" >&2
  exit 1
fi
echo "结论：本节测试全部通过（6 次 cmp 比对无差异，bzip2 打印了成功结语），符合手册预期。"
echo "  本步构建出的静态产物："
ls -l libbz2.a bzip2 bzip2recover | sed 's/^/    /'
echo

echo "手册原文：Install the programs:"
echo "手册命令：make PREFIX=/usr install"
make PREFIX=/usr install
echo

echo "手册原文：Install the shared library:"
echo "手册命令：cp -av libbz2.so.* /usr/lib"
cp -av libbz2.so.* /usr/lib
echo "手册命令：ln -sfv libbz2.so.$VER /usr/lib/libbz2.so"
ln -sfv libbz2.so.$VER /usr/lib/libbz2.so
echo
echo "手册原文：The name of the shared library isn't standardized and it varies among"
echo "  distros. The instruction above has installed libbz2.so.1.0, but some"
echo "  applications, for example Kbd, expects a different name libbz2.so.1 that some"
echo "  other distros are using. Create a compatibility symlink for them:"
echo "手册命令：ln -sfv libbz2.so.$VER /usr/lib/libbz2.so.1"
ln -sfv libbz2.so.$VER /usr/lib/libbz2.so.1
echo "手册 Note：The symlink approach is only valid here because the library name"
echo "  difference is a result of different aesthetic views of the distro maintainers,"
echo "  not real ABI incompatibilities."
echo

echo "手册原文：Install the shared bzip2 binary into the /usr/bin directory, and replace"
echo "  two copies of bzip2 with symlinks:"
echo "手册命令：cp -v bzip2-shared /usr/bin/bzip2"
cp -v bzip2-shared /usr/bin/bzip2
echo "手册命令：for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 \$i; done"
for i in /usr/bin/{bzcat,bunzip2}; do
  ln -sfv bzip2 $i
done
echo

echo "手册原文：Remove a useless static library:"
echo "手册命令：rm -fv /usr/lib/libbz2.a"
rm -fv /usr/lib/libbz2.a
echo

echo "----- 安装后检查（手册 §8.7.2 Contents of Bzip2） -----"
rc=0
echo "手册 §8.7.2 Installed programs：bunzip2 (link to bzip2), bzcat (link to bzip2),"
echo "  bzcmp (link to bzdiff), bzdiff, bzegrep (link to bzgrep), bzfgrep (link to"
echo "  bzgrep), bzgrep, bzip2, bzip2recover, bzless (link to bzmore), and bzmore"
echo "1) 11 个已安装程序全部到位："
for p in bunzip2 bzcat bzcmp bzdiff bzegrep bzfgrep bzgrep bzip2 bzip2recover bzless bzmore; do
  if [ -e "/usr/bin/$p" ]; then
    if [ -L "/usr/bin/$p" ]; then printf '   OK   %-14s 符号链接 -> %s\n' "$p" "$(readlink "/usr/bin/$p")"
    else printf '   OK   %-14s 实体文件（%s 字节）\n' "$p" "$(stat -c %s "/usr/bin/$p")"; fi
  else printf '   FAIL /usr/bin/%s 缺失\n' "$p"; rc=1; fi
done
echo "2) 手册指明的链接关系正确（link to 的目标）："
check_link() {  # $1=链接名 $2=期望目标
  local t; t=$(readlink "/usr/bin/$1" || true)
  if [ "$t" = "$2" ]; then printf '   OK   %-10s -> %s\n' "$1" "$t"
  else printf '   FAIL %s 指向 %s，手册要求指向 %s\n' "$1" "${t:-（非符号链接）}" "$2"; rc=1; fi
}
check_link bunzip2 bzip2
check_link bzcat   bzip2
check_link bzcmp   bzdiff
check_link bzegrep bzgrep
check_link bzfgrep bzgrep
check_link bzless  bzmore
echo "   （手册的第 2 条 sed 要求这些链接是相对的 —— 上面 readlink 的结果均不含"
echo "     /usr/bin/ 前缀，说明 's@\\(ln -s -f \\)\$(PREFIX)/bin/@\\1@' 生效）"
for p in bunzip2 bzcat bzcmp bzegrep bzfgrep bzless; do
  case "$(readlink "/usr/bin/$p")" in
    /*) echo "   FAIL /usr/bin/$p 是绝对符号链接，未按手册改为相对"; rc=1 ;;
  esac
done
echo "3) /usr/bin/bzip2 必须是手册要求的 shared 版本（cp -v bzip2-shared /usr/bin/bzip2）："
if [ -L /usr/bin/bzip2 ]; then echo "   FAIL /usr/bin/bzip2 是符号链接，应为 bzip2-shared 的副本"; rc=1
else
  echo "   OK   /usr/bin/bzip2 是实体文件（$(stat -c %s /usr/bin/bzip2) 字节）"
  echo "   其动态依赖（应链接到 libbz2.so.1.0）："
  ldd /usr/bin/bzip2 | sed 's/^/        /'
  if ldd /usr/bin/bzip2 | grep -q 'libbz2\.so'; then echo "   OK   已动态链接 libbz2.so"
  else echo "   FAIL /usr/bin/bzip2 未链接 libbz2.so，可能装成了静态版本"; rc=1; fi
fi
echo "手册 §8.7.2 Installed libraries：libbz2.so"
echo "4) 共享库及其符号链接："
for f in /usr/lib/libbz2.so /usr/lib/libbz2.so.1 /usr/lib/libbz2.so.1.0 /usr/lib/libbz2.so.$VER; do
  if [ -e "$f" ]; then printf '   OK   %-28s -> %-22s（%s 字节）\n' "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
ls -l /usr/lib/libbz2* | sed 's/^/     /'
echo "   手册要求的两个符号链接目标（均为 libbz2.so.$VER）："
for l in /usr/lib/libbz2.so /usr/lib/libbz2.so.1; do
  t=$(readlink "$l" || true)
  if [ "$t" = "libbz2.so.$VER" ]; then printf '   OK   %-24s -> %s\n' "$l" "$t"
  else printf '   FAIL %s 指向 %s，手册要求 libbz2.so.%s\n' "$l" "${t:-（非符号链接）}" "$VER"; rc=1; fi
done
echo "   共享库 SONAME："
soname=$(objdump -p /usr/lib/libbz2.so.$VER | awk '/SONAME/{print $2}')
echo "   SONAME = $soname"
if [ "$soname" = "libbz2.so.1.0" ]; then echo "   OK   SONAME 为 libbz2.so.1.0（Makefile-libbz2_so 的设定）"
else echo "   INFO SONAME 为 $soname"; fi
echo "5) 手册要求删除的静态库 /usr/lib/libbz2.a（Remove a useless static library）："
if [ -e /usr/lib/libbz2.a ]; then echo "   FAIL /usr/lib/libbz2.a 仍存在"; rc=1
else echo "   OK   /usr/lib/libbz2.a 已删除"; fi
echo "6) 头文件（供后续包 configure 检测 bzip2）："
if [ -s /usr/include/bzlib.h ]; then echo "   OK   /usr/include/bzlib.h（$(stat -c %s /usr/include/bzlib.h) 字节）"
else echo "   FAIL /usr/include/bzlib.h 缺失或为空"; rc=1; fi
echo "手册 §8.7.2 Installed directory：/usr/share/doc/bzip2-$VER"
echo "7) 文档目录（由 $PATCHF 引入）："
if [ -d "/usr/share/doc/bzip2-$VER" ]; then
  echo "   OK   /usr/share/doc/bzip2-$VER"
  ls -l "/usr/share/doc/bzip2-$VER" | sed 's/^/        /'
else echo "   FAIL /usr/share/doc/bzip2-$VER 缺失（补丁未生效？）"; rc=1; fi
echo "8) 手册页（第 3 条 sed 保证装到 /usr/share/man，而不是 /usr/man）："
for m in bzip2 bzdiff bzgrep bzmore; do
  if [ -e "/usr/share/man/man1/$m.1" ]; then printf '   OK   /usr/share/man/man1/%s.1\n' "$m"
  else printf '   FAIL /usr/share/man/man1/%s.1 缺失\n' "$m"; rc=1; fi
done
ls -l /usr/share/man/man1/bz* | sed 's/^/     /'
if [ -d /usr/man ]; then echo "   FAIL /usr/man 存在，说明第 3 条 sed 未生效"; rc=1
else echo "   OK   /usr/man 不存在，手册页位置正确"; fi
echo "9) 实际运行验证（自加检查，非手册命令）：bzip2 压缩 / bunzip2 解压 / bzcat 往返："
tmpd=$(mktemp -d /tmp/bzip2-verify-XXXXXX)
( set -e
  cd "$tmpd"
  head -c 20000 /usr/share/man/man1/bzip2.1 > orig.txt
  cp orig.txt work.txt
  /usr/bin/bzip2 -9 work.txt
  echo "     bzip2 --version：$(/usr/bin/bzip2 --version 2>&1 | sed -n 1p)"
  echo "     压缩：$(stat -c %s orig.txt) -> $(stat -c %s work.txt.bz2) 字节"
  /usr/bin/bzcat work.txt.bz2 > cat.txt
  cmp orig.txt cat.txt && echo "     bzcat 输出与原文一致"
  /usr/bin/bunzip2 work.txt.bz2
  cmp orig.txt work.txt && echo "     bunzip2 还原与原文一致"
) && echo "   OK   bzip2 / bzcat / bunzip2 往返正常" || { echo "   FAIL bzip2 往返测试失败"; rc=1; }
echo "   用 -lbz2 链接一个调用 BZ2_bzBuffToBuffCompress/Decompress 的小程序："
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <bzlib.h>
int main(void) {
    const char *src = "LFS 13.0-systemd bzip2 round trip test -- "
                      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    char buf[512], out[512];
    unsigned int blen = sizeof buf, olen = sizeof out;
    printf("BZ2_bzlibVersion()=%s\n", BZ2_bzlibVersion());
    if (BZ2_bzBuffToBuffCompress(buf, &blen, (char *)src, strlen(src) + 1, 9, 0, 30) != BZ_OK) return 1;
    if (BZ2_bzBuffToBuffDecompress(out, &olen, buf, blen, 0, 0) != BZ_OK) return 2;
    printf("compressed %zu -> %u bytes, round trip %s\n",
           strlen(src) + 1, blen, strcmp(out, src) == 0 ? "OK" : "MISMATCH");
    return strcmp(out, src) == 0 ? 0 : 3;
}
EOF
if gcc -o "$tmpd/t" "$tmpd/t.c" -lbz2 && "$tmpd/t"; then
  echo "   OK   -lbz2 链接、运行、压缩/解压往返均正常"
  echo "   该程序链接到的 libbz2："
  ldd "$tmpd/t" | grep -i libbz2 | sed 's/^/        /'
else
  echo "   FAIL 无法用 -lbz2 编译或运行 bzip2 测试程序"; rc=1
fi
rm -rf "$tmpd"
echo "10) 本节写入系统的全部文件清单："
ls -ld /usr/bin/{bunzip2,bzcat,bzcmp,bzdiff,bzegrep,bzfgrep,bzgrep,bzip2,bzip2recover,bzless,bzmore} 2>/dev/null | sed 's/^/     /'
ls -ld /usr/lib/libbz2* /usr/include/bzlib.h /usr/share/man/man1/bz*.1 "/usr/share/doc/bzip2-$VER" 2>/dev/null | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Bzip2 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留 make（含测试）完整输出后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（输出先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.7.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  make 完整输出已在 $MAKELOG（= 宿主 /root/lfs/sources/.bzip2-make.log）"
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
echo "===== §8.7 完成，结束时间：$(date -Is) ====="
