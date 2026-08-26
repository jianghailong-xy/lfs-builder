#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.52 Sqlite-3510200 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.51 Libffi-3.5.2 产物 -----"
test -e /usr/lib/libffi.so
test -f /usr/include/ffi.h
test -f /usr/include/ffitarget.h
test -f /usr/lib/pkgconfig/libffi.pc
test ! -e /usr/lib/libffi.a
test ! -e /sources/libffi-3.5.2
test "$(pkg-config --modversion libffi)" = 3.5.2
echo "OK   Libffi 3.5.2 产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum sqlite-autoconf-3510200.tar.gz sqlite-doc-3510200.tar.xz
echo '49600a5739d382c648b1a317e4b57446  sqlite-autoconf-3510200.tar.gz' | md5sum -c -
echo '6f798c5dcd409ee563684c70be7e16fe  sqlite-doc-3510200.tar.xz' | md5sum -c -
test ! -e /sources/sqlite-autoconf-3510200
tar -xvf sqlite-autoconf-3510200.tar.gz
cd sqlite-autoconf-3510200
echo "源码目录：$PWD"
echo "补丁：本节无补丁。"
echo

echo "----- 解包文档（手册命令） -----"
tar -xf ../sqlite-doc-3510200.tar.xz
test -d sqlite-doc-3510200
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr     \
            --disable-static  \
            --enable-fts{4,5} \
            CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 \
                      -D SQLITE_ENABLE_UNLOCK_NOTIFY=1   \
                      -D SQLITE_ENABLE_DBSTAT_VTAB=1     \
                      -D SQLITE_SECURE_DELETE=1"
echo

echo "----- 编译（手册命令） -----"
make LDFLAGS.rpath=""
echo

echo "----- 测试 -----"
echo "手册明确说明：This package does not come with a test suite. 因此没有测试命令。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 安装文档（手册可选命令；本次执行） -----"
install -v -m755 -d /usr/share/doc/sqlite-3.51.2
cp -v -R sqlite-doc-3510200/* /usr/share/doc/sqlite-3.51.2
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/sqlite3
test -e /usr/lib/libsqlite3.so
test ! -e /usr/lib/libsqlite3.a
test -f /usr/include/sqlite3.h
test -f /usr/lib/pkgconfig/sqlite3.pc
test -d /usr/share/doc/sqlite-3.51.2
sqlite3 --version
test "$(pkg-config --modversion sqlite3)" = 3.51.2
for opt in ENABLE_COLUMN_METADATA ENABLE_UNLOCK_NOTIFY ENABLE_DBSTAT_VTAB SECURE_DELETE ENABLE_FTS4 ENABLE_FTS5; do
  sqlite3 ':memory:' 'pragma compile_options;' | grep -Fx "$opt"
done
readelf -d /usr/lib/libsqlite3.so | grep -E 'RPATH|RUNPATH' && {
  echo "FAIL libsqlite3.so 含有 RPATH/RUNPATH" >&2
  exit 1
} || true
ls -l /usr/bin/sqlite3 /usr/lib/libsqlite3.so* /usr/include/sqlite3.h /usr/lib/pkgconfig/sqlite3.pc /usr/share/doc/sqlite-3.51.2
echo "OK   Sqlite 3.51.2 程序、共享库、头文件、pkg-config 元数据和文档已安装；所需编译选项已启用，静态库未安装，共享库无 RPATH/RUNPATH。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/sqlite-autoconf-3510200
test ! -e /sources/sqlite-autoconf-3510200
test -f /sources/sqlite-autoconf-3510200.tar.gz
test -f /sources/sqlite-doc-3510200.tar.xz
echo "OK   已删除 /sources/sqlite-autoconf-3510200；两个源码包保留。"
echo
echo "===== §8.52 Sqlite-3510200 完成：$(date -Is) ====="
