#!/usr/bin/env bash
# LFS 13.0-systemd §7.13.1 Cleaning（清理临时系统）
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §7.13.1 的命令序列（全部三条）：
#   rm -rf /usr/share/{info,man,doc}/*
#   find /usr/{lib,libexec} -name \*.la -delete
#   rm -rf /tools
#
# §7.13.2 Backup 与 §7.13.3 Restore 需要在 chroot 之外执行，由宿主机侧
# scripts/pkg/run-7.13.sh 负责，本脚本不涉及。
#
# 本脚本在执行三条清理命令之前，先对第 5/6/7 章的全部产物做一次汇总核对
# （阶段汇总任务要求：确认临时系统目录与工具链状态一致），清理之后再复核一次
# —— 尤其是 rm -rf /tools 之后编译器必须仍然可用，这正是手册在此时才允许删除
# /tools 的前提（§6.18 GCC Pass 2 之后交叉工具链已完成使命）。
set -euo pipefail

echo "===== LFS 13.0-systemd §7.13 Cleaning up and Saving the Temporary System ====="
echo "开始时间：$(date -Is)"
echo "手册简介：First, remove the currently installed documentation files to prevent"
echo "  them from ending up in the final system, and to save about 35 MB. Second, on a"
echo "  modern Linux system, the libtool .la files are only useful for libltdl. ... The"
echo "  current system size is now about 3 GB, however the /tools directory is no longer"
echo "  needed. It uses about 1 GB of disk space. Delete it now."
echo

echo "----- 环境（手册 §7.4 进入 chroot 后的环境） -----"
echo "id        : $(id)"
echo "whoami    : $(whoami)"
echo "PATH      : $PATH"
echo "HOME      : $HOME"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
  *) echo "OK        : /tools/bin 不在 PATH（交叉工具链已停用）" ;;
esac
echo

rc=0

# ==========================================================================
echo "################ 清理前核对（一）：第 5–7 章各节产物 ################"
echo "阶段汇总要求：确认 chapter-05 / chapter-06 / chapter-07 共 28 个 package"
echo "  子任务的产物在 \$LFS 中全部就位、彼此一致，然后才做 §7.13 的收尾清理。"
echo

echo "----- 第 5 章（交叉工具链，安装到 /usr 与 /tools） -----"
if [ -d /tools ]; then
  echo "§5.2 Binutils-2.46.0 Pass 1 → \$LFS/tools（交叉 binutils）"
  for p in /tools/bin/x86_64-lfs-linux-gnu-ld /tools/bin/x86_64-lfs-linux-gnu-as \
           /tools/bin/x86_64-lfs-linux-gnu-ar /tools/bin/x86_64-lfs-linux-gnu-ranlib; do
    if [ -x "$p" ]; then printf '  OK   %s\n' "$p"; else printf '  FAIL %s 缺失\n' "$p"; rc=1; fi
  done
  echo "§5.3 GCC-15.2.0 Pass 1 → \$LFS/tools（交叉 gcc）"
  for p in /tools/bin/x86_64-lfs-linux-gnu-gcc /tools/bin/x86_64-lfs-linux-gnu-g++; do
    if [ -x "$p" ]; then printf '  OK   %s\n' "$p"; else printf '  FAIL %s 缺失\n' "$p"; rc=1; fi
  done
else
  echo "  INFO /tools 不存在：先前的 §7.13.1 Cleaning 已完成；交叉工具检查不再适用"
fi
echo "§5.4 Linux-6.18.10 API Headers → /usr/include"
for h in /usr/include/linux/version.h /usr/include/asm/unistd.h /usr/include/asm-generic/int-ll64.h; do
  if [ -f "$h" ]; then printf '  OK   %s\n' "$h"; else printf '  FAIL %s 缺失\n' "$h"; rc=1; fi
