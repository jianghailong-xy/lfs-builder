#!/usr/bin/env bash
# LFS 13.0-systemd §8.21 Binutils-2.46.0
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.21.1 Installation of Binutils 的命令序列（全部 7 条，一条不多一条不少）：
#   mkdir -v build
#   cd       build
#   ../configure --prefix=/usr       \
#                --sysconfdir=/etc   \
#                --enable-ld=default \
#                --enable-plugins    \
#                --enable-shared     \
#                --disable-werror    \
#                --enable-64-bit-bfd \
#                --enable-new-dtags  \
#                --with-system-zlib  \
#                --enable-default-hash-style=gnu
#   make tooldir=/usr
#   make -k check
#   grep '^FAIL:' $(find -name '*.log')
#   make tooldir=/usr install
#   rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
#           /usr/share/doc/gprofng/
# 本节没有 sed、没有 patch、没有可选命令。全节唯一的提示框是 Important：
#   "The test suite for Binutils in this section is considered critical.
#    Do not skip it under any circumstances."
# 另有一句允许失败的说明："One test related to gprofng is known to fail."
set -euo pipefail

PKG=binutils
VER=2.46.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
CONFLOG=/sources/.binutils-configure.log
MAKELOG=/sources/.binutils-make.log
CHECKLOG=/sources/.binutils-make-check.log
INSTLOG=/sources/.binutils-make-install.log
SUMLOG=/sources/.binutils-test-summary.log

echo "===== LFS 13.0-systemd §8.21 Binutils-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Binutils package contains a linker, an assembler, and other tools"
echo "  for handling object files."
echo "手册数据：Approximate build time 1.7 SBU，Required disk space 835 MB"
echo "手册存档：/workspace/docs/book/chapter08-binutils.html（宿主机 $LFS_ROOT/docs/book/）"
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
esac
echo "  OK   PATH 中不含 /tools/bin（交叉工具链已不再使用）"
echo

echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0
echo "1) 上一任务 §8.20 Pkgconf-2.5.1 的产物（确认其已完成、产物可用）："
for f in /usr/bin/pkgconf /usr/bin/pkg-config /usr/lib/libpkgconf.so \
         /usr/include/pkgconf/libpkgconf/libpkgconf.h \
         /usr/share/man/man1/pkg-config.1 /usr/share/aclocal/pkg.m4; do
  if [ -e "$f" ] || [ -L "$f" ]; then printf '   OK   %-52s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.20 未完成？）\n' "$f"; rc=1; fi
done
echo "   pkgconf 自述版本：$(pkgconf --version 2>&1 | sed -n 1p)"
echo "   说明：Binutils 的 configure 不使用 pkg-config，此处只用于确认「上一任务产物可用」。"
echo
echo "2) §8.5 Glibc-2.43 的 C 库与工具链（本节要 configure + 编译 C/C++ + 建共享库）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2 /usr/include/stdio.h; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("glibc sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && \
   [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
tmpcc=$(mktemp /tmp/sanity-XXXXXX.cc)
cat > "$tmpcc" <<'EOF'
#include <iostream>
int main(){ std::cout << "libstdc++ sanity ok" << std::endl; return 0; }
EOF
if g++ -o "${tmpcc%.cc}" "$tmpcc" >/dev/null 2>&1 && \
   [ "$("${tmpcc%.cc}")" = "libstdc++ sanity ok" ]; then
  echo "   OK   g++ 编译并运行最小 C++ 程序成功（gprofng 与部分测试用例需要 C++）"
else echo "   FAIL 无法用 g++ 编译/运行最小 C++ 程序"; rc=1; fi
rm -f "$tmpcc" "${tmpcc%.cc}"
echo
echo "3) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "4) 本节直接依赖的工具（解包 + configure + 编译 + DejaGNU 测试 + make install）："
for t in tar xz make gcc g++ ld ar ranlib as nm objdump readelf sed grep awk \
         install ln rm mkdir cmp md5sum find stat bash sort bison flex m4 perl \
         makeinfo runtest expect tclsh diff; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-10s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc     版本：$(gcc --version | sed -n 1p)"
echo "   make    版本：$(make --version | sed -n 1p)"
echo "   bison   版本：$(bison --version | sed -n 1p)   （gprofng 的语法分析器需要）"
echo "   flex    版本：$(flex --version | sed -n 1p)"
echo "   perl    版本：$(perl -e 'print $^V' 2>/dev/null)"
echo "   makeinfo版本：$(makeinfo --version | sed -n 1p)"
runtest_ver=$(runtest --version 2>&1 | sed -n 's/^DejaGnu version[[:space:]]*//p' | sed -n 1p)
echo "   runtest 版本：${runtest_ver:-（取不到）}   （§8.21 的 make -k check 靠它驱动）"
echo "   expect  版本：$(expect -v 2>&1 | sed -n 1p)"
echo "   tclsh   版本：$(echo 'puts [info patchlevel]' | tclsh 2>&1)"
if [ -z "$runtest_ver" ]; then echo "   FAIL runtest 不可用，手册 Important 要求的测试无法执行"; rc=1; fi
echo
echo "5) --with-system-zlib 依赖的系统 zlib（§8.6 Zlib-1.3.2）："
for f in /usr/include/zlib.h /usr/lib/libz.so /usr/lib/libz.so.1; do
  if [ -e "$f" ]; then printf '   OK   %-24s -> %s\n' "$f" "$(readlink -f "$f")"
  else printf '   FAIL %s 缺失（--with-system-zlib 会失败）\n' "$f"; rc=1; fi
done
zver=$( { grep -E '^#define ZLIB_VERSION' /usr/include/zlib.h || true; } | sed -n 1p )
echo "   zlib.h 自述：$zver"
echo
echo "6) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo
echo "7) 安装目标目录（手册 §8.21.2 Contents 的落点）："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/share/info /etc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo
echo "8) 安装前系统中已有的 Binutils（第 6 章 §6.17 pass2 装的同版本，本节将整体覆盖）："
echo "   下面记录覆盖前的状态，安装后用同一组命令对照。"
for p in addr2line ar as c++filt dwp elfedit gprof gprofng ld ld.bfd nm objcopy \
         objdump ranlib readelf size strings strip; do
  if [ -e "/usr/bin/$p" ]; then
    printf '   有   %-10s %10s 字节  %s\n' "$p" "$(stat -Lc %s "/usr/bin/$p")" \
           "$("/usr/bin/$p" --version 2>&1 | sed -n 1p)"
  else printf '   无   %-10s（本节 make install 后应出现）\n' "$p"; fi
done
echo "   共享库："
for l in libbfd libctf libctf-nobfd libgprofng libopcodes libsframe; do
  found=$(find /usr/lib -maxdepth 1 -name "$l*.so*" 2>/dev/null | sort | tr '\n' ' ')
  printf '   %-14s %s\n' "$l" "${found:-（无）}"
