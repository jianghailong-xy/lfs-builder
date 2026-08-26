#!/usr/bin/env bash
# LFS 13.0-systemd §5.2 Binutils-2.46.0 - Pass 1；在容器内以 lfs 用户执行。
set -euo pipefail

echo "===== LFS 13.0-systemd §5.2 Binutils-2.46.0 - Pass 1 ====="
echo "开始时间：$(date -Is)"
cd "$LFS/sources"
grep ' binutils-2.46.0.tar.xz$' md5sums | md5sum -c -
rm -rf binutils-2.46.0
tar -xf binutils-2.46.0.tar.xz
cd binutils-2.46.0
mkdir -v build
cd build
../configure --prefix="$LFS/tools" \
             --with-sysroot="$LFS" \
             --target="$LFS_TGT" \
             --disable-nls \
             --enable-gprofng=no \
             --disable-werror \
             --enable-new-dtags \
             --enable-default-hash-style=gnu
make
make install

for tool in ld as ar ranlib nm objdump readelf strip; do
    test -x "$LFS/tools/bin/$LFS_TGT-$tool"
done
"$LFS/tools/bin/$LFS_TGT-ld" --version | head -1
"$LFS/tools/bin/$LFS_TGT-as" --version | head -1
cd "$LFS/sources"
rm -rf binutils-2.46.0
echo "FINAL_RESULT: SUCCESS"
echo "结束时间：$(date -Is)"
