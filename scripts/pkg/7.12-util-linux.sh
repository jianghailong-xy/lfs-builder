#!/usr/bin/env bash
# LFS 13.0-systemd §7.12 Util-linux-2.41.3（临时工具）
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §7.12.1 的命令序列（全部；本节无补丁、无测试套件）：
#   mkdir -pv /var/lib/hwclock
#   ./configure --libdir=/usr/lib     \
#               --runstatedir=/run    \
#               --disable-chfn-chsh   \
#               --disable-login       \
#               --disable-nologin     \
#               --disable-su          \
#               --disable-setpriv     \
#               --disable-runuser     \
#               --disable-pylibmount  \
#               --disable-static      \
#               --disable-liblastlog2 \
#               --without-python      \
#               ADJTIME_PATH=/var/lib/hwclock/adjtime \
#               --docdir=/usr/share/doc/util-linux-2.41.3
#   make
#   make install
set -euo pipefail

PKG=util-linux
VER=2.41.3
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §7.12 Util-linux-$VER（临时工具） ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 192 MB"
echo "手册简介：The Util-linux package contains miscellaneous utility programs."
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
  *) echo "OK        : /tools/bin 不在 PATH（交叉工具链已停用）" ;;
esac
echo "可用空间（手册本节要求 192 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 192 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 192MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§7.11 Texinfo-7.2）产物及 chroot 基础必须可用 -----"
rc=0
echo "1) §7.11 装入 /usr 的 Texinfo 产物（确认上一任务产物完好）："
for p in makeinfo texi2any info install-info texindex; do
  if command -v "$p" >/dev/null 2>&1; then
    printf '   OK   %-13s %-22s\n' "$p" "$(command -v "$p")"
  else
    printf '   FAIL %s 不可用（§7.11 未完成？）\n' "$p"; rc=1
  fi
done
vout=/tmp/.ul-precheck.out
if makeinfo --version >"$vout" 2>&1; then
  echo "   makeinfo --version：$(sed -n 1p "$vout")"
else
  echo "   FAIL makeinfo 无法运行"; rc=1
fi
echo "2) §7.7～§7.10 产物（configure 会探测这些工具）："
for t in msgfmt xgettext bison perl python3; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-9s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   说明：本节 configure 带 --without-python 与 --disable-pylibmount，"
echo "   因此 Python 不会被使用；此处仅确认前序任务产物完好。"
echo "3) 编译器与第 6 章工具（Util-linux 的 configure 是 autoconf 脚本）："
for t in gcc cc g++ ld as ar ranlib make sed grep gawk m4 tar xz patch find diff file bash install-info; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-11s %s\n' "$t" "$(command -v $t)"
  else printf '   INFO %-11s 不可用\n' "$t"; fi
done
for t in gcc cc ld ar make sed grep gawk tar xz find bash; do
  command -v $t >/dev/null 2>&1 || { printf '   FAIL 必需工具 %s 不可用\n' "$t"; rc=1; }
done
gcc --version | sed -n '1s/^/   gcc: /p'
echo "4) C 库头文件与 ncurses（cal/irqtop/lsfd 等需要 terminfo/curses 支持）："
for h in /usr/include/stdio.h /usr/include/sys/mount.h /usr/include/linux/fs.h \
         /usr/include/curses.h /usr/include/term.h; do
  if [ -f "$h" ]; then printf '   OK   %s\n' "$h"; else printf '   INFO %s 缺失\n' "$h"; fi
done
for h in /usr/include/stdio.h /usr/include/sys/mount.h /usr/include/linux/fs.h; do
  [ -f "$h" ] || { printf '   FAIL 必需头文件 %s 缺失\n' "$h"; rc=1; }
done
for l in /usr/lib/libc.so /usr/lib/libncursesw.so; do
  if [ -e "$l" ]; then printf '   OK   %s\n' "$l"; else printf '   INFO %s 缺失\n' "$l"; fi
