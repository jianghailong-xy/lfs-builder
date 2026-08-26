#!/usr/bin/env bash
# LFS 13.0-systemd §6.18 GCC-15.2.0 - Pass 2
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §6.18.1 的命令序列（全部，无补丁、无测试套件）：
#   tar -xf ../mpfr-4.2.2.tar.xz
#   mv -v mpfr-4.2.2 mpfr
#   tar -xf ../gmp-6.3.0.tar.xz
#   mv -v gmp-6.3.0 gmp
#   tar -xf ../mpc-1.3.1.tar.gz
#   mv -v mpc-1.3.1 mpc
#   case $(uname -m) in
#     x86_64)
#       sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
#     ;;
#   esac
#   sed '/thread_header =/s/@.*@/gthr-posix.h/' \
#       -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
#   mkdir -v build
#   cd       build
#   ../configure                   \
#       --build=$(../config.guess) \
#       --host=$LFS_TGT            \
#       --target=$LFS_TGT          \
#       --prefix=/usr              \
#       --with-build-sysroot=$LFS  \
#       --enable-default-pie       \
#       --enable-default-ssp       \
#       --disable-nls              \
#       --disable-multilib         \
#       --disable-libatomic        \
#       --disable-libgomp          \
#       --disable-libquadmath      \
#       --disable-libsanitizer     \
#       --disable-libssp           \
#       --disable-libvtv           \
#       --enable-languages=c,c++   \
#       LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc
#   make
#   make DESTDIR=$LFS install
#   ln -sv gcc $LFS/usr/bin/cc
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=gcc
VER=15.2.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

MPFR_VER=4.2.2
GMP_VER=6.3.0
MPC_VER=1.3.1

echo "===== LFS 13.0-systemd §6.18 GCC-$VER - Pass 2 ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 4.5 SBU，Required disk space 6.0 GB"
echo "手册简介：The GCC package contains the GNU compiler collection, which includes"
echo "          the C and C++ compilers."
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
echo "nproc    : $(nproc)"
echo "手册 §6.18.1 提醒：Before starting to build GCC, remember to unset any environment"
echo "  variables that override the default optimization flags。逐一确认这些变量未设置："
for v in CFLAGS CXXFLAGS CPPFLAGS LDFLAGS CFLAGS_FOR_TARGET CXXFLAGS_FOR_TARGET \
         LDFLAGS_FOR_TARGET LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH \
         LD_LIBRARY_PATH LD_RUN_PATH GCC_EXEC_PREFIX COMPILER_PATH; do
  if [ -n "${!v+x}" ]; then
    echo "   FAIL $v 已设置为「${!v}」，违反手册要求，拒绝继续" >&2
    exit 1
  fi
  printf '   OK   %-22s 未设置\n' "$v"
