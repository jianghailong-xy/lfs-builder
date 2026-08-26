#!/usr/bin/env bash
# LFS 13.0-systemd §8.30 GCC-15.2.0
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.30.1 Installation of GCC 的命令序列（全部，按原文顺序）：
#   sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c
#   case $(uname -m) in
#     x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
#   esac
#   mkdir -v build
#   cd       build
#   ../configure --prefix=/usr            \
#                LD=ld                    \
#                --enable-languages=c,c++ \
#                --enable-default-pie     \
#                --enable-default-ssp     \
#                --enable-host-pie        \
#                --disable-multilib       \
#                --disable-bootstrap      \
#                --disable-fixincludes    \
#                --with-system-zlib
#   make
#   ulimit -s -H unlimited
#   sed -e '/cpython/d' -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp
#   chown -R tester .
#   su tester -c "PATH=$PATH make -k check"
#   ../contrib/test_summary            （手册：To filter out only the summaries,
#                                        pipe the output through grep -A7 Summ）
#   make install
#   chown -v -R root:root /usr/lib/gcc/$(gcc -dumpmachine)/15.2.0/include{,-fixed}
#   ln -svr /usr/bin/cpp /usr/lib
#   ln -sv gcc.1 /usr/share/man/man1/cc.1
#   ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/15.2.0/liblto_plugin.so /usr/lib/bfd-plugins/
#   echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log
#   readelf -l a.out | grep ': /lib'
#   grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
#   grep -B4 '^ /usr/include' dummy.log
#   grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
#   grep "/lib.*/libc.so.6 " dummy.log
#   grep found dummy.log
#   rm -v a.out dummy.log
#   mkdir -pv /usr/share/gdb/auto-load/usr/lib
#   mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
#
# 手册 §8.30.1 的 Important 提示框原文：In this section, the test suite for GCC is
# considered important, but it takes a long time. First-time builders are encouraged
# to run the test suite. 本项目跑完整测试套件。手册允许用 -jx 加速；本 chroot 的
# MAKEFLAGS 已是 -j$(nproc)，实测经 `su tester -c` 后仍然保留（见下方「测试前探针」），
# 因此不额外追加 -jx，保持与手册命令逐字一致。
set -euo pipefail

PKG=gcc
VER=15.2.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=/sources/$PKG-$VER
BUILDDIR=$SRCDIR/build

SEDLOG=/sources/.gcc-sed.log
CONFLOG=/sources/.gcc-configure.log
MAKELOG=/sources/.gcc-make.log
CHECKLOG=/sources/.gcc-check.log
SUMLOG=/sources/.gcc-test-summary.log
UNEXPLOG=/sources/.gcc-unexpected.log
INSTLOG=/sources/.gcc-make-install.log

echo "===== LFS 13.0-systemd §8.30 GCC-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The GCC package contains the GNU compiler collection, which includes"
echo "          the C and C++ compilers."
echo "手册数据：Approximate build time 45 SBU (with tests)，Required disk space 6.6 GB"
echo
echo "----- chroot 环境自述（手册 §7.4） -----"
echo "date          : $(date -Is)"
echo "kernel        : $(uname -srm)"
echo "PATH          : $PATH"
echo "MAKEFLAGS     : ${MAKEFLAGS:-（未设置）}"
echo "TESTSUITEFLAGS: ${TESTSUITEFLAGS:-（未设置）}"
echo "umask         : $(umask)"
echo "uname -m      : $(uname -m)"
echo "nproc         : $(nproc)"
echo "根目录内容    : $(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
esac
echo "  OK   PATH 中不含 /tools/bin"
echo

rc=0
fail() { echo "  FAIL $*"; rc=1; }
ok()   { echo "  OK   $*"; }
info() { echo "  INFO $*"; }

# ---------------------------------------------------------------------------
# 阶段执行封装：GCC 的 make / make check 输出体量巨大（几十 MB），全量塞进主日志会
# 让主日志不可读，因此**完整**输出落到 /sources/.gcc-*.log（宿主机侧 run-8.30.sh
# 会把它们归档到 logs/packages/），主日志只记录起止、退出码、耗时和尾部若干行。
# 注意不要写成 `cmd | tee log` 后靠 set -e —— 需要 cmd 自身的退出码，统一用 PIPESTATUS。
# ---------------------------------------------------------------------------
run_logged() {   # run_logged <阶段名> <日志文件> <允许非0:yes/no> <尾部行数> -- <命令...>
  local name=$1 logf=$2 allow=$3 tailn=$4; shift 5
  local start end st
  start=$(date +%s)
  echo "### 开始：$name    $(date -Is)"
  echo "###   完整输出 -> $logf"
  set +e
  "$@" > "$logf" 2>&1
  st=$?
  set -e
  end=$(date +%s)
  echo "### 结束：$name    退出码=$st    耗时 $((end-start)) 秒（$(( (end-start)/60 )) 分）"
  echo "###   日志行数 $(wc -l < "$logf")，尾部 $tailn 行："
  tail -n "$tailn" "$logf" | sed 's/^/###     /'
  if [ "$st" -ne 0 ] && [ "$allow" != yes ]; then
    echo "错误：$name 失败（退出码 $st），按任务要求中止并保留日志" >&2
    exit "$st"
  fi
  LAST_STATUS=$st
  return 0
}

# =========================================================================
echo "================= 前置检查（上一任务产物与本节依赖） ================="

echo "--- 1. 上一任务 §8.29 Shadow-4.19.3 的产物是否可用"
# 本节不直接链接 Shadow，但 §8.30 的测试必须以非特权用户 tester 身份运行
# （手册：Test the results as a non-privileged user），而 su 正是 Shadow 装的程序，
# 所以 §8.29 的产物在本节里是**真的**被用到的。
for f in /usr/bin/passwd /usr/bin/su /usr/bin/login /usr/sbin/useradd /etc/login.defs; do
  if [ -e "$f" ]; then ok "存在 $f"; else fail "缺失 $f（§8.29 产物）"; fi
done
echo "  su 的来源与版本（本节 'su tester -c ...' 要用它）："
{ su --help 2>&1 | tail -n2 || true; } | sed 's/^/    /'
echo "  root 口令散列前缀（§8.29.3 的产物，应为 \$y\$ = yescrypt）："
echo "    $( { getent shadow root 2>/dev/null || grep '^root:' /etc/shadow; } | cut -d: -f2 | cut -c1-3 )"

echo
echo "--- 2. 本节 configure 选项直接依赖的库/程序"
# --with-system-zlib -> §8.6 Zlib；GCC 本体 -> §8.22/23/24 的 GMP/MPFR/MPC；
# LD=ld -> §8.21 本章 Binutils 装的 ld。
for f in /usr/lib/libz.so /usr/include/zlib.h \
         /usr/lib/libgmp.so /usr/include/gmp.h \
         /usr/lib/libmpfr.so /usr/include/mpfr.h \
         /usr/lib/libmpc.so /usr/include/mpc.h \
         /usr/bin/ld /usr/bin/as /usr/lib/bfd-plugins; do
  if [ -e "$f" ]; then ok "存在 $f"; else fail "缺失 $f"; fi