done
echo "   zlib 状态（决定 cramfs 工具能否构建；LFS 的 Zlib 在第 8 章 §8.5 才安装）："
if [ -f /usr/include/zlib.h ]; then echo "   INFO /usr/include/zlib.h 存在 → fsck.cramfs/mkfs.cramfs 会被构建"
else echo "   INFO /usr/include/zlib.h 不存在 → 手册顺序下 cramfs 工具本节不会被构建（属预期）"; fi
echo "   crypt() 状态（决定 sulogin 能否构建；LFS 的 Libxcrypt 在第 8 章 §8.28 才安装）："
if [ -f /usr/include/crypt.h ]; then echo "   INFO /usr/include/crypt.h 存在 → sulogin 会被构建"
else echo "   INFO /usr/include/crypt.h 不存在 → 手册顺序下 sulogin 本节不会被构建（属预期）"; fi
echo "5) §7.6 建立的基础文件与 §7.3 虚拟内核文件系统："
for f in /etc/passwd /etc/group /etc/hosts /etc/mtab /dev/null /dev/zero /dev/urandom /dev/pts /proc/self /sys; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "6) §7.5 建立的安装目标目录："
for d in /usr/lib /usr/bin /usr/sbin /usr/include /usr/share/man/man1 /usr/share/man/man8 /var/lib; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"; else printf '   FAIL %s 缺失\n' "$d"; rc=1; fi
done
echo "7) 本节安装前 util-linux 相关文件的状态："
for f in /usr/bin/mount /usr/bin/umount /usr/bin/dmesg /usr/sbin/blkid /usr/lib/libblkid.so /usr/lib/libuuid.so; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在（将被 make install 覆盖）\n' "$f"
  else printf '   OK   %s 尚未安装\n' "$f"; fi
done
rm -f "$vout"
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "包自报版本：$(grep -m1 -E '^PACKAGE_STRING=' configure | sed "s/^PACKAGE_STRING=//; s/'//g")"
echo "本节无补丁：手册 §7.12 只有 mkdir、./configure、make、make install 四条命令，"
echo "  没有任何 patch/sed 前置改动（sources 目录下也没有 util-linux 相关补丁文件："
echo "  $(ls /sources | grep -ci 'util-linux.*patch') 个）。"
echo

echo "================= 7.12.1. Installation of Util-linux ================="
echo "----- 手册第 1 条命令：创建 adjtime 目录 -----"
echo "手册原文：The FHS recommends using the /var/lib/hwclock directory instead of the"
echo "  usual /etc directory as the location for the adjtime file."
echo "手册命令：mkdir -pv /var/lib/hwclock"
mkdir -pv /var/lib/hwclock
ls -ld /var/lib/hwclock | sed 's/^/  /'
echo

echo "----- configure（手册原文：Prepare Util-linux for compilation） -----"
echo "手册命令（逐项含义见手册 §7.12.1 The meaning of the configure options）："
echo "  ADJTIME_PATH=/var/lib/hwclock/adjtime  按 FHS 指定硬件时钟信息文件位置；临时工具"
echo "    并非严格需要，但可避免在别处生成一个日后不会被覆盖/删除的文件。"
echo "  --libdir=/usr/lib     使 .so 符号链接直接指向同目录（/usr/lib）中的共享库文件。"
echo "  --disable-*           避免因构建依赖 LFS 之外或尚未安装的包的组件而产生警告。"
echo "  --without-python      不使用 Python，避免构建不需要的绑定。"
echo "  --runstatedir=/run    正确设置 uuidd 与 libuuid 所用套接字的位置。"
echo "  --docdir=...          文档安装目录。"
echo
echo "先确认本版本 configure 支持手册要求的各开关："
# 注意：本脚本开了 pipefail，`./configure --help | grep -q ...` 会因 grep 命中后立即
# 退出而让 configure 收到 SIGPIPE，把整条管道判为失败；故先把 --help 落到文件再检索。
helpout=/tmp/.ul-configure-help.txt
./configure --help > "$helpout" 2>&1
echo "  （configure --help 共 $(wc -l < "$helpout") 行）"
# autoconf 的 --help 对默认开启的特性印作 --disable-FOO、默认关闭的印作 --enable-FOO，
# 两种形式 configure 都接受；因此按特性名匹配，并把命中的原文打出来。
for feat in chfn-chsh login nologin su setpriv runuser pylibmount static \
            liblastlog2 python runstatedir libdir docdir; do
  # 选项名后必须紧跟空白 / = / [，避免 chfn-chsh 命中 --disable-chfn-chsh-password 之类的别的选项
  hit=$(grep -m1 -E -- "--(enable|disable|with|without)-${feat}([[:space:]=[]|$)" "$helpout" || true)
  [ -n "$hit" ] || hit=$(grep -m1 -E -- "--${feat}(=|[[:space:]])" "$helpout" || true)
  if [ -n "$hit" ]; then
    printf '  OK   %-12s configure --help 原文：%s\n' "$feat" "$(echo "$hit" | sed 's/^ *//; s/  */ /g')"
  else
    printf '  FAIL configure --help 中找不到特性 %s\n' "$feat"; rc=1
  fi
