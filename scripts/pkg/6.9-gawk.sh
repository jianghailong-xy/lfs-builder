#!/usr/bin/env bash
# LFS 13.0-systemd §6.9 Gawk-5.3.2
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.9.1 的命令序列（全部，无补丁、无测试套件）：
#   sed -i 's/extras//' Makefile.in
#   ./configure --prefix=/usr   \
#               --host=$LFS_TGT \
#               --build=$(build-aux/config.guess)
#   make
#   make DESTDIR=$LFS install
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=gawk
VER=5.3.2
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.9 Gawk-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 49 MB"
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
echo "可用空间（手册本节要求 49 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2~§6.8 产物必须可用 -----"
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
echo "上一任务（§6.8 Findutils-4.10.0）产物必须可用："
for f in usr/bin/find usr/bin/xargs usr/bin/locate usr/bin/updatedb; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.8 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%-20s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/lib/libncursesw.so.6（§6.3）：%s\n' "$(file -b $LFS/usr/lib/libncursesw.so.6 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/bash（§6.4）：%s\n' "$(file -b $LFS/usr/bin/bash | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/ls（§6.5）：%s\n' "$(file -b $LFS/usr/bin/ls | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/diff（§6.6）：%s\n' "$(file -b $LFS/usr/bin/diff | cut -d, -f1-2)"
printf 'OK   $LFS/usr/bin/file（§6.7）：%s\n' "$(file -b $LFS/usr/bin/file | cut -d, -f1-2)"
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
echo "Gawk 自报版本：$(grep -m1 -E "^PACKAGE_VERSION='" configure)"
echo "本节无补丁：手册 §6.9 未规定任何 patch。"
echo

echo "================= 6.9.1 Installation of Gawk ================="
echo "----- 第一步：确保不安装不需要的文件（手册原文命令） -----"
echo "手册命令：  sed -i 's/extras//' Makefile.in"
echo "作用：从 Makefile.in 的 SUBDIRS/DIST_SUBDIRS 中去掉 extras 子目录。extras/ 只含"
echo "  gawk.sh 与 gawk.csh 两个 shell 启动脚本，会被装到 /etc/profile.d，本章不需要。"
echo "  （注意：grcat/pwcat 来自 awklib/，装到 /usr/libexec/awk，是手册 §8.63.2 列出的"
echo "   正常产物，不受这条 sed 影响。）执行前后对照："
echo "  执行前：$(grep -m1 -n 'extras' Makefile.in | sed 's/^/    /')"
grep -c 'extras' Makefile.in | sed 's/^/  执行前 Makefile.in 中 extras 出现次数：/'
sed -i 's/extras//' Makefile.in
echo "  执行后 Makefile.in 中 extras 出现次数：$(grep -c 'extras' Makefile.in || true)"
echo "  SUBDIRS 行确认（应已不含 extras）："
grep -m2 -n -E '^(SUBDIRS|DIST_SUBDIRS) *=' Makefile.in | sed 's/^/    /'
echo

echo "----- configure（手册原文命令） -----"
echo "手册命令："
echo "  ./configure --prefix=/usr   \\"
echo "              --host=\$LFS_TGT \\"
echo "              --build=\$(build-aux/config.guess)"
echo "build 三元组（build-aux/config.guess）：$(build-aux/config.guess)"
time ./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build)_triplet *=' Makefile | sed 's/^/  /' || true
grep -E '^(prefix|CC) *=' Makefile | head -n5 | sed 's/^/  /' || true
echo "config.log 中的 cross_compiling 判定（应为 yes）："
grep -m1 -E "cross_compiling=" config.log | sed 's/^ */  /' || echo "  （config.log 未以该形式记录，见上面的 build/host 三元组）"
echo "生成的 Makefile 中 SUBDIRS（应不含 extras）："
grep -m1 -E '^SUBDIRS *=' Makefile | sed 's/^/  /' || true
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
echo "手册 §6.9 未规定任何测试：本节命令只有 sed、./configure、make、make DESTDIR=\$LFS install，"
echo "没有 make check / make test（Gawk 的测试套件由第 8 章 §8.63 在 chroot 内执行）。"
echo "原因见手册 §6.1：本章的程序与库是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.63.2 Contents of Gawk） -----"
rc=0
echo "1) 安装的程序：gawk、gawk-$VER（gawk 的硬链接）、awk（指向 gawk 的链接）"
for f in usr/bin/gawk usr/bin/gawk-$VER usr/bin/awk; do
  if [ -e "$LFS/$f" ]; then
    printf '   OK   $LFS/%-20s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
  else
    printf '   FAIL $LFS/%s 缺失\n' "$f"; rc=1
  fi