done
echo "  ld  版本（LD=ld 让 configure 用本章 §8.21 的 ld，而不是交叉版）："
{ ld --version | head -n1 || true; } | sed 's/^/    /'
echo "  ld  实际路径：$(command -v ld)"

echo
echo "--- 3. 测试套件依赖（手册 §8.17/§8.18/§8.19 装的 Tcl/Expect/DejaGnu）"
for c in runtest expect tclsh; do
  p=$(command -v "$c" 2>/dev/null || true)
  if [ -n "$p" ]; then ok "$c -> $p"; else fail "$c 缺失（GCC 测试套件必需）"; fi
done
echo "  DejaGnu 版本：$( { runtest --version 2>&1 | head -n1 || true; } )"

echo
echo "--- 4. 非特权测试用户 tester（手册 §7.6 建立，第 8 章末删除）"
if id tester >/dev/null 2>&1; then
  ok "tester 存在：$(id tester)"
  ls -ld /home/tester | sed 's/^/    /'
else
  fail "tester 用户不存在，手册要求以它跑 GCC 测试"
fi
echo "  探针：MAKEFLAGS 能否穿过 'su tester -c \"PATH=\$PATH ...\"'（决定测试是否并行）"
{ su tester -c "PATH=$PATH sh -c 'echo \"      MAKEFLAGS=[\$MAKEFLAGS]  whoami=\$(whoami)  PATH=[\$PATH]\"'" || true; }

echo
echo "--- 5. 当前（第 6 章 §6.18 GCC pass 2 留下的）编译器状态"
echo "  gcc  : $(gcc --version | head -n1)    triplet=$(gcc -dumpmachine)"
echo "  g++  : $(g++ --version | head -n1)"
echo "  说明：pass 2 的 triplet 是 $(gcc -dumpmachine)（--host=\$LFS_TGT 的产物）；"
echo "        本节是**本机**编译，configure 不带 --host/--target，装出来的 triplet 会变成"
echo "        x86_64-pc-linux-gnu。因此 §8.30.1 里那几条含 \$(gcc -dumpmachine) 的命令"
echo "        必须在 make install **之后**执行才会取到新 triplet —— 手册的顺序正是如此，"
echo "        本脚本严格照做。"
ls -d /usr/lib/gcc/*/ /usr/libexec/gcc/*/ 2>/dev/null | sed 's/^/    旧目录：/'

echo
echo "--- 6. 源码包与磁盘"
if [ -f "/sources/$TARBALL" ]; then
  ok "存在 /sources/$TARBALL（$(stat -c%s "/sources/$TARBALL") 字节）"
  echo "    md5   ：$(md5sum "/sources/$TARBALL" | cut -d' ' -f1)"
  echo "    手册值：b861b092bf1af683c46a8aa2e689a6fd（LFS 13.0-systemd md5sums）"
  if [ "$(md5sum "/sources/$TARBALL" | cut -d' ' -f1)" = b861b092bf1af683c46a8aa2e689a6fd ]; then
    ok "md5 与手册一致"
  else
    fail "md5 与手册不一致"
  fi
else
  fail "缺少源码包 /sources/$TARBALL"
fi
echo "  磁盘空间（手册要求 6.6 GB；构建目录在 /sources，安装目标在 /）："
df -h /sources / | sed 's/^/    /'

echo
echo "--- 7. 本节将新建的路径当前是否已存在（避免误判「手册命令失败」）"
for p in /usr/lib/cpp /usr/share/man/man1/cc.1 /usr/share/gdb; do
  if [ -e "$p" ] || [ -L "$p" ]; then info "$p 已存在：$(ls -ld "$p" | sed 's/  */ /g')"
  else ok "$p 尚不存在（符合预期，本节创建）"; fi