done
rm -f "$helpout"
[ $rc -eq 0 ] || { echo "错误：configure 不支持手册要求的选项" >&2; exit 1; }
echo
# 输出经 tee 复制一份到临时文件，供下方"哪些组件被 configure 跳过"的检查引用；
# 命令本身与手册 §7.12 完全一致（tee 只是透传，不改变 configure 的行为）。
CFGOUT=/tmp/.ul-configure.out
time ./configure --libdir=/usr/lib     \
            --runstatedir=/run    \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-static      \
            --disable-liblastlog2 \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.3 2>&1 | tee "$CFGOUT"
echo
echo "configure 结果确认："
grep -m1 '\$ \./configure' config.log | sed 's/^ *\$ */  实际参数：/' || true
echo "  关键配置项在生成的 Makefile / config.h 中的取值："
grep -m1 '^libdir = '        Makefile | sed 's/^/    Makefile: /' || true
grep -m1 '^runstatedir = '   Makefile | sed 's/^/    Makefile: /' || true
grep -m1 '^docdir = '        Makefile | sed 's/^/    Makefile: /' || true
grep -m1 '^prefix = '        Makefile | sed 's/^/    Makefile: /' || true
grep -m1 'define _PATH_ADJTIME' config.h | sed 's/^/    config.h: /' || true
echo "  手册要求禁用的组件（应全部为 no / 未启用）："
for v in BUILD_CHFN_CHSH BUILD_LOGIN BUILD_NOLOGIN BUILD_SU BUILD_SETPRIV \
         BUILD_RUNUSER BUILD_PYLIBMOUNT BUILD_LIBLASTLOG2; do
  printf '    %-20s %s\n' "$v" "$(grep -m1 "^${v}_TRUE = " Makefile | sed 's/.*= *//; s/^$/(空 → 已启用)/; s/^#$/# → 已禁用/')"
done
echo "  静态库（--disable-static）：$(grep -m1 '^enable_static = ' Makefile | sed 's/.*= *//')"
echo "  Python（--without-python）：$(grep -m1 '^PYTHON = ' Makefile | sed 's/.*= *//; s/^$/(未使用)/')"
echo

echo "----- 编译（手册原文：Compile the package） -----"
echo "手册命令：make"
echo "（MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境提供）"
time make
echo
echo "顶层 make 退出码 0"
echo "构建产物（安装前，在源码树内）："
for b in mount umount dmesg blkid fdisk lsblk findmnt hwclock; do
  if [ -x "./$b" ]; then printf '  OK   %-10s %s\n' "$b" "$(file -b "./$b" | cut -d, -f1-2)"
  else printf '  INFO ./%s 不存在（可能路径不同）\n' "$b"; fi
