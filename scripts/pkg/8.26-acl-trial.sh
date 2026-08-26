#!/usr/bin/env bash
# 试建（不写系统）：在 chroot 的 /tmp 里完整跑一遍 §8.26，用来校准正式脚本的自检断言。
set -uo pipefail
export LC_ALL=C LANG=C
T=/tmp/acl-trial
rm -rf "$T"; mkdir -p "$T"
cd "$T"
echo "nproc=$(nproc)  MAKEFLAGS=${MAKEFLAGS:-}  TESTSUITEFLAGS=${TESTSUITEFLAGS:-}"
tar -xf /sources/acl-2.3.2.tar.xz
cd acl-2.3.2
echo "===== configure ====="
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/acl-2.3.2 > "$T/configure.log" 2>&1
echo "configure rc=$?"
tail -n 20 "$T/configure.log"
echo "===== make ====="
make > "$T/make.log" 2>&1
echo "make rc=$?"
tail -n 5 "$T/make.log"
echo "===== make check ====="
make check > "$T/check.log" 2>&1
echo "make check rc=$?"
echo "----- check.log 尾部 -----"
tail -n 60 "$T/check.log"
echo "----- test-suite.log 是否存在 -----"
ls -l test-suite.log 2>&1
echo "----- 各 .log/.trs 结果 -----"
for f in $(find . -name '*.trs' | sort); do
  echo "== $f"; grep -E '^:(test-result|global-test-result|copy-in-global-log|recheck)' "$f" 2>/dev/null
done
echo "===== DESTDIR install ====="
make DESTDIR="$T/dest" install > "$T/install.log" 2>&1
echo "install rc=$?"
echo "----- 装出的文件树 -----"
find "$T/dest" -type f -o -type l | sort | sed "s|$T/dest||"
echo "----- libacl 实体名 -----"
ls -l "$T/dest/usr/lib/" 2>&1
readelf -d "$T/dest/usr/lib/libacl.so.1.1.2302" 2>/dev/null | grep -E 'SONAME|NEEDED'