done
[ "$(whoami)" = "lfs" ] || { echo "错误：必须以 lfs 用户构建（手册 §6.1 警告：以 root 构建会毁掉宿主系统）" >&2; exit 1; }
[ "$LFS" = "/mnt/lfs" ] || { echo "错误：LFS 不是 /mnt/lfs" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点" >&2; exit 1; }
echo "可用空间（手册本节要求 6.0 GB）："
df -h "$LFS" | tail -n1
avail_mb=$(df -Pm "$LFS" | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 6144 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 6144MB" >&2; exit 1; }
echo

echo "----- 前置检查：第 5 章交叉工具链 + §6.17 Binutils Pass 2 产物必须可用 -----"
echo "1) §5.3 GCC Pass 1 交叉编译器（手册说明本节的目标库 libgcc/libstdc++ 由它构建）："
for t in gcc g++ cpp; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少 §5.3 产物 $f" >&2; exit 1; }
  printf '   OK   %s\n' "$f"
done
{ $LFS_TGT-gcc --version || true; } | head -n1 | sed 's/^/   /'
echo "   -dumpmachine : $($LFS_TGT-gcc -dumpmachine)"
echo "   -print-sysroot: $($LFS_TGT-gcc -print-sysroot)"
echo "2) §5.2 Binutils Pass 1（\$LFS/tools 中的交叉 binutils，本节 make 时被调用）："
for t in ld as ar ranlib; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少 §5.2 产物 $f" >&2; exit 1; }
  printf '   OK   %s\n' "$f"
done
{ $LFS_TGT-ld --version || true; } | head -n1 | sed 's/^/   /'
echo "3) §5.4 Linux API Headers / §5.5 Glibc / §5.6 Libstdc++（交叉编译与链接所必需）："
for f in usr/include/linux/version.h usr/lib/libc.so.6 usr/lib/ld-linux-x86-64.so.2 \
         usr/lib/crt1.o usr/include/stdio.h usr/lib/libstdc++.so.6; do
  [ -e "$LFS/$f" ] || { echo "错误：前置产物缺失：\$LFS/$f" >&2; exit 1; }
  printf '   OK   $LFS/%s\n' "$f"
done
echo "4) 上一任务（§6.17 Binutils-2.46.0 Pass 2）产物必须可用："
for f in usr/bin/ld usr/bin/as usr/bin/ar usr/bin/ranlib usr/lib/libbfd.so; do
  [ -e "$LFS/$f" ] || { echo "错误：\$LFS/$f 缺失，§6.17 未完成" >&2; exit 1; }
  printf '   OK   $LFS/%-18s %s\n' "$f" "$(file -b $LFS/$f | cut -d, -f1-2)"
done
echo "5) §6.2~§6.16 产物抽查（本节 configure/make 依赖这些工具的存在性，虽在宿主侧用容器工具执行）："
for p in m4 bash ls diff file find gawk grep gzip make patch sed tar xz; do
  [ -e "$LFS/usr/bin/$p" ] || { echo "错误：\$LFS/usr/bin/$p 缺失" >&2; exit 1; }
done
echo "   OK   m4 bash ls diff file find gawk grep gzip make patch sed tar xz 均已在 \$LFS/usr/bin"
echo "6) 本节安装前 \$LFS/usr/bin 下不应已有 gcc（本节是首次把 GCC 装入 \$LFS/usr）："
for f in usr/bin/gcc usr/bin/g++ usr/bin/cpp usr/bin/cc; do
  if [ -e "$LFS/$f" ] || [ -L "$LFS/$f" ]; then printf '   INFO $LFS/%s 已存在（将被覆盖）\n' "$f"
  else printf '   OK   $LFS/%s 尚未安装\n' "$f"; fi
done
echo

echo "----- 清理本节此前中断尝试留下的残留（保证本节手册命令可原样执行） -----"
echo "手册 §6.18 假定 \$LFS 上尚无本节产物，其最后一条命令 ln -sv gcc \$LFS/usr/bin/cc"
echo "不是幂等的：若 \$LFS/usr/bin/cc 已存在，ln 会以 \"File exists\" 失败。"
echo "make DESTDIR=\$LFS install 会覆盖其余所有文件，只有这个符号链接需要先清掉。"
if [ -e "$LFS/usr/bin/cc" ] || [ -L "$LFS/usr/bin/cc" ]; then
  echo "  发现残留：$(ls -l $LFS/usr/bin/cc | sed "s|$LFS|\$LFS|")"
  rm -v $LFS/usr/bin/cc
  echo "  已删除，稍后由手册原命令 ln -sv 重新创建"
else
  echo "  OK   \$LFS/usr/bin/cc 不存在，无需清理"
fi
echo

cd $LFS/sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
for f in $TARBALL mpfr-$MPFR_VER.tar.xz gmp-$GMP_VER.tar.xz mpc-$MPC_VER.tar.gz; do
  grep -E " $f\$" md5sums
  grep -E " $f\$" md5sums | md5sum -c -
done
echo

echo "----- 解包（手册 iii：以 lfs 用户在 \$LFS/sources 下解包） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "GCC 自报版本：$(cat gcc/BASE-VER)"
echo "本节无补丁：手册 §6.18 未规定任何 patch，只有下面的解包依赖库、两处 sed、"
echo "  mkdir/cd build、../configure、make、make DESTDIR=\$LFS install 和 ln -sv。"
echo

echo "================= 6.18.1 Installation of GCC ================="
echo "----- 手册命令：解包 GMP / MPFR / MPC 到 GCC 源码树 -----"
echo "手册原文：As in the first build of GCC, the GMP, MPFR, and MPC packages are"
echo "  required. Unpack the tarballs and move them into the required directories:"
tar -xf ../mpfr-$MPFR_VER.tar.xz
mv -v mpfr-$MPFR_VER mpfr
tar -xf ../gmp-$GMP_VER.tar.xz
mv -v gmp-$GMP_VER gmp
tar -xf ../mpc-$MPC_VER.tar.gz
mv -v mpc-$MPC_VER mpc
echo "GCC 源码树内的三个依赖目录（名字必须正好是 mpfr/gmp/mpc，GCC 才会一并构建）："
for d in mpfr gmp mpc; do
  [ -d "$d" ] || { echo "错误：$d 目录不存在" >&2; exit 1; }
  printf '   OK   %-5s -> %s\n' "$d" "$(head -n1 $d/VERSION 2>/dev/null || grep -m1 -E "^PACKAGE_VERSION=" $d/configure || echo '（版本未知）')"
done
echo

echo "----- 手册命令：x86_64 上把 64 位库的默认目录名改成 lib -----"
echo "手册原文：If you are building on x86_64, change the default directory name for"
echo "  64-bit libraries to \"lib\":"
echo "手册命令："
echo "  case \$(uname -m) in"
echo "    x86_64)"
echo "      sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64"
echo "    ;;"
echo "  esac"
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
if [ -f gcc/config/i386/t-linux64.orig ]; then
  echo "diff -u gcc/config/i386/t-linux64{.orig,}："
  diff -u gcc/config/i386/t-linux64.orig gcc/config/i386/t-linux64 | sed 's/^/  /' || true
  if grep -qE 'm64=\.\./lib([^0-9]|$)' gcc/config/i386/t-linux64; then
    echo "   OK   MULTILIB_OSDIRNAMES 中 m64 已指向 ../lib（不再是 ../lib64）"
  else
    echo "   FAIL m64 仍未指向 ../lib：$(grep -n 'm64=' gcc/config/i386/t-linux64)"; exit 1
  fi
else
  echo "   非 x86_64（uname -m = $(uname -m)），按手册跳过该 sed"
fi
echo

echo "----- 手册命令：让 libgcc / libstdc++ 的头文件规则支持 POSIX 线程 -----"
echo "手册原文：Override the build rules of the libgcc and libstdc++ headers to allow"
echo "  building these libraries with POSIX threads support:"
echo "手册命令：sed '/thread_header =/s/@.*@/gthr-posix.h/' \\"
echo "              -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in"
echo "改动前："
grep -n 'thread_header =' libgcc/Makefile.in libstdc++-v3/include/Makefile.in | sed 's/^/  /' || true
sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
echo "改动后："
grep -n 'thread_header =' libgcc/Makefile.in libstdc++-v3/include/Makefile.in | sed 's/^/  /' || true
n=$(grep -h 'thread_header = gthr-posix.h' libgcc/Makefile.in libstdc++-v3/include/Makefile.in | wc -l)
[ "$n" -eq 2 ] || { echo "错误：thread_header 替换未在两个文件中各生效一次（实际 $n 处）" >&2; exit 1; }
echo "   OK   两个 Makefile.in 中的 thread_header 均已指向 gthr-posix.h"
echo

echo "----- 手册命令：mkdir -v build && cd build -----"
echo "手册原文：Create a separate build directory again:"
mkdir -v build
cd       build
echo "构建目录：$PWD"
echo

echo "----- configure（手册原文命令） -----"
echo "手册原文：Now prepare GCC for compilation:"
echo "手册命令："
echo "  ../configure                   \\"
echo "      --build=\$(../config.guess) \\"
echo "      --host=\$LFS_TGT            \\"
echo "      --target=\$LFS_TGT          \\"
echo "      --prefix=/usr              \\"
echo "      --with-build-sysroot=\$LFS  \\"
echo "      --enable-default-pie       \\"
echo "      --enable-default-ssp       \\"
echo "      --disable-nls              \\"
echo "      --disable-multilib         \\"
echo "      --disable-libatomic        \\"
echo "      --disable-libgomp          \\"
echo "      --disable-libquadmath      \\"
echo "      --disable-libsanitizer     \\"
echo "      --disable-libssp           \\"
echo "      --disable-libvtv           \\"
echo "      --enable-languages=c,c++   \\"
echo "      LDFLAGS_FOR_TARGET=-L\$PWD/\$LFS_TGT/libgcc"
echo "../config.guess 的输出：$(../config.guess)"
echo "本次展开后的 LDFLAGS_FOR_TARGET：-L$PWD/$LFS_TGT/libgcc"
echo "手册对新增选项的说明："
echo "  --with-build-sysroot=\$LFS  Normally, using --host ensures that a cross-compiler"
echo "      is used for building GCC, and that compiler knows that it has to look for"
echo "      headers and libraries in \$LFS. However, the build system for GCC uses"
echo "      additional tools which are not aware of this location. This switch is needed"
echo "      so those tools will find the needed files in \$LFS, and not on the host."
echo "  --target=\$LFS_TGT  We are cross-compiling GCC, so it's impossible to build target"
echo "      libraries (libgcc and libstdc++) with the GCC binaries compiled in this pass"
echo "      —those binaries won't run on the host. ... This parameter ensures the"
echo "      libraries are built by GCC pass 1."
echo "  LDFLAGS_FOR_TARGET=...  Allow libstdc++ to use the libgcc being built in this"
echo "      pass, instead of the previous version built in gcc-pass1. The previous version"
echo "      cannot properly support C++ exception handling because it was built without"
echo "      libc support."
echo "  --disable-libsanitizer  Disable GCC sanitizer runtime libraries. They are not"
echo "      needed for the temporary installation. In gcc-pass1 it was implied by"
echo "      --disable-libstdcxx, and now we can explicitly pass it."
time ../configure                   \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --target=$LFS_TGT          \
    --prefix=/usr              \
    --with-build-sysroot=$LFS  \
    --enable-default-pie       \
    --enable-default-ssp       \
    --disable-nls              \
    --disable-multilib         \
    --disable-libatomic        \
    --disable-libgomp          \
    --disable-libquadmath      \
    --disable-libsanitizer     \
    --disable-libssp           \
    --disable-libvtv           \
    --enable-languages=c,c++   \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc
echo
echo "configure 关键结果确认："
grep -E '^(build|host|target) *=' Makefile | head -n6 | sed 's/^/  /' || true
grep -E '^(prefix) *=' Makefile | head -n2 | sed 's/^/  /' || true
echo "  三元组必须是 build=宿主 / host=target=\$LFS_TGT（交叉编译且交叉宿主）："
mk_host=$(grep -m1 -E '^host *=' Makefile | sed 's/.*= *//')
mk_target=$(grep -m1 -E '^target *=' Makefile | sed 's/.*= *//')
[ "$mk_host" = "$LFS_TGT" ] || { echo "  FAIL host=$mk_host 不是 $LFS_TGT" >&2; exit 1; }
[ "$mk_target" = "$LFS_TGT" ] || { echo "  FAIL target=$mk_target 不是 $LFS_TGT" >&2; exit 1; }
echo "  OK   host=$mk_host  target=$mk_target"
echo "  configure 实际收到的完整参数（GCC 把它记录在 build/Makefile 的"
echo "  TOPLEVEL_CONFIGURE_ARGUMENTS 中，比 config.log 更权威）："
cfgargs=$(grep -m1 '^TOPLEVEL_CONFIGURE_ARGUMENTS=' Makefile | sed 's/^[^=]*=//')
echo "    $cfgargs"
echo "  逐项核对本节手册要求的 17 个 configure 参数是否都在其中："
for opt in "--build=$(../config.guess)" "--host=$LFS_TGT" "--target=$LFS_TGT" \
           "--prefix=/usr" "--with-build-sysroot=$LFS" "--enable-default-pie" \
           "--enable-default-ssp" "--disable-nls" "--disable-multilib" \
           "--disable-libatomic" "--disable-libgomp" "--disable-libquadmath" \
           "--disable-libsanitizer" "--disable-libssp" "--disable-libvtv" \
           "--enable-languages=c,c++" "LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc"; do
  case " $cfgargs " in
    *" $opt "*) printf '    OK   %s\n' "$opt" ;;
    *)          printf '    FAIL %s 未出现在 configure 参数中\n' "$opt"; exit 1 ;;
  esac