done
echo "  内核头文件版本：$(grep -m1 LINUX_VERSION_CODE /usr/include/linux/version.h 2>/dev/null | sed 's/^/    /')"
echo "§5.5 Glibc-2.43 → /usr/lib、/lib64 的动态链接器"
for p in /usr/lib/libc.so.6 /usr/lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2; do
  if [ -e "$p" ]; then printf '  OK   %-34s -> %s\n' "$p" "$(readlink -f "$p")"; else printf '  FAIL %s 缺失\n' "$p"; rc=1; fi
done
echo "  glibc 自报版本：$(/usr/lib/libc.so.6 2>/dev/null | head -n1)"
echo "§5.6 Libstdc++ from GCC-15.2.0 → /usr/lib"
for p in /usr/lib/libstdc++.so /usr/lib/libstdc++.so.6; do
  if [ -e "$p" ]; then printf '  OK   %-28s -> %s\n' "$p" "$(readlink "$p" 2>/dev/null || echo '(普通文件)')"; else printf '  FAIL %s 缺失\n' "$p"; rc=1; fi
done
echo

echo "----- 第 6 章（交叉编译的临时工具，17 节） -----"
# 每行：小节 期望的代表性程序（安装在 /usr/bin 或 /usr/sbin）
CH6="6.2:m4
6.3:ncurses:tic,infocmp
6.4:bash
6.5:coreutils:ls,cp,mv,rm,cat,install,chmod,dd,sort,head,tail
6.6:diffutils:diff,cmp,sdiff
6.7:file
6.8:findutils:find,xargs
6.9:gawk:gawk,awk
6.10:grep:grep,egrep,fgrep
6.11:gzip:gzip,gunzip,zcat
6.12:make
6.13:patch
6.14:sed
6.15:tar
6.16:xz:xz,unxz,xzcat
6.17:binutils-pass2:ld,as,ar,ranlib,nm,objdump,strip,readelf
6.18:gcc-pass2:gcc,cc,g++,cpp"
while IFS= read -r line; do
  sect=${line%%:*}; rest=${line#*:}; name=${rest%%:*}
  if [ "$rest" = "$name" ]; then progs=$name; else progs=$(echo "${rest#*:}" | tr ',' ' '); fi
  ok=1; paths=""
  for p in $progs; do
    if command -v "$p" >/dev/null 2>&1; then paths="$paths $(command -v "$p")"
    else ok=0; paths="$paths [缺失:$p]"; fi
  done
  if [ $ok -eq 1 ]; then printf '  OK   §%-5s %-16s%s\n' "$sect" "$name" "$paths"
  else printf '  FAIL §%-5s %-16s%s\n' "$sect" "$name" "$paths"; rc=1; fi
done <<< "$CH6"
echo "  第 6 章库产物："
for l in /usr/lib/libncursesw.so /usr/lib/libmagic.so /usr/lib/liblzma.so /usr/lib/libbfd.so /usr/lib/libopcodes.so; do
  if [ -e "$l" ]; then printf '    OK   %s\n' "$l"; else printf '    INFO %s 不存在\n' "$l"; fi
done
echo

echo "----- 第 7 章（chroot 内构建的临时工具，6 节） -----"
CH7="7.7:gettext:msgfmt,msgmerge,xgettext
7.8:bison:bison,yacc
7.9:perl:perl
7.10:python:python3
7.11:texinfo:makeinfo,texi2any,install-info
7.12:util-linux:mount,umount,blkid,findmnt,lsblk,hwclock,uuidgen"
while IFS= read -r line; do
  sect=${line%%:*}; rest=${line#*:}; name=${rest%%:*}; progs=$(echo "${rest#*:}" | tr ',' ' ')
  ok=1; paths=""
  for p in $progs; do
    if command -v "$p" >/dev/null 2>&1; then paths="$paths $(command -v "$p")"
    else ok=0; paths="$paths [缺失:$p]"; fi
  done
  if [ $ok -eq 1 ]; then printf '  OK   §%-5s %-12s%s\n' "$sect" "$name" "$paths"
  else printf '  FAIL §%-5s %-12s%s\n' "$sect" "$name" "$paths"; rc=1; fi
done <<< "$CH7"
echo "  第 7 章库/目录产物："
for l in /usr/lib/libblkid.so /usr/lib/libmount.so /usr/lib/libuuid.so \
         /usr/lib/libfdisk.so /usr/lib/libsmartcols.so /var/lib/hwclock; do
  if [ -e "$l" ]; then printf '    OK   %s\n' "$l"; else printf '    FAIL %s 缺失\n' "$l"; rc=1; fi
done
echo

echo "----- 版本自报（各节实际装进 \$LFS 的版本，与手册 13.0-systemd 清单核对） -----"
vout=/tmp/.c713-ver.out
# 注意：本脚本开了 pipefail，`cmd | head -n1` 会因 SIGPIPE 把整条管道判为失败，
# 与命令本身无关；故一律先落临时文件再取首行。
check_ver() {   # <期望版本> <命令...>
  local want=$1; shift
  if "$@" >"$vout" 2>&1; then
    local line; line=$(sed -n 1p "$vout")
    case "$line" in
      *"$want"*) printf '  OK   %-22s %s\n' "$1" "$line" ;;
      *) printf '  FAIL %-22s 版本不含 %s：%s\n' "$1" "$want" "$line"; rc=1 ;;
    esac
  else
    printf '  FAIL %-22s 无法执行\n' "$1"; sed -n '1,2p' "$vout" | sed 's/^/         /'; rc=1
  fi
}
check_ver 15.2.0  gcc --version
check_ver 15.2.0  g++ --version
check_ver 2.46    ld --version
check_ver 9.10    ls --version
check_ver 5.3     bash --version
check_ver 4.4.1   make --version
check_ver 4.9     sed --version
check_ver 3.12    grep --version
check_ver 5.3.2   gawk --version
check_ver 1.35    tar --version
check_ver 5.8.2   xz --version
check_ver 1.4.21  m4 --version
check_ver 3.8.2   bison --version
check_ver 7.2     makeinfo --version
check_ver 2.41.3  mount --version
check_ver 3.14.3  python3 --version
if perl -e 'print "perl v$^V\n"' >"$vout" 2>&1 && grep -q '5\.42\.0' "$vout"; then
  printf '  OK   %-22s %s\n' perl "$(sed -n 1p "$vout")"
