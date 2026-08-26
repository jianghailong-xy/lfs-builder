#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

cd /sources

echo "===== LFS 13.0-systemd §8.80 Man-DB-2.13.1 ====="
echo "start: $(date -Iseconds)"

echo "===== 上一任务产物与源码校验 ====="
test -x /usr/bin/dbus-daemon
test -e /usr/lib/libdbus-1.so
test -s /usr/lib/pkgconfig/dbus-1.pc
/usr/bin/dbus-daemon --version | head -1
echo 'b6335533cbeac3b24cd7be31fdee8c83  man-db-2.13.1.tar.xz' | md5sum -c -
test ! -e man-db-2.13.1 || {
  echo "错误：/sources/man-db-2.13.1 已存在；保留现场并停止。" >&2
  exit 1
}
echo "OK: §8.79 D-Bus 关键产物和 Man-DB 源码包可用。"

echo "===== 解包 ====="
tar -xf man-db-2.13.1.tar.xz
cd man-db-2.13.1

echo "===== 补丁 ====="
echo "INFO: LFS 13.0-systemd §8.80 未规定补丁。"

echo "===== 配置 ====="
./configure --prefix=/usr                         \
            --docdir=/usr/share/doc/man-db-2.13.1 \
            --sysconfdir=/etc                     \
            --disable-setuid                      \
            --enable-cache-owner=bin              \
            --with-browser=/usr/bin/lynx          \
            --with-vgrind=/usr/bin/vgrind         \
            --with-grap=/usr/bin/grap

echo "===== 编译 ====="
make

echo "===== 测试 ====="
make check
echo "TEST_RESULT: PASS"

echo "===== 安装 ====="
make install

echo "===== 安装结果验证 ====="
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
