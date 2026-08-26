#!/usr/bin/env bash
set -euo pipefail

PKG=sed-4.9
cd /sources

echo "===== LFS 13.0-systemd §8.32 Sed-4.9 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-（未设置）}"
echo
echo "----- 前置检查：§8.31 Ncurses-6.6 产物 -----"
for f in /usr/bin/tic /usr/bin/tput /usr/lib/libncursesw.so.6.6 /usr/include/curses.h; do
  test -e "$f" || { echo "FAIL 缺少上一任务产物：$f"; exit 1; }
  echo "OK   $f"
done
/usr/bin/tic -V
/usr/bin/tput -V
echo
echo "----- 源码校验与解包 -----"
test -f "$PKG.tar.xz"
grep -E " $PKG.tar.xz$" md5sums | tee /tmp/sed-md5-line
md5sum -c /tmp/sed-md5-line
rm -f /tmp/sed-md5-line
test ! -d "$PKG" || { echo "FAIL：开始前存在旧构建目录 /sources/$PKG"; exit 1; }
tar -xf "$PKG.tar.xz"
cd "$PKG"
echo "源码目录：$PWD"
echo "本节无补丁（官方 §8.32 未规定 patch 命令）。"
echo
echo "----- 配置：./configure --prefix=/usr -----"
./configure --prefix=/usr
echo
echo "----- 编译：make -----"
make
echo
echo "----- 生成 HTML 文档：make html -----"
make html
test -s doc/sed.html
echo "OK   doc/sed.html 已生成（$(wc -c < doc/sed.html) bytes）"
echo
echo "----- 手册规定测试 -----"
echo "chown -R tester ."
chown -R tester .
echo 'su tester -c "PATH=$PATH make check"'
su tester -c "PATH=$PATH make check"
echo "测试结论：make check 退出码 0，无意外失败。"
echo
echo "----- 安装：make install -----"
echo "为避免并行 install 在覆盖当前 /usr/bin/sed 时产生执行竞态，本阶段令 make 串行；命令目标仍为手册规定的 install。"
MAKEFLAGS=-j1 make install
echo
echo "----- 安装 HTML 文档 -----"
install -d -m755 /usr/share/doc/sed-4.9
install -m644 doc/sed.html /usr/share/doc/sed-4.9
echo
echo "----- 安装结果验证 -----"
test -x /usr/bin/sed
test -s /usr/share/doc/sed-4.9/sed.html
/usr/bin/sed --version | head -n2
printf 'alpha\nbeta\n' | /usr/bin/sed -n '2p' | grep -Fx beta
ls -l /usr/bin/sed /usr/share/doc/sed-4.9/sed.html
echo "OK   程序与文档存在，sed 基本变换验证通过。"
echo
echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf "$PKG"
test ! -e "/sources/$PKG"
echo "OK   已删除 /sources/$PKG；tarball 保留。"
echo
echo "===== §8.32 Sed-4.9 完成：$(date -Is) ====="