else printf '  FAIL perl 版本不是 5.42.0：%s\n' "$(sed -n 1p "$vout")"; rc=1; fi
if msgfmt --version >"$vout" 2>&1; then printf '  OK   %-22s %s\n' msgfmt "$(sed -n 1p "$vout")"
else printf '  FAIL msgfmt 无法执行\n'; rc=1; fi
if tic -V >"$vout" 2>&1; then printf '  OK   %-22s %s\n' tic "$(sed -n 1p "$vout")"
else printf '  FAIL tic 无法执行\n'; rc=1; fi
echo

echo "----- 关键一致性：全部临时工具必须来自 /usr，而不是 /tools -----"
echo "手册 §7.4：Notice that /tools/bin is not in the PATH. This means that the cross"
echo "  toolchain will no longer be used. 因此 /tools 现在只剩历史包袱，可以删除。"
bad=0
for p in gcc cc g++ cpp ld as ar ranlib nm objdump strip readelf make sed grep gawk \
         bash tar xz m4 bison perl python3 makeinfo mount find diff file gzip patch; do
  path=$(command -v "$p" 2>/dev/null || true)
  case "$path" in
    /usr/bin/*|/usr/sbin/*) ;;
    "") printf '  FAIL %s 不可用\n' "$p"; rc=1 ;;
    *)  printf '  FAIL %-8s 来自 %s（不在 /usr 下）\n' "$p" "$path"; bad=1; rc=1 ;;
  esac
done
[ $bad -eq 0 ] && echo "  OK   上述 28 个命令全部解析到 /usr/bin 或 /usr/sbin"
echo

echo "----- 关键一致性：工具链自检（手册 §6.18 GCC Pass 2 的 sanity check 原样重跑） -----"
echo "手册命令：echo 'int main(){}' > dummy.c && cc dummy.c -v -Wl,--verbose &> dummy.log"
echo "          readelf -l a.out | grep ': /lib'"
work=$(mktemp -d /tmp/c713-sanity-XXXXXX); cd "$work"
echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose > dummy.log 2>&1 || { echo "  FAIL cc 无法编译链接 dummy.c"; tail -n20 dummy.log | sed 's/^/    /'; rc=1; }
if [ -f a.out ]; then
  interp=$(readelf -l a.out | grep ': /lib' || true)
  echo "  程序解释器：$(echo "$interp" | sed 's/^ *//')"
  case "$interp" in
    *"/lib64/ld-linux-x86-64.so.2"*) echo "  OK   与手册期望一致：[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]" ;;
    *) echo "  FAIL 程序解释器不是手册期望的 /lib64/ld-linux-x86-64.so.2"; rc=1 ;;
  esac
  echo "  手册命令：grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log"
  crt=$(grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log || true)
  if [ -n "$crt" ]; then echo "$crt" | sed 's/^/    /'
    echo "  OK   启动文件取自 /usr/lib（不是 /tools）"
  else echo "  FAIL 未从 /usr/lib 找到 Scrt1.o/crti.o/crtn.o"; rc=1; fi
  echo "  手册命令：grep -B4 '^ /usr/include' dummy.log"
  grep -B4 '^ /usr/include' dummy.log | sed 's/^/    /' || true
  echo "  手册命令：grep 'SEARCH.*/usr/lib' dummy.log"
  grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\n|g' | sed 's/^/    /' || true
  echo "  手册命令：grep '/lib.*/libc.so.6 ' dummy.log"
  libc=$(grep "/lib.*/libc.so.6 " dummy.log || true)
  if [ -n "$libc" ]; then echo "$libc" | sed 's/^/    /'; echo "  OK   libc.so.6 取自 /usr/lib"
  else echo "  FAIL 未找到 libc.so.6 的链接记录"; rc=1; fi
  echo "  手册命令：grep found dummy.log"
  found=$(grep found dummy.log || true)
  echo "$found" | sed 's/^/    /'
  case "$found" in
    *"/usr/lib/ld-linux-x86-64.so.2"*) echo "  OK   found ld-linux-x86-64.so.2 at /usr/lib（与手册一致）" ;;
    *) echo "  FAIL 动态链接器不是在 /usr/lib 找到的"; rc=1 ;;
  esac
  echo "  dummy.log 中是否仍出现 /tools 路径（应为 0 处）："
  n=$(grep -c '/tools' dummy.log || true)
  if [ "$n" -eq 0 ]; then echo "    OK   0 处 —— 编译链接完全不依赖 /tools"
  else echo "    FAIL $n 处引用 /tools："; grep -m5 '/tools' dummy.log | sed 's/^/      /'; rc=1; fi
