#!/usr/bin/env bash
# LFS 13.0-systemd §8.5 Glibc-2.43
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.5.1 Installation of Glibc 的命令序列（全部）：
#   patch -Np1 -i ../glibc-fhs-1.patch
#   mkdir -v build ; cd build
#   echo "rootsbindir=/usr/sbin" > configparms
#   ../configure --prefix=/usr --disable-werror --disable-nscd \
#                libc_cv_slibdir=/usr/lib --enable-stack-protector=strong --enable-kernel=5.4
#   make
#   make check                     （手册 Important：本节测试套件为 critical，任何情况下不得跳过）
#   touch /etc/ld.so.conf
#   sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
#   make install
#   sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
#   localedef ...（34 条，手册“minimum set of locales”）
# 手册 §8.5.2 Configuring Glibc：
#   §8.5.2.1 cat > /etc/nsswitch.conf << "EOF" ...
#   §8.5.2.2 tar -xf ../../tzdata2025c.tar.gz ; zic 循环 ; cp zone.tab ... ; zic -p America/New_York
#            tzselect（交互式，仅用于确定本地时区）; ln -sfv /usr/share/zoneinfo/<xxx> /etc/localtime
#   §8.5.2.3 cat > /etc/ld.so.conf << "EOF" ... ; cat >> ... include ... ; mkdir -pv /etc/ld.so.conf.d
#
# 手册中【不适用于本次全新构建】的命令（属于“在运行中的 LFS 系统上升级 Glibc”的
# Important 方框，明确以 "If upgrading Glibc to a new minor version ... on a running
# LFS system" 为前提）：rm -f /usr/sbin/nscd、systemctl disable --now nscd、
# make DESTDIR=$PWD/dest install + install -vm755 dest/usr/lib/*.so.* /usr/lib、
# 以及重启后搬迁 GCC 头文件的 DIR=$(dirname $(gcc -print-libgcc-file-name)) 那段。
# 本节是第 8 章首次安装 Glibc（此前只有 §5.5 的临时 Glibc），不是升级，故不执行。
# make localedata/install-locales 是手册给出的“Alternatively”方案（安装 SUPPORTED
# 中的全部 locale），与上面 34 条 localedef 二选一，本脚本按手册正文的 minimum set 执行。
set -euo pipefail

PKG=glibc
VER=2.43
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
PATCHFILE=glibc-fhs-1.patch
TZTARBALL=tzdata2025c.tar.gz
# 手册 §8.5.2.2 用 tzselect 交互确定本地时区，chroot 内无法交互；本项目取宿主机时区
# Asia/Shanghai（宿主 /etc/localtime -> /usr/share/zoneinfo/Asia/Shanghai），
# 对应手册命令 ln -sfv /usr/share/zoneinfo/<xxx> /etc/localtime 中的 <xxx>。
LOCALTIME_ZONE=Asia/Shanghai

echo "===== LFS 13.0-systemd §8.5 Glibc-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Glibc package contains the main C library. This library provides the"
echo "  basic routines for allocating memory, searching directories, opening and closing"
echo "  files, reading and writing files, string handling, pattern matching, arithmetic,"
echo "  and so on."
echo "手册数据：Approximate build time 12 SBU，Required disk space 3.5 GB"
echo "手册存档：/workspace/docs/book/chapter08-glibc.html（宿主机 \$LFS_ROOT/docs/book/）"
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
echo "uname -r  : $(uname -r)（手册 --enable-kernel=5.4 要求内核 ≥ 5.4）"
echo "nproc     : $(nproc)"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
  *) echo "OK        : /tools/bin 不在 PATH" ;;
esac
echo "可用空间（手册本节要求 3.5 GB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 3584 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 3.5GB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.4 Iana-Etc-20260202）产物必须可用 -----"
rc=0
echo "1) §8.4 的安装结果（手册 §8.4.2 Installed files：/etc/protocols 和 /etc/services）："
for f in /etc/services /etc/protocols; do
  if [ -s "$f" ]; then printf '   OK   %-16s %s 字节，%s 行\n' "$f" "$(stat -c %s "$f")" "$(wc -l < "$f")"
  else printf '   FAIL %s 缺失或为空（§8.4 未完成？）\n' "$f"; rc=1; fi
done
echo "   （本节 §8.5.2.1 的 nsswitch.conf 里 protocols/services 走 files，正依赖这两个文件）"
echo "2) §8.3 Man-pages 的安装结果（再上一节，抽查）："
if [ -s /usr/share/man/man7/man-pages.7 ]; then echo "   OK   /usr/share/man/man7/man-pages.7 存在"
else echo "   FAIL /usr/share/man/man7/man-pages.7 缺失"; rc=1; fi
echo "3) §7.13.1 Cleaning 的结果（临时工具已并入 /usr，/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在（§7.13.1 未完成？）"; rc=1
else echo "   OK   /tools 已不存在"; fi
echo "4) 本节构建直接依赖的工具链与工具："
for t in gcc g++ cpp ld as ar make bash sed grep awk perl python3 patch tar xz gzip \
         find install msgfmt bison makeinfo diff m4 gawk; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc     ：$(gcc --version | sed -n 1p)"