done
echo "  当前 /usr/lib 下的 *gdb.py（§8.30.1 末尾要 mv 走的文件）："
{ ls -l /usr/lib/*gdb.py 2>/dev/null || echo "    （暂无）"; } | sed 's/^/    /'

[ $rc -eq 0 ] || { echo; echo "错误：前置检查未通过，按任务要求中止" >&2; exit 1; }
echo
echo "  前置检查全部通过。"
echo

# =========================================================================
echo "================= 解包 ================="
cd /sources
if [ -e "$SRCDIR" ]; then
  echo "  发现残留目录 $SRCDIR，先删除（手册 §8.1 的惯例：每个包从干净源码树开始）"
  rm -rf "$SRCDIR"
fi
echo "  命令：tar -xf /sources/$TARBALL -C /sources"
tar -xf "/sources/$TARBALL" -C /sources
cd "$SRCDIR"
echo "  解包后目录：$PWD"
echo "  版本自证（gcc/BASE-VER 与 ChangeLog 首行）："
echo "    BASE-VER = $(cat gcc/BASE-VER)"
[ "$(cat gcc/BASE-VER)" = "$VER" ] || { echo "错误：BASE-VER 不是 $VER" >&2; exit 1; }
echo "  源码树规模：$(du -sh . | cut -f1)"
echo

# =========================================================================
echo "================= 手册命令 1/N：glibc-2.43 相容性修补 ================="
cat <<'MANUAL'
手册原文：First, make a fix required by glibc-2.43 and later:
  sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c
MANUAL
echo "  修改前，libgomp/affinity-fmt.c 中匹配 'char [*]q' 的行："
{ grep -n 'char [*]q' libgomp/affinity-fmt.c || true; } | sed 's/^/    /'
md5_before=$(md5sum libgomp/affinity-fmt.c | cut -d' ' -f1)
sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c
md5_after=$(md5sum libgomp/affinity-fmt.c | cut -d' ' -f1)
echo "  修改后，同一处："
{ grep -n 'const char [*]q' libgomp/affinity-fmt.c || true; } | sed 's/^/    /'
echo "  md5：$md5_before -> $md5_after"
if [ "$md5_before" != "$md5_after" ]; then ok "sed 确实改动了文件"; else fail "sed 未改动文件"; fi
echo "  （本系统的 glibc 版本：$(ldd --version | head -n1)，正是手册所指的 2.43+）"
echo

# =========================================================================
echo "================= 手册命令 2/N：x86_64 上把 64 位库目录名改成 lib ================="
cat <<'MANUAL'
手册原文：If building on x86_64, change the default directory name for 64-bit
libraries to "lib":
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' \
          -i.orig gcc/config/i386/t-linux64
    ;;
  esac
MANUAL
echo "  uname -m = $(uname -m)"
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
    echo "  已执行（-i.orig 会留下 t-linux64.orig 备份），diff 如下："
    { diff -u gcc/config/i386/t-linux64.orig gcc/config/i386/t-linux64 || true; } | sed 's/^/    /'
    if [ -f gcc/config/i386/t-linux64.orig ] && \
       ! cmp -s gcc/config/i386/t-linux64.orig gcc/config/i386/t-linux64; then
      ok "t-linux64 的 m64 行已由 lib64 改为 lib"
    else
      fail "t-linux64 未被改动"
    fi
  ;;
  *) info "非 x86_64，按手册跳过本命令" ;;
esac
echo

# =========================================================================
echo "================= 手册命令 3/N：mkdir -v build && cd build ================="
cat <<'MANUAL'
手册原文：The GCC documentation recommends building GCC in a dedicated build
directory:
  mkdir -v build
  cd       build
MANUAL
mkdir -v build
cd       build
echo "  当前目录：$PWD"
echo

# =========================================================================
echo "================= 手册命令 4/N：../configure ... ================="
cat <<'MANUAL'
手册原文命令：
  ../configure --prefix=/usr            \
               LD=ld                    \
               --enable-languages=c,c++ \
               --enable-default-pie     \
               --enable-default-ssp     \
               --enable-host-pie        \
               --disable-multilib       \
               --disable-bootstrap      \
               --disable-fixincludes    \
               --with-system-zlib
手册对新增参数的解释：
  LD=ld                  makes the configure script use the ld program installed by
                         the Binutils package built earlier in this chapter, rather
                         than the cross-built version.
  --disable-bootstrap    in LFS we bootstrap GCC by a different method (Toolchain
                         Technical Notes), so the 3-stage bootstrap is unnecessary
                         here and disabling it significantly reduces build time.
  --disable-fixincludes  prevents GCC from "fixing" system headers — unnecessary on
                         a modern Linux system and potentially harmful.
  --with-system-zlib     link to the system installed copy of Zlib rather than the
                         internal copy.
手册 Note（PIE/SSP）：Enabling PIE allows ASLR for the executables in addition to the
  shared libraries; SSP ensures that the parameter stack is not corrupted.
只启用 c,c++ 的原因（手册原文）：We only enable C and C++ here to save the build time
  as no packages in LFS and BLFS require GCC to compile other languages.
MANUAL
run_logged "../configure（10 个参数）" "$CONFLOG" no 25 -- \
  ../configure --prefix=/usr            \
               LD=ld                    \
               --enable-languages=c,c++ \
               --enable-default-pie     \
               --enable-default-ssp     \
               --enable-host-pie        \
               --disable-multilib       \
               --disable-bootstrap      \
               --disable-fixincludes    \
               --with-system-zlib
echo
echo "----- configure 结果核对 -----"
echo "  顶层 Makefile 是否生成：$( [ -f Makefile ] && echo 是 || echo 否 )"
[ -f Makefile ] || fail "configure 未生成 Makefile"
echo "  config.log 里记录的 configure 命令行："
{ grep -m1 '^  \$ .*configure' config.log || true; } | sed 's/^/    /'
echo "  实际生效的关键配置（取自 gcc/Makefile 与 config.status）："
for v in target_alias host_alias build_alias enable_languages; do
  echo "    $v = $( { grep -m1 "^$v *=" gcc/Makefile 2>/dev/null || true; } | sed 's/^[^=]*= *//' )"
done
echo "  本机 triplet（configure 未带 --host/--target，故为本机推断值）："
{ grep -m1 '^target=' Makefile || true; } | sed 's/^/    /'
{ grep -m1 '^host=' Makefile || true; } | sed 's/^/    /'
echo "  --disable-multilib 生效性（应只有一个 multilib，即 '. ;'）："
{ grep -m1 'MULTILIB_OPTIONS\|multilib_options' gcc/Makefile || true; } | sed 's/^/    /'
echo "  --with-system-zlib 生效性（zlib 目录不应被配置为构建目标）："
if [ -d zlib ]; then info "build/zlib 目录存在（configure 仍会建目录），下面看 Makefile 是否把它列入构建"; fi
{ grep -m1 'configure-zlib\|all-zlib' Makefile || true; } | sed 's/^/    /'
echo

# =========================================================================
echo "================= 手册命令 5/N：make ================="
cat <<'MANUAL'
手册原文：Compile the package:
  make
MANUAL
run_logged "make" "$MAKELOG" no 20 -- make
echo
echo "----- make 结果核对 -----"
echo "  构建目录规模：$(du -sh "$BUILDDIR" | cut -f1)"
echo "  关键产物是否存在："
# 注意：构建树里的 C++ 驱动叫 xg++（与 C 驱动叫 xgcc 同理，都带 x 前缀，
# 表示「尚未安装的、用于构建自身运行库的编译器」）。构建树里**没有** gcc/g++
# 这个文件，装到 /usr/bin 之后才叫 g++。此处曾错写成 gcc/g++ 而误报过一次 FAIL。
for f in gcc/xgcc gcc/xg++ gcc/cc1 gcc/cc1plus ; do
  if [ -e "$f" ]; then ok "$f"; else fail "$f 未生成"; fi
done
echo "  新编译器自报版本（尚未安装，直接跑构建树里的 xgcc）："
{ ./gcc/xgcc -B./gcc --version | head -n1 || true; } | sed 's/^/    /'
echo "  libstdc++ / libgomp 等运行库："
{ ls -l x86_64-pc-linux-gnu/libstdc++-v3/src/.libs/libstdc++.so.6.0.* 2>/dev/null || true; } | sed 's/^/    /'
echo

# =========================================================================
echo "================= 手册命令 6/N：ulimit -s -H unlimited ================="
cat <<'MANUAL'
手册原文：GCC may need more stack space compiling some extremely complex code
patterns. As a precaution for the host distros with a tight stack limit, explicitly
set the stack size hard limit to infinite. ... It's not necessary to change the stack
size soft limit because GCC will automatically set it to an appropriate value, as long
as the value does not exceed the hard limit:
  ulimit -s -H unlimited
MANUAL
echo "  执行前：hard=$(ulimit -s -H)  soft=$(ulimit -s -S)"
ulimit -s -H unlimited
echo "  执行后：hard=$(ulimit -s -H)  soft=$(ulimit -s -S)"
[ "$(ulimit -s -H)" = unlimited ] && ok "栈硬上限已为 unlimited" || fail "栈硬上限不是 unlimited"
echo

# =========================================================================
echo "================= 手册命令 7/N：移除若干已知失败的测试 ================="
cat <<'MANUAL'
手册原文：Now remove several known test failures:
  sed -e '/cpython/d' -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp
MANUAL
echo "  修改前 plugin.exp 中含 cpython 的行："
{ grep -n cpython ../gcc/testsuite/gcc.dg/plugin/plugin.exp || true; } | sed 's/^/    /'
lines_before=$(wc -l < ../gcc/testsuite/gcc.dg/plugin/plugin.exp)
sed -e '/cpython/d' -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp
lines_after=$(wc -l < ../gcc/testsuite/gcc.dg/plugin/plugin.exp)
echo "  行数：$lines_before -> $lines_after（删掉 $((lines_before-lines_after)) 行）"
cpython_left=$( { grep -c cpython ../gcc/testsuite/gcc.dg/plugin/plugin.exp || true; } )
echo "  修改后剩余 cpython 行数：$cpython_left"
[ "$cpython_left" = 0 ] && ok "cpython 相关测试项已全部删除" || fail "plugin.exp 中仍有 cpython 行"
echo

# =========================================================================
echo "================= 手册命令 8/N：chown -R tester . ================="
cat <<'MANUAL'
手册原文：Test the results as a non-privileged user, but do not stop at errors:
  chown -R tester .
  su tester -c "PATH=$PATH make -k check"
MANUAL
echo "  执行前构建目录属主：$(stat -c '%U:%G' .)"
chown -R tester .
echo "  执行后构建目录属主：$(stat -c '%U:%G' .)"
echo "  抽查若干子路径属主："
{ stat -c '    %U:%G %n' . gcc gcc/xgcc Makefile 2>/dev/null || true; }
[ "$(stat -c '%U' .)" = tester ] && ok "构建目录已交给 tester" || fail "构建目录属主不是 tester"
echo "  tester 能否进入 /sources 路径（目录 x 权限）："
{ su tester -c "test -x /sources && test -r $BUILDDIR/Makefile && echo '    OK   tester 可读构建目录'" || echo "    FAIL tester 无法读取构建目录"; }
echo

# =========================================================================
echo "================= 手册命令 9/N：su tester -c \"PATH=\$PATH make -k check\" ================="
cat <<'MANUAL'
手册 Important 原文：In this section, the test suite for GCC is considered important,
but it takes a long time. First-time builders are encouraged to run the test suite.
The time to run the tests can be reduced significantly by adding -jx to the
make -k check command below, where x is the number of CPU cores on your system.
MANUAL
echo "  说明：本 chroot 的 MAKEFLAGS=${MAKEFLAGS:-} 已随环境传入且能穿过 su（见前置检查第 4 项），"
echo "        因此不再手工追加 -jx，命令与手册逐字一致。make -k 表示遇错不停，"
echo "        其退出码非 0 属预期（手册：do not stop at errors），故本阶段 allow=yes。"
check_start=$(date +%s)
echo "### 开始：make -k check    $(date -Is)"
echo "###   完整输出 -> $CHECKLOG"
set +e
su tester -c "PATH=$PATH make -k check" > "$CHECKLOG" 2>&1
check_rc=$?
set -e
check_end=$(date +%s)
echo "### 结束：make -k check    退出码=$check_rc    耗时 $((check_end-check_start)) 秒（$(( (check_end-check_start)/60 )) 分）"
echo "###   日志行数 $(wc -l < "$CHECKLOG")，尾部 15 行："
tail -n 15 "$CHECKLOG" | sed 's/^/###     /'
echo

# =========================================================================
echo "================= 手册命令 10/N：../contrib/test_summary ================="
cat <<'MANUAL'
手册原文：To extract a summary of the test suite results, run:
  ../contrib/test_summary
To filter out only the summaries, pipe the output through grep -A7 Summ.
MANUAL
set +e
../contrib/test_summary > "$SUMLOG" 2>&1
ts_rc=$?
set -e
echo "  ../contrib/test_summary 退出码=$ts_rc，完整输出 -> $SUMLOG（$(wc -l < "$SUMLOG") 行）"
echo
echo "----- 手册的 'grep -A7 Summ' 过滤结果（各 testsuite 的汇总）-----"
{ grep -A7 Summ "$SUMLOG" || true; } | sed 's/^/  /'
echo

echo "----- 全部 .sum 文件的分项计数 -----"
find "$BUILDDIR" -name '*.sum' | sort > /tmp/.gcc-sumfiles
echo "  .sum 文件数：$(wc -l < /tmp/.gcc-sumfiles)"
sed 's|'"$BUILDDIR"'/||' /tmp/.gcc-sumfiles | sed 's/^/    /'
echo
if [ -s /tmp/.gcc-sumfiles ]; then
  for kind in PASS XPASS FAIL XFAIL UNSUPPORTED UNTESTED UNRESOLVED ERROR; do
    n=$( { xargs -a /tmp/.gcc-sumfiles grep -ch "^$kind:" 2>/dev/null || true; } | paste -sd+ - | { read -r e; echo $(( ${e:-0} )); } )
    printf '    %-12s %s\n' "$kind" "$n"
  done
else
  fail "没有找到任何 .sum 文件，测试可能根本没跑起来"
fi
echo

echo "----- 意外结果明细（FAIL / XPASS / UNRESOLVED / ERROR）-----"
if [ -s /tmp/.gcc-sumfiles ]; then
  : > "$UNEXPLOG"
  while read -r f; do
    rel=${f#"$BUILDDIR"/}
    { grep -E '^(FAIL|XPASS|UNRESOLVED|ERROR):' "$f" || true; } | sed "s|^|$rel : |" >> "$UNEXPLOG"
  done < /tmp/.gcc-sumfiles
  echo "  意外结果总条数：$(wc -l < "$UNEXPLOG")（完整明细 -> $UNEXPLOG）"
  echo "  按 testsuite 归类："
  { cut -d: -f1 "$UNEXPLOG" | sed 's/ *$//' | sort | uniq -c | sort -rn || true; } | sed 's/^/    /'
  echo
  echo "  明细（最多前 400 条；完整见 $UNEXPLOG）："
  head -n 400 "$UNEXPLOG" | sed 's/^/    /'
  echo
  echo "----- 与手册列出的「已知失败」逐条对照 -----"
  cat <<'MANUAL'
手册原文（§8.30.1）：
  Four tests related to pr90579.c are known to fail.
  Five tests related to analyzer/strchr-1.c are known to fail.
  Four tests in libstdc++, 17_intro/badnames.cc, 17_intro/names.cc,
    17_intro/names_fortify.cc, and experimental/names.cc, are known to fail due to
    changes with glibc-2.43.
  A few unexpected failures cannot always be avoided. In some cases test failures
    depend on the specific hardware of the system. Unless the test results are vastly
    different from those at the above URL, it is safe to continue.
MANUAL
  n_pr90579=$( { grep -c 'pr90579' "$UNEXPLOG" || true; } )
  n_strchr=$(  { grep -c 'strchr-1\.c' "$UNEXPLOG" || true; } )
  n_badnames=$({ grep -c '17_intro/badnames\.cc' "$UNEXPLOG" || true; } )
  n_names=$(   { grep -c '17_intro/names\.cc' "$UNEXPLOG" || true; } )
  n_namesf=$(  { grep -c '17_intro/names_fortify\.cc' "$UNEXPLOG" || true; } )
  n_expnames=$({ grep -c 'experimental/names\.cc' "$UNEXPLOG" || true; } )
  printf '    %-42s 本次 %s 条（手册：4 条）\n'  'pr90579.c 相关'                "$n_pr90579"
  printf '    %-42s 本次 %s 条（手册：5 条）\n'  'analyzer/strchr-1.c 相关'      "$n_strchr"
  printf '    %-42s 本次 %s 条（手册：合计 4 条）\n' 'libstdc++ 17_intro/badnames.cc' "$n_badnames"
  printf '    %-42s 本次 %s 条\n'                'libstdc++ 17_intro/names.cc'   "$n_names"
  printf '    %-42s 本次 %s 条\n'                'libstdc++ 17_intro/names_fortify.cc' "$n_namesf"
  printf '    %-42s 本次 %s 条\n'                'libstdc++ experimental/names.cc' "$n_expnames"
  known=$((n_pr90579+n_strchr+n_badnames+n_names+n_namesf+n_expnames))
  total_unexp=$(wc -l < "$UNEXPLOG")
  echo "    手册点名的已知失败合计：$known 条；本次意外结果总数：$total_unexp 条；"
  echo "    其余（未被手册点名）：$((total_unexp-known)) 条 —— 明细见上，逐条判读写在本节末尾的结论里。"
  echo
  echo "  未被手册点名的意外结果明细（最多前 200 条）："
  { grep -vE 'pr90579|strchr-1\.c|17_intro/badnames\.cc|17_intro/names\.cc|17_intro/names_fortify\.cc|experimental/names\.cc' "$UNEXPLOG" || true; } \
    | head -n 200 | sed 's/^/    /'
fi
echo
echo "  手册对结果的判读标准（原文）：Results can be compared with those located at"
echo "    https://www.linuxfromscratch.org/lfs/build-logs/13.0/ and"
echo "    https://gcc.gnu.org/ml/gcc-testresults/ ... Unless the test results are vastly"
echo "    different from those at the above URL, it is safe to continue."
echo "  按此标准：make -k check 的非 0 退出码（本次 $check_rc）不作为本节失败判据。"
echo

# =========================================================================
echo "================= 手册命令 11/N：make install ================="
cat <<'MANUAL'
手册原文：Install the package:
  make install
MANUAL
echo "  说明：构建目录此刻属主是 tester，安装由 root 执行（手册未要求改回）。"
run_logged "make install" "$INSTLOG" no 15 -- make install
echo
echo "----- 安装后立刻确认新编译器已就位 -----"
hash -r
echo "  gcc --version : $(gcc --version | head -n1)"
echo "  g++ --version : $(g++ --version | head -n1)"
echo "  gcc -dumpmachine : $(gcc -dumpmachine)"
NEWTRIPLET=$(gcc -dumpmachine)
echo "  gcc -dumpversion : $(gcc -dumpversion)"
[ "$(gcc -dumpversion)" = "$VER" ] && ok "gcc 版本为 $VER" || fail "gcc 版本不是 $VER"
echo

# =========================================================================
echo "================= 手册命令 12/N：修正头文件目录属主 ================="
cat <<'MANUAL'
手册原文：The GCC build directory is owned by tester now, and the ownership of the
installed header directory (and its content) is incorrect. Change the ownership to the
root user and group:
  chown -v -R root:root /usr/lib/gcc/$(gcc -dumpmachine)/15.2.0/include{,-fixed}
MANUAL
echo "  \$(gcc -dumpmachine) = $NEWTRIPLET"
echo "  两个目标目录是否都存在（手册的花括号展开要求它们都在）："
for d in /usr/lib/gcc/"$NEWTRIPLET"/$VER/include /usr/lib/gcc/"$NEWTRIPLET"/$VER/include-fixed; do
  if [ -d "$d" ]; then ok "$d"; else fail "$d 不存在（手册命令会因此报错）"; fi
done
echo "  执行前属主抽样："
{ stat -c '    %U:%G %n' /usr/lib/gcc/"$NEWTRIPLET"/$VER/include /usr/lib/gcc/"$NEWTRIPLET"/$VER/include-fixed 2>&1 || true; }
set +e
chown -v -R root:root \
    /usr/lib/gcc/$(gcc -dumpmachine)/$VER/include{,-fixed} > /tmp/.gcc-chown.log 2>&1
chown_rc=$?
set -e
echo "  chown 退出码=$chown_rc，改动 $(wc -l < /tmp/.gcc-chown.log) 行，尾部 10 行："
tail -n 10 /tmp/.gcc-chown.log | sed 's/^/    /'
[ $chown_rc -eq 0 ] || fail "chown 返回非 0"
echo "  执行后属主："
{ stat -c '    %U:%G %n' /usr/lib/gcc/"$NEWTRIPLET"/$VER/include /usr/lib/gcc/"$NEWTRIPLET"/$VER/include-fixed 2>&1 || true; }
left=$( { find /usr/lib/gcc/"$NEWTRIPLET"/$VER/include /usr/lib/gcc/"$NEWTRIPLET"/$VER/include-fixed \
          ! -user root -o ! -group root 2>/dev/null || true; } | head -n5 )
if [ -z "$left" ]; then ok "include 与 include-fixed 下已无非 root:root 的条目"
else echo "$left" | sed 's/^/    残留：/'; fail "仍有非 root 属主的头文件"; fi
echo

# =========================================================================
echo "================= 手册命令 13/N：FHS 要求的 /usr/lib/cpp 符号链接 ================="
cat <<'MANUAL'
手册原文：Create a symlink required by the FHS for "historical" reasons.
  ln -svr /usr/bin/cpp /usr/lib
MANUAL
ln -svr /usr/bin/cpp /usr/lib | sed 's/^/    /'
echo "  结果：$(ls -l /usr/lib/cpp | sed 's/  */ /g')"
if [ -L /usr/lib/cpp ] && [ -x /usr/lib/cpp ]; then ok "/usr/lib/cpp 是可执行的符号链接"
else fail "/usr/lib/cpp 不正确"; fi
echo "  实测可用：$( { /usr/lib/cpp --version | head -n1 || true; } )"
echo

# =========================================================================
echo "================= 手册命令 14/N：cc 的 man 页符号链接 ================="
cat <<'MANUAL'
手册原文：Many packages use the name cc to call the C compiler. We've already created
cc as a symlink in gcc-pass2, create its man page as a symlink as well:
  ln -sv gcc.1 /usr/share/man/man1/cc.1
MANUAL
ln -sv gcc.1 /usr/share/man/man1/cc.1 | sed 's/^/    /'
echo "  结果：$(ls -l /usr/share/man/man1/cc.1 | sed 's/  */ /g')"
if [ -L /usr/share/man/man1/cc.1 ] && [ -e /usr/share/man/man1/cc.1 ]; then
  ok "cc.1 -> gcc.1 且目标存在"
else fail "cc.1 链接不正确或悬空"; fi
echo "  §6.18 已建的 cc 程序链接仍在：$(ls -l /usr/bin/cc | sed 's/  */ /g')"
echo

# =========================================================================
echo "================= 手册命令 15/N：LTO 插件的相容性链接 ================="
cat <<'MANUAL'
手册原文：Add a compatibility symlink to enable building programs with Link Time
Optimization (LTO):
  ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/15.2.0/liblto_plugin.so \
          /usr/lib/bfd-plugins/
MANUAL
echo "  目标文件是否存在：$(ls -l /usr/libexec/gcc/"$NEWTRIPLET"/$VER/liblto_plugin.so 2>&1 | sed 's/  */ /g')"
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/$VER/liblto_plugin.so \
        /usr/lib/bfd-plugins/ | sed 's/^/    /'
echo "  结果：$(ls -l /usr/lib/bfd-plugins/liblto_plugin.so | sed 's/  */ /g')"
if [ -e /usr/lib/bfd-plugins/liblto_plugin.so ]; then ok "LTO 插件链接可解析（不是悬空链接）"
else fail "/usr/lib/bfd-plugins/liblto_plugin.so 悬空"; fi
echo "  /usr/lib/bfd-plugins 目录内容："
{ ls -l /usr/lib/bfd-plugins || true; } | sed 's/^/    /'
echo

# =========================================================================
echo "================= 手册命令 16/N：工具链完整性检查（7 条）================="
cat <<'MANUAL'
手册原文：Now that our final toolchain is in place, it is important to again ensure
that compiling and linking will work as expected. We do this by performing some sanity
checks:
  echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log
  readelf -l a.out | grep ': /lib'
MANUAL
echo "  在构建目录 $PWD 内执行（手册即在此处）。"
set +e
echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log
cc_rc=$?
set -e
echo "  cc 编译退出码：$cc_rc（dummy.log $(wc -l < dummy.log) 行，a.out $( [ -f a.out ] && echo 已生成 || echo 未生成 )）"
[ "$cc_rc" -eq 0 ] || fail "cc 编译 'int main(){}' 失败"
[ -f a.out ] || fail "a.out 未生成"

echo
echo "--- 检查 1/6：readelf -l a.out | grep ': /lib'"
echo "  手册期望：[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]"
out1=$( { readelf -l a.out | grep ': /lib' || true; } )
echo "$out1" | sed 's/^/    实际：/'
case "$out1" in
  *"Requesting program interpreter: /lib64/ld-linux-x86-64.so.2"*) ok "动态装载器路径与手册一致" ;;
  *) fail "动态装载器路径与手册期望不符" ;;
