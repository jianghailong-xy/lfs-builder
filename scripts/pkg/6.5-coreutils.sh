#!/usr/bin/env bash
# LFS 13.0-systemd §6.5 Coreutils-9.10
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.5.1 的命令序列（全部，无补丁、无测试套件）：
#   ./configure --prefix=/usr                     \
#               --host=$LFS_TGT                   \
#               --build=$(build-aux/config.guess) \
#               --enable-install-program=hostname \
#               --enable-no-install-program=kill,uptime
#   make
#   make DESTDIR=$LFS install
#   mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
#   mkdir -pv $LFS/usr/share/man/man8
#   mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
#   sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=coreutils
VER=9.10
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §6.5 Coreutils-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.3 SBU，Required disk space 185 MB"
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
echo "可用空间（手册本节要求 185 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.2/§6.3/§6.4 产物必须可用 -----"
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
echo "上一任务（§6.4 Bash-5.3）产物必须可用："
for f in usr/bin/bash usr/bin/bashbug bin/sh; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.4 未完成" >&2; exit 1; }
  printf 'OK   $LFS/%-14s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
printf 'OK   $LFS/usr/bin/m4（§6.2）：%s\n' "$(file -b $LFS/usr/bin/m4 | cut -d, -f1-2)"
printf 'OK   $LFS/usr/lib/libncursesw.so.6（§6.3）：%s\n' "$(file -b $LFS/usr/lib/libncursesw.so.6 | cut -d, -f1-2)"
echo "手册 §4.2 的目录布局（本节最后的 mv 依赖 \$LFS/usr/sbin 存在）："
ls -ld $LFS/bin $LFS/usr/sbin | sed 's/^/  /'
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
echo "Coreutils 自报版本：$(grep -m1 -E '^AC_INIT' configure.ac | tr -d '\n')  /  $(cat .version 2>/dev/null || echo 'N/A')"
echo "本节无补丁：手册 §6.5 未规定任何 patch。"
echo "（注意：sources/ 下的 coreutils-9.10-i18n-1.patch 属于第 8 章 §8.61，本节不得应用。）"
echo

echo "----- 6.5.1 configure（交叉编译到 /usr） -----"
echo "build 三元组（build-aux/config.guess）：$(build-aux/config.guess)"
echo "--enable-install-program=hostname   ：手册说明 hostname 默认不装，但 Perl 测试套件需要它"
echo "--enable-no-install-program=kill,uptime：kill/uptime 由后续 Procps-ng、Util-linux 提供"
time ./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
echo
echo "configure 关键结果确认（必须是交叉编译：host=$LFS_TGT）："
grep -E '^(host|build)[a-z_]* *=' Makefile | head -n8 | sed 's/^/  /' || true
grep -E '^(prefix|CC|cross_compiling) *=' Makefile | sed 's/^/  /' || true
echo "config.log 中的 cross_compiling 判定："
grep -m1 -E "^cross_compiling='" config.log | sed 's/^/  /' || true
echo "--enable-install-program / --enable-no-install-program 是否生效："
grep -m1 -E '^no_install_progs_default *=' Makefile | sed 's/^/  /' || true
echo -n "  Makefile 中 hostname 应出现在待装程序里："
grep -c 'src/hostname' Makefile || true
echo -n "  Makefile 中 kill/uptime 应不在 bin_PROGRAMS 里："
grep -m1 -E '^bin_PROGRAMS *=' Makefile | tr ' ' '\n' | grep -cE '^src/(kill|uptime)$' || echo " 0（符合预期）"
echo

echo "----- 6.5.1 编译：make -----"
time make
echo

echo "----- 6.5.1 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 6.5.1 安装后处理：把程序移到最终位置（有程序硬编码可执行文件路径） -----"
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
echo "chroot.8 手册页节号改写结果（.TH 行应为 \"8\"）："
head -n 3 $LFS/usr/share/man/man8/chroot.8 | sed 's/^/  /'
echo