else
  echo "  FAIL 没有生成 a.out"; rc=1
fi
echo "  C++ 链路（§5.6 libstdc++ + §6.18 g++）："
cat > hello.cc <<'CXX'
#include <iostream>
#include <string>
int main(){ std::string s="LFS"; std::cout << "c++ ok " << s << std::endl; return 0; }
CXX
if g++ -o hello hello.cc >cxx.log 2>&1 && ./hello >cxx.out 2>&1; then
  echo "    OK   g++ 编译并运行成功：$(cat cxx.out)"
  echo "    动态依赖：$(readelf -d hello | grep NEEDED | sed 's/^ *//' | tr '\n' ' ')"
else
  echo "    FAIL g++ 编译或运行失败"; tail -n15 cxx.log | sed 's/^/      /'; rc=1
fi
cd /; rm -rf "$work"
echo

echo "----- 清理前的目录状态（{} 展开后的实际大小，供清理后对照） -----"
echo "  根文件系统占用："
df -h / | tail -n1 | sed 's/^/    /'
before_avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
for d in /usr/share/info /usr/share/man /usr/share/doc /tools; do
  if [ -d "$d" ]; then printf '  %-18s %-7s %s 个文件\n' "$d" "$(du -sh "$d" | cut -f1)" "$(find "$d" | wc -l)"
  else printf '  %-18s (不存在)\n' "$d"; fi
