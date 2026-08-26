#!/usr/bin/env bash
# §8.31 Ncurses-6.6 试建（chroot 内 /tmp，DESTDIR 安装，不写系统）
# 目的：为正式脚本校准断言（程序数、库名、terminfo 条目、curses.h 的 sed 命中行数…）
set -uo pipefail
T=/tmp/ncurses-trial
rm -rf "$T"; mkdir -p "$T"; cd "$T"
tar -xf /sources/ncurses-6.6.tar.gz
cd ncurses-6.6
echo "=== 环境 ==="
gcc --version | head -1; g++ --version | head -1; pkg-config --version
echo "PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-未设置}"
echo "=== configure ==="
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig > c.log 2>&1
echo "configure rc=$?"
tail -25 c.log
echo "=== make ==="
make > m.log 2>&1
echo "make rc=$?"; tail -5 m.log
echo "=== make DESTDIR install ==="
make DESTDIR=$PWD/dest install > i.log 2>&1
echo "install rc=$?"; tail -5 i.log
echo "=== dest 树概览 ==="
find dest -maxdepth 4 -type d | sort | head -40
echo "--- dest/usr/bin ---"; ls dest/usr/bin
echo "--- dest/usr/lib (非 pkgconfig) ---"; ls -l dest/usr/lib | sed 's/  */ /g'
echo "--- dest/usr/lib/pkgconfig ---"; ls dest/usr/lib/pkgconfig
echo "--- dest/usr/include ---"; ls dest/usr/include
echo "--- 静态库(.a) 应为 0 个 ---"; find dest -name '*.a' | wc -l
echo "--- 各类文件数 ---"
echo "man 页: $(find dest/usr/share/man -type f | wc -l)"
for n in 1 3 5 7; do echo "  man$n: $(ls dest/usr/share/man/man$n 2>/dev/null | wc -l)"; done
echo "terminfo 条目: $(find dest/usr/share/terminfo -type f | wc -l)"
echo "terminfo 目录: $(find dest/usr/share/terminfo -maxdepth 1 -type d | wc -l)"
echo "tabset: $(ls dest/usr/share/tabset 2>/dev/null | wc -l)"
echo "总文件数: $(find dest -type f | wc -l)  总链接数: $(find dest -type l | wc -l)"
echo "=== curses.h 的 XOPEN sed ==="
echo "命中行(执行前):"; grep -n '^#if.*XOPEN.*$' dest/usr/include/curses.h
cp dest/usr/include/curses.h /tmp/curses.h.before
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
echo "diff:"; diff /tmp/curses.h.before dest/usr/include/curses.h
echo "=== SONAME / 实体库 ==="
for f in $(find dest/usr/lib -maxdepth 1 -name '*.so.*' -type f | sort); do
  echo "$f  SONAME=$(readelf -d $f | grep SONAME | sed 's/.*\[//;s/\]//')"
done
echo "=== .pc 文件内容示例 ==="
cat dest/usr/lib/pkgconfig/ncursesw.pc
echo "=== doc 目录 ==="
ls doc | head; echo "doc 文件数: $(find doc -type f | wc -l)"
echo "=== test/README 头 ==="
sed -n '1,40p' test/README
echo "=== 大小 ==="
du -sh "$T" dest
