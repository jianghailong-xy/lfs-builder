#!/usr/bin/env bash
# LFS 13.0-systemd §7.9 Perl-5.42.0（临时工具）
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §7.9.1 的命令序列（全部；本节无补丁、无测试套件）：
#   sh Configure -des                                         \
#                -D prefix=/usr                               \
#                -D vendorprefix=/usr                         \
#                -D useshrplib                                \
#                -D privlib=/usr/lib/perl5/5.42/core_perl     \
#                -D archlib=/usr/lib/perl5/5.42/core_perl     \
#                -D sitelib=/usr/lib/perl5/5.42/site_perl     \
#                -D sitearch=/usr/lib/perl5/5.42/site_perl    \
#                -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
#                -D vendorarch=/usr/lib/perl5/5.42/vendor_perl
#   make
#   make install
set -euo pipefail

PKG=perl
VER=5.42.0
MMVER=5.42                 # 手册按 MAJOR.MINOR 组织模块目录
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §7.9 Perl-$VER（临时工具） ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.6 SBU，Required disk space 295 MB"
echo "手册简介：The Perl package contains the Practical Extraction and Report Language."
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
echo "可用空间（手册本节要求 295 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 295 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 295MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§7.8 Bison-3.8.2）产物及 chroot 基础必须可用 -----"
rc=0
echo "1) §7.8 装入 /usr 的 Bison 产物："
for f in /usr/bin/bison /usr/bin/yacc /usr/lib/liby.a; do
  if [ -e "$f" ]; then printf '   OK   %-16s %s\n' "$f" "$([ -x "$f" ] && $f --version 2>/dev/null | head -n1)"
  else printf '   FAIL %s 缺失（§7.8 未完成？）\n' "$f"; rc=1; fi
done
echo "2) §7.7 Gettext 产物（Perl 构建期不强依赖，但确认链路完好）："
for t in msgfmt msgmerge xgettext; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-9s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "3) 编译器与第 6 章工具（Perl 的 Configure 需要 sh/sed/grep/awk/cc/ld/ar/make 等）："
for t in gcc cc ld as ar ranlib make sed grep gawk m4 tar xz patch find diff file bash sh; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
gcc --version | sed -n '1s/^/   gcc: /p'
echo "4) Perl 需要的 C 库头文件与库（Configure 会探测大量 libc 特性）："
for f in /usr/include/stdio.h /usr/include/sys/types.h /usr/lib/libc.so /usr/lib/libm.so; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "5) §7.6 建立的基础文件 / §7.3 虚拟内核文件系统："
for f in /etc/passwd /etc/group /etc/hosts /etc/mtab /dev/null /dev/zero /dev/urandom /proc/self /sys; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "6) 本节安装前 perl 相关文件的状态："
for f in /usr/bin/perl /usr/lib/perl5; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在（将被 make install 覆盖/合并）\n' "$f"
  else printf '   OK   %s 尚未安装\n' "$f"; fi
done
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
echo "包自报版本：$(sed -n 's/^#define *PERL_REVISION *\([0-9]*\).*/\1/p' patchlevel.h | head -n1).$(sed -n 's/^#define *PERL_VERSION *\([0-9]*\).*/\1/p' patchlevel.h | head -n1).$(sed -n 's/^#define *PERL_SUBVERSION *\([0-9]*\).*/\1/p' patchlevel.h | head -n1)"
echo "本节无补丁：手册 §7.9 只有 sh Configure -des ...、make、make install 三条命令，"
echo "  没有任何 patch/sed 前置改动。"
echo

