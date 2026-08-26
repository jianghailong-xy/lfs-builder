#!/usr/bin/env bash
set -euo pipefail

PKG=gettext-1.0
cd /sources

echo "===== LFS 13.0-systemd §8.34 Gettext-1.0 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-（未设置）}"
echo
echo "----- 前置检查：§8.33 Psmisc-23.7 产物 -----"
for f in fuser killall peekfd prtstat pslog pstree; do
  test -x "/usr/bin/$f" || { echo "FAIL 缺少上一任务产物：/usr/bin/$f"; exit 1; }
  echo "OK   /usr/bin/$f"
done
test -L /usr/bin/pstree.x11
test "$(readlink /usr/bin/pstree.x11)" = pstree
/usr/bin/pstree --version
echo "OK   Psmisc 23.7 及 pstree.x11 链接可用。"
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
echo "本节无补丁（官方 §8.34 未规定 patch 或 sed 命令）。"
echo
echo "----- 配置 -----"
echo "./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/gettext-1.0"
./configure --prefix=/usr \
            --disable-static \
            --docdir=/usr/share/doc/gettext-1.0
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
echo "chmod -v 0755 /usr/lib/preloadable_libintl.so"
chmod -v 0755 /usr/lib/preloadable_libintl.so
echo
echo "----- 安装结果验证 -----"
for f in gettext gettext.sh gettextize msgattrib msgcat msgcmp msgcomm msgconv msgen msgexec msgfilter msgfmt msggrep msginit msgmerge msgunfmt msguniq ngettext recode-sr-latin xgettext; do
  test -e "/usr/bin/$f" || { echo "FAIL 缺少安装文件：/usr/bin/$f"; exit 1; }
done
test -x /usr/lib/preloadable_libintl.so
/usr/bin/gettext --version | head -n1
/usr/bin/msgfmt --version | head -n1
ls -l /usr/lib/preloadable_libintl.so
test -d /usr/share/doc/gettext-1.0
echo "OK   Gettext 程序、preloadable_libintl.so 权限及文档目录均已验证。"
echo
echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf "$PKG"
test ! -e "/sources/$PKG"
echo "OK   已删除 /sources/$PKG；tarball 保留。"
echo
echo "===== §8.34 Gettext-1.0 完成：$(date -Is) ====="
