#!/usr/bin/env bash
set -euo pipefail
PKG=openssl-3.6.1; cd /sources; test ! -d "$PKG"; tar -xf "$PKG.tar.gz"; cd "$PKG"
./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
make
HARNESS_JOBS="${HARNESS_JOBS:-$(nproc)}" make test
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install
mv -v /usr/share/doc/openssl /usr/share/doc/openssl-3.6.1
cd /sources; rm -rf "$PKG"