echo "================= 7.9.1. Installation of Perl ================="
echo "----- Configure（手册原文：Prepare Perl for compilation） -----"
echo "手册命令："
echo "  sh Configure -des                                         \\"
echo "               -D prefix=/usr                               \\"
echo "               -D vendorprefix=/usr                         \\"
echo "               -D useshrplib                                \\"
echo "               -D privlib=/usr/lib/perl5/$MMVER/core_perl     \\"
echo "               -D archlib=/usr/lib/perl5/$MMVER/core_perl     \\"
echo "               -D sitelib=/usr/lib/perl5/$MMVER/site_perl     \\"
echo "               -D sitearch=/usr/lib/perl5/$MMVER/site_perl    \\"
echo "               -D vendorlib=/usr/lib/perl5/$MMVER/vendor_perl \\"
echo "               -D vendorarch=/usr/lib/perl5/$MMVER/vendor_perl"
echo "手册对 Configure 选项的说明："
echo "  -des  This is a combination of three options: -d uses defaults for all items;"
echo "        -e ensures completion of all tasks; -s silences non-essential output."
echo "  -D vendorprefix=/usr  This ensures perl knows how to tell packages where they"
echo "        should install their Perl modules."
echo "  -D useshrplib  Build libperl needed by some Perl modules as a shared library,"
echo "        instead of a static library."
echo "  -D privlib,-D archlib,-D sitelib,...  These settings define where Perl looks"
echo "        for installed modules. The LFS editors chose to put them in a directory"
echo "        structure based on the MAJOR.MINOR version of Perl (5.42) which allows"
echo "        upgrading Perl to newer patch levels (the patch level is the last dot"
echo "        separated part in the full version string like 5.42.0) without"
echo "        reinstalling all of the modules."
time sh Configure -des                                         \
             -D prefix=/usr                               \
             -D vendorprefix=/usr                         \
             -D useshrplib                                \
             -D privlib=/usr/lib/perl5/5.42/core_perl     \
             -D archlib=/usr/lib/perl5/5.42/core_perl     \
             -D sitelib=/usr/lib/perl5/5.42/site_perl     \
             -D sitearch=/usr/lib/perl5/5.42/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.42/vendor_perl
echo
echo "Configure 结果确认（读 config.sh，手册 9 个 -D 逐条核对）："
cfg_rc=0
check_cfg() {  # $1=变量名 $2=期望值
  local got
  got=$(sed -n "s/^$1='\(.*\)'\$/\1/p" config.sh | head -n1)
  if [ "$got" = "$2" ]; then printf '   OK   %-14s = %s\n' "$1" "$got"
  else printf '   FAIL %-14s = %s（手册要求 %s）\n' "$1" "$got" "$2"; cfg_rc=1; fi
}
check_cfg prefix       /usr
check_cfg vendorprefix /usr
# 注意：config.sh 里 useshrplib 用 Perl 自己的 true/false 词汇记录（-D useshrplib
# 生效即为 'true'），不是 d_* 那套 define/undef；下面另外核验 libperl 确为 .so。
check_cfg useshrplib   true
check_cfg privlib      /usr/lib/perl5/$MMVER/core_perl
check_cfg archlib      /usr/lib/perl5/$MMVER/core_perl
check_cfg sitelib      /usr/lib/perl5/$MMVER/site_perl
check_cfg sitearch     /usr/lib/perl5/$MMVER/site_perl
check_cfg vendorlib    /usr/lib/perl5/$MMVER/vendor_perl
check_cfg vendorarch   /usr/lib/perl5/$MMVER/vendor_perl
[ $cfg_rc -eq 0 ] || { echo "错误：Configure 结果与手册 §7.9 要求不一致" >&2; exit 1; }
echo "   其它相关配置："
for v in version cc ld libperl osname archname; do
  sed -n "s/^$v='\(.*\)'\$/   config.sh: $v = \1/p" config.sh | head -n1
done
echo

echo "----- 编译（手册原文：Compile the package） -----"
echo "手册命令：make"
echo "（MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境提供）"
time make
echo

echo "================= 本节测试 ================="
echo "手册 §7.9 未规定任何测试：本节命令只有 sh Configure -des ...、make 和"
echo "  make install，没有 make test / make check。第 7 章各小节（Gettext、Bison、"
echo "  Perl、Python、Texinfo、Util-linux）均不跑测试；Perl 的完整测试套件出现在"
echo "  第 8 章 §8.44（make test）。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装（手册原文：Install the package） -----"
echo "手册命令：make install"
time make install
echo

echo "----- 安装结果检查（对照手册 §8.44.2 Contents of Perl） -----"
echo "手册 §8.44.2：Installed programs: corelist, cpan, enc2xs, encguess, h2ph, h2xs,"
echo "  instmodsh, json_pp, libnetcfg, perl, perl5.42.0 (hard link to perl), perlbug,"
echo "  perldoc, perlivp, perlthanks (hard link to perlbug), piconv, pl2pm, pod2html,"
echo "  pod2man, pod2text, pod2usage, podchecker, podselect, prove, ptar, ptardiff,"
echo "  ptargrep, shasum, splain, xsubpp, and zipdetails"
echo "  Installed libraries: Many which cannot all be listed here"
echo "  Installed directory: /usr/lib/perl5"
rc=0
echo "1) 手册列出的全部程序："
for p in corelist cpan enc2xs encguess h2ph h2xs instmodsh json_pp libnetcfg perl \
         perl$VER perlbug perldoc perlivp perlthanks piconv pl2pm pod2html pod2man \
         pod2text pod2usage podchecker prove ptar ptardiff ptargrep \
         shasum splain xsubpp zipdetails; do
  if [ -x "/usr/bin/$p" ]; then printf '   OK   /usr/bin/%-12s\n' "$p"
  else printf '   FAIL /usr/bin/%s 缺失或不可执行\n' "$p"; rc=1; fi