echo "================= 本节测试 ================="
echo "手册 §6.5 未规定任何测试：本节命令只有 configure、make、make DESTDIR=\$LFS install"
echo "以及安装后的 mv/mkdir/sed，没有 make check / make test"
echo "（Coreutils 的测试套件由第 8 章 §8.61 在 chroot 内执行）。"
echo "原因见手册 §6.1：本章的程序与库是用交叉工具链为目标平台（\$LFS_TGT）编译的，"
echo "在进入 chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.61.2 Contents of Coreutils） -----"
rc=0
# 手册 §8.61.2 的程序清单里，chcon 与 runcon 只在系统有 libselinux 时才会被构建：
# coreutils-9.10/configure.ac 中 "Don't build chcon and runcon if only have gnulib stubs"
# 一段，仅当 selinux/selinux.h 存在时才把它们加入 optional_bin_progs。
# LFS 不提供 libselinux（本次 configure 输出 "checking for selinux/selinux.h... no"），
# 故这两个程序按上游设计不安装，属预期结果而非本节失败。
PROGS="[ b2sum base32 base64 basename basenc cat chgrp chmod chown cksum comm
cp csplit cut date dd df dir dircolors dirname du echo env expand expr factor false
fmt fold groups head hostid id install join link ln logname ls md5sum mkdir mkfifo
mknod mktemp mv nice nl nohup nproc numfmt od paste pathchk pinky pr printenv printf
ptx pwd readlink realpath rm rmdir seq sha1sum sha224sum sha256sum sha384sum
sha512sum shred shuf sleep sort split stat stdbuf stty sum sync tac tail tee test
timeout touch tr true truncate tsort tty uname unexpand uniq unlink users vdir wc
who whoami yes"
missing=""; n=0
for p in $PROGS; do
  n=$((n+1))
  [ -f "$LFS/usr/bin/$p" ] || missing="$missing $p"
done
echo "1) 手册 §8.61.2 列出的程序（去掉 SELinux 专属的 chcon/runcon 后共 $n 个；"
echo "   chroot 已按本节要求移到 /usr/sbin，单独在第 2 项检查）："
if [ -n "$missing" ]; then
  echo "   FAIL 缺失：$missing"; rc=1
else
  echo "   OK   全部 $n 个都在 \$LFS/usr/bin 下"
fi
echo "   SELinux 专属程序（无 libselinux 时上游不构建，本节预期不存在）："
for p in chcon runcon; do
  if [ -e "$LFS/usr/bin/$p" ]; then printf '   INFO $LFS/usr/bin/%s 存在（宿主提供了 selinux 头文件）\n' "$p"
  else printf '   OK   $LFS/usr/bin/%s 不存在，符合无 libselinux 的预期\n' "$p"; fi
done
echo "   configure 对 selinux 头文件的判定："
echo "   （当前工作目录 $PWD 的 config.log 中的判定行）"
grep -m1 -E "^configure:.*checking for selinux/selinux\.h" config.log | sed "s/^/     /" || \
  grep -m1 "ac_cv_header_selinux_selinux_h=" config.log | sed "s/^/     /" || true
echo
echo "2) 本节 mv 的结果：chroot 必须在 /usr/sbin 而不是 /usr/bin："
if [ -f "$LFS/usr/sbin/chroot" ] && [ ! -e "$LFS/usr/bin/chroot" ]; then
  printf '   OK   $LFS/usr/sbin/chroot  %s\n' "$(file -b $LFS/usr/sbin/chroot | cut -d, -f1-2)"
else
  echo "   FAIL chroot 位置不对（usr/sbin 有：$([ -f $LFS/usr/sbin/chroot ] && echo 是 || echo 否)，usr/bin 残留：$([ -e $LFS/usr/bin/chroot ] && echo 是 || echo 否)）"; rc=1