done
echo "  源码树内已构建的可执行文件数：$(find . -maxdepth 1 -type f -perm -u+x ! -name '*.sh' ! -name 'config*' ! -name 'libtool' | wc -l)"
echo "  已构建的共享库："
ls -1 .libs/*.so.* 2>/dev/null | sed 's/^/    /' || true
echo

echo "================= 本节测试 ================="
echo "手册 §7.12 未规定任何测试：该节命令只有 mkdir -pv /var/lib/hwclock、"
echo "  ./configure ...、make 和 make install，没有 make check / make test。"
echo "  手册第 7 章的临时工具一律不跑测试套件（Util-linux 的测试套件在第 8 章"
echo "  §8.82.1 才以 tester 用户运行：bash tests/run.sh --srcdir=\$PWD --builddir=\$PWD）。"
echo "结论：本节无手册规定的测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装（手册原文：Install the package） -----"
echo "手册命令：make install"
time make install
echo

echo "----- 安装结果检查（对照手册 §8.82.2 Contents of Util-linux） -----"
echo "手册 §8.82.2 Installed programs：addpart, agetty, blkdiscard, blkid, blkzone,"
echo "  blockdev, cal, cfdisk, chcpu, chmem, choom, chrt, col, colcrt, colrm, column,"
echo "  ctrlaltdel, delpart, dmesg, eject, fallocate, fdisk, fincore, findfs, findmnt,"
echo "  flock, fsck, fsck.cramfs, fsck.minix, fsfreeze, fstrim, getopt, hardlink,"
echo "  hexdump, hwclock, i386, ionice, ipcmk, ipcrm, ipcs, irqtop, isosize, kill, last,"
echo "  lastb, ldattach, linux32, linux64, logger, look, losetup, lsblk, lscpu, lsipc,"
echo "  lsirq, lsfd, lslocks, lslogins, lsmem, lsns, mcookie, mesg, mkfs, mkfs.bfs,"
echo "  mkfs.cramfs, mkfs.minix, mkswap, more, mount, mountpoint, namei, nsenter, partx,"
echo "  pivot_root, prlimit, readprofile, rename, renice, resizepart, rev, rfkill,"
echo "  rtcwake, script, scriptlive, scriptreplay, setarch, setsid, setterm, sfdisk,"
echo "  sulogin, swaplabel, swapoff, swapon, switch_root, taskset, uclampset, ul,"
echo "  umount, uname26, unshare, utmpdump, uuidd, uuidgen, uuidparse, wall, wdctl,"
echo "  whereis, wipefs, x86_64, zramctl"
echo "  Installed libraries：libblkid.so, libfdisk.so, libmount.so, libsmartcols.so, libuuid.so"
echo "  Installed directories：/usr/include/blkid, /usr/include/libfdisk,"
echo "  /usr/include/libmount, /usr/include/libsmartcols, /usr/include/uuid,"
echo "  /usr/share/doc/util-linux-2.41.3, /var/lib/hwclock"
rc=0
PROGS="addpart agetty blkdiscard blkid blkzone blockdev cal cfdisk chcpu chmem choom
chrt col colcrt colrm column ctrlaltdel delpart dmesg eject fallocate fdisk fincore
findfs findmnt flock fsck fsck.minix fsfreeze fstrim getopt hardlink hexdump hwclock
i386 ionice ipcmk ipcrm ipcs irqtop isosize kill last lastb ldattach linux32 linux64
logger look losetup lsblk lscpu lsipc lsirq lsfd lslocks lslogins lsmem lsns mcookie
mesg mkfs mkfs.bfs mkfs.minix mkswap more mount mountpoint namei nsenter partx
pivot_root prlimit readprofile rename renice resizepart rev rfkill rtcwake script
scriptlive scriptreplay setarch setsid setterm sfdisk swaplabel swapoff swapon
switch_root taskset uclampset ul umount uname26 unshare utmpdump uuidd uuidgen
uuidparse wall wdctl whereis wipefs x86_64 zramctl"
# 手册 §8.82.2 的清单描述的是第 8 章的最终构建。第 7 章按手册顺序执行时，Zlib(§8.5)
# 与 Libxcrypt(§8.28) 尚未安装，configure 会相应跳过依赖它们的三个程序；这三个单列
# 在下面按其依赖是否存在分别判定。
COND_PROGS="fsck.cramfs mkfs.cramfs sulogin"
echo "1) 程序（在 /usr/bin 或 /usr/sbin 中查找）："
missing=""
found=0
for p in $PROGS; do
  path=""
  for d in /usr/bin /usr/sbin; do [ -e "$d/$p" ] && { path="$d/$p"; break; }; done
  if [ -n "$path" ]; then found=$((found+1))
  else missing="$missing $p"; fi
done
echo "   已安装 $found / $(echo $PROGS | wc -w) 个（手册列表中依赖 zlib/crypt 的三项单列在下面）"
if [ -n "$missing" ]; then
  echo "   FAIL 以下手册列出的程序缺失：$missing"; rc=1
else
  echo "   OK   手册 §8.82.2 列出的程序（依赖 zlib/crypt 的三项除外）全部安装"
fi
echo "   逐项路径与类型（抽样，全部清单见下方 ls）："
for p in mount umount dmesg blkid findmnt lsblk hwclock fdisk sfdisk losetup mkswap \
         uuidgen getopt hexdump script setarch unshare nsenter agetty switch_root; do
  path=""
  for d in /usr/bin /usr/sbin; do [ -e "$d/$p" ] && { path="$d/$p"; break; }; done
  if [ -n "$path" ]; then printf '     OK   %-22s %s\n' "$path" "$(file -b "$path" | cut -d, -f1-2)"
  else printf '     FAIL %s 缺失\n' "$p"; rc=1; fi
done
echo "   手册指出的符号链接（i386/linux32/linux64/uname26/x86_64 → setarch，lastb → last）："
for l in i386 linux32 linux64 uname26 x86_64 lastb; do
  for d in /usr/bin /usr/sbin; do
    if [ -e "$d/$l" ]; then
      if [ -L "$d/$l" ]; then printf '     OK   %-18s -> %s\n' "$d/$l" "$(readlink "$d/$l")"
      else printf '     INFO %s 是普通文件（非符号链接）\n' "$d/$l"; fi
    fi
  done
done
echo "   依赖尚未安装的包、本节按手册顺序必然跳过的三个程序："
echo "   （手册 §8.82.2 的 Contents 描述的是第 8 章的最终 util-linux；第 7 章此处"
echo "     Zlib(§8.5) 与 Libxcrypt(§8.28) 都还没装，configure 会自行跳过对应组件，"
echo "     并在其输出中给出 WARNING —— 见本日志上方 configure 段落。）"
for p in $COND_PROGS; do
  case $p in
    fsck.cramfs|mkfs.cramfs) dep="zlib";  hdr=/usr/include/zlib.h;  sect="§8.5 Zlib" ;;
    sulogin)                 dep="crypt"; hdr=/usr/include/crypt.h; sect="§8.28 Libxcrypt" ;;
  esac
  path=""
  for d in /usr/bin /usr/sbin; do [ -e "$d/$p" ] && { path="$d/$p"; break; }; done
  if [ -n "$path" ]; then
    printf '     OK   %-32s（%s 可用，已构建）\n' "$path" "$dep"
  elif [ -f "$hdr" ]; then
    printf '     FAIL %s 缺失（%s 可用却未构建）\n' "$p" "$dep"; rc=1
  else
    printf '     INFO %s 未构建：它依赖 %s，而 %s 要到 %s 才安装（%s 此时不存在）；\n' \
           "$p" "$dep" "$dep" "$sect" "$hdr"
    printf '          第 8 章 §8.82 重建 util-linux 时会补齐。属手册顺序下的预期结果。\n'
  fi
done
echo "   configure 自己给出的全部 WARNING（本次 configure 输出原文）："
grep -E 'configure: WARNING:' "$CFGOUT" 2>/dev/null | sed 's/^/     /' || \
  echo "     （见本日志上方 configure 段落）"
echo "2) 库（--libdir=/usr/lib，--disable-static 故不应有 .a）："
for l in libblkid libfdisk libmount libsmartcols libuuid; do
  if [ -e "/usr/lib/$l.so" ]; then
    printf '   OK   %-24s -> %s\n' "/usr/lib/$l.so" "$(readlink "/usr/lib/$l.so" 2>/dev/null || echo '(普通文件)')"
    ls -1 /usr/lib/$l.so.* 2>/dev/null | sed 's/^/        /'
  else printf '   FAIL /usr/lib/%s.so 缺失\n' "$l"; rc=1; fi
  if [ -e "/usr/lib/$l.a" ]; then printf '   FAIL /usr/lib/%s.a 存在，与 --disable-static 矛盾\n' "$l"; rc=1; fi
done
echo "   手册 --libdir=/usr/lib 的意图是 .so 符号链接直接指向同目录中的共享库文件："
for l in libblkid libfdisk libmount libsmartcols libuuid; do
  t=$(readlink /usr/lib/$l.so 2>/dev/null || true)
  case "$t" in
    */*) printf '     FAIL %s.so 指向 %s（含路径，不是同目录）\n' "$l" "$t"; rc=1 ;;
    "")  printf '     INFO %s.so 不是符号链接\n' "$l" ;;
    *)   printf '     OK   %s.so -> %s（同目录）\n' "$l" "$t" ;;
  esac