echo "   ld      ：$(ld --version | sed -n 1p)"
echo "   make    ：$(make --version | sed -n 1p)"
echo "   bash    ：$(bash --version | sed -n 1p)"
echo "   perl    ：$(perl -v | sed -n 2p | tr -s ' ')"
echo "   python3 ：$(python3 --version)"
echo "   bison   ：$(bison --version | sed -n 1p)（Glibc 构建需要 bison）"
echo "   sed     ：$(sed --version | sed -n 1p)"
echo "5) 当前（§5.5 安装的临时）Glibc 版本，本节将就地覆盖它："
if [ -x /usr/bin/ldd ]; then /usr/bin/ldd --version | sed -n 1p | sed 's/^/   /'
else echo "   INFO /usr/bin/ldd 不存在"; fi
for so in /usr/lib/libc.so.6 /usr/lib64/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2; do
  [ -e "$so" ] && printf '   INFO 现有 %s -> %s\n' "$so" "$(readlink -f "$so")"
done
echo "6) 内核 API 头文件（§5.4 安装，Glibc configure 会检查其版本 ≥ 5.4）："
if [ -f /usr/include/linux/version.h ]; then
  grep -E "LINUX_VERSION_(CODE|MAJOR|PATCHLEVEL)" /usr/include/linux/version.h | sed 's/^/   /' || true
else echo "   FAIL /usr/include/linux/version.h 缺失"; rc=1; fi
echo "7) 源码与补丁（/sources 是宿主机 bind mount）："
for f in "/sources/$TARBALL" "/sources/$PATCHFILE" "/sources/$TZTARBALL"; do
  if [ -f "$f" ]; then printf '   OK   %-38s %s 字节\n' "$f" "$(stat -c %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "8) §7.3 虚拟内核文件系统（Glibc 测试套件大量依赖 /proc、/dev/pts、/dev/shm）："
for f in /dev/null /dev/zero /dev/pts/ptmx /dev/shm /proc/self /sys /etc/passwd /etc/group; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
mountpoint -q /dev/shm && echo "   OK   /dev/shm 已挂载：$(findmnt -no FSTYPE,OPTIONS /dev/shm)" \
                       || echo "   INFO /dev/shm 不是独立挂载点"
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1 / §3.2） -----"
for f in "$TARBALL" "$PATCHFILE" "$TZTARBALL"; do
  grep -E " $f\$" md5sums
done
for f in "$TARBALL" "$PATCHFILE" "$TZTARBALL"; do
  grep -E " $f\$" md5sums | md5sum -c -
done
echo

echo "----- 解包（手册 iii. General Compilation Instructions：第 8 章以 root 解包） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "版本确认：$(cat version.h 2>/dev/null | grep VERSION || sed -n '1,3p' version.h 2>/dev/null || true)"
grep -m1 "VERSION" version.h 2>/dev/null | sed 's/^/  /' || true
echo "顶层内容："
ls | sed -n '1,40p' | sed 's/^/  /' 
echo

echo "================= 8.5.1. Installation of Glibc ================="
echo "手册原文：Some of the Glibc programs use the non-FHS compliant /var/db directory"
echo "  to store their runtime data. Apply the following patch to make such programs"
echo "  store their runtime data in the FHS-compliant locations:"
echo "手册命令：patch -Np1 -i ../glibc-fhs-1.patch"
echo "补丁内容概览："
sed -n '1,12p' "/sources/$PATCHFILE" | sed 's/^/  /'
echo "  ...（共 $(wc -l < "/sources/$PATCHFILE") 行，影响文件：$(grep -c '^--- ' "/sources/$PATCHFILE") 个）"
patch -Np1 -i "../$PATCHFILE"
echo "补丁后 /var/db 引用检查（应指向 FHS 位置 /var/lib/nss_db 等）："
grep -rn "var/db\|var/lib/nss_db" nss/db-Makefile Makeconfig 2>/dev/null | sed -n '1,5p' | sed 's/^/  /' || true
echo

echo "手册原文：The Glibc documentation recommends building Glibc in a dedicated build directory:"
echo "手册命令：mkdir -v build / cd build"
mkdir -v build
cd       build
echo "构建目录：$PWD"
echo

echo "手册原文：Ensure that the ldconfig and sln utilities will be installed into /usr/sbin:"
echo "手册命令：echo \"rootsbindir=/usr/sbin\" > configparms"
echo "rootsbindir=/usr/sbin" > configparms
echo "configparms 内容：$(cat configparms)"
echo