done
echo

echo "----- 编译：make（手册原文：Compile the package） -----"
time make
echo

echo "----- 安装：make DESTDIR=\$LFS install（手册原文：Install the package） -----"
echo "安装前再次确认身份与 DESTDIR（手册 §6.1 Warning）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 手册命令：创建 cc 符号链接 -----"
echo "手册原文：As a finishing touch, create a utility symlink. Many programs and scripts"
echo "  run cc instead of gcc, which is used to keep programs generic and therefore usable"
echo "  on all kinds of UNIX systems where the GNU C compiler is not always installed."
echo "  Running cc leaves the system administrator free to decide which C compiler to install:"
echo "手册命令：ln -sv gcc \$LFS/usr/bin/cc"
ln -sv gcc $LFS/usr/bin/cc
echo "确认："
ls -l $LFS/usr/bin/cc | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
[ "$(readlink $LFS/usr/bin/cc)" = "gcc" ] || { echo "错误：\$LFS/usr/bin/cc 不是指向 gcc 的符号链接" >&2; exit 1; }
echo "  OK   \$LFS/usr/bin/cc -> gcc"
echo

echo "================= 本节测试 ================="
echo "手册 §6.18 未规定任何测试：本节命令只有解包 mpfr/gmp/mpc、两处 sed、mkdir/cd build、"
echo "../configure、make、make DESTDIR=\$LFS install 和 ln -sv gcc \$LFS/usr/bin/cc，"
echo "没有 make check / make -k check。"
echo "（对比：第 8 章 §8.30 GCC 才有完整的 make -k check 与 ../contrib/test_summary；"
echo "  第 5 章 §5.3 GCC Pass 1、§5.6 Libstdc++ 同样无测试。）"
echo "原因见手册 §6.1：本章的程序是用交叉工具链为目标平台（\$LFS_TGT）编译的，在进入"
echo "chroot 之前无法在宿主上运行，因此手册不要求也无法执行测试套件。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装结果检查（对照手册 §8.30.2 Contents of GCC，扣除本节禁用的部分） -----"
rc=0
echo "1) 安装的程序（\$LFS/usr/bin）："
for f in cpp gcc g++ gcov gcov-dump gcov-tool lto-dump \
         $LFS_TGT-gcc $LFS_TGT-gcc-$VER $LFS_TGT-g++ $LFS_TGT-c++ \
         $LFS_TGT-gcc-ar $LFS_TGT-gcc-nm $LFS_TGT-gcc-ranlib; do
  p=$LFS/usr/bin/$f
  if [ -e "$p" ]; then
    printf '   OK   $LFS/usr/bin/%-28s %s\n' "$f" "$(file -b $p | cut -d, -f1-2)"
  else
    printf '   FAIL $LFS/usr/bin/%s 缺失\n' "$f"; rc=1
  fi
