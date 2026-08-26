#!/usr/bin/env bash
set -euo pipefail
echo "===== Chapter 8 independent final verification ====="
echo "Time: $(date -Is)"
echo "Identity: $(id)"
rc=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; rc=1; fi; }
check "no libtool .la files" "! find /usr/lib /usr/libexec -name '*.la' -print -quit | grep -q ."
check "temporary cross toolchain removed" "! find /usr -depth -name \"$(uname -m)-lfs-linux-gnu*\" -print -quit | grep -q ."
check "tester account removed" "! id tester >/dev/null 2>&1"
check "seven preserved compressed debug files" "[ \"$(find /usr/lib -maxdepth 1 -name '*.dbg' | wc -l)\" -eq 7 ]"
# scripts/chroot.sh installs this verifier itself at /tmp/.lfs-chroot-job.sh
# for the duration of the run; it removes the file immediately afterwards.
check "temporary directory contains only the active verification wrapper" \
  "! find /tmp -mindepth 1 ! -name .lfs-chroot-job.sh -print -quit | grep -q ."
for p in bash gcc g++ ld strip find awk sed grep make tar systemctl dbus-daemon e2fsck; do
  check "command $p is executable" "command -v $p >/dev/null"
done
printf 'int main(void){return 0;}\n' >/tmp/ch8-verify.c
if cc /tmp/ch8-verify.c -o /tmp/ch8-verify && /tmp/ch8-verify &&
   readelf -l /tmp/ch8-verify | grep -q '/lib64/ld-linux-x86-64.so.2'; then
  echo "PASS: native C compile, link, loader, and execution"
else
  echo "FAIL: native C compile/link/runtime sanity"; rc=1
fi
rm -f /tmp/ch8-verify.c /tmp/ch8-verify
/usr/lib/libc.so.6 | sed -n '1p'
gcc --version | sed -n '1p'
systemctl --version | sed -n '1p'
e2fsck -V 2>&1 | sed -n '1p'
[ "$rc" -eq 0 ] || exit "$rc"
echo "RESULT: PASS"