echo "----- 8.5.1 configure（手册：Prepare Glibc for compilation） -----"
echo "手册命令："
echo "  ../configure --prefix=/usr                   \\"
echo "               --disable-werror                \\"
echo "               --disable-nscd                  \\"
echo "               libc_cv_slibdir=/usr/lib        \\"
echo "               --enable-stack-protector=strong \\"
echo "               --enable-kernel=5.4"
echo "手册对选项的说明："
echo "  --disable-werror                 disables the -Werror option passed to GCC."
echo "                                   This is necessary for running the test suite."
echo "  --enable-kernel=5.4              this Glibc may be used with kernels as old as 5.4."
echo "  --enable-stack-protector=strong  adds extra code to check for buffer overflows."
echo "  --disable-nscd                   do not build the name service cache daemon."
echo "  libc_cv_slibdir=/usr/lib         sets the correct library for all systems（不使用 lib64）。"
echo
../configure --prefix=/usr                   \
             --disable-werror                \
             --disable-nscd                  \
             libc_cv_slibdir=/usr/lib        \
             --enable-stack-protector=strong \
             --enable-kernel=5.4
echo
echo "configure 结果抽查（config.make 关键变量）："
grep -E "^(prefix|slibdir|rootsbindir|libdir|bindir|sbindir|enable-werror|stack-protector|have-cc-with-libunwind|build-nscd|minimum-kernel) " config.make \
  | sed 's/^/  /' || true
echo

echo "----- 8.5.1 编译（手册命令：make） -----"
echo "编译开始：$(date -Is)"
make
echo "编译结束：$(date -Is)"
echo

echo "================= 8.5.1 测试套件（手册命令：make check） ================="
echo "手册 Important 原文：In this section, the test suite for Glibc is considered"
echo "  critical. Do not skip it under any circumstance."
echo "手册原文：Generally a few tests do not pass. The test failures listed below are"
echo "  usually safe to ignore. ... A few failures out of over 6000 tests can generally"
echo "  be ignored. This is a list of the most common issues seen for recent versions of LFS:"
echo "    * io/tst-lchmod is known to fail in the LFS chroot environment."
echo "    * Some tests, for example nss/tst-nss-files-hosts-multi and nptl/tst-thread-affinity*"
echo "      are known to fail due to a timeout (especially when the system is relatively slow"
echo "      and/or running the test suite with multiple parallel make jobs)."
echo "    * Additionally, some tests may fail with a relatively old CPU model (for example"
echo "      elf/tst-cpu-features-cpuinfo) or host kernel version (for example"
echo "      stdlib/tst-arc4random-thread)."
echo "本次并行度：MAKEFLAGS=${MAKEFLAGS:-} TESTSUITEFLAGS=${TESTSUITEFLAGS:-}"
echo "测试开始：$(date -Is)"
check_rc=0
make check || check_rc=$?
echo "测试结束：$(date -Is)"
echo "make check 退出码：$check_rc（非 0 表示存在未通过用例，下面按手册逐条甄别）"
echo

echo "----- 测试结果汇总（glibc 生成的 tests.sum） -----"
if [ -f tests.sum ]; then
  echo "tests.sum 总行数：$(wc -l < tests.sum)"
  echo "各状态计数："
  awk '{print $1}' tests.sum | sort | uniq -c | sort -rn | sed 's/^/  /'
else
  echo "警告：未找到 tests.sum"
fi
echo
echo "全部非 PASS/XFAIL/UNSUPPORTED 条目（即 FAIL / ERROR / XPASS）："
fails_file=/tmp/glibc-fails.txt
: > "$fails_file"
if [ -f tests.sum ]; then
  grep -E "^(FAIL|ERROR|XPASS):" tests.sum | sort > "$fails_file" || true
fi
if [ -s "$fails_file" ]; then sed 's/^/  /' "$fails_file"; else echo "  （无）"; fi
echo
echo "----- 手册给出的排查命令：grep \"Timed out\" \$(find -name \\*.out) -----"
out_cnt=$(find -name \*.out | wc -l)
echo "本次共产生 $out_cnt 个 .out 测试输出文件"
timeout_out=""
if [ "$out_cnt" -gt 0 ]; then
  timeout_out=$(grep -l "Timed out" $(find -name \*.out) 2>/dev/null || true)
fi
if [ -n "$timeout_out" ]; then
  echo "超时的测试输出文件："
  echo "$timeout_out" | sed 's/^/  /'
  echo "对应行："
  grep "Timed out" $(find -name \*.out) 2>/dev/null | sed 's/^/  /' || true
else
  echo "  （没有任何 .out 含 \"Timed out\"）"
