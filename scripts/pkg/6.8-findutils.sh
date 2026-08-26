#!/usr/bin/env bash
# LFS 13.0-systemd §6.8 Findutils-4.10.0
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.8.1 的命令序列（全部，无补丁、无测试套件）：
#   ./configure --prefix=/usr                   \
#               --localstatedir=/var/lib/locate \
#               --host=$LFS_TGT                 \
#               --build=$(build-aux/config.guess)
#   make
#   make DESTDIR=$LFS install
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=findutils
VER=4.10.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.8 Findutils-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 48 MB"
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
echo "可用空间（手册本节要求 48 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2~§6.7 产物必须可用 -----"
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
echo "上一任务（§6.7 File-5.46）产物必须可用："
for f in usr/bin/file usr/lib/libmagic.so.1 usr/share/misc/magic.mgc; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.7 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%-28s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/lib/libncursesw.so.6（§6.3）：%s\n' "$(file -b $LFS/usr/lib/libncursesw.so.6 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/bash（§6.4）：%s\n' "$(file -b $LFS/usr/bin/bash | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/ls（§6.5）：%s\n' "$(file -b $LFS/usr/bin/ls | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/diff（§6.6）：%s\n' "$(file -b $LFS/usr/bin/diff | cut -d, -f1-2)"
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
echo "Findutils 自报版本：$(grep -m1 -E '^AC_INIT' configure.ac 2>/dev/null || grep -m1 -E "^PACKAGE_VERSION='" configure)"
echo "本节无补丁：手册 §6.8 未规定任何 patch。"
echo

echo "================= 6.8.1 Installation of Findutils ================="
echo "----- configure（手册原文命令） -----"
echo "手册命令："
echo "  ./configure --prefix=/usr                   \\"
echo "              --localstatedir=/var/lib/locate \\"
echo "              --host=\$LFS_TGT                 \\"
echo "              --build=\$(build-aux/config.guess)"
echo "选项含义（手册 §8.64.1 对 --localstatedir 的说明）：把 locate 数据库放到"
echo "  /var/lib/locate，这是 FHS 规定的位置。"
echo "build 三元组（build-aux/config.guess）：$(build-aux/config.guess)"
time ./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build)_triplet *=' Makefile | sed 's/^/  /' || true
grep -E '^(prefix|localstatedir|CC) *=' Makefile | head -n5 | sed 's/^/  /' || true
echo "config.log 中的 cross_compiling 判定（应为 yes）："
grep -m1 -E "cross_compiling=" config.log | sed 's/^ */  /' || echo "  （config.log 未以该形式记录，见上面的 build/host 三元组）"
echo "localstatedir 落点确认（应为 /var/lib/locate）："
grep -m1 -E '^localstatedir *=' Makefile | sed 's/^/  /' || true
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
echo "手册 §6.8 未规定任何测试：本节命令只有 ./configure、make、make DESTDIR=\$LFS install，"
echo "没有 make check / make test（Findutils 的测试套件由第 8 章 §8.64 在 chroot 内执行）。"
echo "原因见手册 §6.1：本章的程序与库是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.64.2 Contents of Findutils） -----"
rc=0
echo "1) 安装的程序：find、locate、updatedb、xargs"
for f in usr/bin/find usr/bin/locate usr/bin/updatedb usr/bin/xargs; do
  if [ -e "$LFS/$f" ]; then
    printf '   OK   $LFS/%-18s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
  else
    printf '   FAIL $LFS/%s 缺失\n' "$f"; rc=1
  fi
done
echo "2) 安装的目录：/var/lib/locate"
if [ -d "$LFS/var/lib/locate" ]; then
  printf '   OK   $LFS/var/lib/locate 存在\n'
else
  printf '   INFO $LFS/var/lib/locate 未在本节创建（--localstatedir 已指向该路径，见上面 Makefile 确认；\n'
  printf '        目录由第 8 章重装 Findutils 或首次 updatedb 时生成）\n'
fi
echo "3) 手册页与库目录抽查："
for f in usr/share/man/man1/find.1 usr/share/man/man1/xargs.1 \
         usr/share/man/man1/locate.1 usr/share/man/man1/updatedb.1 \
         usr/share/man/man5/locatedb.5 usr/libexec/frcode; do
  if [ -e "$LFS/$f" ]; then printf '   OK   $LFS/%s\n' "$f"
  else printf '   INFO $LFS/%s 未安装\n' "$f"; fi
done
echo "4) 本节安装清单（\$LFS 下与 findutils 相关的文件）："
find $LFS/usr/bin $LFS/usr/libexec -maxdepth 1 \( -name find -o -name locate -o -name updatedb -o -name xargs -o -name frcode -o -name bigram -o -name code \) 2>/dev/null \
  | sed "s|^$LFS|   \$LFS|" | sort
[ $rc -eq 0 ] || { echo "错误：Findutils 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
for b in find xargs locate updatedb; do
  t=$(file -b $LFS/usr/bin/$b)
  case "$t" in
    ELF*x86-64*) echo "  $b: $t" ;;
    *)           echo "  $b: $t（脚本/非 ELF）" ;;
  esac
done
echo "readelf 头（find）："
readelf -h $LFS/usr/bin/find | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应链接 §5.5 的 libc）："
$LFS_TGT-readelf -d $LFS/usr/bin/find | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/find | grep 'interpreter' | sed 's/^/  /'
echo "xargs 动态依赖："
$LFS_TGT-readelf -d $LFS/usr/bin/xargs | grep -E 'NEEDED' | sed 's/^/  /'
echo "二进制中的版本字符串（应为 4.10.0）："
strings -a $LFS/usr/bin/find | grep -m1 -E '^(GNU findutils\) )?4\.10\.0$' | sed 's/^/  版本: /' || \
  strings -a $LFS/usr/bin/find | grep -m1 -E '4\.10\.0' | sed 's/^/  版本: /' || true
echo "locate 数据库路径编译进二进制的确认（应含 /var/lib/locate）："
strings -a $LFS/usr/bin/locate | grep -m2 -E '/var/lib/locate' | sed 's/^/  /' || \
  echo "  （未在 locate 中直接命中字符串，localstatedir 已由上面的 Makefile 确认）"
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/find --version）"
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
echo "===== §6.8 完成，结束时间：$(date -Is) ====="
