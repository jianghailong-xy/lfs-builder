#!/usr/bin/env bash
# LFS 13.0-systemd §8.28 Libxcrypt-4.5.2
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.28.1 Installation of Libxcrypt 的命令序列（必需部分，全部 5 条）：
#   sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
#   ./configure --prefix=/usr --enable-hashes=strong,glibc --enable-obsolete-api=no \
#               --disable-static --disable-failure-tokens
#   make
#   make check
#   make install
#
# 手册在 §8.28.1 末尾有**一个 Note 提示框**（本节唯一的提示框），它给出的
# `make distclean` + 第二次 configure(--enable-obsolete-api=glibc) + make +
# `cp -av --remove-destination .libs/libcrypt.so.1* /usr/lib` 这组命令是**条件性的**：
# 原文写的是「If you must have such functions because of some binary-only application
# or to be compliant with LSB, build the package again with the following commands」。
# 本系统全部从源码构建、无任何 binary-only 应用、也不追求 LSB 兼容，故按手册默认路径
# **不执行**这组命令；脚本会在安装后实测确认系统里没有任何东西需要 ABI version 1
# （即 libcrypt.so.1），把这个判断落成证据而不是断言。
set -euo pipefail

PKG=libxcrypt
VER=4.5.2
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
SEDLOG=/sources/.libxcrypt-sed.log
CONFLOG=/sources/.libxcrypt-configure.log
MAKELOG=/sources/.libxcrypt-make.log
TESTLOG=/sources/.libxcrypt-make-check.log
INSTLOG=/sources/.libxcrypt-make-install.log
SUMLOG=/sources/.libxcrypt-test-summary.log

echo "===== LFS 13.0-systemd §8.28 Libxcrypt-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Libxcrypt package contains a modern library for one-way hashing"
echo "  of passwords."
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 14 MB"
echo
echo "----- chroot 环境自述（手册 §7.4） -----"
echo "date      : $(date -Is)"
echo "kernel    : $(uname -srm)"
echo "PATH      : $PATH"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
esac
echo "  OK   PATH 中不含 /tools/bin"
echo

rc=0
fail() { echo "  FAIL $*"; rc=1; }
ok()   { echo "  OK   $*"; }

# =========================================================================
echo "================= 前置检查（上一任务产物与本节依赖） ================="

echo "--- 1. 上一任务 §8.27 Libcap-2.77 的产物是否可用"
# 说明：本节在**构建层面并不依赖** libcap（libxcrypt 只用 libc）。这里逐项核对是
# 任务书「开始前确认上一任务产物可用」的要求，不是编译依赖。
for f in /usr/lib/libcap.so.2.77 /usr/lib/libcap.so.2 /usr/lib/libcap.so \
         /usr/lib/libpsx.so.2.77 /usr/include/sys/capability.h \
         /usr/sbin/capsh /usr/sbin/getcap /usr/sbin/setcap /usr/sbin/getpcaps; do
  if [ -e "$f" ]; then ok "存在 $f"; else fail "缺失 $f（§8.27 产物）"; fi
done
capsh_out=$(/usr/sbin/capsh --help 2>&1 | sed -n '1p' || true)
echo "  capsh --help 首行：$capsh_out"
case "$capsh_out" in
  *capsh*) ok "§8.27 的 capsh 可运行" ;;
  *)       fail "capsh 无法运行，§8.27 产物不可用" ;;
esac

echo "--- 2. 本节真正需要的工具（只列本节确实要用、且此刻必须已装的）"
# 教训（§8.26）：不要把手册后面才装的包写进必需清单。本节是 autotools 包，
# 但用的是发行 tarball 里**已生成好**的 configure/Makefile.in/libtool，
# 不需要系统的 autoconf/automake/libtool/aclocal。
for t in gcc make sed tar xz grep find awk readelf nm ldconfig; do
  p=$(command -v "$t" || true)
  if [ -n "$p" ]; then ok "$t -> $p"; else fail "缺少 $t"; fi
done
pkgcfg=$(command -v pkg-config || true)
echo "  pkg-config：${pkgcfg:-（未安装，本节不强制需要，仅用于事后展示 .pc 是否可读）}"
echo "  说明：autoconf/automake/libtool/aclocal 均**不需要**（tarball 自带生成物）："
for t in autoconf automake libtool aclocal; do
  echo "    $t: $(command -v $t || echo '未安装（不影响本节）')"
done

echo "--- 3. 源码包"
cd /sources
if [ -f "$TARBALL" ]; then ok "存在 /sources/$TARBALL（$(stat -c %s "$TARBALL") 字节）"; else fail "缺失 /sources/$TARBALL"; fi
if [ -f /sources/md5sums ]; then
  want=$(awk -v t="$TARBALL" '$2==t || $2=="./"t {print $1}' /sources/md5sums | head -n1)
  got=$(md5sum "$TARBALL" 2>/dev/null | awk '{print $1}')
  echo "  md5 期望：${want:-（md5sums 中未列出）}"
  echo "  md5 实测：$got"
  if [ -n "$want" ]; then
    if [ "$want" = "$got" ]; then ok "md5 校验通过"; else fail "md5 不符"; fi
  fi
fi

echo "--- 4. 安装前系统里不应已有 libcrypt（本节是首次安装）"
# 手册 §8.5 的 Glibc 不再自带 libcrypt，libxcrypt 是其唯一提供者。
pre_libcrypt=$( { ls -d /usr/lib/libcrypt* /usr/include/crypt.h \
                    /usr/lib/pkgconfig/libcrypt.pc /usr/lib/pkgconfig/libxcrypt.pc 2>/dev/null || true; } | tr '\n' ' ')
echo "  安装前匹配到的路径：${pre_libcrypt:-（无，符合预期）}"
if [ -z "$pre_libcrypt" ]; then ok "系统中尚无 libcrypt，属首次安装"; else fail "已存在 libcrypt 相关文件，与首次安装的前提不符"; fi
echo "  glibc 版本：$(/usr/bin/ldd --version | sed -n '1p')"
echo "    （手册这条 sed 的注释是 \"a fix required by glibc-2.43 and later\"，本机正是 2.43）"