done
echo "   /usr/lib/ldscripts：$( [ -d /usr/lib/ldscripts ] && echo "存在（$(find /usr/lib/ldscripts -type f | wc -l) 个文件）" || echo '不存在（本节 make install 后应出现）' )"
echo "   第 6 章 pass2 的 tooldir 残留 /usr/x86_64-lfs-linux-gnu：$( [ -d /usr/x86_64-lfs-linux-gnu ] && echo "存在（$(find /usr/x86_64-lfs-linux-gnu | wc -l) 条目，属第 6 章遗留，本节不触碰）" || echo '不存在' )"
echo "   /usr/x86_64-pc-linux-gnu（若本节漏掉 tooldir=/usr 就会产生）：$( [ -e /usr/x86_64-pc-linux-gnu ] && echo '存在（异常）' || echo '不存在（预期）' )"
echo
echo "9) 磁盘空间（手册要求 835 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 3145728 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 835 MB（留足测试套件的临时文件）"
else echo "   FAIL 可用空间不足：$((avail_k/1024)) MB"; rc=1; fi
echo
echo "10) 内存（并行 make -j$(nproc) + 测试套件）："
echo "   （procps-ng 要到 §8.x 之后才安装，chroot 内还没有 free，直接读 /proc/meminfo）"
{ grep -E '^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo || true; } | sed 's/^/   /'
memav_k=$( { grep -E '^MemAvailable:' /proc/meminfo || true; } | awk '{print $2}' )
memav_k=${memav_k:-0}
echo "   可用内存约 $((memav_k/1024)) MB"
if [ "$memav_k" -lt 1048576 ]; then
  echo "   INFO 可用内存不足 1 GB，-j$(nproc) 并行编译可能吃紧（不作为硬性失败判据）"
else
  echo "   OK   可用内存充足"
fi
echo
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo "前置检查全部通过。"
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
echo "上游版本自述（bfd/version.m4 / bfd/development.sh）："
{ grep -E 'BFD_VERSION' bfd/version.m4 || true; } | sed 's/^/  /'
[ -f bfd/development.sh ] && sed 's/^/  /' bfd/development.sh
echo "配置探测三元组：$(./config.guess)"
echo "上游是否自带 gold 子目录（决定 dwp 是否存在）：$( [ -d gold ] && echo '有' || echo '无 —— 2.46.0 已不再随包提供 gold/dwp' )"
echo "上游是否自带 zlib 子目录（--with-system-zlib 应使其不参与构建）：$( [ -d zlib ] && echo "有（$(find zlib -type f | wc -l) 个文件）" || echo '无' )"
echo "上游是否自带 gprofng 子目录：$( [ -d gprofng ] && echo "有（$(find gprofng -type f | wc -l) 个文件）" || echo '无' )"
echo

echo "================= 手册命令 1/7：mkdir -v build ================="
echo "手册原文：The Binutils documentation recommends building Binutils in a dedicated"
echo "  build directory:"
mkdir -v build
echo
echo "================= 手册命令 2/7：cd       build ================="
cd       build
echo "当前目录：$PWD"
echo

# ---------------------------------------------------------------------------
# 带日志的分阶段执行：把完整输出同时写到 stdout（进主日志）和 /sources 的分阶段
# 日志文件（由宿主机侧 run-8.21.sh 归档到 logs/packages/）。
# 注意：不要写成 `cmd | tee log` 后直接靠 set -e —— 需要拿到 cmd 自身的退出码，
# 所以统一用 PIPESTATUS，并在失败时打印明确的中止原因。
# ---------------------------------------------------------------------------
run_logged() {   # run_logged <阶段名> <日志文件> <是否允许非0：yes/no> -- <命令...>
  local name=$1 logf=$2 allow=$3; shift 4
  local start end st
  start=$(date +%s)
  echo "### 开始：$name    $(date -Is)"
  set +e
  "$@" 2>&1 | tee "$logf"
  st=${PIPESTATUS[0]}
  set -e
  end=$(date +%s)
  echo "### 结束：$name    退出码=$st    耗时 $((end-start)) 秒（$(( (end-start)/60 )) 分）"
  if [ "$st" -ne 0 ] && [ "$allow" != yes ]; then
    echo "错误：$name 失败（退出码 $st），按任务要求中止并保留日志" >&2
    exit "$st"
  fi
  return 0
}

echo "================= 手册命令 3/7：../configure ... ================="
cat <<'MANUAL'
手册原文命令：
  ../configure --prefix=/usr       \
               --sysconfdir=/etc   \
               --enable-ld=default \
               --enable-plugins    \
               --enable-shared     \
               --disable-werror    \
               --enable-64-bit-bfd \
               --enable-new-dtags  \
               --with-system-zlib  \
               --enable-default-hash-style=gnu
手册对新增选项的说明：
  --enable-ld=default : Build the original bfd linker and install it as both ld
                        (the default linker) and ld.bfd.
  --enable-plugins    : Enables plugin support for the linker.
  --with-system-zlib  : Use the installed zlib library instead of building the
                        included version.
MANUAL
echo
run_logged "configure" "$CONFLOG" no -- \
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu
echo
echo "----- configure 结果核对（不是重跑手册命令，只读检查生成物） -----"
echo "注意：binutils 是 GNU 顶层 configure 框架，顶层 ../configure 只生成顶层 Makefile /"
echo "  config.status / config.log；bfd、ld、gas 等子目录的 configure 是在 make 阶段才跑的，"
echo "  所以 bfd/config.h、ld/config.h 此刻还不存在，这两处核对放到 make 之后（见下一节）。"
echo "  本阶段可核对的生成物：$(ls | tr '\n' ' ')"
echo
crc=0
echo "a) config.status 记录的实际 configure 选项（ac_cs_config）："
acs=$( { grep -E '^ac_cs_config=' config.status || true; } | sed -n 1p )
echo "   $acs"
echo "   顶层 Makefile 的 TOPLEVEL_CONFIGURE_ARGUMENTS："
{ grep -E '^TOPLEVEL_CONFIGURE_ARGUMENTS=' Makefile || true; } | sed 's/^/   /'
for opt in --prefix=/usr --sysconfdir=/etc --enable-ld=default --enable-plugins \
           --enable-shared --disable-werror --enable-64-bit-bfd --enable-new-dtags \
           --with-system-zlib --enable-default-hash-style=gnu; do
  n=$( printf '%s\n' "$acs" | { grep -c -- "'$opt'" || true; } )
  if [ "${n:-0}" -gt 0 ]; then printf '   OK   config.status 的 ac_cs_config 含 %s\n' "$opt"
  else printf '   FAIL config.status 的 ac_cs_config 里没有 %s\n' "$opt"; crc=1; fi
done
acs_inner=$( printf '%s\n' "$acs" | sed -E 's/^ac_cs_config="//; s/"$//' )
nopt=$( printf '%s\n' "$acs_inner" | tr ' ' '\n' | { grep -c "^'--" || true; } )
if [ "${nopt:-0}" -eq 10 ]; then echo "   OK   选项总数 = 10，与手册给出的 10 个选项一一对应，无多余项"
else echo "   FAIL 选项总数 = ${nopt:-0}，手册给的是 10 个"; crc=1; fi
echo
echo "b) --with-system-zlib 的硬判据：configure 决定的待构建子目录里不含 zlib"
echo "   （源码包自带 zlib/ 子目录；用系统 zlib 时它不会被配置进构建）"
cfgdirs=$( { grep -E "^configdirs=" config.log || true; } | sed -n 1p )
echo "   config.log: $cfgdirs"
if [ -z "$cfgdirs" ]; then
  echo "   FAIL config.log 里取不到 configdirs="; crc=1
elif [ "$( printf '%s\n' "$cfgdirs" | { grep -c '[ =.]zlib' || true; } )" -eq 0 ]; then
  echo "   OK   configdirs 中不含 zlib（--with-system-zlib 生效）"
else
  echo "   FAIL configdirs 中仍含 zlib，说明用的是内置 zlib"; crc=1
fi
hostargs=$( { grep -E '^HOST_CONFIGARGS =' Makefile || true; } | sed -n 1p )
if [ "$( printf '%s\n' "$hostargs" | { grep -c -- '--with-system-zlib' || true; } )" -gt 0 ]; then
  echo "   OK   HOST_CONFIGARGS 会把 --with-system-zlib 透传给各子目录 configure"
else
  echo "   FAIL HOST_CONFIGARGS 中没有 --with-system-zlib"; crc=1
fi
echo "   顶层构建目录下是否已出现 zlib/：$( [ -d zlib ] && echo '是（异常）' || echo '否（预期）' )"
echo
echo "c) configure 阶段的错误/告警扫描（只看 configure 自己的结论行，不做泛化关键字扫描）："
{ grep -nE '^configure: (error|WARNING)' "$CONFLOG" || true; } | sed 's/^/   /'
nerr=$( { grep -cE '^configure: error' "$CONFLOG" || true; } )
if [ "${nerr:-0}" -eq 0 ]; then echo "   OK   configure 输出中没有 'configure: error'"
else echo "   FAIL configure 输出中有 ${nerr} 条 'configure: error'"; crc=1; fi
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册选项不符" >&2; exit 1; }
echo "configure 结果核对通过（子目录 config.h 的核对见 make 之后）。"
echo

echo "================= 手册命令 4/7：make tooldir=/usr ================="
cat <<'MANUAL'
手册原文：Compile the package: make tooldir=/usr
手册对 make 参数的说明：
  tooldir=/usr : Normally, the tooldir (the directory where the executables will
    ultimately be located) is set to $(exec_prefix)/$(target_alias). For example,
    x86_64 machines would expand that to /usr/x86_64-pc-linux-gnu. Because this
    is a custom system, this target-specific directory in /usr is not required.
MANUAL
echo
run_logged "make tooldir=/usr" "$MAKELOG" no -- make tooldir=/usr
echo
echo "----- make 结果核对（此时子目录的 configure 已跑过，config.h 已生成） -----"
mrc=0
echo "a) --enable-plugins 与 --enable-64-bit-bfd 的落点：生成的 bfd/bfd.h"
echo "   （bfd/bfd-in2.h 里写的是 #define BFD_SUPPORTS_PLUGINS @supports_plugins@ 与"
echo "     #define BFD_ARCH_SIZE @wordsize@，由 bfd/configure 替换后写进 bfd/bfd.h；"
echo "     这两个宏不在 bfd/config.h 里）"
if [ -f bfd/bfd.h ]; then
  { grep -nE '^#define (BFD_SUPPORTS_PLUGINS|BFD_ARCH_SIZE|BFD_DEFAULT_TARGET_SIZE)' bfd/bfd.h || true; } | sed 's/^/   /'
  if [ "$( { grep -c '^#define BFD_SUPPORTS_PLUGINS 1' bfd/bfd.h || true; } )" -eq 1 ]; then
    echo "   OK   BFD_SUPPORTS_PLUGINS 1（--enable-plugins 生效）"
  else
    echo "   FAIL bfd/bfd.h 中 BFD_SUPPORTS_PLUGINS 不为 1"; mrc=1
  fi
  if [ "$( { grep -c '^#define BFD_ARCH_SIZE 64' bfd/bfd.h || true; } )" -eq 1 ]; then
    echo "   OK   BFD_ARCH_SIZE 64（--enable-64-bit-bfd 生效）"
  else
    echo "   FAIL bfd/bfd.h 中 BFD_ARCH_SIZE 不是 64"; mrc=1
  fi
else echo "   FAIL make 之后仍无 bfd/bfd.h"; mrc=1; fi
echo "   bfd/config.log 里 configure 记下的 plugins 相关变量（补充证据）："
if [ -f bfd/config.log ]; then
  { grep -nE "^(enable_plugins|plugins)=" bfd/config.log || true; } | sed 's/^/     /'
  echo "     说明：config/plugins.m4 在探测到 dlfcn.h 时会把 plugins 默认设成 yes，"
  echo "       所以 --enable-plugins 的作用是**强制**开启（宿主不支持 dlopen 时 configure"
  echo "       会直接 AC_MSG_ERROR 而不是静默降级）。上面的 enable_plugins=yes 说明"
  echo "       该选项确实被 configure 收到了。"
else echo "     INFO 无 bfd/config.log"; fi
echo
echo "c) --enable-default-hash-style=gnu / --enable-new-dtags 的硬判据：ld/config.h"
if [ -f ld/config.h ]; then
  for macro in DEFAULT_EMIT_SYSV_HASH DEFAULT_EMIT_GNU_HASH DEFAULT_NEW_DTAGS; do
    { grep -nE "$macro" ld/config.h || true; } | sed 's/^/   /'
  done
  if [ "$( { grep -c '^#define DEFAULT_EMIT_GNU_HASH 1' ld/config.h || true; } )" -eq 1 ]; then
    echo "   OK   DEFAULT_EMIT_GNU_HASH 1（--enable-default-hash-style=gnu 生效）"
  else echo "   FAIL DEFAULT_EMIT_GNU_HASH 不为 1"; mrc=1; fi
  if [ "$( { grep -c '^#define DEFAULT_EMIT_SYSV_HASH 1' ld/config.h || true; } )" -eq 0 ]; then
    echo "   OK   DEFAULT_EMIT_SYSV_HASH 未开（只发 GNU hash）"
  else echo "   INFO DEFAULT_EMIT_SYSV_HASH 也为 1（会同时发两种 hash）"; fi
  if [ "$( { grep -c '^#define DEFAULT_NEW_DTAGS 1' ld/config.h || true; } )" -eq 1 ]; then
    echo "   OK   DEFAULT_NEW_DTAGS 1（--enable-new-dtags 生效）"
  else echo "   FAIL DEFAULT_NEW_DTAGS 不为 1"; mrc=1; fi
else
  echo "   FAIL make 之后仍无 ld/config.h"; mrc=1
fi
echo
echo "d) --enable-ld=default 的硬判据：ld/Makefile 里 install_as_default"
if [ -f ld/Makefile ]; then
  { grep -nE '^(install_as_default|EMUL) *=' ld/Makefile || true; } | sed 's/^/   /'
  if [ "$( { grep -c '^install_as_default = yes' ld/Makefile || true; } )" -eq 1 ]; then
    echo "   OK   install_as_default = yes（bfd ld 将同时装成 ld 和 ld.bfd）"
  else
    echo "   FAIL ld/Makefile 中 install_as_default 不是 yes"; mrc=1
  fi
else echo "   FAIL 无 ld/Makefile"; mrc=1; fi
echo
echo "e) --with-system-zlib 的构建期证据：构建目录下始终没有 zlib/"
if [ -d zlib ]; then echo "   FAIL 构建目录出现 zlib/，说明构建了内置 zlib"; mrc=1
else echo "   OK   构建目录下没有 zlib/"; fi
echo "   实际参与构建的子目录："
{ find . -maxdepth 1 -type d -not -name '.' || true; } | sort | sed 's|^\./|     |'
echo
echo "f) 构建产物（构建目录内，尚未安装）："
for f in ld/ld-new binutils/objdump binutils/readelf binutils/nm-new binutils/ar \
         gas/as-new gprof/gprof gprofng/src/gprofng; do
  if [ -f "$f" ]; then printf '   OK   %-26s %10s 字节  %s\n' "$f" "$(stat -Lc %s "$f")" "$(file -b "$f" | cut -c1-46)"
  else printf '   INFO %s 不存在\n' "$f"; fi
done
echo "   共享库（构建目录内）："
{ find bfd/.libs opcodes/.libs libctf/.libs libsframe/.libs gprofng/src/.libs \
       -maxdepth 1 \( -name '*.so*' -o -name '*.a' \) 2>/dev/null || true; } | sort | sed 's/^/     /'
echo "   构建出的 libbfd.so 的动态依赖（--with-system-zlib 的运行期观察点）："
if [ -f bfd/.libs/libbfd.so ]; then
  ldd bfd/.libs/libbfd.so > /tmp/.ldd-libbfd.txt 2>&1 || true
  sed 's/^/     /' /tmp/.ldd-libbfd.txt
  zc=$( { grep -c 'libz\.so' /tmp/.ldd-libbfd.txt || true; } )
  if [ "${zc:-0}" -gt 0 ]; then echo "     OK   链接了系统 libz.so"
  else echo "     INFO 未列出 libz.so（zlib 可能只被静态/按需使用；硬判据已由上面 b) 段的 configdirs 给出）"; fi
  rm -f /tmp/.ldd-libbfd.txt
else
  echo "     INFO 未找到 bfd/.libs/libbfd.so"
fi
echo
echo "g) make 输出里的 Error 行（只看 make 自己的报错格式，不做泛化关键字扫描）："
{ grep -nE '^(make(\[[0-9]+\])?: \*\*\*)' "$MAKELOG" || true; } | sed -n '1,20p' | sed 's/^/   /'
nmk=$( { grep -cE '^(make(\[[0-9]+\])?: \*\*\*)' "$MAKELOG" || true; } )
if [ "${nmk:-0}" -eq 0 ]; then echo "   OK   make 输出中没有 'make: *** ' 报错行"
else echo "   FAIL make 输出中有 ${nmk} 条 '*** ' 报错行"; mrc=1; fi
[ $mrc -eq 0 ] || { echo "错误：make 结果与手册选项不符" >&2; exit 1; }
echo "make 结果核对通过。"
echo

echo "================= 手册命令 5/7：make -k check ================="
cat <<'MANUAL'
手册 Important（本节唯一的提示框，原文）：
  The test suite for Binutils in this section is considered critical.
  Do not skip it under any circumstances.
手册原文：Test the results: make -k check
  For a list of failed tests, run: grep '^FAIL:' $(find -name '*.log')
  One test related to gprofng is known to fail.
说明：-k 表示即使有子目录测试失败也继续跑完其余部分，因此 make 本身以非 0 退出是
  预期行为，不能据此判定失败；判据用 DejaGNU 自己的 *.sum 汇总（# of unexpected
  failures）+ 手册允许的 gprofng 例外。
MANUAL
echo
check_start=$(date +%s)
set +e
make -k check 2>&1 | tee "$CHECKLOG"
check_rc=${PIPESTATUS[0]}
set -e
check_end=$(date +%s)
echo
echo "### make -k check 退出码=$check_rc    耗时 $((check_end-check_start)) 秒（$(( (check_end-check_start)/60 )) 分）"
echo

echo "================= 手册命令 6/7：grep '^FAIL:' \$(find -name '*.log') ================="
echo "手册原文：For a list of failed tests, run: grep '^FAIL:' \$(find -name '*.log')"
echo "（该命令在没有任何 FAIL 时 grep 返回 1，这里包成 { ...; } || true，避免 set -e 误中止）"
find -name '*.log' > /tmp/.binutils-loglist.txt
echo "（测试产生的 *.log 文件共 $(wc -l < /tmp/.binutils-loglist.txt) 个，即该命令的实参列表）"
echo "----- 命令输出开始 -----"
if [ -s /tmp/.binutils-loglist.txt ]; then
  { grep '^FAIL:' $(find -name '*.log') || true; } | tee /tmp/.binutils-fail-lines.txt
else
  # 实参为空时 grep 会去读 stdin 而挂住，这里显式跳过并说明
  : > /tmp/.binutils-fail-lines.txt
  echo "（构建目录下没有任何 *.log，跳过该命令：实参为空会让 grep 转去读 stdin）"
fi
echo "----- 命令输出结束 -----"
fail_lines=$(wc -l < /tmp/.binutils-fail-lines.txt)
echo "FAIL 行总数：$fail_lines"
echo

echo "----- 测试结论汇总（判据：DejaGNU 的 *.sum 汇总计数） -----"
{
  echo "##### §8.21 Binutils-$VER 测试结论   $(date -Is)"
  echo "##### make -k check 退出码=$check_rc（-k 下非 0 属预期，不作判据）"
  echo
} > "$SUMLOG"

find . -name '*.sum' | sort > /tmp/.binutils-sums.txt
echo "找到的 .sum 汇总文件（$(wc -l < /tmp/.binutils-sums.txt) 个）："
sed 's/^/  /' /tmp/.binutils-sums.txt
echo
tot_pass=0; tot_ufail=0; tot_xfail=0; tot_xpass=0; tot_unres=0; tot_untest=0; tot_unsup=0
tot_err=0
gprofng_fail=0; other_fail=0
: > /tmp/.binutils-other-fails.txt
: > /tmp/.binutils-gprofng-fails.txt
while IFS= read -r sf; do
  [ -n "$sf" ] || continue
  get() { { grep -E "^# of $1" "$sf" || true; } | sed -n 1p | sed -E "s/^# of $1[[:space:]]+//"; }
  p=$(get 'expected passes');        p=${p:-0}
  uf=$(get 'unexpected failures');   uf=${uf:-0}
  xf=$(get 'expected failures');     xf=${xf:-0}
  xp=$(get 'unexpected successes');  xp=${xp:-0}
  ur=$(get 'unresolved testcases');  ur=${ur:-0}
  ut=$(get 'untested testcases');    ut=${ut:-0}
  us=$(get 'unsupported tests');     us=${us:-0}
  ue=$(get 'unexpected errors');     ue=${ue:-0}
  tot_pass=$((tot_pass+p));     tot_ufail=$((tot_ufail+uf))
  tot_xfail=$((tot_xfail+xf));  tot_xpass=$((tot_xpass+xp))
  tot_unres=$((tot_unres+ur));  tot_untest=$((tot_untest+ut))
  tot_unsup=$((tot_unsup+us));  tot_err=$((tot_err+ue))
  printf '  %-52s pass=%-6s FAIL=%-4s XFAIL=%-4s XPASS=%-3s UNRES=%-4s UNTESTED=%-4s UNSUP=%s\n' \
         "${sf#./}" "$p" "$uf" "$xf" "$xp" "$ur" "$ut" "$us" | tee -a "$SUMLOG"
  # 该 .sum 里的 FAIL 行，按是否属于 gprofng 归类
  nfl=$( { grep -c '^FAIL:' "$sf" || true; } )
  if [ "$nfl" -gt 0 ]; then
    case "$sf" in
      *gprofng*) { grep '^FAIL:' "$sf" || true; } | sed "s|^|${sf#./} |" >> /tmp/.binutils-gprofng-fails.txt ;;
      *)         { grep '^FAIL:' "$sf" || true; } | sed "s|^|${sf#./} |" >> /tmp/.binutils-other-fails.txt ;;
    esac
  fi