done
echo "   cc 符号链接（本节最后一条手册命令）："
if [ -L "$LFS/usr/bin/cc" ] && [ "$(readlink $LFS/usr/bin/cc)" = gcc ]; then
  printf '   OK   $LFS/usr/bin/cc -> gcc\n'
else printf '   FAIL $LFS/usr/bin/cc 不是指向 gcc 的符号链接\n'; rc=1; fi
echo "2) 目标库（\$LFS/usr/lib，由 GCC Pass 1 为 \$LFS_TGT 构建）："
for f in libgcc_s.so.1 libstdc++.so.6 libsupc++.a; do
  if [ -e "$LFS/usr/lib/$f" ]; then
    printf '   OK   $LFS/usr/lib/%-18s %s\n' "$f" "$(file -b $LFS/usr/lib/$f | cut -d, -f1-2)"
  else printf '   FAIL $LFS/usr/lib/%s 缺失\n' "$f"; rc=1; fi
done
echo "   \$LFS/usr/lib 下 libstdc++ / libgcc 相关文件："
ls -l $LFS/usr/lib/libstdc++* $LFS/usr/lib/libgcc* 2>/dev/null | sed "s|$LFS|\$LFS|" | sed 's/^/     /' || true
echo "3) 本节按手册禁用的部分不应出现（逐项对应一个 --disable-* 选项）："
echo "   --disable-libgomp -> libgomp / --disable-libatomic -> libatomic /"
echo "   --disable-libquadmath -> libquadmath / --disable-libsanitizer -> libasan,libubsan,liblsan,libtsan /"
echo "   --disable-libssp -> libssp / --disable-libvtv -> libvtv"
for f in libgomp.so libatomic.so libquadmath.so libasan.so libubsan.so liblsan.so libtsan.so libvtv.so libssp.so; do
  if [ -e "$LFS/usr/lib/$f" ]; then printf '   FAIL $LFS/usr/lib/%s 存在，对应的 --disable-* 未生效\n' "$f"; rc=1
  else printf '   OK   $LFS/usr/lib/%s 不存在（符合 --disable-*）\n' "$f"; fi