echo "--- 5. /usr/lib64 不应存在（手册 §7.5.1）"
if [ -e /usr/lib64 ]; then fail "/usr/lib64 存在"; else ok "/usr/lib64 不存在"; fi

echo "--- 6. 构建目录不应有残留"
if [ -e "/sources/$SRCDIR" ]; then
  echo "  发现残留 /sources/$SRCDIR，按手册惯例先删除再解包"
  rm -rf "/sources/$SRCDIR"
fi
ok "构建目录干净"

[ $rc -eq 0 ] || { echo; echo "前置检查未通过，终止（不执行任何手册命令）"; exit 1; }
echo "前置检查全部通过。"
echo

# =========================================================================
echo "================= 解包 ================="
cd /sources
tar -xf "$TARBALL"
cd "/sources/$SRCDIR"
echo "构建目录：$(pwd)"
echo "顶层内容：$(ls | tr '\n' ' ')"
echo "版本自述（configure --version 首行）：$(./configure --version | sed -n '1p')"
echo

# =========================================================================
echo "================= 8.28.1. Installation of Libxcrypt ================="
echo "手册原文：First, make a fix required by glibc-2.43 and later:"
echo "手册命令（第 1 条，逐字）："
echo "  sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c"
echo
echo "--- sed 执行前：两个文件里所有含 strchr 的行"
cp lib/crypt-sm3-yescrypt.c  /tmp/.xc-sm3.before
cp lib/crypt-gost-yescrypt.c /tmp/.xc-gost.before
for f in lib/crypt-sm3-yescrypt.c lib/crypt-gost-yescrypt.c; do
  echo "  [$f]"
  { grep -n strchr "$f" || true; } | sed 's/^/    /'
done
echo "  全树含 strchr 的文件（确认手册只需改这两个）："
{ grep -rln strchr lib/ || true; } | sed 's/^/    /'

sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
sed_rc=$?
echo "  sed 退出码：$sed_rc"
[ $sed_rc -eq 0 ] || { echo "sed 失败" >&2; exit 1; }

echo "--- sed 执行后：两个文件里所有含 strchr 的行"
for f in lib/crypt-sm3-yescrypt.c lib/crypt-gost-yescrypt.c; do
  echo "  [$f]"
  { grep -n strchr "$f" || true; } | sed 's/^/    /'
done
echo "--- 差异（仅作展示；diff 有差异时返回 1，故包成 { … || true; }）"
{ diff -u /tmp/.xc-sm3.before  lib/crypt-sm3-yescrypt.c  || true; } | sed 's/^/    /'
{ diff -u /tmp/.xc-gost.before lib/crypt-gost-yescrypt.c || true; } | sed 's/^/    /'
{
  echo "sed 前后完整差异："
  { diff -u /tmp/.xc-sm3.before  lib/crypt-sm3-yescrypt.c  || true; }
  { diff -u /tmp/.xc-gost.before lib/crypt-gost-yescrypt.c || true; }
} > "$SEDLOG" 2>&1