fi
echo
echo "----- 按手册的“safe to ignore”清单甄别 -----"
# 手册列出的可忽略项：io/tst-lchmod（chroot 环境）、因超时失败的用例（手册举例
# nss/tst-nss-files-hosts-multi、nptl/tst-thread-affinity*）、以及受 CPU 型号或
# 宿主内核版本影响的用例（手册举例 elf/tst-cpu-features-cpuinfo、
# stdlib/tst-arc4random-thread）。
known_re='^(FAIL|ERROR|XPASS): (io/tst-lchmod|nss/tst-nss-files-hosts-multi|nptl/tst-thread-affinity[^ ]*|elf/tst-cpu-features-cpuinfo|stdlib/tst-arc4random-thread)$'
known_cnt=0; other_cnt=0
if [ -s "$fails_file" ]; then
  known_cnt=$(grep -cE "$known_re" "$fails_file" || true)
  grep -vE "$known_re" "$fails_file" > /tmp/glibc-fails-other.txt || true
  other_cnt=$(grep -c . /tmp/glibc-fails-other.txt || true)
fi
echo "手册明确点名、可安全忽略的失败：$known_cnt 条"
if [ "$known_cnt" -gt 0 ]; then grep -E "$known_re" "$fails_file" | sed 's/^/  /'; fi
echo "不在手册点名清单中的失败：$other_cnt 条"
if [ "$other_cnt" -gt 0 ]; then
  sed 's/^/  /' /tmp/glibc-fails-other.txt
  echo "  （其中因超时而失败的，按手册第二条同样可忽略；上面的 \"Timed out\" 列表是判据）"
  echo "  逐条附带其 .out 末尾内容，便于判定原因："
  while read -r line; do
    t=$(echo "$line" | sed -E 's/^(FAIL|ERROR|XPASS): //')
    out="./$t.out"
    echo "  ---- $line ----"
    if [ -f "$out" ]; then tail -n 15 "$out" | sed 's/^/      /'; else echo "      （无 $out）"; fi
  done < /tmp/glibc-fails-other.txt
fi
total_fail=$(( known_cnt + other_cnt ))
echo "失败总数：$total_fail（手册：A few failures out of over 6000 tests can generally be ignored）"
if [ "$other_cnt" -gt 20 ]; then
  echo "错误：手册清单之外的失败达 $other_cnt 条，已超出“a few failures”的范围，" >&2
  echo "      不继续执行 make install，构建目录保留以便排查。" >&2
  exit 3
fi
echo

echo "----- 安装前的两条手册命令 -----"
echo "手册原文：Though it is a harmless message, the install stage of Glibc will complain"
echo "  about the absence of /etc/ld.so.conf. Prevent this warning with:"
echo "手册命令：touch /etc/ld.so.conf"
touch /etc/ld.so.conf
ls -l /etc/ld.so.conf | sed 's/^/  /'
echo
echo "手册原文：Fix the Makefile to skip an outdated sanity check that fails with a modern"
echo "  Glibc configuration:"
echo "手册命令：sed '/test-installation/s@\$(PERL)@echo not running@' -i ../Makefile"
echo "修改前："
grep -n "test-installation" ../Makefile | sed 's/^/  /' || true
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
echo "修改后："
grep -n "test-installation" ../Makefile | sed 's/^/  /' || true
echo
echo "说明：手册此处的 Important 方框（rm -f /usr/sbin/nscd、systemctl disable --now nscd、"
echo "  make DESTDIR=\$PWD/dest install + install -vm755 dest/usr/lib/*.so.* /usr/lib、"
echo "  以及重启后搬迁 GCC 头文件的 DIR=\$(dirname \$(gcc -print-libgcc-file-name)) 那段）"
echo "  前提是 \"If upgrading Glibc to a new minor version ... on a running LFS system\"。"
echo "  本次是第 8 章首次安装最终 Glibc（此前只有 §5.5 的临时 Glibc），不是升级，故不执行。"
echo

echo "----- 8.5.1 安装（手册命令：make install） -----"
echo "安装开始：$(date -Is)"
make install
echo "安装结束：$(date -Is)"
echo

echo "手册原文：Fix a hardcoded path to the executable loader in the ldd script:"
echo "手册命令：sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd"
echo "修改前：$(grep -n 'RTLDLIST=' /usr/bin/ldd)"
sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
echo "修改后：$(grep -n 'RTLDLIST=' /usr/bin/ldd)"
echo

