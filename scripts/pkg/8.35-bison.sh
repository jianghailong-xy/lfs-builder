#!/usr/bin/env bash
set -euo pipefail

PKG=bison-3.8.2
cd /sources

echo "===== LFS 13.0-systemd §8.35 Bison-3.8.2 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-（未设置）}"
echo
echo "----- 前置检查：§8.34 Gettext-1.0 产物 -----"
for f in gettext gettextize msgfmt xgettext; do
  test -x "/usr/bin/$f" || { echo "FAIL 缺少上一任务产物：/usr/bin/$f"; exit 1; }
  echo "OK   /usr/bin/$f"
done
/usr/bin/msgfmt --version | head -n1
test -x /usr/lib/preloadable_libintl.so
test ! -d /sources/gettext-1.0
echo "OK   Gettext 1.0 关键产物可用，且上一构建目录已清理。"
echo
echo "----- 源码校验与解包 -----"
test -f "$PKG.tar.xz"
md5_line=$(grep -E " $PKG.tar.xz$" md5sums)
test -n "$md5_line"
echo "$md5_line"
echo "$md5_line" | md5sum -c -
test ! -d "$PKG" || { echo "FAIL：开始前存在旧构建目录 /sources/$PKG"; exit 1; }
tar -xf "$PKG.tar.xz"
cd "$PKG"
echo "源码目录：$PWD"
echo "本节无补丁（LFS 13.0-systemd §8.35 未规定 patch 或 sed 命令）。"
echo
echo "----- 配置 -----"
echo "./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2"
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
echo
echo "----- 编译：make -----"
make
echo
echo "----- 手册规定测试：make check -----"
make check
echo "测试结论：make check 退出码 0，无意外失败。"
echo
echo "----- 安装：make install -----"
make install
echo
echo "----- 安装结果验证 -----"
test -x /usr/bin/bison
test -x /usr/bin/yacc
test -f /usr/lib/liby.a
test -d /usr/share/bison
test -d /usr/share/doc/bison-3.8.2
/usr/bin/bison --version | head -n1
ls -l /usr/bin/bison /usr/bin/yacc /usr/lib/liby.a
echo "OK   bison、yacc、liby.a、共享数据及版本化文档目录均已验证。"
echo
echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf "$PKG"
test ! -e "/sources/$PKG"
echo "OK   已删除 /sources/$PKG；tarball 保留。"
echo
echo "===== §8.35 Bison-3.8.2 完成：$(date -Is) ====="