echo "--- sed 硬判据"
# 试建校准：每个文件恰好改动 1 行，改的是把 (const char *) 的强制转换去掉 const，
# 其余含 strchr 的行（hptr = strchr (hptr + 1, '$');）本来就没有 const，不受影响。
for pair in "lib/crypt-sm3-yescrypt.c:/tmp/.xc-sm3.before" \
            "lib/crypt-gost-yescrypt.c:/tmp/.xc-gost.before"; do
  f=${pair%%:*}; b=${pair#*:}
  nchg=$( { diff "$b" "$f" || true; } | { grep -c '^> ' || true; } )
  if [ "$nchg" = "1" ]; then ok "$f 恰好改动 1 行"; else fail "$f 改动了 $nchg 行（期望 1）"; fi
  nconst=$( { grep -c 'strchr ((const char \*)' "$f" || true; } )
  if [ "$nconst" = "0" ]; then ok "$f 中已无 'strchr ((const char *)'"; else fail "$f 中仍有 $nconst 处 const 强转"; fi
  ncast=$( { grep -c 'strchr (( char \*)' "$f" || true; } )
  if [ "$ncast" = "1" ]; then ok "$f 中出现 1 处去掉 const 的强转"; else fail "$f 中去 const 的强转有 $ncast 处（期望 1）"; fi
done
rm -f /tmp/.xc-sm3.before /tmp/.xc-gost.before
[ $rc -eq 0 ] || { echo "sed 校验失败，终止（尚未执行 configure，系统未被写入）"; exit 1; }
echo

# ---------------------------------------------------------------- configure
echo "手册原文：Prepare Libxcrypt for compilation:"
echo "手册命令（第 2 条，逐字）："
echo "  ./configure --prefix=/usr                \\"
echo "      --enable-hashes=strong,glibc \\"
echo "      --enable-obsolete-api=no     \\"
echo "      --disable-static             \\"
echo "      --disable-failure-tokens"
echo "手册对新选项的说明（The meaning of the new configure options）："
echo "  --enable-hashes=strong,glibc —— Build strong hash algorithms recommended for"
echo "    security use cases, and the hash algorithms provided by traditional Glibc"
echo "    libcrypt for compatibility."
echo "  --enable-obsolete-api=no —— Disable obsolete API functions. They are not needed"
echo "    for a modern Linux system built from source."
echo "  --disable-failure-tokens —— Disable failure token feature. It's needed for"
echo "    compatibility with the traditional hash libraries of some platforms, but a"
echo "    Linux system based on Glibc does not need it."
echo "（--disable-static 手册未在本节复述，是全书通用选项：不建静态库。）"
echo

set +e
./configure --prefix=/usr                \
    --enable-hashes=strong,glibc \
    --enable-obsolete-api=no     \
    --disable-static             \
    --disable-failure-tokens     > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（完整输出：$CONFLOG，共 $(wc -l < "$CONFLOG") 行）"
echo "--- configure 输出尾部 30 行"
tail -n 30 "$CONFLOG" | sed 's/^/  /'
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，config.log 尾部 60 行："
  tail -n 60 config.log | sed 's/^/  /'
  exit $conf_rc
fi
ok "configure 退出码为 0"

echo "--- config.status: creating 行（生成文件的真实落点，别靠目录直觉猜）"
{ grep '^config.status: creating' "$CONFLOG" || true; } | sed 's/^/  /'

echo "--- 选项核对（ac_cs_config 与手册逐字比对，一个不多一个不少）"
acs=$( { grep -m1 '^ac_cs_config=' config.status || true; } | sed "s/^ac_cs_config='//; s/'$//" )
want_acs="--prefix=/usr --enable-hashes=strong,glibc --enable-obsolete-api=no --disable-static --disable-failure-tokens"
echo "  实测：$acs"
echo "  期望：$want_acs"
if [ "$acs" = "$want_acs" ]; then ok "configure 选项与手册逐字一致"; else fail "configure 选项与手册不一致"; fi

echo "--- --enable-obsolete-api=no / --disable-failure-tokens 的落点（config.h 宏）"
{ grep -E '^#define ENABLE_(OBSOLETE_API|OBSOLETE_API_ENOSYS|FAILURE_TOKENS)' config.h || true; } | sed 's/^/  /'
for m in "ENABLE_OBSOLETE_API 0" "ENABLE_OBSOLETE_API_ENOSYS 0" "ENABLE_FAILURE_TOKENS 0"; do
  n=$( { grep -c "^#define $m\$" config.h || true; } )
  if [ "$n" = "1" ]; then ok "config.h 有 #define $m"; else fail "config.h 缺少 #define $m"; fi
done
echo "  SYMVER_FLOOR（obsolete-api=no 时最低符号版本应为 XCRYPT_2.0，而非 XCRYPT_1.0）："
{ grep -E '^#define SYMVER_FLOOR' config.h || true; } | sed 's/^/    /'
sf=$( { grep -m1 '^#define SYMVER_FLOOR' config.h || true; } | awk '{print $3}' )
if [ "$sf" = "XCRYPT_2.0" ]; then ok "SYMVER_FLOOR = XCRYPT_2.0"; else fail "SYMVER_FLOOR = ${sf:-（未定义）}（期望 XCRYPT_2.0）"; fi

echo "--- --disable-static 的落点（生成的 libtool 脚本，取**第一处** build_old_libs）"
{ grep -n 'build_old_libs=' libtool || true; } | sed -n '1,3p' | sed 's/^/  /'
bol=$( { grep -m1 '^build_old_libs=' libtool || true; } )
if [ "$bol" = "build_old_libs=no" ]; then ok "libtool 首个 build_old_libs=no"; else fail "libtool 首个 build_old_libs 是「$bol」"; fi
echo "  （libtool 里 build_old_libs 出现 3 次，第 2/3 处属另一段 case 重算，只看第一处。）"

echo "--- --enable-hashes=strong,glibc 展开成了哪些算法"
he=$( { grep -m1 '^hashes_enabled = ' Makefile || true; } | sed 's/^hashes_enabled = //' )
want_he=",bcrypt,bcrypt_a,bcrypt_y,descrypt,gost_yescrypt,md5crypt,scrypt,sha256crypt,sha512crypt,sm3_yescrypt,yescrypt,"
echo "  Makefile hashes_enabled 实测：$he"
echo "  期望：$want_he"
if [ "$he" = "$want_he" ]; then ok "启用的 11 个 hash 与 strong,glibc 展开一致"; else fail "hashes_enabled 与期望不符"; fi
echo "  crypt-hashes.h 里的 INCLUDE_* 开关（由上面这行生成）："
{ grep -E '^#define INCLUDE_' crypt-hashes.h || true; } | sed 's/^/    /'
n_on=$(  { grep -cE '^#define INCLUDE_[a-z0-9_]+ +1$' crypt-hashes.h || true; } )
n_off=$( { grep -cE '^#define INCLUDE_[a-z0-9_]+ +0$' crypt-hashes.h || true; } )
echo "  启用 $n_on 个 / 禁用 $n_off 个"
if [ "$n_on" = "11" ] && [ "$n_off" = "7" ]; then
  ok "INCLUDE_* 为 11 启用 / 7 禁用（禁用的 7 个：bcrypt_x bigcrypt bsdicrypt nt sha1crypt sm3crypt sunmd5）"
else
  fail "INCLUDE_* 为 $n_on 启用 / $n_off 禁用（期望 11 / 7）"
fi
[ $rc -eq 0 ] || { echo "configure 结果核对失败，终止（尚未 make，系统未被写入）"; exit 1; }
echo

# ---------------------------------------------------------------- make -----
echo "手册原文：Compile the package:"
echo "手册命令（第 3 条，逐字）：make"
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "make 退出码：$make_rc（完整输出：$MAKELOG，共 $(wc -l < "$MAKELOG") 行）"
echo "--- make 输出尾部 12 行"
tail -n 12 "$MAKELOG" | sed 's/^/  /'
if [ $make_rc -ne 0 ]; then
  echo "make 失败，尾部 80 行："; tail -n 80 "$MAKELOG" | sed 's/^/  /'; exit $make_rc
fi
ok "make 退出码为 0"
echo "  （本包 CFLAGS 里带 -Werror，任何警告都会直接变成编译失败；能走到这里说明零警告。）"

echo "--- 构建产物"
{ ls -l .libs/ | grep -E 'libcrypt' || true; } | sed 's/^/  /'
SO=.libs/libcrypt.so.2.0.0
if [ -f "$SO" ]; then ok "共享库实体 $SO 已生成"; else fail "未生成 $SO"; fi
echo "  （实体名 libcrypt.so.2.0.0 来自 Makefile 的 -version-info 2:0:0，"
echo "    不是包版本 4.5.2；SONAME 取 current-age = 2-0 = 2。）"

echo "--- --disable-static 的实证：源码树内不得有任何 .a"
tree_a=$( { find . -name '*.a' || true; } | tr '\n' ' ' )
echo "  树内 .a：${tree_a:-（无）}"
if [ -z "$tree_a" ]; then ok "源码树内无静态库"; else fail "源码树内存在静态库：$tree_a"; fi
echo "  （本包没有 noinst_LTLIBRARIES 式的 convenience library，故与 §8.25 Attr 的"
echo "    libmisc.a 情况不同，这里「一个 .a 都没有」是正确断言。）"

echo "--- SONAME 与 NEEDED"
{ readelf -d "$SO" | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/  /'
soname=$( { readelf -d "$SO" || true; } | sed -n 's/.*SONAME.*\[\(.*\)\]/\1/p' )
if [ "$soname" = "libcrypt.so.2" ]; then ok "SONAME = libcrypt.so.2"; else fail "SONAME = ${soname:-（无）}（期望 libcrypt.so.2）"; fi
needed=$( { readelf -d "$SO" || true; } | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | sort | tr '\n' ' ' )
echo "  NEEDED 集合：$needed"
if [ "$needed" = "libc.so.6 " ]; then ok "只依赖 libc.so.6"; else fail "依赖集合非预期：$needed"; fi

echo "--- 导出符号（--enable-obsolete-api=no 的最强实证）"
nm -D --defined-only "$SO" > /tmp/.xc-syms.txt
{ cat /tmp/.xc-syms.txt || true; } | sed 's/^/  /'
n_sym=$(wc -l < /tmp/.xc-syms.txt)
if [ "$n_sym" = "12" ]; then ok "导出符号 12 个（3 个版本节点 + 9 个函数）"; else fail "导出符号 $n_sym 个（期望 12）"; fi
for f in crypt crypt_r crypt_rn crypt_ra crypt_gensalt crypt_gensalt_rn crypt_gensalt_ra \
         crypt_checksalt crypt_preferred_method; do
  if { grep -qE " T ${f}@@XCRYPT_" /tmp/.xc-syms.txt; }; then ok "导出 $f"; else fail "未导出 $f"; fi
done
# obsolete API（fcrypt/encrypt/encrypt_r/setkey/setkey_r）必须**不存在**
for f in fcrypt encrypt encrypt_r setkey setkey_r; do
  if { grep -qE " T ${f}@" /tmp/.xc-syms.txt; }; then fail "不应导出 obsolete 函数 $f"; else ok "未导出 obsolete 函数 $f（--enable-obsolete-api=no 生效）"; fi
done
n_v1=$( { grep -c 'XCRYPT_1\.0\|@@GLIBC_' /tmp/.xc-syms.txt || true; } )
if [ "$n_v1" = "0" ]; then ok "无 XCRYPT_1.0 / GLIBC_* 版本的**定义**符号（即不提供 ABI version 1）"; else fail "存在 $n_v1 个 XCRYPT_1.0/GLIBC_* 定义符号"; fi
echo "  提示：readelf --version-info 里会出现 GLIBC_2.x 等名字，那是**需要**的版本"
echo "    （verneed，来自 libc），不是本库定义的版本；判据只看 nm -D --defined-only。"
rm -f /tmp/.xc-syms.txt
[ $rc -eq 0 ] || { echo "make 产物核对失败，终止（尚未 make install，系统未被写入）"; exit 1; }
echo

# ---------------------------------------------------------------- check ----
echo "手册原文：To test the results, issue:"
echo "手册命令（第 4 条，逐字）：make check"
echo "判定方式：本节手册**没有任何关于测试的提示框**，也没有 known-to-fail 的说法，"
echo "  故 make check 的退出码就是判据，必须为 0（与 §8.26 Acl 相反）。"
echo "  同时因 MAKEFLAGS=-j$(nproc)，输出里 PASS/SKIP 行的顺序是乱的，逐项结论"
echo "  一律取 automake 的 .trs 文件（:global-test-result:），不看输出行顺序。"
set +e
make check > "$TESTLOG" 2>&1
check_rc=$?
set -e
echo "make check 退出码：$check_rc（完整输出：$TESTLOG，共 $(wc -l < "$TESTLOG") 行）"
if [ $check_rc -eq 0 ]; then ok "make check 退出码为 0"; else fail "make check 退出码为 $check_rc（本节无 known-to-fail，必须为 0）"; fi

echo "--- automake 测试汇总"
{ grep -E '^# (TOTAL|PASS|SKIP|XFAIL|FAIL|XPASS|ERROR):' "$TESTLOG" || true; } | sed 's/^/  /'
num() { { grep -m1 "^# $1:" "$TESTLOG" || true; } | awk '{print $3}' | { grep -E '^[0-9]+$' || echo 0; }; }
T_TOTAL=$(num TOTAL); T_PASS=$(num PASS); T_SKIP=$(num SKIP)
T_XFAIL=$(num XFAIL); T_FAIL=$(num FAIL); T_XPASS=$(num XPASS); T_ERROR=$(num ERROR)
echo "  解析结果：TOTAL=$T_TOTAL PASS=$T_PASS SKIP=$T_SKIP XFAIL=$T_XFAIL FAIL=$T_FAIL XPASS=$T_XPASS ERROR=$T_ERROR"

echo "--- .trs 文件的权威计数（比输出里的 PASS:/SKIP: 行可靠）"
# 注意：grep 在文件名列表为空时会转去读 stdin 而卡死，故先把列表落到文件再判空。
{ find . -name '*.trs' || true; } | sort > /tmp/.xc-trs-list.txt
trs_all=$(wc -l < /tmp/.xc-trs-list.txt)
if [ "$trs_all" -eq 0 ]; then
  echo "  未找到任何 .trs 文件"
  trs_pass=0; trs_skip=0
else
  trs_pass=$( { grep -l '^:global-test-result: PASS' $(cat /tmp/.xc-trs-list.txt) || true; } | wc -l )
  trs_skip=$( { grep -l '^:global-test-result: SKIP' $(cat /tmp/.xc-trs-list.txt) || true; } | wc -l )
fi
echo "  .trs 总数 $trs_all，PASS $trs_pass，SKIP $trs_skip"

# 试建校准出的期望值（同源码同选项，可写成等号硬判据）
for pair in "TOTAL:$T_TOTAL:52" "PASS:$T_PASS:38" "SKIP:$T_SKIP:14" \
            "XFAIL:$T_XFAIL:0" "FAIL:$T_FAIL:0" "XPASS:$T_XPASS:0" "ERROR:$T_ERROR:0"; do
  k=${pair%%:*}; rest=${pair#*:}; got=${rest%%:*}; want=${rest#*:}
  if [ "$got" = "$want" ]; then ok "$k = $want"; else fail "$k = $got（期望 $want）"; fi
done
if [ "$trs_all" = "52" ] && [ "$trs_pass" = "38" ] && [ "$trs_skip" = "14" ]; then
  ok ".trs 逐项结论与汇总一致（52 = 38 PASS + 14 SKIP）"
else
  fail ".trs 计数（$trs_all/$trs_pass/$trs_skip）与汇总（52/38/14）不一致"
fi

echo "--- 14 个 SKIP 分别是谁、为什么跳过"
if [ "$trs_all" -eq 0 ]; then skips=""; else
skips=$( { grep -l '^:global-test-result: SKIP' $(cat /tmp/.xc-trs-list.txt) || true; } \
         | sed 's|.*/||; s|\.trs$||' | sort | tr '\n' ' ' ); fi
echo "  实测 SKIP 列表：$skips"
want_skips="alg-hmac-sha1 alg-md4 alg-sha1 alg-sm3 gensalt-bcrypt_x gensalt-nthash getrandom-fallbacks ka-bcrypt-x ka-bigcrypt ka-bsdicrypt ka-nt ka-sha1crypt ka-sm3crypt ka-sunmd5 "
echo "  期望 SKIP 列表：$want_skips"
if [ "$skips" = "$want_skips" ]; then ok "SKIP 集合与预期逐项一致"; else fail "SKIP 集合与预期不符"; fi
cat <<'WHY' | sed 's/^/  /'
跳过原因（读测试源码得出，不是猜的；每个测试的 main() 直接 return 77 = UNSUPPORTED）：
  · INCLUDE_sha1crypt=0 → alg-sha1、alg-hmac-sha1、ka-sha1crypt        （3）
  · INCLUDE_nt=0        → alg-md4、gensalt-nthash、ka-nt                （3）
  · INCLUDE_sm3crypt=0  → alg-sm3、ka-sm3crypt                          （2）
  · INCLUDE_bcrypt_x=0  → gensalt-bcrypt_x、ka-bcrypt-x                 （2）
  · INCLUDE_bigcrypt=0  → ka-bigcrypt                                   （1）
  · INCLUDE_bsdicrypt=0 → ka-bsdicrypt                                  （1）
  · INCLUDE_sunmd5=0    → ka-sunmd5                                     （1）
  以上 13 个全部是 --enable-hashes=strong,glibc **未选中**的算法，跳过是该选项的
  直接结果，属预期；注意 alg-sm3.c 的守卫是 #if INCLUDE_sm3crypt 而不是
  INCLUDE_sm3_yescrypt —— sm3_yescrypt 虽然启用，独立的 sm3crypt 并未启用，
  所以 alg-sm3 跳过而 alg-sm3-hmac / crypt-sm3-yescrypt / ka-sm3-yescrypt 全部通过。
  · getrandom-fallbacks                                                 （1）
  其源码第 30 行守卫为 #if defined HAVE_ARC4RANDOM_BUF || !defined HAVE_LD_WRAP
  → return 77。本机 config.h 里 HAVE_ARC4RANDOM_BUF=1（glibc 2.36 起提供
  arc4random_buf），库直接走它，那条 getrandom/getentropy/urandom 的回退链根本没
  编进来，故该测试无从测起。这与权限、内核、文件系统都无关，不是环境缺件。
合计 13 + 1 = 14，与 SKIP 计数吻合。
WHY

{
  echo "§8.28 Libxcrypt-$VER make check 汇总"
  echo "make check 退出码：$check_rc"
  echo "TOTAL=$T_TOTAL PASS=$T_PASS SKIP=$T_SKIP XFAIL=$T_XFAIL FAIL=$T_FAIL XPASS=$T_XPASS ERROR=$T_ERROR"
  echo
  echo "PASS 明细（取自 .trs）："
  { grep -l '^:global-test-result: PASS' $(cat /tmp/.xc-trs-list.txt) || true; } \
    | sed 's|.*/||; s|\.trs$||' | sort | sed 's/^/  /'
  echo
  echo "SKIP 明细（取自 .trs）："
  { grep -l '^:global-test-result: SKIP' $(cat /tmp/.xc-trs-list.txt) || true; } \
    | sed 's|.*/||; s|\.trs$||' | sort | sed 's/^/  /'
} > "$SUMLOG" 2>&1
rm -f /tmp/.xc-trs-list.txt
echo "  测试逐项明细另存：$SUMLOG"

echo "--- FAIL / ERROR / XPASS 行（应为空）"
{ grep -E '^(FAIL|ERROR|XPASS):' "$TESTLOG" || true; } | sed 's/^/  /'
echo "--- make check 输出尾部 14 行"
tail -n 14 "$TESTLOG" | sed 's/^/  /'
[ $rc -eq 0 ] || { echo "测试未达手册要求，终止（尚未 make install，系统未被写入）"; exit 1; }
echo

# ---------------------------------------------------------------- install --
echo "手册原文：Install the package:"
echo "手册命令（第 5 条，逐字）：make install"
set +e
make install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "make install 退出码：$inst_rc（完整输出：$INSTLOG，共 $(wc -l < "$INSTLOG") 行）"
if [ $inst_rc -ne 0 ]; then
  echo "make install 失败，尾部 60 行："; tail -n 60 "$INSTLOG" | sed 's/^/  /'; exit $inst_rc
fi
ok "make install 退出码为 0"
echo "--- make install 输出尾部 12 行"
tail -n 12 "$INSTLOG" | sed 's/^/  /'
echo

# =========================================================================
echo "================= 安装结果检查 ================="
echo "--- 手册 §8.28.2 Contents 列出的内容：Installed libraries: libcrypt.so"
if [ -L /usr/lib/libcrypt.so ]; then ok "/usr/lib/libcrypt.so 存在（符号链接 -> $(readlink /usr/lib/libcrypt.so)）"; else fail "/usr/lib/libcrypt.so 缺失"; fi

echo "--- 实际落地的全部文件（14 个普通文件）"
inst_files="/usr/include/crypt.h
/usr/lib/libcrypt.la
/usr/lib/libcrypt.so.2.0.0
/usr/lib/pkgconfig/libxcrypt.pc
/usr/share/man/man3/crypt.3
/usr/share/man/man3/crypt_checksalt.3
/usr/share/man/man3/crypt_gensalt.3
/usr/share/man/man3/crypt_gensalt_ra.3
/usr/share/man/man3/crypt_gensalt_rn.3
/usr/share/man/man3/crypt_preferred_method.3
/usr/share/man/man3/crypt_r.3
/usr/share/man/man3/crypt_ra.3
/usr/share/man/man3/crypt_rn.3
/usr/share/man/man5/crypt.5"
n_missing=0
while IFS= read -r f; do
  if [ -f "$f" ] && [ ! -L "$f" ]; then echo "  OK   $f"; else echo "  FAIL $f 缺失或不是普通文件"; n_missing=$((n_missing+1)); fi
done <<< "$inst_files"
if [ $n_missing -eq 0 ]; then ok "14 个普通文件全部就位"; else fail "$n_missing 个普通文件缺失"; fi

echo "--- 3 个符号链接"
for pair in "/usr/lib/libcrypt.so:libcrypt.so.2.0.0" \
            "/usr/lib/libcrypt.so.2:libcrypt.so.2.0.0" \
            "/usr/lib/pkgconfig/libcrypt.pc:libxcrypt.pc"; do
  l=${pair%%:*}; t=${pair#*:}
  if [ -L "$l" ] && [ "$(readlink "$l")" = "$t" ]; then ok "$l -> $t"; else fail "$l 应为指向 $t 的符号链接（实测：$( [ -L "$l" ] && readlink "$l" || echo '不是链接/不存在' )）"; fi
done
echo "  （libcrypt.pc 是指向 libxcrypt.pc 的链接，两者内容当然相同；"
echo "    找 .pc 时按 libcrypt.pc 或 libxcrypt.pc 都能命中。）"

echo "--- 库文件详情"
{ ls -l /usr/lib/libcrypt.so /usr/lib/libcrypt.so.2 /usr/lib/libcrypt.so.2.0.0 /usr/lib/libcrypt.la || true; } | sed 's/^/  /'
echo "--- man 页数量"
n_man3=$( { find /usr/share/man/man3 -name 'crypt*.3' -type f || true; } | wc -l )
n_man5=$( { find /usr/share/man/man5 -name 'crypt.5' -type f || true; } | wc -l )
echo "  man3 中 crypt*.3：$n_man3 页；man5 中 crypt.5：$n_man5 页"
if [ "$n_man3" = "9" ] && [ "$n_man5" = "1" ]; then ok "man 页共 10 页（9 + 1）"; else fail "man 页数为 $n_man3 + $n_man5（期望 9 + 1）"; fi

echo "--- 不应出现的东西"
if [ -e /usr/lib/libcrypt.a ]; then fail "/usr/lib/libcrypt.a 存在（--disable-static 未生效）"; else ok "/usr/lib/libcrypt.a 不存在"; fi
if [ -e /usr/lib64 ]; then fail "/usr/lib64 被创建"; else ok "/usr/lib64 仍不存在"; fi
if [ -e /usr/lib/libcrypt.so.1 ]; then fail "/usr/lib/libcrypt.so.1 存在（本次未按 Note 走 obsolete-api=glibc 路径，不应有）"; else ok "/usr/lib/libcrypt.so.1 不存在（符合本次未执行手册 Note 的选择）"; fi
echo "  说明：/usr/lib/libcrypt.la 是 libtool 正常安装的库描述文件（old_library=''，"
echo "    即无静态库），手册本节没有要求删除，保留。"
echo "  libcrypt.la 内容："
{ grep -E "^(dlname|library_names|old_library|current|age|revision|libdir)=" /usr/lib/libcrypt.la || true; } | sed 's/^/    /'

echo "--- 安装后的库自身核对"
{ readelf -d /usr/lib/libcrypt.so.2.0.0 | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/  /'
inst_syms=$( { nm -D --defined-only /usr/lib/libcrypt.so.2.0.0 || true; } | wc -l )
echo "  安装后导出符号数：$inst_syms"
if [ "$inst_syms" = "12" ]; then ok "安装后导出符号仍为 12"; else fail "安装后导出符号 $inst_syms 个（期望 12）"; fi

echo "--- 动态链接器能否找到它（ldconfig 缓存）"
ldconfig
{ ldconfig -p > /tmp/.xc-ldcache.txt 2>&1 || true; }
{ grep 'libcrypt' /tmp/.xc-ldcache.txt || true; } | sed 's/^/  /'
if { grep -E 'libcrypt\.so\.2 ' /tmp/.xc-ldcache.txt > /dev/null; }; then ok "ld.so 缓存中已有 libcrypt.so.2"; else fail "ld.so 缓存中找不到 libcrypt.so.2"; fi
rm -f /tmp/.xc-ldcache.txt

echo "--- pkg-config 可读性"
if [ -n "$(command -v pkg-config || true)" ]; then
  echo "  pkg-config --modversion libcrypt : $(pkg-config --modversion libcrypt 2>&1 || true)"
  echo "  pkg-config --libs libcrypt       : $(pkg-config --libs libcrypt 2>&1 || true)"
  echo "  pkg-config --modversion libxcrypt: $(pkg-config --modversion libxcrypt 2>&1 || true)"
  pcv=$(pkg-config --modversion libcrypt 2>/dev/null || true)
  if [ "$pcv" = "$VER" ]; then ok "pkg-config 报告版本 $VER"; else fail "pkg-config 报告版本「$pcv」（期望 $VER）"; fi
else
  echo "  （pkg-config 未安装，跳过该项展示）"
fi
echo

# =========================================================================
echo "================= 功能验证（用刚装进系统的库） ================="
echo "期望值全部取自本节开工前在 chroot /tmp 内的完整试建实测输出（同源码同选项，"
echo "  crypt() 对固定 setting 是确定性的），不从任何外部表格抄。"
cat > /tmp/.xc-verify.c <<'EOF'
#include <crypt.h>
#include <stdio.h>
#include <string.h>

struct kv { const char *desc, *setting, *expect; };

int main (void)
{
  static const struct kv ok_cases[] = {
    { "sha512crypt (glibc)", "$6$saltstring",
      "$6$saltstring$adDbXsJjcDlq2662QPgd.tkSOVmnG9Tt3oXl4HR60SusC3AGjirnDenVZp3DGwLwqy6iYKCzannhaX9DR72nN1" },
    { "sha256crypt (glibc)", "$5$saltstring",
      "$5$saltstring$OH4IDuTlsuTYPdED1gsuiRMyTAwNlRWyA6Xr3I4/dQ5" },
    { "md5crypt (glibc)", "$1$saltstri",
      "$1$saltstri$qQY4WxjABChYG1ccLpfkz/" },
    { "yescrypt (strong)", "$y$j9T$LdJMENpBABJJ3hIHjB1Bi.",
      "$y$j9T$LdJMENpBABJJ3hIHjB1Bi.$u2OTvjfFNnWXgGAOFvgB1vH5NgjtzZuf1aX1t4YvTE." },
    { "bcrypt (strong)", "$2b$05$abcdefghijklmnopqrstuu",
      "$2b$05$abcdefghijklmnopqrstuuWG29KuyeAicPCJODk1zjyGvyQUU2awu" },
    { "descrypt (glibc)", "ab", "abJnggxhB/yWI" },
  };
  /* --enable-hashes=strong,glibc 未选中的算法，必须返回 NULL */
  static const char *const disabled[] = {
    "$sm3$j9T$LdJMENpBABJJ3hIHjB1Bi.",   /* sm3crypt  */
    "$md5$rounds=1000$salt",             /* sunmd5    */
    "$3$$",                              /* nt        */
    "_J9..salt",                         /* bsdicrypt */
  };
  int bad = 0;
  struct crypt_data d;

  for (unsigned i = 0; i < sizeof ok_cases / sizeof ok_cases[0]; i++)
    {
      memset (&d, 0, sizeof d);
      char *h = crypt_r ("password", ok_cases[i].setting, &d);
      int good = h && !strcmp (h, ok_cases[i].expect);
      printf ("  %-4s %-20s %s\n", good ? "OK" : "FAIL", ok_cases[i].desc,
              h ? h : "(NULL)");
      if (!good)
        {
          printf ("       期望 %s\n", ok_cases[i].expect);
          bad++;
        }
    }
  for (unsigned i = 0; i < sizeof disabled / sizeof disabled[0]; i++)
    {
      memset (&d, 0, sizeof d);
      char *h = crypt_r ("password", disabled[i], &d);
      /* --disable-failure-tokens：不支持的 setting 返回 NULL 而不是失败令牌 */
      int good = (h == NULL);
      printf ("  %-4s 未启用算法 %-32s -> %s\n", good ? "OK" : "FAIL",
              disabled[i], h ? h : "NULL（预期）");
      if (!good)
        bad++;
    }
  {
    const char *pm = crypt_preferred_method ();
    int good = pm && !strcmp (pm, "$y$");
    printf ("  %-4s crypt_preferred_method() = %s（期望 $y$）\n",
            good ? "OK" : "FAIL", pm ? pm : "(NULL)");
    if (!good)
      bad++;
  }
  {
    char *gs = crypt_gensalt ("$y$", 0, NULL, 0);
    /* 随机盐，只能校验前缀与长度形态 */
    int good = gs && !strncmp (gs, "$y$j9T$", 7);
    printf ("  %-4s crypt_gensalt(\"$y$\") = %s（期望以 $y$j9T$ 开头）\n",
            good ? "OK" : "FAIL", gs ? gs : "(NULL)");
    if (!good)
      bad++;
  }
  printf ("  不合格项：%d\n", bad);
  return bad ? 1 : 0;
}
EOF
echo "--- 编译（只给 -lcrypt，不给任何 -I/-L/-rpath，全靠系统默认路径找到刚装的库）"
set +e
gcc /tmp/.xc-verify.c -o /tmp/.xc-verify -lcrypt > /tmp/.xc-verify-build.log 2>&1
gcc_rc=$?
set -e
{ cat /tmp/.xc-verify-build.log || true; } | sed 's/^/  /'
if [ $gcc_rc -eq 0 ]; then ok "验证程序编译成功（说明 /usr/include/crypt.h 与 /usr/lib/libcrypt.so 均可用）"; else fail "验证程序编译失败"; fi
if [ $gcc_rc -eq 0 ]; then
  echo "--- 它链接到了哪个库"
  { ldd /tmp/.xc-verify | grep -i crypt || true; } | sed 's/^/  /'
  if { ldd /tmp/.xc-verify | grep 'libcrypt.so.2 => /usr/lib/libcrypt.so.2' > /dev/null; }; then
    ok "运行期解析到 /usr/lib/libcrypt.so.2"
  else
    fail "运行期未解析到 /usr/lib/libcrypt.so.2"
  fi
  echo "--- 运行结果"
  set +e
  /tmp/.xc-verify
  ver_rc=$?
  set -e
  if [ $ver_rc -eq 0 ]; then ok "全部功能断言通过"; else fail "功能验证有 $ver_rc 类不合格项"; fi
fi
rm -f /tmp/.xc-verify.c /tmp/.xc-verify /tmp/.xc-verify-build.log
echo

echo "--- 手册 Note（obsolete API 重建）在本环境是否需要执行"
echo "  Note 原文：… If you must have such functions because of some binary-only"
echo "    application or to be compliant with LSB, build the package again with"
echo "    the following commands: make distclean / ./configure … --enable-obsolete-api=glibc"
echo "    … / make / cp -av --remove-destination .libs/libcrypt.so.1* /usr/lib"
echo "  触发条件与实测："
echo "    (a) 存在 binary-only 应用需要 ABI version 1？—— 本系统此刻的全部二进制"
echo "        都是本书从源码编译产出的，无任何预编译二进制。实测：整个 /usr/bin、"
echo "        /usr/sbin、/usr/lib 里没有任何文件的 NEEDED 含 libcrypt.so.1。"
n_need1=0
for d in /usr/bin /usr/sbin /usr/lib /usr/libexec; do
  [ -d "$d" ] || continue
  while IFS= read -r b; do
    if { readelf -d "$b" 2>/dev/null | grep 'libcrypt.so.1]' > /dev/null; }; then
      echo "        依赖 libcrypt.so.1：$b"
      n_need1=$((n_need1+1))
    fi
  done < <(find "$d" -maxdepth 1 -type f -executable 2>/dev/null; find "$d" -maxdepth 1 -type f -name '*.so*' 2>/dev/null)
done
echo "        实测依赖 libcrypt.so.1 的文件数：$n_need1"
if [ "$n_need1" -eq 0 ]; then ok "无任何已装文件需要 ABI version 1，Note 的条件 (a) 不成立"; else fail "有 $n_need1 个文件需要 libcrypt.so.1"; fi
echo "    (b) 需要 LSB 兼容？—— 本项目目标是可启动的 LFS 系统，不追求 LSB 认证。"
echo "  结论：两个条件都不成立，按手册默认路径**不执行**这组命令，"
echo "    因此系统里没有 libcrypt.so.1（上面已核对）。这是手册允许的选择，不是遗漏。"
echo

# =========================================================================
echo "================= 构建目录清理 ================="
echo "手册 §8.3 通用说明：After the installation of each package, delete the source"
echo "  and build directories, unless instructed otherwise."
cd /sources
du -sh "/sources/$SRCDIR" 2>/dev/null | sed 's/^/  清理前占用：/'
rm -rf "/sources/$SRCDIR"
if [ -e "/sources/$SRCDIR" ]; then fail "/sources/$SRCDIR 未能删除"; else ok "/sources/$SRCDIR 已删除"; fi
echo "  /sources 下当前的非归档条目（应只剩 md5sums / wget-list-systemd 与本节的阶段日志）："
{ ls -A /sources | grep -vE '\.(tar\.(xz|gz|bz2)|tgz|patch|zip)$' || true; } | sed 's/^/    /'
echo

# =========================================================================
echo "================= 本节结论 ================="
echo "手册 §8.28 的 5 条必需命令全部执行且退出码均为 0："
echo "  sed（去 const）        -> $sed_rc"
echo "  ./configure（5 个选项）-> $conf_rc"
echo "  make                   -> $make_rc"
echo "  make check             -> $check_rc"
echo "  make install           -> $inst_rc"
echo "测试：TOTAL=$T_TOTAL  PASS=$T_PASS  SKIP=$T_SKIP  FAIL=$T_FAIL  XFAIL=$T_XFAIL  XPASS=$T_XPASS  ERROR=$T_ERROR"
echo "  本节手册无任何测试提示框、无 known-to-fail，故判据是「退出码 0 且 FAIL/ERROR/XPASS 全为 0」。"
echo "  14 个 SKIP 已逐项归因：13 个来自 --enable-hashes=strong,glibc 未选中的算法"
echo "  （sha1crypt/nt/sm3crypt/bcrypt_x/bigcrypt/bsdicrypt/sunmd5），1 个是"
echo "  getrandom-fallbacks（HAVE_ARC4RANDOM_BUF=1 使回退链未编译）。全部属预期。"
echo "安装产物：14 个普通文件 + 3 个符号链接"
echo "  库：/usr/lib/libcrypt.so.2.0.0（SONAME libcrypt.so.2，来自 -version-info 2:0:0）"
echo "      + libcrypt.so.2 / libcrypt.so 两个链接 + libcrypt.la"
echo "  头：/usr/include/crypt.h"
echo "  pc：/usr/lib/pkgconfig/libxcrypt.pc + libcrypt.pc（链接）"
echo "  man：$n_man3 页 man3 + $n_man5 页 man5"
echo "  导出符号 $inst_syms 个：crypt / crypt_r / crypt_rn / crypt_ra / crypt_gensalt /"
echo "    crypt_gensalt_rn / crypt_gensalt_ra / crypt_checksalt / crypt_preferred_method"
echo "    + 3 个版本节点（XCRYPT_2.0 / XCRYPT_4.3 / XCRYPT_4.4）；无 obsolete API。"
echo "手册 §8.28.2 Contents 只列了 libcrypt.so 一项，已就位。"
echo "手册 Note 的 obsolete-api=glibc 重建：条件不成立，按默认路径未执行（已实测佐证）。"
echo "构建目录 /sources/$SRCDIR 已清理。"
echo
if [ $rc -eq 0 ]; then
  echo "===== §8.28 Libxcrypt-$VER 完成（全部检查通过）====="
else
  echo "===== §8.28 Libxcrypt-$VER 存在未通过的检查项（见上方 FAIL）====="
fi
echo "结束时间：$(date -Is)"
exit $rc