echo "----- 8.5.1 安装 locale（手册的 minimum set，34 条 localedef） -----"
echo "手册原文：Next, install the locales that can make the system respond in a different"
echo "  language. None of these locales are required, but if some of them are missing, the"
echo "  test suites of some packages will skip important test cases. ... The following"
echo "  instructions will install the minimum set of locales necessary for the optimal"
echo "  coverage of tests:"
# localedef 对 GB18030 / BIG5-HKSCS 这类非 ASCII 兼容字符集会打印警告并可能返回非 0，
# 而 locale 本身是正常生成的。脚本处于 set -e 下，故用 ld_run 包一层：命令逐条原样执行、
# 原样打印，退出码单独记录，最后用 locale -a 逐个确认 locale 确实生成（真缺才算失败）。
ld_fail=0
ld_run() {
  echo "  + localedef $*"
  local r=0
  localedef "$@" || r=$?
  if [ $r -ne 0 ]; then
    echo "    （退出码 $r，多为字符集警告；该 locale 是否真的生成由下面的 locale -a 校验判定）"
    ld_fail=$((ld_fail+1))
  fi
}
ld_run -i C -f UTF-8 C.UTF-8
ld_run -i cs_CZ -f UTF-8 cs_CZ.UTF-8
ld_run -i de_DE -f ISO-8859-1 de_DE
ld_run -i de_DE@euro -f ISO-8859-15 de_DE@euro
ld_run -i de_DE -f UTF-8 de_DE.UTF-8
ld_run -i el_GR -f ISO-8859-7 el_GR
ld_run -i en_GB -f ISO-8859-1 en_GB
ld_run -i en_GB -f UTF-8 en_GB.UTF-8
ld_run -i en_HK -f ISO-8859-1 en_HK
ld_run -i en_PH -f ISO-8859-1 en_PH
ld_run -i en_US -f ISO-8859-1 en_US
ld_run -i en_US -f UTF-8 en_US.UTF-8
ld_run -i es_ES -f ISO-8859-15 es_ES@euro
ld_run -i es_MX -f ISO-8859-1 es_MX
ld_run -i fa_IR -f UTF-8 fa_IR
ld_run -i fr_FR -f ISO-8859-1 fr_FR
ld_run -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
ld_run -i fr_FR -f UTF-8 fr_FR.UTF-8
ld_run -i is_IS -f ISO-8859-1 is_IS
ld_run -i is_IS -f UTF-8 is_IS.UTF-8
ld_run -i it_IT -f ISO-8859-1 it_IT
ld_run -i it_IT -f ISO-8859-15 it_IT@euro
ld_run -i it_IT -f UTF-8 it_IT.UTF-8
ld_run -i ja_JP -f EUC-JP ja_JP
ld_run -i ja_JP -f UTF-8 ja_JP.UTF-8
ld_run -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
ld_run -i ru_RU -f KOI8-R ru_RU.KOI8-R
ld_run -i ru_RU -f UTF-8 ru_RU.UTF-8
ld_run -i se_NO -f UTF-8 se_NO.UTF-8
ld_run -i ta_IN -f UTF-8 ta_IN.UTF-8
ld_run -i tr_TR -f UTF-8 tr_TR.UTF-8
ld_run -i zh_CN -f GB18030 zh_CN.GB18030
ld_run -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
ld_run -i zh_TW -f UTF-8 zh_TW.UTF-8
echo "手册的 34 条 localedef 全部执行完毕（非 0 退出码计数：$ld_fail）"
echo "手册原文：In addition, install the locale for your own country, language and"
echo "  character set. —— 本项目所在地区为中国大陆（宿主机时区 Asia/Shanghai），手册的"
echo "  minimum set 中已含 zh_CN.GB18030；按这句话再补装 zh_CN.UTF-8："
ld_run -i zh_CN -f UTF-8 zh_CN.UTF-8
echo "校验：上述 35 个 locale 是否都已写入 /usr/lib/locale/locale-archive"
# locale -a 打印的是规范化后的名字（UTF-8 -> utf8、KOI8-R -> koi8r、GB18030 -> gb18030 等）
expected="C.utf8 cs_CZ.utf8 de_DE de_DE@euro de_DE.utf8 el_GR en_GB en_GB.utf8 en_HK en_PH \
en_US en_US.utf8 es_ES@euro es_MX fa_IR fr_FR fr_FR@euro fr_FR.utf8 is_IS is_IS.utf8 \
it_IT it_IT@euro it_IT.utf8 ja_JP ja_JP.utf8 nl_NL@euro ru_RU.koi8r ru_RU.utf8 se_NO.utf8 \
ta_IN.utf8 tr_TR.utf8 zh_CN.gb18030 zh_HK.big5hkscs zh_TW.utf8 zh_CN.utf8"
locale -a > /tmp/locale-a.txt
miss=0
for l in $expected; do
  if grep -qx -- "$l" /tmp/locale-a.txt; then printf '   OK   %s\n' "$l"
  else printf '   FAIL %s 未生成\n' "$l"; miss=$((miss+1)); fi
done
rm -f /tmp/locale-a.txt
[ "$miss" -eq 0 ] || { echo "错误：$miss 个 locale 未生成" >&2; exit 1; }

echo "手册的 Alternatively 方案 make localedata/install-locales（安装 SUPPORTED 中全部"
echo "  locale，time-consuming）与上面二选一，本次按手册正文执行 minimum set，故不执行。"
echo "已安装 locale（localedef 写入 /usr/lib/locale/locale-archive）："
locale -a | sed 's/^/  /'
echo "locale-archive：$(ls -l /usr/lib/locale/locale-archive | awk '{print $5" 字节"}')"
echo