done
echo "   podselect（手册 §8.44.2 仍然列出，但 Perl $VER 不再提供）："
echo "     上游在 Perl 5.32 起把 Pod::Parser 移出核心发行版，podselect 随之消失；"
echo "     本包 pod/perl5320delta.pod 的原文："
grep -h 'Pod::Parser has been removed' /sources/$SRCDIR/pod/perl5320delta.pod \
  | sed 's/^/       /'
echo "     源码包中确无 podselect/Pod::Select（下面若无输出即为确认）："
find /sources/$SRCDIR -iname 'podselect*' -o -path '*Pod/Select.pm' | sed 's/^/       /'
if [ -e /usr/bin/podselect ]; then
  echo "     注意：/usr/bin/podselect 竟然存在，与上游情况不符"; rc=1
else
  echo "     OK   /usr/bin/podselect 不存在，属手册 §8.44.2 程序清单相对上游过时，"
  echo "          不是本次构建的缺陷（本节命令未跳过任何步骤）"
fi
echo "2) 手册标注的两处硬链接："
ino_perl=$(stat -c %i /usr/bin/perl); ino_perlv=$(stat -c %i /usr/bin/perl$VER)
if [ "$ino_perl" = "$ino_perlv" ]; then
  echo "   OK   perl 与 perl$VER 同 inode（$ino_perl）—— hard link to perl"
else
  echo "   FAIL perl($ino_perl) 与 perl$VER($ino_perlv) 不是硬链接"; rc=1
fi
ino_bug=$(stat -c %i /usr/bin/perlbug); ino_thx=$(stat -c %i /usr/bin/perlthanks)
if [ "$ino_bug" = "$ino_thx" ]; then
  echo "   OK   perlbug 与 perlthanks 同 inode（$ino_bug）—— hard link to perlbug"
else
  echo "   FAIL perlbug($ino_bug) 与 perlthanks($ino_thx) 不是硬链接"; rc=1
fi
echo "3) Installed directory: /usr/lib/perl5（以及手册 -D 指定的版本化子目录）："
if [ -d /usr/lib/perl5 ]; then
  echo "   OK   /usr/lib/perl5（$(find /usr/lib/perl5 -type f | wc -l) 个文件）"
  ls /usr/lib/perl5 | sed 's/^/     /'
  ls /usr/lib/perl5/$MMVER | sed 's/^/       /'
else
  echo "   FAIL /usr/lib/perl5 缺失"; rc=1
fi
for d in /usr/lib/perl5/$MMVER/core_perl /usr/lib/perl5/$MMVER/site_perl; do
  if [ -d "$d" ]; then printf '   OK   %-42s（%s 个文件）\n' "$d" "$(find $d -type f | wc -l)"
  else printf '   FAIL %s 缺失\n' "$d"; rc=1; fi
done
vdir=/usr/lib/perl5/$MMVER/vendor_perl
if [ -d "$vdir" ]; then
  printf '   OK   %-42s（%s 个文件）\n' "$vdir" "$(find $vdir -type f | wc -l)"
else
  echo "   INFO $vdir 尚未创建：make install 不会建立空的 vendorlib 目录，"
  echo "        它在第一个 vendor 模块装进来时才出现。手册对这组 -D 的说明是"
  echo "        \"These settings define where Perl looks for installed modules\"，"
  echo "        即只要求搜索路径正确——下面第 5) 项校验 @INC 确实包含该目录。"
fi
echo "   版本化目录检查（手册用 MAJOR.MINOR=$MMVER，不应出现按完整版本号 $VER 命名的目录）："
if [ -e "/usr/lib/perl5/$VER" ]; then
  echo "     FAIL 存在 /usr/lib/perl5/$VER（-D privlib/archlib 等未生效）"; rc=1
else
  echo "     OK   不存在 /usr/lib/perl5/$VER"
fi
echo "4) -D useshrplib 生效检查（libperl 应是共享库，手册：Build libperl ... as a"
echo "   shared library, instead of a static library）："
libperl=$(sed -n "s/^libperl='\(.*\)'\$/\1/p" config.sh | head -n1)
echo "   config.sh 的 libperl = $libperl"
if [ -f "/usr/lib/perl5/$MMVER/core_perl/CORE/$libperl" ]; then
  echo "   OK   /usr/lib/perl5/$MMVER/core_perl/CORE/$libperl"
  file -b "/usr/lib/perl5/$MMVER/core_perl/CORE/$libperl" | sed 's/^/        /'
  case "$libperl" in
    *.so*) echo "        OK   是 .so 共享库" ;;
    *)     echo "        FAIL libperl 不是共享库（useshrplib 未生效）"; rc=1 ;;
  esac