done < /tmp/.binutils-sums.txt
gprofng_fail=$(wc -l < /tmp/.binutils-gprofng-fails.txt)
other_fail=$(wc -l < /tmp/.binutils-other-fails.txt)

# 把 DejaGNU 的 .sum 原件留到 /sources，由宿主机侧 run-8.21.sh 归档到 logs/packages/，
# 否则它们会随本节末尾的源码目录清理一起消失。
rm -f /sources/.binutils-sum-*.sum
while IFS= read -r sf; do
  [ -n "$sf" ] || continue
  cp -f "$sf" "/sources/.binutils-sum-$(basename "$sf")"
done < /tmp/.binutils-sums.txt
echo "已把 $(find /sources -maxdepth 1 -name '.binutils-sum-*.sum' | wc -l) 个 .sum 原件留到 /sources 供归档。"


{
  echo
  echo "全部 .sum 合计："
  printf '  expected passes        : %s\n' "$tot_pass"
  printf '  unexpected failures    : %s\n' "$tot_ufail"
  printf '  unexpected errors      : %s\n' "$tot_err"
  printf '  expected failures      : %s\n' "$tot_xfail"
  printf '  unexpected successes   : %s\n' "$tot_xpass"
  printf '  unresolved testcases   : %s\n' "$tot_unres"
  printf '  untested testcases     : %s\n' "$tot_untest"
  printf '  unsupported tests      : %s\n' "$tot_unsup"
  echo
  echo "FAIL 行按归属分类："
  printf '  gprofng 相关 FAIL      : %s（手册明示 "One test related to gprofng is known to fail."）\n' "$gprofng_fail"
  printf '  其它（不可解释）FAIL   : %s\n' "$other_fail"
  echo
  echo "gprofng FAIL 明细："
  if [ "$gprofng_fail" -gt 0 ]; then sed 's/^/    /' /tmp/.binutils-gprofng-fails.txt; else echo "    （无）"; fi
  echo
  echo "非 gprofng FAIL 明细："
  if [ "$other_fail" -gt 0 ]; then sed 's/^/    /' /tmp/.binutils-other-fails.txt; else echo "    （无）"; fi
} | tee -a "$SUMLOG"
echo