echo "================= 8.5.2. Configuring Glibc ================="
echo "----- 8.5.2.1. Adding nsswitch.conf -----"
echo "手册原文：The /etc/nsswitch.conf file needs to be created because the Glibc"
echo "  defaults do not work well in a networked environment."
echo "手册命令：cat > /etc/nsswitch.conf << \"EOF\" ... EOF"
cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files systemd
group: files systemd
shadow: files systemd

hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF
echo "写入结果 /etc/nsswitch.conf："
cat /etc/nsswitch.conf | sed 's/^/  /'
echo

echo "----- 8.5.2.2. Adding Time Zone Data -----"
echo "手册原文：Install and set up the time zone data with the following:"
echo "手册命令：tar -xf ../../tzdata2025c.tar.gz"
echo "  （当前目录 $PWD，../.. 即 /sources）"
tar -xf "../../$TZTARBALL"
echo "tzdata 解包后的数据文件："
ls -l etcetera southamerica northamerica europe africa antarctica asia australasia \
      backward leapseconds zone.tab zone1970.tab iso3166.tab | sed 's/^/  /'
echo
echo "手册命令："
echo "  ZONEINFO=/usr/share/zoneinfo"
echo "  mkdir -pv \$ZONEINFO/{posix,right}"
echo "  for tz in etcetera southamerica northamerica europe africa antarctica \\"
echo "            asia australasia backward; do"
echo "      zic -L /dev/null   -d \$ZONEINFO       \${tz}"
echo "      zic -L /dev/null   -d \$ZONEINFO/posix \${tz}"
echo "      zic -L leapseconds -d \$ZONEINFO/right \${tz}"
echo "  done"
echo "  cp -v zone.tab zone1970.tab iso3166.tab \$ZONEINFO"
echo "  zic -d \$ZONEINFO -p America/New_York"
echo "  unset ZONEINFO tz"
echo "手册对 zic 的说明："
echo "  zic -L /dev/null ...    creates posix time zones without any leap seconds."
echo "  zic -L leapseconds ...  creates right time zones, including leap seconds."
echo "  zic ... -p ...          creates the posixrules file. We use New York because POSIX"
echo "                          requires the daylight saving time rules to be in accordance"
echo "                          with US rules."
ZONEINFO=/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}

for tz in etcetera southamerica northamerica europe africa antarctica  \
          asia australasia backward; do
    echo "  zic: $tz"
    zic -L /dev/null   -d $ZONEINFO       ${tz}
    zic -L /dev/null   -d $ZONEINFO/posix ${tz}
    zic -L leapseconds -d $ZONEINFO/right ${tz}
done

cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
zic -d $ZONEINFO -p America/New_York
unset ZONEINFO tz
echo "安装结果："
echo "  /usr/share/zoneinfo 总大小：$(du -sh /usr/share/zoneinfo | cut -f1)"
echo "  时区文件数：$(find /usr/share/zoneinfo -type f | wc -l)"
echo "  posix/ 与 right/ 子目录：$(du -sh /usr/share/zoneinfo/posix | cut -f1) / $(du -sh /usr/share/zoneinfo/right | cut -f1)"
echo "  posixrules：$(ls -l /usr/share/zoneinfo/posixrules 2>/dev/null || echo '（zic -p 在新版 tzdata 中可能不再生成，见下方校验）')"
echo
echo "手册原文：One way to determine the local time zone is to run the following script:"
echo "手册命令：tzselect"
echo "  tzselect 是交互式脚本（询问所在地区后输出时区名），chroot 内无交互终端，"
echo "  因此不运行它；改为直接采用宿主机时区 $LOCALTIME_ZONE 作为手册中的 <xxx>。"
echo "  tzselect 已随本节安装：$(command -v tzselect)"
echo "手册原文：Then create the /etc/localtime file by running:"
echo "手册命令：ln -sfv /usr/share/zoneinfo/<xxx> /etc/localtime   （<xxx> = $LOCALTIME_ZONE）"
[ -f "/usr/share/zoneinfo/$LOCALTIME_ZONE" ] || { echo "错误：/usr/share/zoneinfo/$LOCALTIME_ZONE 不存在" >&2; exit 1; }
ln -sfv "/usr/share/zoneinfo/$LOCALTIME_ZONE" /etc/localtime
echo "校验："
ls -l /etc/localtime | sed 's/^/  /'
echo "  当前 chroot 内本地时间：$(date)"
echo "  UTC 时间：$(date -u)"
echo "  zdump 验证：$(zdump /etc/localtime)"
echo