done
la_before=$(find /usr/lib /usr/libexec -name '*.la' 2>/dev/null | wc -l)
echo "  /usr/{lib,libexec} 下 .la 文件：$la_before 个"
find /usr/lib /usr/libexec -name '*.la' 2>/dev/null | sed 's/^/    /'
echo "  /tools 顶层："
if [ -d /tools ]; then ls -la /tools | sed 's/^/    /'; else echo "    (不存在，已清理)"; fi
echo

[ $rc -eq 0 ] || { echo "错误：清理前的核对未全部通过，按任务要求不执行 §7.13 的删除操作" >&2; exit 1; }
echo "################ 清理前核对通过：第 5–7 章产物齐全、工具链自洽 ################"
echo

# ==========================================================================
echo "================= 7.13.1. Cleaning ================="
echo "----- 第 1 条命令 -----"
echo "手册原文：First, remove the currently installed documentation files to prevent them"
echo "  from ending up in the final system, and to save about 35 MB:"
echo "手册命令：rm -rf /usr/share/{info,man,doc}/*"
rm -rf /usr/share/{info,man,doc}/*
for d in /usr/share/info /usr/share/man /usr/share/doc; do
  n=$(find "$d" -mindepth 1 | wc -l)
  # 注意：man 下的 man1..man8 由 §7.5 建立，rm 的是 /usr/share/man/* 即这些子目录本身，
  # 手册预期它们此时被一并删除；第 8 章各包 make install 会按需重建。
  printf '  %-18s 剩余 %s 项，%s\n' "$d" "$n" "$(du -sh "$d" | cut -f1)"
done
echo "  说明：手册的 rm -rf /usr/share/{info,man,doc}/* 连同 §7.5 建立的 man1..man8"
echo "    子目录一起删除，这是手册预期的结果；第 8 章各包安装时会自行重建所需子目录。"
echo

echo "----- 第 2 条命令 -----"
echo "手册原文：Second, on a modern Linux system, the libtool .la files are only useful for"
echo "  libltdl. No libraries in LFS are loaded by libltdl, and it's known that some .la"
echo "  files can cause BLFS package failures. Remove those files now:"
echo "手册命令：find /usr/{lib,libexec} -name \\*.la -delete"
find /usr/{lib,libexec} -name \*.la -delete
la_after=$(find /usr/lib /usr/libexec -name '*.la' 2>/dev/null | wc -l)
echo "  删除前 $la_before 个 → 删除后 $la_after 个"
if [ "$la_after" -eq 0 ]; then echo "  OK   /usr/{lib,libexec} 下已无 .la 文件"
else echo "  FAIL 仍有 .la 文件："; find /usr/lib /usr/libexec -name '*.la' | sed 's/^/    /'; rc=1; fi
echo

echo "----- 第 3 条命令 -----"
echo "手册原文：The current system size is now about 3 GB, however the /tools directory is"
echo "  no longer needed. It uses about 1 GB of disk space. Delete it now:"
echo "手册命令：rm -rf /tools"
echo "  删除前 /tools 大小：$(du -sh /tools 2>/dev/null | cut -f1)"
rm -rf /tools
if [ -e /tools ]; then echo "  FAIL /tools 仍然存在"; rc=1
else echo "  OK   /tools 已删除"; fi
echo

# ==========================================================================
echo "################ 清理后复核 ################"
echo "----- 1) 三条命令的直接结果 -----"
for d in /usr/share/info /usr/share/man /usr/share/doc; do
  n=$(find "$d" -mindepth 1 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then printf '  OK   %-18s 为空\n' "$d"
  else printf '  FAIL %-18s 仍有 %s 项\n' "$d" "$n"; rc=1; fi
done
if [ "$(find /usr/lib /usr/libexec -name '*.la' 2>/dev/null | wc -l)" -eq 0 ]; then
  echo "  OK   /usr/{lib,libexec} 下无 .la 文件"; else echo "  FAIL 仍有 .la 文件"; rc=1; fi
[ -e /tools ] && { echo "  FAIL /tools 仍在"; rc=1; } || echo "  OK   /tools 不存在"
echo "  根目录内容：$(ls / | tr '\n' ' ')"
echo

echo "----- 2) 删除 /tools 之后工具链必须仍然可用（本节最关键的验证） -----"
echo "手册允许此时删除 /tools 的前提：§6.18 GCC Pass 2 之后，/usr 下的编译器已经"
echo "  自洽（自举完成），交叉工具链不再被任何东西引用。下面重跑 §6.18 的 sanity check。"
work=$(mktemp -d /tmp/c713-post-XXXXXX); cd "$work"
echo 'int main(){}' > dummy.c
if cc dummy.c -v -Wl,--verbose > dummy.log 2>&1 && [ -f a.out ]; then
  echo "  OK   cc 在 /tools 删除后仍能编译链接"
  echo "  程序解释器：$(readelf -l a.out | grep ': /lib' | sed 's/^ *//')"
  readelf -l a.out | grep -q '/lib64/ld-linux-x86-64.so.2' \
    && echo "  OK   解释器仍为 /lib64/ld-linux-x86-64.so.2" \
    || { echo "  FAIL 解释器不正确"; rc=1; }
  n=$(grep -c '/tools' dummy.log || true)
  if [ "$n" -eq 0 ]; then echo "  OK   编译链接过程 0 处引用 /tools"
  else echo "  FAIL $n 处引用 /tools"; grep -m5 '/tools' dummy.log | sed 's/^/    /'; rc=1; fi
  if ./a.out; then echo "  OK   生成的 a.out 可以运行（退出码 0）"; else echo "  FAIL a.out 无法运行"; rc=1; fi