done
echo "3) 目录："
for d in /usr/include/blkid /usr/include/libfdisk /usr/include/libmount \
         /usr/include/libsmartcols /usr/include/uuid \
         /usr/share/doc/util-linux-$VER /var/lib/hwclock; do
  if [ -d "$d" ]; then echo "   OK   $d（$(find "$d" -type f | wc -l) 个文件）"
  else echo "   FAIL $d 缺失"; rc=1; fi
done
echo "   头文件："
ls -1 /usr/include/blkid /usr/include/libfdisk /usr/include/libmount \
      /usr/include/libsmartcols /usr/include/uuid 2>/dev/null | sed 's/^/     /'
echo "4) 手册要求禁用的程序确认未被安装（--disable-chfn-chsh/login/nologin/su/setpriv/runuser）："
for p in chfn chsh login nologin su setpriv runuser; do
  if [ -e "/usr/bin/$p" ] || [ -e "/usr/sbin/$p" ]; then
    echo "   FAIL $p 被安装了，与手册的 --disable-* 矛盾"; rc=1
  else
    printf '   OK   %s 未安装（符合手册）\n' "$p"
  fi
done
echo "5) ADJTIME_PATH 生效确认（手册：按 FHS 指向 /var/lib/hwclock/adjtime）："
adj=$(hwclock --help 2>&1 | grep -o '/[[:alnum:]/._-]*adjtime' | head -n1 || true)
if [ -z "$adj" ]; then
  adj=$(strings /usr/sbin/hwclock 2>/dev/null | grep -m1 'adjtime$' || true)
