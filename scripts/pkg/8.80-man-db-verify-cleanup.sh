#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

echo "===== §8.80 安装后验证续执行 ====="
echo "start: $(date -Iseconds)"
test -d /sources/man-db-2.13.1
test -x /usr/sbin/accessdb
echo "OK: /usr/sbin/accessdb"
for program in apropos catman lexgrog man man-recode mandb manpath whatis; do
  test -x "/usr/bin/$program"
  echo "OK: /usr/bin/$program"
done
test -e /usr/lib/man-db/libman.so
test -e /usr/lib/man-db/libmandb.so
test -d /usr/libexec/man-db
test -d /usr/share/doc/man-db-2.13.1
/usr/bin/man --version
/usr/bin/mandb --version
echo "OK: Man-DB-2.13.1 关键程序、库和目录均已验证。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf -- man-db-2.13.1
test ! -e man-db-2.13.1
echo "OK: /sources/man-db-2.13.1 已删除，源码包保留。"
echo "finish: $(date -Iseconds)"
echo "FINAL_RESULT: SUCCESS"
