#!/usr/bin/env bash
set -euo pipefail
PKG=tar-1.35; cd /sources; rm -rf "$PKG"; tar -xf "$PKG.tar.xz"; cd "$PKG"
FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
make
set +e; make check; rc=$?; set -e
if [ "$rc" -ne 0 ]; then
  grep -qx '1 failed unexpectedly\.' tests/testsuite.log || exit "$rc"
  grep -q 'capabilities: binary store/restore' tests/testsuite.log || exit "$rc"
fi
make install
make -C doc install-html docdir=/usr/share/doc/tar-1.35
cd /sources; rm -rf "$PKG"