done
echo "   注意：手册 §6.18 的 configure 参数中没有 --disable-libitm，因此 libitm 是本节的"
echo "   预期产物，不属于\"禁用项\"。实际情况："
ls -1 $LFS/usr/lib/libitm.* 2>/dev/null | sed "s|$LFS|\$LFS|" | sed 's/^/     /' || echo "     （未安装 libitm）"
echo "   --disable-multilib：不应有 32 位库目录 \$LFS/usr/lib32 或 \$LFS/usr/libx32："
for d in usr/lib32 usr/libx32; do
  if [ -d "$LFS/$d" ]; then printf '   FAIL $LFS/%s 存在\n' "$d"; rc=1
  else printf '   OK   $LFS/%s 不存在\n' "$d"; fi
done
echo "4) GCC 内部库目录（\$LFS/usr/lib/gcc/\$LFS_TGT/$VER）："
gccint=$LFS/usr/lib/gcc/$LFS_TGT/$VER
if [ -d "$gccint" ]; then
  printf '   OK   %s\n' "$(echo $gccint | sed "s|$LFS|\$LFS|")"
  for f in libgcc.a libgcc_eh.a libgcov.a crtbegin.o crtbeginS.o crtend.o crtendS.o include/stddef.h; do
    if [ -e "$gccint/$f" ]; then printf '     OK   %s\n' "$f"
    else printf '     FAIL %s 缺失\n' "$f"; rc=1; fi
  done
  echo "     include-fixed 内容："
  ls -1 $gccint/include-fixed 2>/dev/null | sed 's/^/       /' || echo "       （无 include-fixed）"