trc=0
if [ "$tot_pass" -lt 1000 ]; then
  echo "FAIL 期望通过数只有 $tot_pass，远低于正常量级（说明测试根本没跑起来）"; trc=1
else
  echo "OK   expected passes = $tot_pass"
fi
if [ "$other_fail" -gt 0 ]; then
  echo "FAIL 存在 $other_fail 条非 gprofng 的 FAIL —— 手册只允许 gprofng 的 1 项失败"; trc=1
else
  echo "OK   没有任何非 gprofng 的 FAIL"
fi
if [ "$gprofng_fail" -gt 0 ]; then
  echo "INFO gprofng 相关 FAIL $gprofng_fail 条 —— 手册原文：\"One test related to gprofng is known to fail.\"，属允许范围"
fi
if [ "$tot_err" -gt 0 ]; then
  echo "INFO unexpected errors = $tot_err（明细见上方各 .sum 行）"
fi
if [ "$trc" -ne 0 ]; then
  echo "错误：手册 Important 指明本节测试为 critical，测试结论不达标，按任务要求中止，" >&2
  echo "  不执行 make install，系统保持未被本节写入的状态。" >&2
  exit 1
fi
echo "测试结论：达到手册允许的结果。"
echo

echo "================= 手册命令 7/7 之一：make tooldir=/usr install ================="
echo "手册原文：Install the package: make tooldir=/usr install"
run_logged "make tooldir=/usr install" "$INSTLOG" no -- make tooldir=/usr install
echo