fi
if [ "$adj" = /var/lib/hwclock/adjtime ]; then
  echo "   OK   hwclock 使用 $adj"
elif [ -n "$adj" ]; then
  echo "   FAIL hwclock 使用 $adj，不是 /var/lib/hwclock/adjtime"; rc=1
else
  echo "   INFO 无法从二进制中读出 adjtime 路径；config.h 中的取值为："
  echo "        $(grep -m1 'define _PATH_ADJTIME' /sources/$SRCDIR/config.h 2>/dev/null || echo '(源码树已不可读)')"
fi
echo "6) 运行冒烟测试："
vout=/tmp/.ul-smoke.out
# 注意：本脚本开了 pipefail，`cmd | head -n1` 会让 cmd 收到 SIGPIPE 而把整条管道
# 判为失败，与命令本身无关；因此一律先写临时文件再取首行。
for c in "mount --version" "umount --version" "dmesg --version" "blkid --version" \
         "findmnt --version" "lsblk --version" "fdisk --version" "sfdisk --version" \
         "losetup --version" "mkswap --version" "hwclock --version" "uuidgen --version" \
         "getopt --version" "hexdump --version" "column --version" "flock --version" \
         "setarch --version" "unshare --version" "lscpu --version" "wipefs --version"; do
  if $c >"$vout" 2>&1; then
    printf '   OK   %-22s %s\n' "$c" "$(sed -n 1p "$vout")"
  else
    echo "   FAIL $c 执行失败"; sed -n '1,3p' "$vout" | sed 's/^/        /'; rc=1
  fi
done
mount --version >"$vout" 2>&1 || true
ver_line=$(sed -n 1p "$vout")
case "$ver_line" in *"$VER"*) echo "   OK   mount 报告的版本含 $VER" ;;
  *) echo "   FAIL mount 报告的版本不含 $VER：$ver_line"; rc=1 ;; esac
echo "   实际功能验证："
if uuidgen >"$vout" 2>&1 && grep -qE '^[0-9a-f-]{36}$' "$vout"; then
  echo "     OK   uuidgen 生成 UUID：$(cat "$vout")（libuuid 可用）"
else
  echo "     FAIL uuidgen 未生成合法 UUID"; sed -n 1p "$vout" | sed 's/^/        /'; rc=1
fi
if findmnt -n / >"$vout" 2>&1 && [ -s "$vout" ]; then
  echo "     OK   findmnt 读出根挂载（libmount 可用）：$(sed -n 1p "$vout")"
else
  echo "     FAIL findmnt 无法读出根挂载"; rc=1