else printf '   FAIL %s 缺失\n' "$gccint"; rc=1; fi
echo "   GCC 内部可执行程序目录（\$LFS/usr/libexec/gcc/\$LFS_TGT/$VER，编译器本体所在）："
gcclibexec=$LFS/usr/libexec/gcc/$LFS_TGT/$VER
if [ -d "$gcclibexec" ]; then
  printf '   OK   %s\n' "$(echo $gcclibexec | sed "s|$LFS|\$LFS|")"
  for f in cc1 cc1plus collect2 lto1 lto-wrapper liblto_plugin.so; do
    if [ -e "$gcclibexec/$f" ]; then
      printf '     OK   %-16s %s\n' "$f" "$(file -b $gcclibexec/$f | cut -d, -f1-2)"
    else printf '     FAIL %s 缺失\n' "$f"; rc=1; fi
  done
  echo "     （cc1 = C 编译器本体，cc1plus = C++ 编译器本体；--enable-languages=c,c++ 两者都必须有）"
else printf '   FAIL %s 缺失\n' "$gcclibexec"; rc=1; fi
echo "5) C++ 头文件（libstdc++ 的 include 树）："
if [ -d "$LFS/usr/include/c++/$VER" ]; then
  printf '   OK   $LFS/usr/include/c++/%s（%s 项）\n' "$VER" "$(ls -A $LFS/usr/include/c++/$VER | wc -l)"
  for h in iostream vector string $LFS_TGT/bits/c++config.h; do
    if [ -e "$LFS/usr/include/c++/$VER/$h" ]; then printf '     OK   %s\n' "$h"
    else printf '     FAIL %s 缺失\n' "$h"; rc=1; fi
  done
else printf '   FAIL $LFS/usr/include/c++/%s 缺失\n' "$VER"; rc=1; fi
echo "6) 本次 make install 落盘的文件统计（DESTDIR=\$LFS，按修改时间挑出本次安装的）："
newf=$(find $LFS/usr -newer $LFS/sources/$SRCDIR/build/config.log \( -type f -o -type l \) 2>/dev/null | wc -l)
echo "     共 $newf 个文件/链接；\$LFS/usr/bin 顶层部分："
find $LFS/usr/bin -maxdepth 1 -newer $LFS/sources/$SRCDIR/build/config.log \( -type f -o -type l \) 2>/dev/null \
  | sed "s|$LFS|\$LFS|" | sort | sed 's/^/       /' || true