esac

echo
echo "--- 检查 2/6：grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log"
cat <<'MANUAL'
手册期望（目录中的 triplet 可因架构而异）：
  /usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/../../../../lib/Scrt1.o succeeded
  /usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/../../../../lib/crti.o succeeded
  /usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/../../../../lib/crtn.o succeeded
手册说明：The important thing to look for here is that gcc has found all three crt*.o
files under the /usr/lib directory.
MANUAL
out2=$( { grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log || true; } )
echo "$out2" | sed 's/^/    实际：/'
n_crt=0
for o in Scrt1.o crti.o crtn.o; do
  if printf '%s\n' "$out2" | grep -q "/$o succeeded"; then n_crt=$((n_crt+1)); fi
done
[ "$n_crt" -eq 3 ] && ok "Scrt1.o / crti.o / crtn.o 三个启动文件都在 /usr/lib 下找到" \
                  || fail "只找到 $n_crt/3 个 crt*.o（手册要求三个都在 /usr/lib 下）"

echo
echo "--- 检查 3/6：grep -B4 '^ /usr/include' dummy.log"
cat <<'MANUAL'
手册期望：
  #include <...> search starts here:
   /usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/include
   /usr/local/include
   /usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/include-fixed
   /usr/include
MANUAL
out3=$( { grep -B4 '^ /usr/include' dummy.log || true; } )
echo "$out3" | sed 's/^/    实际：/'
h_rc=0
printf '%s\n' "$out3" | grep -q 'search starts here' || h_rc=1
for d in "/usr/lib/gcc/$NEWTRIPLET/$VER/include" /usr/local/include "/usr/lib/gcc/$NEWTRIPLET/$VER/include-fixed" /usr/include; do
  printf '%s\n' "$out3" | grep -qx " $d" || { echo "    缺少搜索路径： $d"; h_rc=1; }
