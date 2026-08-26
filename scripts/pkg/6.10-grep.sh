#!/usr/bin/env bash
# LFS 13.0-systemd §6.10 Grep-3.12
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.10.1 的命令序列（全部，无补丁、无 sed、无测试套件）：
#   ./configure --prefix=/usr   \
#               --host=$LFS_TGT \
#               --build=$(./build-aux/config.guess)
#   make
#   make DESTDIR=$LFS install
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=grep
VER=3.12
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.10 Grep-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 32 MB"
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
echo "可用空间（手册本节要求 32 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2~§6.9 产物必须可用 -----"
for t in ld as ar ranlib gcc g++; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少前置产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS_TGT-gcc --version | head -n1
echo "§5.5 Glibc / §5.6 Libstdc++ 产物（本节交叉编译与链接所必需）："
for f in usr/lib/libc.so.6 usr/lib/ld-linux-x86-64.so.2 usr/lib/crt1.o \
         usr/include/stdio.h usr/lib/libstdc++.so.6; do
  [ -e "$LFS/$f" ] || { echo "错误：前置产物缺失：\$LFS/$f" >&2; exit 1; }
  printf 'OK   $LFS/%s\n' "$f"
done
echo "上一任务（§6.9 Gawk-5.3.2）产物必须可用："
for f in usr/bin/gawk usr/bin/awk usr/bin/gawk-5.3.2; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.9 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%-20s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/lib/libncursesw.so.6（§6.3）：%s\n' "$(file -b $LFS/usr/lib/libncursesw.so.6 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/bash（§6.4）：%s\n' "$(file -b $LFS/usr/bin/bash | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/ls（§6.5）：%s\n' "$(file -b $LFS/usr/bin/ls | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/diff（§6.6）：%s\n' "$(file -b $LFS/usr/bin/diff | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/file（§6.7）：%s\n' "$(file -b $LFS/usr/bin/file | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/find（§6.8）：%s\n' "$(file -b $LFS/usr/bin/find | cut -d, -f1-2)"
echo "本节安装前 \$LFS/usr/bin 下不应已有 grep（应为首次安装）："
for f in usr/bin/grep usr/bin/egrep usr/bin/fgrep; do
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
echo "Grep 自报版本：$(grep -m1 -E "^PACKAGE_VERSION='" configure)"
echo "本节无补丁：手册 §6.10 未规定任何 patch。"
echo "本节也没有 sed 预处理：手册 §8.36.1 的 sed -i \"s/echo/#echo/\" src/egrep.sh"
echo "  属于第 8 章的 Grep，本章 §6.10 不执行（本章只有 configure/make/make install 三条命令）。"
echo

echo "================= 6.10.1 Installation of Grep ================="
echo "----- configure（手册原文命令） -----"
echo "手册命令："
echo "  ./configure --prefix=/usr   \\"
echo "              --host=\$LFS_TGT \\"
echo "              --build=\$(./build-aux/config.guess)"
echo "build 三元组（./build-aux/config.guess）：$(./build-aux/config.guess)"
time ./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build)_triplet *=' Makefile | sed 's/^/  /' || true
grep -E '^(prefix|CC) *=' Makefile | head -n5 | sed 's/^/  /' || true
echo "config.log 中的 cross_compiling 判定（应为 yes）："
grep -m1 -E "^cross_compiling=" config.log | sed 's/^ */  /' || echo "  （config.log 未以该形式记录，见上面的 build/host 三元组）"
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

echo "================= 本节测试 ================="
echo "手册 §6.10 未规定任何测试：本节命令只有 ./configure、make、make DESTDIR=\$LFS install，"
echo "没有 make check（Grep 的测试套件由第 8 章 §8.36 在 chroot 内执行：那里才有 make check）。"
echo "原因见手册 §6.1：本章的程序是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.36.2 Contents of Grep） -----"
rc=0
echo "1) 安装的程序：egrep、fgrep、grep"
for f in usr/bin/grep usr/bin/egrep usr/bin/fgrep; do
  if [ -e "$LFS/$f" ]; then
    printf '   OK   $LFS/%-16s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
  else
    printf '   FAIL $LFS/%s 缺失\n' "$f"; rc=1
  fi
done
echo "   egrep/fgrep 的形态（Grep 3.x 起是调用 grep -E / grep -F 的 shell 包装脚本）："
for f in usr/bin/egrep usr/bin/fgrep; do
  [ -e "$LFS/$f" ] && sed -n '1,$p' "$LFS/$f" | grep -m1 -E 'grep (-E|-F)' | sed "s|^|     \$LFS/$f: |" || true
done
echo "2) grep 二进制不应是宿主 /usr/bin/grep 的拷贝，且必须可执行位齐全："
ls -l $LFS/usr/bin/grep $LFS/usr/bin/egrep $LFS/usr/bin/fgrep | sed "s|$LFS|\$LFS|" | sed 's/^/     /'
echo "3) 手册页抽查："
for f in usr/share/man/man1/grep.1 usr/share/man/man1/egrep.1 usr/share/man/man1/fgrep.1; do
  if [ -e "$LFS/$f" ]; then printf '   OK   $LFS/%s\n' "$f"
  else printf '   INFO $LFS/%s 未安装\n' "$f"; fi
done
echo "4) 本章不应有多余目录被装到 \$LFS（信息性）："
for d in usr/share/doc/grep usr/share/info; do
  if [ -e "$LFS/$d" ]; then printf '   INFO $LFS/%s 存在\n' "$d"
  else printf '   INFO $LFS/%s 未安装\n' "$d"; fi
done
[ $rc -eq 0 ] || { echo "错误：Grep 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
echo "  grep: $(file -b $LFS/usr/bin/grep)"
echo "readelf 头（grep）："
readelf -h $LFS/usr/bin/grep | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应链接 §5.5 的 libc）："
$LFS_TGT-readelf -d $LFS/usr/bin/grep | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/grep | grep 'interpreter' | sed 's/^/  /'
echo "二进制中的版本字符串（应为 $VER）："
strings -a $LFS/usr/bin/grep | grep -m2 -E "^(GNU grep )?$VER\$|grep.*$VER" | sed 's/^/  版本: /' || true
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/grep --version）"
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
[ -d "$LFS/sources/$SRCDIR" ] && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"
echo "$LFS 占用：$(du -sh $LFS 2>/dev/null | cut -f1)"

echo
echo "===== §6.10 完成，结束时间：$(date -Is) ====="
