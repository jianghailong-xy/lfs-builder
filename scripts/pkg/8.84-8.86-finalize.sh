#!/usr/bin/env bash
# LFS 13.0-systemd §§8.84--8.86: debugging-symbol note, stripping, cleanup,
# and the Chapter 8 userspace checkpoint.  Run as root inside the LFS chroot.
set -euo pipefail

marker=/var/lib/lfs/chapter-08-finalized
[ ! -e "$marker" ] || { echo "Chapter 8 finalization already completed: $marker"; exit 0; }

echo "===== LFS 13.0-systemd §§8.84--8.86 final userspace ====="
echo "Started: $(date -Is)"
[ "$(id -u)" -eq 0 ]

before_kib=$(du -skx /usr | awk '{print $1}')
echo "§8.84 About Debugging Symbols: record-only section; /usr before strip: ${before_kib} KiB"

echo "§8.85 Stripping"
save_usrlib="$(cd /usr/lib; ls ld-linux*[^g])
             libc.so.6
             libthread_db.so.1
             libquadmath.so.0.0.0
             libstdc++.so.6.0.34
             libitm.so.1.0.0
             libatomic.so.1.2.0"

cd /usr/lib
for LIB in $save_usrlib; do
    [ -f "$LIB" ] || { echo "Missing required library: /usr/lib/$LIB" >&2; exit 1; }
    objcopy --only-keep-debug --compress-debug-sections=zstd "$LIB" "$LIB.dbg"
    cp "$LIB" "/tmp/$LIB"
    strip --strip-debug "/tmp/$LIB"
    objcopy --add-gnu-debuglink="$LIB.dbg" "/tmp/$LIB"
    install -vm755 "/tmp/$LIB" /usr/lib
    rm "/tmp/$LIB"
done

online_usrbin="bash find strip"
online_usrlib="libbfd-2.46.0.20260210.so
               libsframe.so.3.0.0
               libhistory.so.8.3
               libncursesw.so.6.6
               libm.so.6
               libreadline.so.8.3
               libz.so.1.3.2
               libzstd.so.1.5.7
               $(cd /usr/lib; find libnss*.so* -type f)"

for BIN in $online_usrbin; do
    cp "/usr/bin/$BIN" "/tmp/$BIN"
    strip --strip-debug "/tmp/$BIN"
    install -vm755 "/tmp/$BIN" /usr/bin
    rm "/tmp/$BIN"
done
for LIB in $online_usrlib; do
    [ -f "/usr/lib/$LIB" ] || { echo "Missing required library: /usr/lib/$LIB" >&2; exit 1; }
    cp "/usr/lib/$LIB" "/tmp/$LIB"
    strip --strip-debug "/tmp/$LIB"
    install -vm755 "/tmp/$LIB" /usr/lib
    rm "/tmp/$LIB"
done

strip_warnings=/tmp/ch8-strip-warnings.log
: > "$strip_warnings"
for i in $(find /usr/lib -type f -name \*.so\* ! -name \*dbg) \
         $(find /usr/lib -type f -name \*.a)                 \
         $(find /usr/{bin,sbin,libexec} -type f); do
    case "$online_usrbin $online_usrlib $save_usrlib" in
        *$(basename "$i")*) ;;
        *) strip --strip-debug "$i" 2>>"$strip_warnings" || true ;;
    esac
done
echo "Expected non-ELF strip diagnostics: $(wc -l < "$strip_warnings") lines"

unset BIN LIB save_usrlib online_usrbin online_usrlib

echo "§8.86 Cleaning Up"
rm -rf /tmp/{*,.*}
find /usr/lib /usr/libexec -name \*.la -delete
find /usr -depth -name "$(uname -m)-lfs-linux-gnu*" -print -exec rm -rf {} +
if id tester >/dev/null 2>&1; then userdel -r tester; else echo "tester already absent"; fi

echo "Final userspace checks"
test "$(find /usr/lib /usr/libexec -name '*.la' -print -quit)" = ""
test "$(find /usr -depth -name "$(uname -m)-lfs-linux-gnu*" -print -quit)" = ""
! id tester >/dev/null 2>&1
for p in bash sh gcc g++ ld strip find awk sed grep make tar systemctl dbus-daemon e2fsck; do
    command -v "$p" >/dev/null || { echo "Missing command: $p" >&2; exit 1; }
done
printf 'int main(void){return 0;}\n' >/tmp/ch8-sanity.c
cc /tmp/ch8-sanity.c -o /tmp/ch8-sanity
/tmp/ch8-sanity
readelf -l /tmp/ch8-sanity | grep -q '/lib64/ld-linux-x86-64.so.2'
rm -f /tmp/ch8-sanity.c /tmp/ch8-sanity
/usr/lib/libc.so.6 | sed -n '1p'
gcc --version | sed -n '1p'
systemctl --version | sed -n '1p'
e2fsck -V 2>&1 | sed -n '1p'
dbg_count=$(find /usr/lib -maxdepth 1 -name '*.dbg' | wc -l)
[ "$dbg_count" -ge 7 ]
after_kib=$(du -skx /usr | awk '{print $1}')
echo "Preserved compressed debug files: $dbg_count"
echo "/usr after strip: ${after_kib} KiB; reclaimed: $((before_kib-after_kib)) KiB"
echo "RESULT: PASS -- Chapter 8 final userspace checks passed"
install -d /var/lib/lfs
printf 'LFS 13.0-systemd Chapter 8 finalized %s\n' "$(date -Is)" > "$marker"
echo "Finished: $(date -Is)"