fi
if [ -f "$LFS/usr/share/man/man8/chroot.8" ] && [ ! -e "$LFS/usr/share/man/man1/chroot.1" ]; then
  echo "   OK   \$LFS/usr/share/man/man8/chroot.8（man1/chroot.1 已移走）"
else
  echo "   FAIL chroot 手册页未按本节要求移动到 man8"; rc=1
fi
if head -n3 $LFS/usr/share/man/man8/chroot.8 | grep -q '"8"'; then
  echo "   OK   chroot.8 的 .TH 节号已由 \"1\" 改为 \"8\"（本节 sed）"
else
  echo "   FAIL chroot.8 节号未改写"; rc=1
fi
echo
echo "3) --enable-install-program=hostname 的结果（手册要求安装 hostname）："
if [ -f "$LFS/usr/bin/hostname" ]; then
  printf '   OK   $LFS/usr/bin/hostname  %s\n' "$(file -b $LFS/usr/bin/hostname | cut -d, -f1-2)"
else
  echo "   FAIL \$LFS/usr/bin/hostname 未安装"; rc=1
fi
echo "4) --enable-no-install-program=kill,uptime 的结果（这两个不应由本包安装）："
for p in kill uptime; do
  if [ -e "$LFS/usr/bin/$p" ]; then echo "   FAIL \$LFS/usr/bin/$p 不该存在"; rc=1
  else echo "   OK   \$LFS/usr/bin/$p 未安装，符合预期"; fi
done
echo
echo "5) 库与目录（手册 §8.61.2：libstdbuf.so 在 /usr/libexec/coreutils）："
if [ -f "$LFS/usr/libexec/coreutils/libstdbuf.so" ]; then
  printf '   OK   $LFS/usr/libexec/coreutils/libstdbuf.so  %s\n' "$(file -b $LFS/usr/libexec/coreutils/libstdbuf.so | cut -d, -f1-2)"
else
  echo "   FAIL \$LFS/usr/libexec/coreutils/libstdbuf.so 缺失"; rc=1
fi
echo "   \$LFS/usr/libexec/coreutils 内容：$(ls $LFS/usr/libexec/coreutils 2>/dev/null | tr '\n' ' ')"
echo
echo "6) 手册页与 info（抽样）："
for f in usr/share/man/man1/ls.1 usr/share/man/man1/cp.1 usr/share/man/man1/hostname.1 \
         usr/share/info/coreutils.info; do
  if [ -e "$LFS/$f" ]; then printf '   OK   $LFS/%s\n' "$f"
  else printf '   INFO $LFS/%s 未安装\n' "$f"; fi
done
echo "   \$LFS/usr/share/man/man1 下 man 页数：$(ls $LFS/usr/share/man/man1 | wc -l)"
[ $rc -eq 0 ] || { echo "错误：Coreutils 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
file $LFS/usr/bin/ls
readelf -h $LFS/usr/bin/ls | grep -E 'Class|Machine|Type' | sed 's/^/  /'
echo "动态依赖（应只链接 §5.5 的 libc）："
$LFS_TGT-readelf -d $LFS/usr/bin/ls | grep -E 'NEEDED' | sed 's/^/  /'
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/ls | grep 'interpreter' | sed 's/^/  /'
echo "chroot 也确认一次："
file $LFS/usr/sbin/chroot | sed 's/^/  /'
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/ls --version）"
echo "ls 二进制中的版本字符串（应为 9.10）："
strings -a $LFS/usr/bin/ls | grep -m1 -E '^(ls \()?GNU coreutils' | sed 's/^/  /' || true
strings -a $LFS/usr/bin/ls | grep -m1 -E '^9\.10$' | sed 's/^/  版本: /' || true
echo "宿主上不应出现任何“可执行文件格式错误”以外的运行结果，故不运行；改用 ELF 头判定。"
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
echo "===== §6.5 完成，结束时间：$(date -Is) ====="