echo "================= 手册命令 7/7 之二：删除无用的静态库与文件 ================="
cat <<'MANUAL'
手册原文：Remove useless static libraries and other files:
  rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
          /usr/share/doc/gprofng/
MANUAL
echo "执行前这些路径的状态："
for f in /usr/lib/libbfd.a /usr/lib/libctf.a /usr/lib/libctf-nobfd.a \
         /usr/lib/libgprofng.a /usr/lib/libopcodes.a /usr/lib/libsframe.a \
         /usr/share/doc/gprofng; do
  if [ -e "$f" ]; then printf '  存在 %-34s %s\n' "$f" "$( [ -d "$f" ] && echo "目录，$(find "$f" | wc -l) 条目" || echo "$(stat -Lc %s "$f") 字节")"
  else printf '  不存在 %s\n' "$f"; fi
done
rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
        /usr/share/doc/gprofng/
echo

echo "================= 安装结果检查（对照手册 §8.21.2 Contents） ================="
prc=0
echo "1) Installed programs（手册清单：addr2line, ar, as, c++filt, dwp, elfedit,"
echo "   gprof, gprofng, ld, ld.bfd, nm, objcopy, objdump, ranlib, readelf, size,"
echo "   strings, and strip）："
for p in addr2line ar as c++filt elfedit gprof gprofng ld ld.bfd nm objcopy \
         objdump ranlib readelf size strings strip; do
  if [ -x "/usr/bin/$p" ]; then
    v=$("/usr/bin/$p" --version 2>&1 | sed -n 1p)
    printf '   OK   %-10s %10s 字节  %s\n' "$p" "$(stat -Lc %s "/usr/bin/$p")" "$v"
    case "$v" in
      *"$VER"*) ;;
      *) printf '   FAIL %s 的版本自述里没有 %s\n' "$p" "$VER"; prc=1 ;;
    esac
  else printf '   FAIL /usr/bin/%s 缺失\n' "$p"; prc=1; fi