else
  echo "  FAIL 删除 /tools 后 cc 无法编译链接 —— 工具链未自洽"; tail -n20 dummy.log | sed 's/^/    /'; rc=1
fi
cat > hello.cc <<'CXX'
#include <iostream>
int main(){ std::cout << "c++ still ok" << std::endl; return 0; }
CXX
if g++ -o hello hello.cc >cxx.log 2>&1 && ./hello; then echo "  OK   g++ 在 /tools 删除后仍可用"
else echo "  FAIL g++ 在 /tools 删除后不可用"; tail -n15 cxx.log | sed 's/^/    /'; rc=1; fi
echo "  一段用到 §7.7–§7.12 各工具的联合冒烟："
printf 'BEGIN{print "gawk ok"}\n' > t.awk && gawk -f t.awk
echo 'my $x = "perl ok"; print "$x\n";' > t.pl && perl t.pl
echo 'print("python ok")' > t.py && python3 t.py
printf '%%{\n%%}\n%%%%\ns: ;\n' > t.y && bison -o t.tab.c t.y >/dev/null 2>&1 && echo "bison ok（生成 $(wc -l < t.tab.c) 行 C 代码）"
printf '\\input texinfo\n@setfilename t.info\n@node Top\n@top T\nhi\n@bye\n' > t.texi \
  && makeinfo --no-split -o t.info t.texi >/dev/null 2>&1 && echo "makeinfo ok（生成 $(wc -c < t.info) 字节 info）"
echo hi > t.txt && tar -cJf t.tar.xz t.txt && tar -tJf t.tar.xz && echo "tar+xz ok"
uuid=$(uuidgen) && echo "uuidgen ok: $uuid"
echo "  上述命令全部返回 0（set -e 保证：任一失败脚本立即终止）"
cd /; rm -rf "$work"
echo

echo "----- 3) 第 8 章要用到的临时工具仍然齐全（清理不应误伤任何程序/库） -----"
miss=0
for p in gcc cc g++ cpp ld as ar ranlib nm objdump strip readelf make sed grep egrep \
         gawk awk bash tar xz gzip m4 bison yacc perl python3 makeinfo texi2any \
         install-info msgfmt xgettext mount umount blkid findmnt lsblk hwclock uuidgen \
         find xargs diff cmp file patch tic infocmp ls cp mv rm cat install chmod dd sort; do
  command -v "$p" >/dev/null 2>&1 || { printf '  FAIL %s 在清理后不可用\n' "$p"; miss=1; rc=1; }