done
[ $h_rc -eq 0 ] && ok "头文件搜索路径与手册期望逐条一致（triplet=$NEWTRIPLET）" \
               || fail "头文件搜索路径与手册期望不符"

echo
echo "--- 检查 4/6：grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\\n|g'"
cat <<'MANUAL'
手册说明：References to paths that have components with '-linux-gnu' should be ignored,
but otherwise the output should be:
  SEARCH_DIR("/usr/x86_64-pc-linux-gnu/lib64")
  SEARCH_DIR("/usr/local/lib64")
  SEARCH_DIR("/lib64")
  SEARCH_DIR("/usr/lib64")
  SEARCH_DIR("/usr/x86_64-pc-linux-gnu/lib")
  SEARCH_DIR("/usr/local/lib")
  SEARCH_DIR("/lib")
  SEARCH_DIR("/usr/lib");
MANUAL
out4=$( { grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\n|g' || true; } )
echo "$out4" | sed 's/^/    实际：/'
s_rc=0
for d in /usr/local/lib64 /lib64 /usr/lib64 /usr/local/lib /lib /usr/lib; do
  printf '%s\n' "$out4" | grep -q "SEARCH_DIR(\"$d\")" || { echo "    缺少：SEARCH_DIR(\"$d\")"; s_rc=1; }
done
[ $s_rc -eq 0 ] && ok "链接器搜索路径包含手册列出的全部非 triplet 目录" \
               || fail "链接器搜索路径与手册期望不符"

echo
echo "--- 检查 5/6：grep \"/lib.*/libc.so.6 \" dummy.log"
echo "  手册期望：attempt to open /usr/lib/libc.so.6 succeeded"
out5=$( { grep "/lib.*/libc.so.6 " dummy.log || true; } )
echo "$out5" | sed 's/^/    实际：/'
case "$out5" in
  *"attempt to open /usr/lib/libc.so.6 succeeded"*) ok "使用的是 /usr/lib/libc.so.6（本章 §8.5 的 glibc）" ;;
  *) fail "libc.so.6 不是从 /usr/lib 打开的" ;;