else
  echo "   FAIL 未找到 CORE/$libperl"; rc=1
fi
echo "   /usr/bin/perl 动态链接到 libperl："
file -b /usr/bin/perl | sed 's/^/     /'
readelf -d /usr/bin/perl | grep -E 'NEEDED|RUNPATH|RPATH' | sed 's/^/     /'
if readelf -d /usr/bin/perl | grep -q "libperl"; then
  echo "     OK   perl 可执行文件 NEEDED 中含 libperl（确认共享库构建）"
else
  echo "     FAIL perl 未链接 libperl 共享库"; rc=1
fi
echo "5) 实际运行与 @INC 检查："
perl_v=$(perl -e 'print "$^V\n"')
echo "   perl -e 'print \$^V'         : $perl_v"
echo "   perl -V:version             : $(perl -V:version)"
case "$perl_v" in *"$VER"*) echo "   OK   版本为 $VER" ;;
  *) echo "   FAIL perl 报告的版本 $perl_v 不含 $VER"; rc=1 ;; esac
echo "   @INC（应为手册 -D 指定的三组版本化目录）："
perl -e 'print "     $_\n" for @INC'
for d in /usr/lib/perl5/$MMVER/core_perl /usr/lib/perl5/$MMVER/site_perl /usr/lib/perl5/$MMVER/vendor_perl; do
  if perl -e 'exit(grep({ $_ eq $ARGV[0] } @INC) ? 0 : 1)' "$d"; then
    printf '   OK   @INC 含 %s\n' "$d"
  else
    printf '   FAIL @INC 不含 %s\n' "$d"; rc=1
  fi
done
echo "   perl -V:vendorprefix        : $(perl -V:vendorprefix)"
echo "6) 功能性冒烟测试："
out=$(perl -e 'print 20 + 22, "\n"')
if [ "$out" = "42" ]; then echo "   OK   perl -e 'print 20+22' = $out"
else echo "   FAIL perl 算术输出为 \"$out\"（期望 42）"; rc=1; fi
echo "   核心模块加载（后续 §7.10 起多个包的构建脚本依赖这些模块）："
for m in strict warnings Config Data::Dumper File::Path File::Temp Getopt::Long \
         POSIX Encode Text::Tabs IPC::Open3 ExtUtils::MakeMaker; do
  if perl -M"$m" -e1 2>/dev/null; then printf '   OK   use %s\n' "$m"
  else printf '   FAIL use %s 失败\n' "$m"; rc=1; fi
done
echo "   XS（编译型扩展）可用性 —— 依赖 DynaLoader 与共享库路径："
if perl -MList::Util=sum -e 'print sum(1..9), "\n"' | grep -qx 45; then
  echo "   OK   List::Util（XS）sum(1..9)=45"
else
  echo "   FAIL List::Util（XS 模块）不可用"; rc=1
fi
echo "   pod2man / prove / corelist 冒烟（手册 §8.44.2 列出的程序确实可运行）："
mkdir -p /tmp/.perl-smoke && cd /tmp/.perl-smoke
printf '=head1 NAME\n\nsmoke - lfs 7.9 check\n\n=cut\n' > smoke.pod
if pod2man --section=1 smoke.pod > smoke.1 && grep -q 'smoke' smoke.1; then
  echo "   OK   pod2man 生成 man 页（$(wc -c < smoke.1) 字节）"
else
  echo "   FAIL pod2man 失败"; rc=1
fi
if pod2text smoke.pod | grep -q 'lfs 7.9 check'; then
  echo "   OK   pod2text 正常"
else echo "   FAIL pod2text 失败"; rc=1; fi
printf 'use strict; use warnings;\nprint "1..1\\nok 1\\n";\n' > t.t
if prove -q t.t 2>&1 | tail -n2 | grep -qi 'Result: PASS'; then
  echo "   OK   prove 运行 TAP 测试通过"
else
  echo "   FAIL prove 未报告 PASS"; rc=1
fi
if corelist Data::Dumper | grep -q 'Data::Dumper'; then
  echo "   OK   corelist 可查询核心模块"
else echo "   FAIL corelist 失败"; rc=1; fi
cd /sources
rm -rf /tmp/.perl-smoke
[ $rc -eq 0 ] || { echo "错误：Perl 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
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
echo "===== §7.9 完成，结束时间：$(date -Is) ====="
