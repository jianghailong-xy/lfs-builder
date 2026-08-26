#!/usr/bin/env bash
# LFS 13.0-systemd §6.17 Binutils-2.46.0 - Pass 2
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.17.1 的命令序列（全部，无补丁、无测试套件）：
#   sed '6031s/$add_dir//' -i ltmain.sh
#   mkdir -v build
#   cd       build
#   ../configure                   \
#       --prefix=/usr              \
#       --build=$(../config.guess) \
#       --host=$LFS_TGT            \
#       --disable-nls              \
#       --enable-shared            \
#       --enable-gprofng=no        \
#       --disable-werror           \
#       --enable-64-bit-bfd        \
#       --enable-new-dtags         \
#       --enable-default-hash-style=gnu
#   make
#   make DESTDIR=$LFS install
#   rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=binutils
VER=2.46.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.17 Binutils-$VER - Pass 2 ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.4 SBU，Required disk space 557 MB"
echo "手册简介：The Binutils package contains a linker, an assembler, and other"
echo "          tools for handling object files."
echo
echo "----- 环境（手册 §4.4 / iii. General Compilation Instructions） -----"
echo "whoami   : $(whoami)"
echo "LFS      : $LFS"
echo "LFS_TGT  : $LFS_TGT"
echo "PATH     : $PATH"
echo "LC_ALL   : $LC_ALL"
echo "CONFIG_SITE: $CONFIG_SITE"
echo "MAKEFLAGS: ${MAKEFLAGS:-（未设置）}"
echo "umask    : $(umask)"
echo "hash 关闭: $(set -o | grep hashall)"
echo "uname -m : $(uname -m)"
[ "$(whoami)" = "lfs" ] || { echo "错误：必须以 lfs 用户构建（手册 §6.1 警告：以 root 构建会毁掉宿主系统）" >&2; exit 1; }
[ "$LFS" = "/mnt/lfs" ] || { echo "错误：LFS 不是 /mnt/lfs" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点" >&2; exit 1; }
echo "可用空间（手册本节要求 557 MB）："
df -h "$LFS" | tail -n1
avail_mb=$(df -Pm "$LFS" | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 557 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 557MB" >&2; exit 1; }
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2~§6.16 产物必须可用 -----"
for t in ld as ar ranlib gcc g++; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少前置产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS_TGT-gcc --version | head -n1
echo "§5.2 Binutils Pass 1 产物（本节要在其之上重建）：$($LFS_TGT-ld --version | head -n1)"
echo "§5.5 Glibc / §5.6 Libstdc++ 产物（本节交叉编译与链接所必需）："
for f in usr/lib/libc.so.6 usr/lib/ld-linux-x86-64.so.2 usr/lib/crt1.o \
         usr/include/stdio.h usr/lib/libstdc++.so.6; do
  [ -e "$LFS/$f" ] || { echo "错误：前置产物缺失：\$LFS/$f" >&2; exit 1; }
  printf 'OK   $LFS/%s\n' "$f"
done
echo "上一任务（§6.16 Xz-5.8.2）产物必须可用："
for f in usr/bin/xz usr/lib/liblzma.so.5; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.16 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%-24s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
echo "§6.2~§6.15 产物抽查："
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n'                "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/lib/libncursesw.so.6（§6.3）：%s\n'  "$(file -b $LFS/usr/lib/libncursesw.so.6 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/bash（§6.4）：%s\n'              "$(file -b $LFS/usr/bin/bash | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/ls（§6.5）：%s\n'                "$(file -b $LFS/usr/bin/ls | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/diff（§6.6）：%s\n'              "$(file -b $LFS/usr/bin/diff | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/file（§6.7）：%s\n'              "$(file -b $LFS/usr/bin/file | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/find（§6.8）：%s\n'              "$(file -b $LFS/usr/bin/find | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/gawk（§6.9）：%s\n'              "$(file -b $LFS/usr/bin/gawk | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/grep（§6.10）：%s\n'             "$(file -b $LFS/usr/bin/grep | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/gzip（§6.11）：%s\n'             "$(file -b $LFS/usr/bin/gzip | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/make（§6.12）：%s\n'             "$(file -b $LFS/usr/bin/make | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/patch（§6.13）：%s\n'            "$(file -b $LFS/usr/bin/patch | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/sed（§6.14）：%s\n'              "$(file -b $LFS/usr/bin/sed | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/tar（§6.15）：%s\n'              "$(file -b $LFS/usr/bin/tar | cut -d, -f1-2)"
echo "本节安装前 \$LFS/usr/bin 下不应已有 binutils 程序（应为首次装入 \$LFS/usr）："
for f in usr/bin/ld usr/bin/as usr/lib/libbfd.so; do
  if [ -e "$LFS/$f" ]; then printf '   INFO $LFS/%s 已存在（将被覆盖）\n' "$f"
  else printf '   OK   $LFS/%s 尚未安装\n' "$f"; fi
done
echo

cd $LFS/sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii：以 lfs 用户在 \$LFS/sources 下解包） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "Binutils 自报版本：$(grep -m1 -E "^PACKAGE_VERSION='" configure)"
echo "bfd/version.m4：$(cat bfd/version.m4)"
echo "本节无补丁：手册 §6.17 未规定任何 patch，只有下面的 sed 变通 + configure/make/install + rm。"
echo

echo "================= 6.17.1 Installation of Binutils ================="
echo "----- 手册变通：修正 ltmain.sh 第 6031 行（手册原文命令） -----"
echo "手册原文说明：Binutils building system relies on an shipped libtool copy to link"
echo "  against internal static libraries, but the libiberty and zlib copies shipped in"
echo "  the package do not use libtool. This inconsistency may cause produced binaries"
echo "  mistakenly linked against libraries from the host distro. Work around this issue:"
echo "手册命令：sed '6031s/\$add_dir//' -i ltmain.sh"
echo "改动前 ltmain.sh:6031："
sed -n '6031p' ltmain.sh | sed 's/^/  /'
grep -q 'add_dir' <(sed -n '6031p' ltmain.sh) || {
  echo "错误：ltmain.sh 第 6031 行不含 \$add_dir，源码版本与手册 §6.17 不一致，拒绝继续" >&2
  echo "  实际含 \$add_dir 的行号：$(grep -n 'add_dir' ltmain.sh | head -20)" >&2
  exit 1
}
sed '6031s/$add_dir//' -i ltmain.sh
echo "改动后 ltmain.sh:6031："
sed -n '6031p' ltmain.sh | sed 's/^/  /'
echo

echo "----- 手册命令：mkdir -v build && cd build -----"
mkdir -v build
cd       build
echo "构建目录：$PWD"
echo

echo "----- configure（手册原文命令） -----"
echo "手册命令："
echo "  ../configure                   \\"
echo "      --prefix=/usr              \\"
echo "      --build=\$(../config.guess) \\"
echo "      --host=\$LFS_TGT            \\"
echo "      --disable-nls              \\"
echo "      --enable-shared            \\"
echo "      --enable-gprofng=no        \\"
echo "      --disable-werror           \\"
echo "      --enable-64-bit-bfd        \\"
echo "      --enable-new-dtags         \\"
echo "      --enable-default-hash-style=gnu"
echo "../config.guess 的输出：$(../config.guess)"
echo "手册对新增选项的说明："
echo "  --enable-shared      Builds libbfd as a shared library."
echo "  --enable-64-bit-bfd  Enables 64-bit support (on hosts with smaller word sizes)."
echo "                       This may not be needed on 64-bit systems, but it does no harm."
time ../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-new-dtags         \
    --enable-default-hash-style=gnu
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build|target) *=' Makefile | head -n6 | sed 's/^/  /' || true
grep -E '^(prefix) *=' Makefile | head -n2 | sed 's/^/  /' || true
echo "  --enable-shared 生效确认（应 enable_shared=yes）："
grep -m1 -E "^enable_shared=" bfd/config.log 2>/dev/null | sed 's/^/    /' || true
echo "  --disable-nls 生效确认（应 USE_NLS=no / enable_nls=no）："
grep -m1 -E "^enable_nls=" bfd/config.log 2>/dev/null | sed 's/^/    /' || true
echo "  --enable-gprofng=no 生效确认（configured-subdirs 中不应有 gprofng）："
if grep -qw gprofng Makefile; then echo "    INFO Makefile 中出现 gprofng 字样："; grep -nw gprofng Makefile | head -n3 | sed 's/^/      /'
else echo "    OK   Makefile 中无 gprofng 子目录"; fi
echo "  --enable-64-bit-bfd 生效确认："
grep -m1 -E "^enable_64_bit_bfd=" bfd/config.log 2>/dev/null | sed 's/^/    /' || echo "    （bfd/config.log 未以该形式记录）"
echo "  --enable-default-hash-style=gnu 生效确认（ld 默认 hash style）："
grep -m1 -E "DEFAULT_EMIT_(SYSV|GNU)_HASH|default_hash_style" ld/config.log 2>/dev/null | sed 's/^/    /' || echo "    （见下方安装后 ld 行为，本节不在宿主运行目标二进制）"
echo "  cross_compiling 判定（应为 yes）："
grep -m1 -E "^cross_compiling=" config.log | sed 's/^ */    /' || echo "    （config.log 未以该形式记录，见上面的 build/host 三元组）"
echo

echo "----- 编译：make -----"
time make
echo

echo "----- 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 手册要求：删除对交叉编译有害的 libtool 归档文件与多余静态库 -----"
echo "手册原文：Remove the libtool archive files because they are harmful for cross"
echo "  compilation, and remove unnecessary static libraries:"
echo "手册命令：rm -v \$LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}"
echo "删除前 \$LFS/usr/lib 下的 .a/.la 文件："
find $LFS/usr/lib -maxdepth 1 \( -name '*.a' -o -name '*.la' \) | sed "s|$LFS|\$LFS|" | sort | sed 's/^/  /' || true
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
echo "删除后确认（下列 10 个文件必须都不存在）："
rc=0
for f in bfd ctf ctf-nobfd opcodes sframe; do
  for e in a la; do
    if [ -e "$LFS/usr/lib/lib$f.$e" ]; then printf '   FAIL $LFS/usr/lib/lib%s.%s 仍存在\n' "$f" "$e"; rc=1
    else printf '   OK   $LFS/usr/lib/lib%s.%s 已删除\n' "$f" "$e"; fi
  done
done
[ $rc -eq 0 ] || { echo "错误：libtool 归档/静态库未按手册删除" >&2; exit 1; }
echo "\$LFS/usr/lib 下剩余的 .a/.la（本节之后应无 binutils 相关残留）："
find $LFS/usr/lib -maxdepth 1 \( -name '*.a' -o -name '*.la' \) | sed "s|$LFS|\$LFS|" | sort | sed 's/^/  /' || true
echo "  （上面若无输出即为无残留）"
echo

echo "================= 本节测试 ================="
echo "手册 §6.17 未规定任何测试：本节命令只有 sed 变通、mkdir/cd build、../configure、"
echo "make、make DESTDIR=\$LFS install 和 rm -v \$LFS/usr/lib/lib{...}.{a,la}，没有 make check。"
echo "（对比：第 8 章 §8.21 Binutils 才有 make -k check 与结果检查；第 5 章 §5.2 Pass 1 同样无测试。）"
echo "原因见手册 §6.1：本章的程序是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.21.2 Contents of Binutils） -----"
rc=0
echo "1) 安装的程序（手册 §8.21.2 Installed programs，扣除本节禁用的部分）："
for f in addr2line ar as c++filt elfedit gprof ld ld.bfd nm objcopy objdump \
         ranlib readelf size strings strip; do
  p=$LFS/usr/bin/$f
  if [ -e "$p" ]; then
    printf '   OK   $LFS/usr/bin/%-10s %s\n' "$f" "$(file -b $p | cut -d, -f1-2)"
  else
    printf '   FAIL $LFS/usr/bin/%s 缺失\n' "$f"; rc=1
  fi
done
echo "   本节按手册用 --enable-gprofng=no 禁用了 gprofng，故 §8.21.2 中的 gprofng 不应存在："
if [ -e "$LFS/usr/bin/gprofng" ]; then printf '   FAIL $LFS/usr/bin/gprofng 存在，--enable-gprofng=no 未生效\n'; rc=1
else printf '   OK   $LFS/usr/bin/gprofng 不存在（符合 --enable-gprofng=no）\n'; fi
echo "   dwp 属 gold 链接器，本节 configure 未启用 gold，故不应存在："
if [ -e "$LFS/usr/bin/dwp" ]; then printf '   INFO $LFS/usr/bin/dwp 存在\n'
else printf '   OK   $LFS/usr/bin/dwp 不存在（未启用 gold）\n'; fi
echo "2) 安装的库（手册 §8.21.2 Installed libraries，扣除 libgprofng）："
for f in libbfd.so libctf.so libctf-nobfd.so libopcodes.so libsframe.so; do
  if [ -e "$LFS/usr/lib/$f" ]; then
    printf '   OK   $LFS/usr/lib/%-18s %s\n' "$f" "$(file -b $LFS/usr/lib/$f | cut -d, -f1-2)"
  else printf '   FAIL $LFS/usr/lib/%s 缺失\n' "$f"; rc=1; fi
done
if [ -e "$LFS/usr/lib/libgprofng.so" ]; then printf '   FAIL $LFS/usr/lib/libgprofng.so 存在，--enable-gprofng=no 未生效\n'; rc=1
else printf '   OK   $LFS/usr/lib/libgprofng.so 不存在（符合 --enable-gprofng=no）\n'; fi
echo "3) 安装的目录（手册 §8.21.2 Installed directory：/usr/lib/ldscripts）："
echo "   注意：§8.21.2 的 /usr/lib/ldscripts 描述的是第 8 章的本地（native）构建。本节是交叉"
echo "   构建（--host=\$LFS_TGT），binutils 把 ld 脚本装到 tooldir 下，即："
echo "     scriptdir = tooldir/lib = \$exec_prefix/\$target_alias/lib = /usr/$LFS_TGT/lib"
echo "   本次 ld/Makefile 的实际取值："
grep -E '^(exec_prefix|target_alias|tooldir|scriptdir) *=' ld/Makefile | sed 's/^/     /'
ldsdir=""
for d in usr/$LFS_TGT/lib/ldscripts usr/lib/ldscripts; do
  [ -d "$LFS/$d" ] && { ldsdir=$d; break; }
done
if [ -n "$ldsdir" ]; then
  printf '   OK   $LFS/%s（%s 项）\n' "$ldsdir" "$(ls -A $LFS/$ldsdir | wc -l)"
  ls $LFS/$ldsdir | head -n5 | sed 's/^/        /'
  echo "        ..."
  echo "   默认链接脚本存在性确认（elf_x86_64.x）："
  if [ -e "$LFS/$ldsdir/elf_x86_64.x" ]; then echo "     OK   \$LFS/$ldsdir/elf_x86_64.x"
  else echo "     FAIL \$LFS/$ldsdir/elf_x86_64.x 缺失"; rc=1; fi
else printf '   FAIL ldscripts 目录在 $LFS/usr/%s/lib 和 $LFS/usr/lib 下均缺失\n' "$LFS_TGT"; rc=1; fi
echo "4) ld 与 ld.bfd（手册：ld.bfd is a hard link to ld）："
ls -l $LFS/usr/bin/ld $LFS/usr/bin/ld.bfd | sed "s|$LFS|\$LFS|" | sed 's/^/     /'
if [ "$(stat -c %i $LFS/usr/bin/ld)" = "$(stat -c %i $LFS/usr/bin/ld.bfd)" ]; then
  echo "     OK   ld 与 ld.bfd 同 inode（硬链接，符合手册描述）"
else
  echo "     INFO ld 与 ld.bfd 不同 inode：$(stat -c %i $LFS/usr/bin/ld) / $(stat -c %i $LFS/usr/bin/ld.bfd)"
fi
echo "5) 共享库软链（--enable-shared 应产出带 soname 的 .so.*）："
ls -l $LFS/usr/lib/libbfd.so* $LFS/usr/lib/libopcodes.so* | sed "s|$LFS|\$LFS|" | sed 's/^/     /'
echo "6) 本次 make install 落盘的文件统计（DESTDIR=\$LFS，按修改时间挑出本次安装的）："
newf=$(find $LFS/usr -newer $LFS/sources/$SRCDIR/build/config.log \( -type f -o -type l \) 2>/dev/null | wc -l)
echo "     共 $newf 个文件/链接；其中 \$LFS/usr/bin 与 \$LFS/usr/lib 顶层部分："
find $LFS/usr/bin $LFS/usr/lib -maxdepth 1 -newer $LFS/sources/$SRCDIR/build/config.log \( -type f -o -type l \) 2>/dev/null \
  | sed "s|$LFS|\$LFS|" | sort | sed 's/^/       /' || true
[ $rc -eq 0 ] || { echo "错误：Binutils 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
echo "  ld:        $(file -b $LFS/usr/bin/ld)"
echo "  as:        $(file -b $LFS/usr/bin/as)"
echo "  libbfd.so: $(file -b $LFS/usr/lib/libbfd.so)"
echo "readelf 头（ld）："
readelf -h $LFS/usr/bin/ld | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应链接 §5.5 的 libc 与本包自己的 libbfd/libopcodes/libsframe/libctf）："
$LFS_TGT-readelf -d $LFS/usr/bin/ld | grep -E 'NEEDED|RUNPATH|RPATH' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/ld | grep 'interpreter' | sed 's/^/  /'
echo "二进制中的版本字符串（应为 $VER；binutils 把 \"GNU ld %s\" 与 \"(GNU Binutils) <ver>\""
echo "  分开存放，故分别匹配这两段）："
strings -a $LFS/usr/bin/ld | grep -m2 -E "^\(GNU Binutils\) $VER|^GNU ld " | sed 's/^/  ld  版本: /' || true
strings -a $LFS/usr/bin/as | grep -m2 -E "^\(GNU Binutils\) $VER|^$VER|^GNU assembler" | sed 's/^/  as  版本: /' || true
echo "  库 soname 佐证（应含 $VER）：$(basename $(readlink -f $LFS/usr/lib/libbfd.so))"
vercheck=$(strings -a $LFS/usr/bin/ld | grep -cE "$VER") || true
[ "${vercheck:-0}" -ge 1 ] || { echo "错误：ld 二进制中未出现版本号 $VER" >&2; exit 1; }
echo "  OK   ld 二进制中出现 $VER 的字符串共 $vercheck 处"
echo "确认未误链接宿主发行版的库（ltmain.sh 变通的目的；NEEDED 中不应出现宿主专有路径）："
$LFS_TGT-readelf -d $LFS/usr/bin/ld | grep -E 'NEEDED' | grep -vE 'libbfd|libopcodes|libsframe|libctf|libc\.so|libm\.so|libstdc\+\+|libgcc_s|libzstd|libz\.so' \
  | sed 's/^/  可疑: /' || true
echo "  （上面若无 \"可疑:\" 行，即无异常依赖）"
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/ld --version）"
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
[ -d "$LFS/sources/$SRCDIR" ] && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR（含其中的 build 子目录）"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"
echo "$LFS 占用：$(du -sh $LFS 2>/dev/null | cut -f1)"
df -h "$LFS" | tail -n1

echo
echo "===== §6.17 完成，结束时间：$(date -Is) ====="