done
[ $miss -eq 0 ] && echo "  OK   清理后 $(echo gcc cc g++ cpp ld as ar ranlib nm objdump strip readelf make sed grep egrep gawk awk bash tar xz gzip m4 bison yacc perl python3 makeinfo texi2any install-info msgfmt xgettext mount umount blkid findmnt lsblk hwclock uuidgen find xargs diff cmp file patch tic infocmp ls cp mv rm cat install chmod dd sort | wc -w) 个关键程序全部仍可用"
for l in /usr/lib/libc.so.6 /usr/lib/libstdc++.so.6 /usr/lib/libncursesw.so \
         /usr/lib/libblkid.so /usr/lib/libmount.so /usr/lib/libuuid.so /usr/lib/libmagic.so; do
  if [ -e "$l" ]; then printf '  OK   %s\n' "$l"; else printf '  FAIL %s 在清理后缺失\n' "$l"; rc=1; fi
done
echo "  §7.6 建立的基础文件仍在（第 8 章依赖）："
for f in /etc/passwd /etc/group /etc/hosts /etc/mtab /home/tester /var/log/lastlog /var/lib/hwclock; do
  if [ -e "$f" ]; then printf '    OK   %s\n' "$f"; else printf '    FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "  §7.5 建立的目录骨架仍在（/usr/share/man 下的 manN 已按手册随文档一并删除）："
for d in /boot /home /mnt /opt /srv /etc/opt /etc/sysconfig /usr/lib/locale \
         /usr/local/bin /usr/local/lib /usr/local/sbin /var/cache /var/log /var/mail \
         /var/spool /var/lib/color /var/lib/misc /var/lib/locate /root /tmp /var/tmp; do
  [ -d "$d" ] || { printf '    FAIL 目录缺失：%s\n' "$d"; rc=1; }
done
echo "    OK   上述 §7.5 目录检查完毕"
echo "  §7.5.1 Warning：/usr/lib64 必须不存在"
if [ -e /usr/lib64 ]; then echo "    FAIL /usr/lib64 存在"; rc=1; else echo "    OK   /usr/lib64 不存在"; fi
echo

echo "----- 4) 空间回收 -----"
after_avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
echo "  清理前可用：${before_avail_mb} MB"
echo "  清理后可用：${after_avail_mb} MB"
echo "  回收：$(( after_avail_mb - before_avail_mb )) MB（手册预估：文档约 35 MB + /tools 约 1 GB）"
echo "  根文件系统："
df -h / | tail -n1 | sed 's/^/    /'
echo "  当前临时系统各顶层目录占用（手册称此时约 3 GB）："
du -sh /usr /etc /var /root 2>/dev/null | sed 's/^/    /'
echo "  /sources（宿主机 bind mount，不占镜像空间）：$(find /sources -maxdepth 1 -type f | wc -l) 个文件"
echo "  /sources 下不应有解包残留目录："
leftover=$(find /sources -maxdepth 1 -mindepth 1 -type d | wc -l)
if [ "$leftover" -eq 0 ]; then echo "    OK   无残留目录"
else echo "    FAIL 残留 $leftover 个："; find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/      /'; rc=1; fi
echo

echo "================= 7.13.2 / 7.13.3 说明 ================="
echo "手册 §7.13.2 Backup 的全部步骤都在 chroot 之外执行（exit → 卸载虚拟内核文件系统"
echo "  → cd \$LFS && tar -cJpf \$HOME/lfs-temp-tools-13.0-systemd.tar.xz .），"
echo "  §7.13.3 Restore 同理。本脚本运行在 chroot 内，因此这两小节由宿主机侧的"
echo "  scripts/pkg/run-7.13.sh 在本脚本返回之后接手执行。"
echo

[ $rc -eq 0 ] || { echo "错误：§7.13.1 清理后的复核未全部通过" >&2; exit 1; }
echo "===== §7.13.1 Cleaning 完成，结束时间：$(date -Is) ====="