done
echo "   awk 链接目标：$(readlink $LFS/usr/bin/awk 2>/dev/null || echo '（非符号链接）')"
echo "   gawk 与 gawk-$VER 的 inode（手册说 gawk-$VER 是 gawk 的硬链接，应相同）："
stat -c '     %i  %n' $LFS/usr/bin/gawk $LFS/usr/bin/gawk-$VER | sed "s|$LFS|\$LFS|"
echo "2) 安装的库（/usr/lib/gawk 下的扩展模块）："
if [ -d "$LFS/usr/lib/gawk" ]; then
  for l in filefuncs fnmatch fork inplace intdiv ordchr readdir readfile revoutput revtwoway rwarray time; do
    if [ -e "$LFS/usr/lib/gawk/$l.so" ]; then printf '   OK   $LFS/usr/lib/gawk/%s.so\n' "$l"
    else printf '   FAIL $LFS/usr/lib/gawk/%s.so 缺失\n' "$l"; rc=1; fi
  done
else
  echo "   FAIL \$LFS/usr/lib/gawk 目录缺失"; rc=1
fi
echo "3) 安装的目录（手册 §8.63.2：/usr/lib/gawk、/usr/libexec/awk、/usr/share/awk、/usr/share/doc/gawk-$VER）"
for d in usr/lib/gawk usr/libexec/awk usr/share/awk usr/share/doc/gawk-$VER; do
  if [ -d "$LFS/$d" ]; then printf '   OK   $LFS/%s\n' "$d"
  else printf '   INFO $LFS/%s 未安装（本章 DESTDIR 安装可不含文档等）\n' "$d"; fi
done
echo "   $LFS/usr/libexec/awk 内容（来自 awklib/，手册 §8.63.2 列出的正常产物）："
ls -l $LFS/usr/libexec/awk 2>/dev/null | sed 's/^/        /' || echo "        （目录不存在）"
echo "5) 本节 sed 's/extras//' 的效果验证：extras/ 的 gawk.sh、gawk.csh 不应被安装"
extras_rc=0
for f in etc/profile.d/gawk.sh etc/profile.d/gawk.csh; do
  if [ -e "$LFS/$f" ]; then printf '   FAIL $LFS/%s 被安装了——sed 未生效\n' "$f"; extras_rc=1
  else printf '   OK   $LFS/%s 未安装（符合预期）\n' "$f"; fi
done
[ $extras_rc -eq 0 ] || rc=1
echo "6) 手册页抽查："
for f in usr/share/man/man1/gawk.1 usr/share/man/man1/awk.1; do
  if [ -e "$LFS/$f" ]; then printf '   OK   $LFS/%s\n' "$f"
  else printf '   INFO $LFS/%s 未安装\n' "$f"; fi
done
[ $rc -eq 0 ] || { echo "错误：Gawk 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
echo "  gawk: $(file -b $LFS/usr/bin/gawk)"
echo "readelf 头（gawk）："
readelf -h $LFS/usr/bin/gawk | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应链接 §5.5 的 libc）："
$LFS_TGT-readelf -d $LFS/usr/bin/gawk | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/gawk | grep 'interpreter' | sed 's/^/  /'
echo "扩展模块 filefuncs.so 的类型与机器："
file -b $LFS/usr/lib/gawk/filefuncs.so | sed 's/^/  /'
echo "二进制中的版本字符串（应为 $VER）："
strings -a $LFS/usr/bin/gawk | grep -m2 -E "$VER" | sed 's/^/  版本: /' || true
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/gawk --version）"
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
echo "===== §6.9 完成，结束时间：$(date -Is) ====="