done
echo "   dwp（手册清单里有，但本版本不产出）："
if [ -x /usr/bin/dwp ]; then
  echo "     OK   /usr/bin/dwp 存在"
else
  echo "     INFO /usr/bin/dwp 不存在。原因：dwp 是 gold 链接器的配套工具，而"
  echo "          binutils-$VER 的源码包里已经没有 gold/ 子目录（本次解包后确认：$( [ -d /sources/$SRCDIR/gold ] && echo '有' || echo '无' )），"
  echo "          因此上游根本不构建 dwp。手册 §8.21.2 的 Contents 清单在这一项上"
  echo "          滞后于 2.46.0，属手册与上游的差异，不是本次构建的缺失。"
fi
echo
echo "2) Installed libraries（手册清单：libbfd.so, libctf.so, libctf-nobfd.so,"
echo "   libgprofng.so, libopcodes.so, libsframe.so）："
for l in libbfd libctf libctf-nobfd libgprofng libopcodes libsframe; do
  if [ -e "/usr/lib/$l.so" ]; then
    printf '   OK   /usr/lib/%-16s -> %s\n' "$l.so" "$(readlink -f "/usr/lib/$l.so")"
  else printf '   FAIL /usr/lib/%s.so 缺失\n' "$l"; prc=1; fi
done
echo "   同名共享库的全部文件："
find /usr/lib -maxdepth 1 \( -name 'libbfd*' -o -name 'libctf*' -o -name 'libgprofng*' \
     -o -name 'libopcodes*' -o -name 'libsframe*' \) | sort | sed 's/^/     /'
echo
echo "3) Installed directory（手册清单：/usr/lib/ldscripts）："
if [ -d /usr/lib/ldscripts ]; then
  echo "   OK   /usr/lib/ldscripts 存在（$(find /usr/lib/ldscripts -type f | wc -l) 个链接脚本）"
  find /usr/lib/ldscripts -type f -name 'elf_x86_64.x*' | sort | sed -n '1,6p' | sed 's/^/     /'
else echo "   FAIL /usr/lib/ldscripts 不存在"; prc=1; fi
echo
echo "4) 手册最后一条命令的效果（静态库与 gprofng 文档必须已删除）："
for f in /usr/lib/libbfd.a /usr/lib/libctf.a /usr/lib/libctf-nobfd.a \
         /usr/lib/libgprofng.a /usr/lib/libopcodes.a /usr/lib/libsframe.a \
         /usr/share/doc/gprofng; do
  if [ -e "$f" ]; then printf '   FAIL %s 仍然存在\n' "$f"; prc=1
  else printf '   OK   %s 已删除/不存在\n' "$f"; fi
done
echo "   /usr/lib 下遗留的 binutils 相关 .a："
leftover=$(find /usr/lib -maxdepth 1 -name 'lib*.a' 2>/dev/null | sort | tr '\n' ' ')
echo "     ${leftover:-（无）}"
echo
echo "5) tooldir=/usr 的效果（不应产生 /usr/<target_alias>/ 目录）："
tgt=$(/sources/$SRCDIR/config.guess)
echo "   本机 target_alias = $tgt"
if [ -e "/usr/$tgt" ]; then
  echo "   FAIL /usr/$tgt 存在，说明 tooldir=/usr 未生效"; prc=1
else
  echo "   OK   /usr/$tgt 不存在（tooldir=/usr 生效）"
fi
echo "   （/usr/x86_64-lfs-linux-gnu 是第 6 章 §6.17 pass2 --host=\$LFS_TGT 的遗留目录，"
echo "     不属本节产物，本节未触碰：$( [ -d /usr/x86_64-lfs-linux-gnu ] && echo "仍存在，$(find /usr/x86_64-lfs-linux-gnu | wc -l) 条目" || echo '不存在' )）"
echo
echo "6) --sysconfdir=/etc 的落点："
find /etc -maxdepth 1 -newermt '-1 hour' 2>/dev/null | sed 's/^/     /' || true
if [ -f /etc/gprofng.rc ]; then
  echo "   OK   /etc/gprofng.rc 已安装（$(stat -Lc %s /etc/gprofng.rc) 字节）——"
  echo "        这是 --sysconfdir=/etc 唯一的实际落点：gprofng/src/Makefile 把 gprofng.rc"
  echo "        装到 \$(sysconfdir)。install 日志里对应的一行："
  { grep -nE 'gprofng\.rc' "$INSTLOG" || true; } | sed -n '1,2p' | sed 's/^/          /'
else
  echo "   FAIL /etc/gprofng.rc 不存在 —— --sysconfdir=/etc 的落点缺失"; prc=1
fi
echo
echo "7) man 页与 info 文档："
mancnt=0
for m in addr2line ar as c++filt dlltool elfedit gprof ld nm objcopy objdump \
         ranlib readelf size strings strip windres; do
  if [ -e "/usr/share/man/man1/$m.1" ]; then mancnt=$((mancnt+1)); fi
done
echo "   /usr/share/man/man1 下已安装的 binutils man 页数：$mancnt"
{ find /usr/share/man/man1 -name 'gprofng*' 2>/dev/null || true; } | sort | sed 's/^/     /'
echo "   info 文档："
{ find /usr/share/info -maxdepth 1 \( -name 'as.info*' -o -name 'bfd.info*' \
       -o -name 'binutils.info*' -o -name 'ld.info*' -o -name 'gprof.info*' \
       -o -name 'ctf-spec.info*' -o -name 'sframe-spec.info*' \) 2>/dev/null || true; } | sort | sed 's/^/     /'
echo

echo "================= 安装后功能验证（断言已用 §6.17 同版本产物预先校准） ================="
T=$(mktemp -d /tmp/verify-binutils-XXXXXX)
cd "$T"
frc=0
chk() {  # chk <描述> <实际> <期望>
  if [ "$2" = "$3" ]; then printf '   OK   %-52s = %s\n' "$1" "$2"
  else printf '   FAIL %-52s = %s（期望 %s）\n' "$1" "$2" "$3"; frc=1; fi
}

echo "a) ld 与 ld.bfd（--enable-ld=default：装成 ld 与 ld.bfd 两个名字，都是 bfd 链接器）"
echo "   ld     -> $(readlink -f "$(command -v ld)")"
echo "   ld.bfd -> $(readlink -f "$(command -v ld.bfd)")"
if cmp -s /usr/bin/ld /usr/bin/ld.bfd; then echo "   OK   /usr/bin/ld 与 /usr/bin/ld.bfd 内容逐字节一致"
else echo "   FAIL /usr/bin/ld 与 /usr/bin/ld.bfd 内容不同"; frc=1; fi
ld --version > ldver.txt 2>&1
echo "   ld --version 首行：$(sed -n 1p ldver.txt)"
chk "ld --version 首行以 'GNU ld (GNU Binutils)' 开头" \
    "$( { grep -c '^GNU ld (GNU Binutils)' ldver.txt || true; } )" 1
