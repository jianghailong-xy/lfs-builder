#!/usr/bin/env bash
set -euo pipefail
PKG=diffutils-3.12; cd /sources; test ! -d "$PKG"; tar -xf "$PKG.tar.xz"; cd "$PKG"
./configure --prefix=/usr
make
make check
make install
cd /sources; rm -rf "$PKG"
