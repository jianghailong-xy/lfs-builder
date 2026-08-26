#!/usr/bin/env bash
set -euo pipefail
PKG=flit_core-3.12.0; cd /sources; test ! -d "$PKG"; tar -xf "$PKG.tar.gz"; cd "$PKG"
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
pip3 install --no-index --find-links dist flit_core
cd /sources; rm -rf "$PKG"