[ $rc -eq 0 ] || { echo "错误：GCC 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 确认安装的是为目标平台交叉编译的 ELF（不是宿主二进制） -----"
echo "  gcc:            $(file -b $LFS/usr/bin/gcc)"
echo "  g++:            $(file -b $LFS/usr/bin/g++)"
echo "  cc1:            $(file -b $gcclibexec/cc1)"
echo "  cc1plus:        $(file -b $gcclibexec/cc1plus)"
echo "  libstdc++.so.6: $(file -b $LFS/usr/lib/libstdc++.so.6)"
echo "readelf 头（gcc）："
readelf -h $LFS/usr/bin/gcc | grep -E 'Class|Machine|Type' | sed 's/^/  /' || true
echo "解释器（应为 /lib64/ld-linux-x86-64.so.2）："
readelf -l $LFS/usr/bin/gcc | grep 'interpreter' | sed 's/^/  /' || true
echo "动态依赖（gcc）："
$LFS_TGT-readelf -d $LFS/usr/bin/gcc | grep -E 'NEEDED|RUNPATH|RPATH' | sed 's/^/  /' || true
echo "动态依赖（libstdc++.so.6；本节 LDFLAGS_FOR_TARGET 指向本次构建的 libgcc，"
echo "  libgcc 的 unwinder 以静态方式并入，故 NEEDED 中只见 libm/libc）："
$LFS_TGT-readelf -d $(readlink -f $LFS/usr/lib/libstdc++.so.6) | grep -E 'NEEDED' | sed 's/^/  /' || true
echo "二进制中的版本字符串（应为 $VER）："
strings -a $LFS/usr/bin/gcc | grep -m3 -E "^$VER$|gcc version $VER|GCC.*$VER" | sed 's/^/  gcc 版本: /' || true
vercheck=$(strings -a $LFS/usr/bin/gcc | grep -cE "$VER") || true
[ "${vercheck:-0}" -ge 1 ] || { echo "错误：gcc 二进制中未出现版本号 $VER" >&2; exit 1; }
echo "  OK   gcc 二进制中出现 $VER 的字符串共 $vercheck 处"
echo "libstdc++ soname 与实体："
ls -l $LFS/usr/lib/libstdc++.so* | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
echo "libstdc++ 是否带 POSIX 线程支持（本节两处 sed 的目的：thread_header = gthr-posix.h）："
echo "  说明：构建系统把 gthr-posix.h 复制成 bits/gthr-default.h，所以判定依据是该文件的"
echo "  内容（include <pthread.h> 且定义 __GTHREADS），而不是文件里出现 \"gthr-posix.h\" 字样。"
gthr=$LFS/usr/include/c++/$VER/$LFS_TGT/bits/gthr-default.h
if [ -f "$gthr" ]; then
  echo "  OK   存在 \$LFS/usr/include/c++/$VER/$LFS_TGT/bits/gthr-default.h"
  if grep -q '#include <pthread.h>' "$gthr"; then
    echo "  OK   gthr-default.h 包含 #include <pthread.h>（即 gthr-posix.h 的内容，非 gthr-single.h）"
  else
    echo "  FAIL gthr-default.h 不含 #include <pthread.h>，线程模型不是 posix"; exit 1
  fi
  if grep -qE '^#define +__GTHREADS +1' "$gthr"; then
    grep -m2 -E '^#define +__GTHREADS' "$gthr" | sed 's/^/    /'
    echo "  OK   __GTHREADS 已定义，POSIX 线程模型生效"
  else
    echo "  FAIL gthr-default.h 未定义 __GTHREADS"; exit 1
  fi
else
  echo "  FAIL $gthr 缺失"; exit 1
fi
echo "  libstdc++ 侧的佐证（bits/c++config.h 中的 _GLIBCXX_HAS_GTHREADS）："
grep -m1 '_GLIBCXX_HAS_GTHREADS' $LFS/usr/include/c++/$VER/$LFS_TGT/bits/c++config.h | sed 's/^/    /' || true
echo "  libgcc 侧的佐证（libgcc 里应有 pthread 相关符号）："
$LFS_TGT-nm -D --defined-only $LFS/usr/lib/libgcc_s.so.1 2>/dev/null | grep -c . | sed 's/^/    libgcc_s.so.1 导出符号数：/' || true
echo "（说明：本节产物只能在 chroot 之后运行，宿主上不执行 \$LFS/usr/bin/gcc --version）"
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
[ -d "$LFS/sources/$SRCDIR" ] && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR（含其中的 build/mpfr/gmp/mpc 子目录）"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"
echo "$LFS 占用：$(du -sh $LFS 2>/dev/null | cut -f1)"
df -h "$LFS" | tail -n1

echo
echo "===== §6.18 完成，结束时间：$(date -Is) ====="
echo "===== 第 6 章（Cross Compiling Temporary Tools）到此结束，下一步是第 7 章 Entering Chroot ====="