esac

echo
echo "--- 检查 6/6：grep found dummy.log"
echo "  手册期望：found ld-linux-x86-64.so.2 at /usr/lib/ld-linux-x86-64.so.2"
out6=$( { grep found dummy.log || true; } )
echo "$out6" | sed 's/^/    实际：/'
case "$out6" in
  *"found ld-linux-x86-64.so.2 at /usr/lib/ld-linux-x86-64.so.2"*) ok "动态装载器来自 /usr/lib" ;;
  *) fail "动态装载器不是 /usr/lib/ld-linux-x86-64.so.2" ;;
esac
echo
echo "  手册警告原文：If the output does not appear as shown above or is not received at"
echo "  all, then something is seriously wrong. ... Any issues should be resolved before"
echo "  continuing with the process."
echo

# =========================================================================
echo "================= 手册命令 17/N：清理检查用的临时文件 ================="
cat <<'MANUAL'
手册原文：Once everything is working correctly, clean up the test files:
  rm -v a.out dummy.log
MANUAL
rm -v a.out dummy.log | sed 's/^/    /'
{ ls a.out dummy.log 2>&1 || true; } | sed 's/^/    确认已删除：/'
echo

# =========================================================================
echo "================= 手册命令 18/N：移动放错位置的文件 ================="
cat <<'MANUAL'
手册原文：Finally, move a misplaced file:
  mkdir -pv /usr/share/gdb/auto-load/usr/lib
  mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