echo "----- 8.5.2.3. Configuring the Dynamic Loader -----"
echo "手册原文：By default, the dynamic loader (/lib/ld-linux.so.2) searches through"
echo "  /usr/lib for dynamic libraries that are needed by programs as they are run."
echo "  However, if there are libraries in directories other than /usr/lib, these need"
echo "  to be added to the /etc/ld.so.conf file ... Two directories that are commonly"
echo "  known to contain additional libraries are /usr/local/lib and /opt/lib."
echo "手册命令：cat > /etc/ld.so.conf << \"EOF\" ... EOF"
cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF
echo "手册原文：If desired, the dynamic loader can also search a directory and include the"
echo "  contents of files found there. ... To add this capability run the following commands:"
echo "手册命令：cat >> /etc/ld.so.conf << \"EOF\" ... EOF  与  mkdir -pv /etc/ld.so.conf.d"
cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
mkdir -pv /etc/ld.so.conf.d
echo "写入结果 /etc/ld.so.conf："
cat /etc/ld.so.conf | sed 's/^/  /'
ls -ld /etc/ld.so.conf.d | sed 's/^/  /'
echo

echo "================= 安装后检查（手册 §8.5.3 Contents of Glibc） ================="
rc=0
echo "1) 已安装程序（手册 Installed programs 列表；ld.so 为指向 ld-linux-x86-64.so.2 的符号链接，"
echo "   lddlibc4 已不随 x86_64 安装则记为 INFO）："
for p in gencat getconf getent iconv iconvconfig ldconfig ldd locale localedef \
         makedb mtrace pcprofiledump pldd sln sotruss sprof tzselect xtrace zdump zic; do
  if f=$(command -v "$p" 2>/dev/null); then printf '   OK   %-14s %s\n' "$p" "$f"
  else printf '   FAIL %s 未安装\n' "$p"; rc=1; fi
done
for p in lddlibc4; do
  if f=$(command -v "$p" 2>/dev/null); then printf '   OK   %-14s %s\n' "$p" "$f"
  else printf '   INFO %s 未安装（该工具已从现代 Glibc 移除，非本次构建缺陷）\n' "$p"; fi
done
echo "   手册要求 ldconfig 与 sln 装到 /usr/sbin（configparms rootsbindir=/usr/sbin）："
for p in /usr/sbin/ldconfig /usr/sbin/sln; do
  if [ -x "$p" ]; then printf '   OK   %s\n' "$p"; else printf '   FAIL %s 缺失\n' "$p"; rc=1; fi
done
echo "2) 已安装库（手册 Installed libraries 抽查，含动态装载器）："
for l in /usr/lib/libc.so.6 /usr/lib/libm.so.6 /usr/lib/libc.a /usr/lib/libm.a \
         /usr/lib/libpthread.so.0 /usr/lib/libdl.so.2 /usr/lib/librt.so.1 \
         /usr/lib/libresolv.so.2 /usr/lib/libutil.so.1 /usr/lib/libanl.so.1 \
         /usr/lib/libmvec.so.1 /usr/lib/libnss_files.so.2 /usr/lib/libnss_dns.so.2 \
         /usr/lib/libthread_db.so.1 /usr/lib/libc_malloc_debug.so.0 \
         /usr/lib/ld-linux-x86-64.so.2; do
  if [ -e "$l" ]; then printf '   OK   %-40s %s\n' "$l" "$(stat -c %s "$l") 字节"
  else printf '   FAIL %s 缺失\n' "$l"; rc=1; fi
done
echo "   手册 libc_cv_slibdir=/usr/lib：核心库必须在 /usr/lib 而不是 /usr/lib64"
if [ -e /usr/lib64/libc.so.6 ]; then echo "   FAIL /usr/lib64/libc.so.6 存在，说明 slibdir 不正确"; rc=1
else echo "   OK   /usr/lib64 下没有 libc.so.6"; fi
echo "   /lib64 里的装载器（ABI 要求的路径）："
ls -l /lib64/ld-linux-x86-64.so.2 2>/dev/null | sed 's/^/     /' || echo "     （/lib64/ld-linux-x86-64.so.2 不存在）"
echo "3) 已安装目录（手册 Installed directories 抽查）："
for d in /usr/include/arpa /usr/include/bits /usr/include/gnu /usr/include/net \
         /usr/include/netinet /usr/include/rpc /usr/include/sys /usr/include/protocols \
         /usr/lib/audit /usr/lib/gconv /usr/lib/locale /usr/libexec/getconf \
         /usr/share/i18n /usr/share/zoneinfo /var/lib/nss_db; do
  if [ -d "$d" ]; then printf '   OK   %-26s（%s 个条目）\n' "$d" "$(ls -A "$d" | wc -l)"
  else printf '   FAIL %s 缺失\n' "$d"; rc=1; fi