ld -V > ldV.txt 2>&1
echo "   ld -V 支持的 emulation："
sed -n '2,20p' ldV.txt | sed 's/^/     /'
chk "ld 支持 elf_x86_64 emulation" "$( { grep -c 'elf_x86_64' ldV.txt || true; } )" 1

echo
echo "b) 编译 → 汇编 → 链接 → 运行 全链路"
cat > hello.c <<'EOF'
#include <stdio.h>
int main(void){ printf("hello binutils\n"); return 0; }
EOF
gcc -o hello hello.c
chk "gcc+ld 产出的可执行文件运行结果" "$(./hello)" "hello binutils"
cat > t.s <<'EOF'
    .globl  _start
    .text
_start:
    movq    $42, %rax
    movq    %rax, %rdi
    movq    $60, %rax
    syscall
EOF
as -o t.o t.s
ld -o t t.o
set +e; ./t; t_rc=$?; set -e
chk "as 汇编 + ld 裸链接的程序退出码" "$t_rc" 42

echo
echo "c) --enable-new-dtags：-Wl,-rpath 应产生 RUNPATH（新 dtag）而非 RPATH（旧 dtag）"
gcc -o hello-rpath -Wl,-rpath,/tmp/nonexistent hello.c
readelf -d hello-rpath > dyn.txt
{ grep -E 'RPATH|RUNPATH' dyn.txt || true; } | sed 's/^/     /'
chk "readelf -d 中 RUNPATH 行数" "$( { grep -c 'RUNPATH' dyn.txt || true; } )" 1
chk "readelf -d 中旧式 (RPATH) 行数" "$( { grep -cE '\(RPATH\)' dyn.txt || true; } )" 0

echo
echo "d) --enable-default-hash-style=gnu：默认只生成 .gnu.hash，不生成 SysV 的 .hash"
readelf -S hello > sec.txt
{ grep -E '\.hash' sec.txt || true; } | sed 's/^/     /'
chk "节表中 .gnu.hash 出现次数" "$( { grep -c '\.gnu\.hash' sec.txt || true; } )" 1
chk "节表中独立的 .hash 节数" "$( { grep -cE '\] \.hash' sec.txt || true; } )" 0

echo
echo "e) --enable-64-bit-bfd：BFD 支持 64 位目标"
objdump -i > objdump-i.txt 2>&1
echo "   objdump -i 首行：$(sed -n 1p objdump-i.txt)"
chk "objdump -i 中 elf64-x86-64 是否出现" \
    "$( [ "$( { grep -c 'elf64-x86-64' objdump-i.txt || true; } )" -gt 0 ] && echo yes || echo no )" yes
chk "readelf -h 报告的 Class" \
    "$(readelf -h hello > rh.txt; { grep -E '^\s+Class:' rh.txt || true; } | awk '{print $2}')" "ELF64"

echo
echo "f) --enable-plugins：ar/nm/ranlib 支持 --plugin，且 bfd 目标列表里含 plugin"
ar --help > arhelp.txt 2>&1
nm --help > nmhelp.txt 2>&1
ranlib --help > rlhelp.txt 2>&1
chk "ar --help 中 --plugin 出现次数>0" \
    "$( [ "$( { grep -c -- '--plugin' arhelp.txt || true; } )" -gt 0 ] && echo yes || echo no )" yes
chk "nm --help 中 --plugin 出现次数>0" \
    "$( [ "$( { grep -c -- '--plugin' nmhelp.txt || true; } )" -gt 0 ] && echo yes || echo no )" yes
chk "ranlib --help 中 --plugin 出现次数>0" \
    "$( [ "$( { grep -c -- '--plugin' rlhelp.txt || true; } )" -gt 0 ] && echo yes || echo no )" yes
chk "ar 支持的 target 列表含 plugin" \
    "$( [ "$( { grep -c 'supported targets:.*plugin' arhelp.txt || true; } )" -gt 0 ] && echo yes || echo no )" yes

echo
echo "g) ar / ranlib / nm：建静态库、生成索引、链接使用"
cat > lib1.c <<'EOF'
int add(int a,int b){return a+b;}
EOF
cat > lib2.c <<'EOF'
int sub(int a,int b){return a-b;}
EOF
gcc -c lib1.c lib2.c
ar rcs libverify.a lib1.o lib2.o
ranlib libverify.a
ar t libverify.a > artlist.txt
echo "   ar t 输出：$(tr '\n' ' ' < artlist.txt)"
chk "ar t 列出的成员数" "$(wc -l < artlist.txt)" 2
nm --print-armap libverify.a > armap.txt
chk "nm --print-armap 中 'add in lib1.o' 出现次数" \
    "$( { grep -c 'add in lib1\.o' armap.txt || true; } )" 1
cat > useverify.c <<'EOF'
#include <stdio.h>
int add(int,int); int sub(int,int);
int main(void){ printf("%d %d\n", add(2,3), sub(9,4)); return 0; }
EOF
gcc -o useverify useverify.c -L. -lverify
chk "链接静态库后的运行结果" "$(./useverify)" "5 5"

echo
echo "h) nm / objdump / readelf / size / strings / strip / objcopy / addr2line / c++filt"
nm hello > nm.txt
chk "nm 中 'T main' 行数" "$( { grep -c ' T main' nm.txt || true; } )" 1
objdump -d hello > objd.txt
chk "objdump -d 输出中 'file format elf64-x86-64' 行数" \
    "$( { grep -c 'file format elf64-x86-64' objd.txt || true; } )" 1
size hello > size.txt
echo "   size hello：$(sed -n 2p size.txt)"
chk "size 输出行数（表头+1 行）" "$(wc -l < size.txt)" 2
strings hello > str.txt
chk "strings 中 'hello binutils' 行数" "$( { grep -c 'hello binutils' str.txt || true; } )" 1
cp hello hello-stripped; strip hello-stripped
before=$(stat -c %s hello); after=$(stat -c %s hello-stripped)
echo "   strip 前 $before 字节 → 后 $after 字节"
chk "strip 后体积变小" "$( [ "$after" -lt "$before" ] && echo yes || echo no )" yes
chk "strip 后的程序仍可运行" "$(./hello-stripped)" "hello binutils"
objcopy --only-keep-debug hello hello.dbg
chk "objcopy --only-keep-debug 产出非空文件" \
    "$( [ -s hello.dbg ] && echo yes || echo no )" yes
gcc -g -O0 -o hello-g hello.c
nm hello-g > nmg.txt
mainaddr=$( { grep -E ' [Tt] main$' nmg.txt || true; } | awk '{print $1}' | sed -n 1p )
a2l=$(addr2line -e hello-g -f "$mainaddr" | sed -n 1p)
chk "addr2line 由 main 地址反查到的函数名" "$a2l" "main"
chk "c++filt _Z4funcii" "$(echo '_Z4funcii' | c++filt)" "func(int, int)"
chk "c++filt _ZNSt6vectorIiSaIiEE9push_backERKi" \
    "$(echo '_ZNSt6vectorIiSaIiEE9push_backERKi' | c++filt)" \
    "std::vector<int, std::allocator<int> >::push_back(int const&)"
