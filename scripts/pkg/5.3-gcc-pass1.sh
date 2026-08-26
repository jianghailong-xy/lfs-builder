#!/usr/bin/env bash
# LFS 13.0-systemd §5.3 GCC-15.2.0 - Pass 1
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
# 本节没有补丁；手册也未规定测试套件（Pass 1 仅 configure / make / make install，
# GCC 的 make check 要到 §8.30 最终构建时才执行）。
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=gcc
VER=15.2.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

MPFR_VER=4.2.2
GMP_VER=6.3.0
MPC_VER=1.3.1

echo "===== LFS 13.0-systemd §5.3 GCC-$VER - Pass 1 ====="
echo "开始时间：$(date -Is)"
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
[ "$LFS" = "/mnt/lfs" ] || { echo "错误：LFS 不是 /mnt/lfs" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点" >&2; exit 1; }
echo

echo "----- 前置检查：§5.2 Binutils Pass 1 的产物必须可用 -----"
for t in ld as ar ranlib; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少 §5.2 产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS/tools/bin/$LFS_TGT-ld --version | head -n1
echo

cd $LFS/sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
for f in $TARBALL mpfr-$MPFR_VER.tar.xz gmp-$GMP_VER.tar.xz mpc-$MPC_VER.tar.gz; do
  grep " $f\$" md5sums
  grep " $f\$" md5sums | md5sum -c -
done
echo

echo "----- 解包（手册 iii：只用 tar 解包） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "本节无补丁需要应用。"
echo

echo "----- 5.3.1 Installation of Cross GCC：解包 GMP / MPFR / MPC 到 GCC 源码树 -----"
tar -xf ../mpfr-$MPFR_VER.tar.xz
mv -v mpfr-$MPFR_VER mpfr
tar -xf ../gmp-$GMP_VER.tar.xz
mv -v gmp-$GMP_VER gmp
tar -xf ../mpc-$MPC_VER.tar.gz
mv -v mpc-$MPC_VER mpc
echo
echo "GCC 源码树内的三个依赖目录："
ls -d mpfr gmp mpc
echo

echo "----- x86_64 宿主：把 64 位库的默认目录名改成 lib -----"
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac
echo "diff -u gcc/config/i386/t-linux64{.orig,}："
diff -u gcc/config/i386/t-linux64.orig gcc/config/i386/t-linux64 || true
echo

echo "----- 手册推荐的专用构建目录 -----"
mkdir -v build
cd       build

echo
echo "----- configure / make / make install（time 计量 SBU） -----"
time { ../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.43 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++ &&
       make &&
       make install; }

echo
echo "----- 生成完整的内部 limits.h（手册 §5.3.1 结尾） -----"
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h

LIMITS_H=$(dirname $($LFS_TGT-gcc -print-libgcc-file-name))/include/limits.h
echo "生成的文件：$LIMITS_H"
ls -l "$LIMITS_H"
echo "行数：$(wc -l < "$LIMITS_H")"
echo "开头 5 行："
head -n5 "$LIMITS_H"
grep -q '#include_next' "$LIMITS_H" \
  && echo "OK   完整版内部 limits.h（含 #include_next，即会串到系统 limits.h）" \
  || { echo "FAIL 内部 limits.h 看起来仍是自包含的精简版"; exit 1; }
echo

echo "----- 安装结果检查 -----"
for t in gcc cpp g++ gcc-$VER; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  if [ -x "$f" ]; then
    printf 'OK   %s\n' "$f"
  else
    printf 'FAIL %s 缺失\n' "$f"; exit 1
  fi
done
echo
ls -l $LFS/tools/bin/
echo
$LFS_TGT-gcc --version | head -n1
$LFS_TGT-g++ --version | head -n1
echo
echo "交叉编译器 target/sysroot："
$LFS_TGT-gcc -dumpmachine
$LFS_TGT-gcc -print-sysroot
echo "libgcc.a：$($LFS_TGT-gcc -print-libgcc-file-name)"
echo
echo "默认 PIE / SSP 是否开启（--enable-default-pie / --enable-default-ssp）："
$LFS_TGT-gcc -v 2>&1 | grep -o -e --enable-default-pie -e --enable-default-ssp || true
echo
echo "$LFS/tools/lib/gcc 下的内部目录："
ls -d $LFS/tools/lib/gcc/$LFS_TGT/*/ 2>/dev/null || true

echo
echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
ls -d $LFS/sources/$SRCDIR 2>/dev/null && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -type d ! -path $LFS/sources | sed 's/^/  /' || true

echo
echo "===== §5.3 完成，结束时间：$(date -Is) ====="