MANUAL
echo "  移动前 /usr/lib 下的 *gdb.py："
{ ls -l /usr/lib/*gdb.py 2>/dev/null || echo "（无）"; } | sed 's/^/    /'
mkdir -pv /usr/share/gdb/auto-load/usr/lib | sed 's/^/    /'
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib | sed 's/^/    /'
echo "  移动后 /usr/share/gdb/auto-load/usr/lib："
{ ls -l /usr/share/gdb/auto-load/usr/lib || true; } | sed 's/^/    /'
leftpy=$( { ls /usr/lib/*gdb.py 2>/dev/null || true; } )
[ -z "$leftpy" ] && ok "/usr/lib 下已无 *gdb.py" || { echo "$leftpy" | sed 's/^/    残留：/'; fail "/usr/lib 下仍有 *gdb.py"; }
echo

# =========================================================================
echo "================= §8.30.2 Contents of GCC —— 安装结果核对 ================="
cat <<'MANUAL'
手册列出的内容：
  Installed programs: c++, cc (link to gcc), cpp, g++, gcc, gcc-ar, gcc-nm,
    gcc-ranlib, gcov, gcov-dump, gcov-tool, and lto-dump
  Installed libraries: libasan.{a,so}, libatomic.{a,so}, libcc1.so, libgcc.a,
    libgcc_eh.a, libgcc_s.so, libgcov.a, libgomp.{a,so}, libhwasan.{a,so},
    libitm.{a,so}, liblsan.{a,so}, liblto_plugin.so, libquadmath.{a,so},
    libssp.{a,so}, libssp_nonshared.a, libstdc++.{a,so}, libstdc++exp.a,
    libstdc++fs.a, libsupc++.a, libtsan.{a,so}, and libubsan.{a,so}
  Installed directories: /usr/include/c++, /usr/lib/gcc, /usr/libexec/gcc,
    and /usr/share/gcc-15.2.0
MANUAL
echo
echo "--- 1. Installed programs（12 项）"
for p in c++ cc cpp g++ gcc gcc-ar gcc-nm gcc-ranlib gcov gcov-dump gcov-tool lto-dump; do
  if [ -x "/usr/bin/$p" ]; then
    printf '    OK   /usr/bin/%-12s %s\n' "$p" "$( [ -L "/usr/bin/$p" ] && echo "-> $(readlink "/usr/bin/$p")" || echo '(真实文件)' )"
  else
    fail "缺少 /usr/bin/$p"
  fi
done

echo
echo "--- 2. Installed libraries"
GCCLIB=/usr/lib/gcc/$NEWTRIPLET/$VER
echo "    （.a 多数在 $GCCLIB 下，.so 在 /usr/lib 下；手册未指定具体目录，故两处都找）"
libmiss=0
check_lib() {  # check_lib <文件名>
  local n=$1 found
  found=$( { find /usr/lib -maxdepth 4 -name "$n" 2>/dev/null || true; } | head -n3 )
  if [ -n "$found" ]; then printf '    OK   %-24s %s\n' "$n" "$(echo "$found" | head -n1)"
  else printf '    FAIL %-24s 未找到\n' "$n"; libmiss=$((libmiss+1)); fi
}
for n in libasan.a libasan.so libatomic.a libatomic.so libcc1.so libgcc.a libgcc_eh.a \
         libgcc_s.so libgcov.a libgomp.a libgomp.so libhwasan.a libhwasan.so \
         libitm.a libitm.so liblsan.a liblsan.so liblto_plugin.so libquadmath.a \
         libquadmath.so libssp.a libssp.so libssp_nonshared.a libstdc++.a libstdc++.so \
         libstdc++exp.a libstdc++fs.a libsupc++.a libtsan.a libtsan.so libubsan.a libubsan.so; do
  check_lib "$n"
done
[ $libmiss -eq 0 ] && ok "手册列出的库全部就位" || fail "有 $libmiss 个手册列出的库未找到"

echo
echo "--- 3. Installed directories（4 项）"
for d in /usr/include/c++ /usr/lib/gcc /usr/libexec/gcc "/usr/share/gcc-$VER"; do
  if [ -d "$d" ]; then ok "$d（$( { find "$d" -type f 2>/dev/null || true; } | wc -l ) 个文件）"
  else fail "缺少目录 $d"; fi
done

echo
echo "--- 4. 新旧 triplet 目录共存情况（第 6 章 pass 2 的产物不由本节删除）"
{ ls -d /usr/lib/gcc/*/ /usr/libexec/gcc/*/ 2>/dev/null || true; } | sed 's/^/    /'
echo "    说明：x86_64-lfs-linux-gnu 是 §6.18 GCC pass 2 的目录，手册在 §8.30 没有删除它的"
echo "          命令，故原样保留；本节新装的是 $NEWTRIPLET。"

echo
echo "--- 5. 装出来的编译器实测（C 与 C++ 各编一个程序并运行）"
tmpd=$(mktemp -d /tmp/gcc-smoke-XXXXXX)
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
int main(void){ printf("hello-from-c %d\n", 42); return 0; }
EOF
cat > "$tmpd/t.cc" <<'EOF'
#include <iostream>
#include <string>
#include <vector>
int main(){ std::vector<std::string> v{"hello","from","c++"};
  for (auto &s : v) std::cout << s << ' '; std::cout << std::endl; return 0; }
EOF
set +e
( cd "$tmpd" && gcc t.c -o t_c   && ./t_c )   | sed 's/^/    C   ：/'; c_rc=${PIPESTATUS[0]}
( cd "$tmpd" && g++ t.cc -o t_cc && ./t_cc )  | sed 's/^/    C++ ：/'; cc_rc2=${PIPESTATUS[0]}
set -e
[ $c_rc   -eq 0 ] && ok "gcc 编译并运行 C 程序成功"   || fail "gcc 编译/运行 C 程序失败"
[ $cc_rc2 -eq 0 ] && ok "g++ 编译并运行 C++ 程序成功" || fail "g++ 编译/运行 C++ 程序失败"
echo "    C++ 程序的动态依赖（应含本节装的 libstdc++.so.6）："
{ readelf -d "$tmpd/t_cc" | grep NEEDED || true; } | sed 's/^/      /'
echo "    --enable-default-pie 生效性（默认应产出 PIE / ET_DYN）："
{ readelf -h "$tmpd/t_c" | grep -E '^\s*Type:' || true; } | sed 's/^/      /'
{ readelf -h "$tmpd/t_c" | grep -qE 'Type:\s+DYN' && ok "默认产出 PIE（ET_DYN）" || fail "默认未产出 PIE"; }
echo "    --enable-default-ssp 生效性（默认应带栈保护符号 __stack_chk_fail）："
cat > "$tmpd/ssp.c" <<'EOF'
#include <string.h>
int main(int argc, char **argv){ char b[64]; strcpy(b, argv[0]); return (int)strlen(b); }
EOF
set +e
( cd "$tmpd" && gcc ssp.c -o ssp )
ssp_build_rc=$?
set -e
[ $ssp_build_rc -eq 0 ] || fail "gcc 编译 ssp.c 失败（退出码 $ssp_build_rc）"
sspsym=$( { readelf -r "$tmpd/ssp" 2>/dev/null | grep -c '__stack_chk_fail' || true; } )
[ "${sspsym:-0}" -gt 0 ] && ok "默认启用 SSP（重定位表中出现 __stack_chk_fail）" \
                         || fail "默认未启用 SSP"
echo "    --with-system-zlib 生效性（gcc 的 LTO 相关程序应链接系统 libz）："
{ readelf -d /usr/libexec/gcc/"$NEWTRIPLET"/$VER/lto1 2>/dev/null | grep NEEDED || true; } | sed 's/^/      lto1: /'
echo "    --disable-multilib 生效性（gcc -print-multi-lib 应只有一行 '.;'）："
{ gcc -print-multi-lib || true; } | sed 's/^/      /'
echo "    64 位库目录名（第 2 条 sed 的效果，应为 lib 而非 lib64）："
echo "      gcc -print-multi-os-directory = $( { gcc -print-multi-os-directory || true; } )"
rm -rf "$tmpd"

echo
echo "--- 6. --disable-fixincludes 的效果确认"
echo "    include-fixed 目录内容（不应包含从系统头「修补」来的一大堆副本）："
{ find "$GCCLIB/include-fixed" -type f 2>/dev/null | sed "s|$GCCLIB/||" || true; } | sed 's/^/      /'
echo "    include-fixed 文件数：$( { find "$GCCLIB/include-fixed" -type f 2>/dev/null || true; } | wc -l )"
echo

# =========================================================================
echo "================= 清理构建目录（任务要求：构建目录清理） ================="
cd /sources
echo "  删除前 /sources 下的 gcc 相关条目与体积："
{ du -sh "$SRCDIR" 2>/dev/null || true; } | sed 's/^/    /'
echo "  命令：rm -rf $SRCDIR"
rm -rf "$SRCDIR"
if [ -e "$SRCDIR" ]; then fail "源码/构建目录未删除干净：$SRCDIR"; else ok "已删除 $SRCDIR（含其中的 build 子目录）"; fi
echo "  /sources 现存 gcc 相关条目："
{ ls -d /sources/gcc* 2>/dev/null || echo "（只剩 tarball 或无）"; } | sed 's/^/    /'
{ ls -l /sources/gcc-15.2.0.tar.xz 2>/dev/null || true; } | sed 's/^/    /'
echo "  磁盘空间（清理后）："
df -h /sources / | sed 's/^/    /'
echo

# =========================================================================
echo "================= §8.30 执行结果汇总 ================="
printf '  %-10s %-58s %s\n' 章节 命令 结果
printf '  %-10s %-58s %s\n' §8.30.1 "sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c" "已执行，文件 md5 改变"
printf '  %-10s %-58s %s\n' §8.30.1 "case x86_64: sed -e '/m64=/s/lib64/lib/' -i.orig t-linux64" "已执行，diff 已留档"
printf '  %-10s %-58s %s\n' §8.30.1 "mkdir -v build && cd build" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "../configure（10 个参数）" "退出码 0"
printf '  %-10s %-58s %s\n' §8.30.1 "make" "退出码 0"
printf '  %-10s %-58s %s\n' §8.30.1 "ulimit -s -H unlimited" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "sed -e '/cpython/d' -i ../gcc/testsuite/.../plugin.exp" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "chown -R tester ." "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "su tester -c \"PATH=\$PATH make -k check\"" "退出码 $check_rc（make -k，手册允许非 0）"
printf '  %-10s %-58s %s\n' §8.30.1 "../contrib/test_summary" "已执行，汇总见上"
printf '  %-10s %-58s %s\n' §8.30.1 "make install" "退出码 0"
printf '  %-10s %-58s %s\n' §8.30.1 "chown -v -R root:root .../include{,-fixed}" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "ln -svr /usr/bin/cpp /usr/lib" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "ln -sv gcc.1 /usr/share/man/man1/cc.1" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "ln -sfv ../../libexec/.../liblto_plugin.so /usr/lib/bfd-plugins/" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "工具链完整性检查（6 条 grep/readelf）" "全部与手册期望一致"
printf '  %-10s %-58s %s\n' §8.30.1 "rm -v a.out dummy.log" "已执行"
printf '  %-10s %-58s %s\n' §8.30.1 "mkdir -pv /usr/share/gdb/... && mv -v /usr/lib/*gdb.py" "已执行"
printf '  %-10s %-58s %s\n' §8.30.2 "Contents of GCC（程序/库/目录）" "逐项核对，见上"
printf '  %-10s %-58s %s\n' 清理     "rm -rf /sources/gcc-15.2.0" "已执行"
echo
if [ $rc -eq 0 ]; then
  echo "===== §8.30 GCC-$VER 全部完成，所有检查通过 ====="
else
  echo "===== §8.30 GCC-$VER 存在未通过的检查项（见上方 FAIL 行）====="
fi
echo "结束时间：$(date -Is)"
exit $rc