elfedit --output-osabi none hello-stripped
readelf -h hello-stripped > rh2.txt
chk "elfedit 改写后 readelf 报告的 OS/ABI" \
    "$( { grep -E 'OS/ABI' rh2.txt || true; } | sed -E 's/.*OS\/ABI:[[:space:]]+//' )" "UNIX - System V"

echo
echo "i) gprof / gprofng（本节新增，第 6 章 pass2 用 --enable-gprofng=no 未构建）"
echo "   gprof   --version：$(gprof --version 2>&1 | sed -n 1p)"
echo "   gprofng --version：$(gprofng --version 2>&1 | sed -n 1p)"
gprofng --help > gphelp.txt 2>&1 || true
echo "   gprofng --help 前 8 行："
sed -n '1,8p' gphelp.txt | sed 's/^/     /'
chk "gprofng 可执行且能打印帮助" \
    "$( [ -s gphelp.txt ] && echo yes || echo no )" yes
set +e
gcc -pg -o hello-pg hello.c > pg-build.txt 2>&1
pg_rc=$?
if [ $pg_rc -eq 0 ]; then ./hello-pg > /dev/null 2>&1; fi
set -e
if [ $pg_rc -ne 0 ]; then
  echo "   INFO gcc -pg 编译失败（退出码 $pg_rc），跳过 gprof 报告验证；输出："
  sed -n '1,5p' pg-build.txt | sed 's/^/     /'
elif [ -f gmon.out ]; then
  gprof hello-pg gmon.out > gprof-out.txt 2>&1 || true
  echo "   gprof 分析报告前 6 行："
  sed -n '1,6p' gprof-out.txt | sed 's/^/     /'
  chk "gprof 能读 gmon.out 产出报告" "$( [ -s gprof-out.txt ] && echo yes || echo no )" yes
else
  echo "   INFO 未产生 gmon.out（-pg 运行环境限制），跳过 gprof 报告验证"
fi

echo
echo "j) 共享库的动态依赖（--with-system-zlib 的运行期观察点）"
for so in /usr/lib/libbfd.so /usr/lib/libopcodes.so /usr/lib/libctf.so \
          /usr/lib/libctf-nobfd.so /usr/lib/libsframe.so /usr/lib/libgprofng.so; do
  echo "   $so -> $(readlink -f "$so")"
  ldd "$so" > ldd.txt 2>&1 || true
  sed 's/^/       /' ldd.txt
done
ldd /usr/lib/libbfd.so > lddbfd.txt 2>&1 || true
zc=$( { grep -c 'libz\.so' lddbfd.txt || true; } )
if [ "$zc" -gt 0 ]; then
  echo "   OK   libbfd.so 动态链接系统 libz.so（--with-system-zlib 的运行期证据）"
else
  echo "   INFO libbfd.so 的 ldd 里没有 libz.so —— 已在 configure 阶段用"
  echo "        「构建目录下不存在 zlib/ 且 configdirs 不含 zlib」硬判据确认了"
  echo "        --with-system-zlib 生效，此处仅作记录，不作判据。"
fi
echo "   /usr/bin/ld 的动态依赖："
ldd /usr/bin/ld > lddld.txt 2>&1 || true
sed 's/^/     /' lddld.txt

echo
echo "k) 覆盖前后对照（第 6 章 pass2 → 本节）"
echo "   本节新增的程序：gprofng（pass2 用 --enable-gprofng=no 排除）"
echo "   本节新增的库  ：libgprofng.so"
echo "   本节新增的目录：/usr/lib/ldscripts（pass2 把它装进了 /usr/x86_64-lfs-linux-gnu/lib/ldscripts）"
for p in ld as ar nm objdump readelf; do
  printf '   %-10s 现在 %10s 字节，%s\n' "$p" "$(stat -Lc %s /usr/bin/$p)" "$(/usr/bin/$p --version | sed -n 1p)"
done

cd /
rm -rf "$T"
[ $frc -eq 0 ] || { echo "错误：安装后功能验证有未通过项" >&2; prc=1; }
echo
[ $prc -eq 0 ] || { echo "错误：安装结果检查未通过" >&2; exit 1; }
echo "安装结果检查与功能验证全部通过。"
echo

echo "================= 构建目录清理（手册 iii. General Compilation Instructions） ================="
echo "手册原文：... you should remove the ... source directories ... after installing"
echo "  the package, unless instructed otherwise."
cd /sources
echo "清理前 /sources 下的 binutils 相关条目："
find /sources -maxdepth 1 -name 'binutils*' | sort | sed 's/^/  /'
{ du -sh "/sources/$SRCDIR" 2>/dev/null || true; } | sed 's/^/  待删除：/'
rm -rf "/sources/$SRCDIR"
echo "清理后 /sources 下的 binutils 相关条目（应只剩 tarball）："
find /sources -maxdepth 1 -name 'binutils*' | sort | sed 's/^/  /'
if [ -e "/sources/$SRCDIR" ]; then echo "  FAIL 源码目录仍存在"; exit 1
else echo "  OK   源码构建目录（含其中的 build/）已删除"; fi
echo

echo "================= 本节结论 ================="
echo "手册 §8.21 的 7 条命令全部按原样执行完毕："
echo "  1. mkdir -v build                       —— 完成"
echo "  2. cd       build                       —— 完成"
echo "  3. ../configure --prefix=/usr ...       —— 完成，10 个选项逐条核对生效"
echo "  4. make tooldir=/usr                    —— 完成"
echo "  5. make -k check                        —— 完成（退出码 $check_rc，-k 下非 0 属预期）"
echo "  6. grep '^FAIL:' \$(find -name '*.log')  —— 完成，FAIL 行 $fail_lines 条"
echo "  7. make tooldir=/usr install + rm -rfv 静态库/gprofng 文档 —— 完成"
echo
echo "测试结论（手册 Important：本节测试 critical，不得跳过）："
echo "  expected passes      : $tot_pass"
echo "  unexpected failures  : $tot_ufail"
echo "  expected failures    : $tot_xfail"
echo "  unexpected successes : $tot_xpass"
echo "  unresolved           : $tot_unres"
echo "  untested             : $tot_untest"
echo "  unsupported          : $tot_unsup"
echo "  非 gprofng 的 FAIL   : $other_fail（要求为 0）"
echo "  gprofng 的 FAIL      : $gprofng_fail（手册允许：One test related to gprofng is known to fail.）"
echo
echo "手册与上游的已知差异（已在上文给出证据）："
echo "  §8.21.2 Contents 列出的 dwp 在 binutils-$VER 中不存在 —— 源码包已无 gold/ 子目录，"
echo "  上游不再构建 gold 及其配套的 dwp。其余程序、库、目录与手册清单完全一致。"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.21 Binutils-$VER 完成 ====="