fi
if lsblk --version >/dev/null 2>&1; then
  lsblk -o NAME,SIZE,TYPE >"$vout" 2>&1 || true
  if [ -s "$vout" ]; then
    echo "     OK   lsblk 输出块设备（libblkid/libsmartcols 可用），前 3 行："
    sed -n '1,3p' "$vout" | sed 's/^/       /'
  else
    echo "     INFO lsblk 无输出（chroot 内 /sys 视图受限，不影响本节结论）"
  fi
fi
echo "     hexdump 处理数据："
if printf 'LFS' | hexdump -C >"$vout" 2>&1 && grep -q '4c 46 53' "$vout"; then
  echo "       OK   $(sed -n 1p "$vout")"
else
  echo "       FAIL hexdump 输出不符预期"; sed -n '1,3p' "$vout" | sed 's/^/          /'; rc=1
fi
echo "     column 格式化（第 8 章多个包的构建脚本会用到）："
if printf 'a b c\nd e f\n' | column -t >"$vout" 2>&1 && [ -s "$vout" ]; then
  sed 's/^/       /' "$vout"
else
  echo "       FAIL column 失败"; rc=1
fi
echo "     getopt 解析（第 8 章 shell 脚本会用到）："
if getopt -o ab: -- -a -b val >"$vout" 2>&1; then
  echo "       OK   $(cat "$vout")"
else
  echo "       FAIL getopt 失败"; sed -n 1p "$vout" | sed 's/^/          /'; rc=1
fi
echo "     mkswap/fdisk 对一个临时文件操作（不触碰任何真实设备）："
work=$(mktemp -d /tmp/util-linux-smoke-XXXXXX)
if dd if=/dev/zero of="$work/swap.img" bs=1M count=16 status=none && \
   mkswap "$work/swap.img" >"$vout" 2>&1; then
  sed -n '1,3p' "$vout" | sed 's/^/       OK   /'
else
  echo "       FAIL mkswap 失败"; sed -n '1,5p' "$vout" | sed 's/^/          /'; rc=1
fi
if blkid "$work/swap.img" >"$vout" 2>&1 && grep -q 'TYPE="swap"' "$vout"; then
  echo "       OK   blkid 识别出 swap 签名：$(cat "$vout")"
else
  echo "       INFO blkid 未识别（低权限/缓存原因，不影响本节结论）"
fi
if fdisk -l "$work/swap.img" >"$vout" 2>&1; then
  echo "       OK   fdisk -l 可读该镜像：$(sed -n 1p "$vout")"
else
  echo "       INFO fdisk -l 对无分区表镜像报错属正常：$(sed -n 1p "$vout")"
fi
if wipefs "$work/swap.img" >"$vout" 2>&1; then
  echo "       OK   wipefs 列出签名：$(sed -n '1,2p' "$vout" | tr '\n' ' ')"
else
  echo "       INFO wipefs 无输出"
fi
rm -rf "$work" "$vout"
echo "7) 安装清单概览："
echo "   /usr/bin 中的 util-linux 程序数：$(for p in $PROGS; do [ -e /usr/bin/$p ] && echo x; done | wc -l)"
echo "   /usr/sbin 中的 util-linux 程序数：$(for p in $PROGS; do [ -e /usr/sbin/$p ] && echo x; done | wc -l)"
echo "   /usr/lib 中新增的 util-linux 共享库："
ls -1 /usr/lib/lib{blkid,fdisk,mount,smartcols,uuid}.so* 2>/dev/null | sed 's/^/     /'
echo "   /usr/share/doc/util-linux-$VER 文件数：$(find /usr/share/doc/util-linux-$VER -type f 2>/dev/null | wc -l)"
echo "   抽样确认 man 页已安装："
for m in /usr/share/man/man8/mount.8 /usr/share/man/man8/fdisk.8 /usr/share/man/man1/dmesg.1 \
         /usr/share/man/man1/getopt.1 /usr/share/man/man3/uuid.3 /usr/share/man/man5/fstab.5; do
  if [ -e "$m" ]; then printf '     OK   %s\n' "$m"; else printf '     INFO %s 未安装\n' "$m"; fi
done
[ $rc -eq 0 ] || { echo "错误：Util-linux 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
rm -f "$CFGOUT"          # 本脚本自用的 configure 输出副本，不留在 chroot 的 /tmp 里
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
echo "===== §7.12 完成，结束时间：$(date -Is) ====="