done
echo "   §8.5.1 的 glibc-fhs-1.patch 效果：运行时数据落在 FHS 位置 /var/lib/nss_db，"
echo "   而不是非 FHS 的 /var/db："
if [ -d /var/db ]; then echo "   FAIL /var/db 存在，补丁未生效"; rc=1
else echo "   OK   /var/db 不存在"; fi
echo "4) 版本与功能自检："
echo "   ldd  --version : $(ldd --version | sed -n 1p)"
echo "   getconf GNU_LIBC_VERSION : $(getconf GNU_LIBC_VERSION)"
echo "   /usr/lib/libc.so.6 自述 : $(/usr/lib/libc.so.6 --version 2>&1 | sed -n 1p)"
ver=$(getconf GNU_LIBC_VERSION | awk '{print $2}')
if [ "$ver" = "$VER" ]; then echo "   OK   运行中的 Glibc 版本为 $ver，与本节 $VER 一致"
else echo "   FAIL 运行中的 Glibc 版本为 $ver，期望 $VER"; rc=1; fi
echo "   手册 §8.5.1 的 sed 修正 ldd 中硬编码路径的效果："
grep -n "RTLDLIST=" /usr/bin/ldd | sed 's/^/     /'
if grep -q "RTLDLIST=/usr/lib" /usr/bin/ldd; then echo "   FAIL ldd 中仍是 /usr/lib 开头的路径"; rc=1
else echo "   OK   ldd 的 RTLDLIST 已去掉 /usr 前缀"; fi
echo "   编译并运行一个最小程序，确认新 Glibc 的头文件/库/装载器可用："
echo 'int main(void){return 0;}' > /tmp/glibc-sanity.c
gcc -o /tmp/glibc-sanity /tmp/glibc-sanity.c
/tmp/glibc-sanity && echo "   OK   /tmp/glibc-sanity 编译并运行成功（退出码 0）"
echo "   readelf 检查其解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l /tmp/glibc-sanity | grep -A1 "program interpreter" | sed 's/^/     /' || true
echo "   ldd 该程序："
ldd /tmp/glibc-sanity | sed 's/^/     /'
rm -f /tmp/glibc-sanity /tmp/glibc-sanity.c
echo "5) §8.5.2 三项配置的结果："
for f in /etc/nsswitch.conf /etc/ld.so.conf; do
  if [ -s "$f" ]; then printf '   OK   %-20s %s 字节\n' "$f" "$(stat -c %s "$f")"
  else printf '   FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
if [ -d /etc/ld.so.conf.d ]; then echo "   OK   /etc/ld.so.conf.d 存在"; else echo "   FAIL /etc/ld.so.conf.d 缺失"; rc=1; fi
if [ -L /etc/localtime ]; then echo "   OK   /etc/localtime -> $(readlink /etc/localtime)"
else echo "   FAIL /etc/localtime 不是符号链接"; rc=1; fi
echo "   getent 走 nsswitch.conf 的 files 后端（§8.4 的 /etc/services 与 /etc/protocols）："
getent services ssh | sed 's/^/     /' || { echo "   FAIL getent services 失败"; rc=1; }
getent protocols tcp | sed 's/^/     /' || { echo "   FAIL getent protocols 失败"; rc=1; }
getent passwd root | sed 's/^/     /' || { echo "   FAIL getent passwd 失败"; rc=1; }
echo "   ldconfig 重建缓存（验证 /etc/ld.so.conf 语法可用）："
ldconfig -v > /tmp/ldconfig.log 2>&1 || { echo "   FAIL ldconfig 失败"; rc=1; }
echo "     缓存条目数：$(ldconfig -p | sed -n 1p)"
rm -f /tmp/ldconfig.log
echo "   locale 环境自检："
LC_ALL=en_US.UTF-8 locale 2>&1 | sed -n '1,6p' | sed 's/^/     /' 
LC_ALL=zh_CN.UTF-8 locale charmap 2>&1 | sed 's/^/     zh_CN.UTF-8 charmap: /'
echo "6) 测试结论（供任务验收引用）："
echo "   make check 退出码：$check_rc"
echo "   失败总数：$total_fail（手册点名可忽略 $known_cnt，其余 $other_cnt）"
if [ -f tests.sum ]; then
  echo "   tests.sum 计数：$(awk '{print $1}' tests.sum | sort | uniq -c | tr '\n' ' ' | tr -s ' ')"
fi
[ $rc -eq 0 ] || { echo "错误：Glibc 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留测试摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
# 注意：本脚本运行在 chroot 内，chroot 根就是 $LFS，宿主项目目录 /workspace 在这里
# 是【不存在】的；写 /workspace/... 只会在镜像根下凭空造出一个 /workspace 目录。
# chroot 内唯一通向宿主的路径是 /sources（bind mount 到宿主 \$LFS_ROOT/sources），
# 因此测试摘要先落到 /sources，再由宿主侧 run-8.5.sh 移入 logs/packages。
if [ -f tests.sum ]; then
  cp -v tests.sum /sources/8.5-glibc-2.43.tests.sum
fi
cd /sources
rm -rf "$SRCDIR"
[ -d "/sources/$SRCDIR" ] && { echo "错误：源码目录未清理" >&2; exit 1; }
echo "已删除 /sources/$SRCDIR（含其中的 build/ 构建目录与解包出的 tzdata 数据文件）"
echo "/sources 下的解包残留（应为空）："
find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.5 完成，结束时间：$(date -Is) ====="
