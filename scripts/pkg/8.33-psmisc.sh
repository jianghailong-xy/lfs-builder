#!/usr/bin/env bash
set -euo pipefail

PKG=psmisc-23.7
cd /sources

echo "===== LFS 13.0-systemd §8.33 Psmisc-23.7 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-（未设置）}"
echo
echo "----- 前置检查：§8.32 Sed-4.9 产物 -----"
test -x /usr/bin/sed || { echo "FAIL 缺少上一任务产物：/usr/bin/sed"; exit 1; }
/usr/bin/sed --version | head -n1
(/usr/bin/sed --version | head -n1 | grep -Fq "sed (GNU sed) 4.9") || {
  echo "FAIL：上一任务安装的 sed 版本不是 4.9"
  exit 1
}
echo "OK   /usr/bin/sed 为 GNU sed 4.9"
echo
echo "----- 源码校验与解包 -----"
test -f "$PKG.tar.xz"
grep -E " $PKG.tar.xz$" md5sums | tee /tmp/psmisc-md5-line
md5sum -c /tmp/psmisc-md5-line
rm -f /tmp/psmisc-md5-line
test ! -d "$PKG" || { echo "FAIL：开始前存在旧构建目录 /sources/$PKG"; exit 1; }
tar -xf "$PKG.tar.xz"
cd "$PKG"
echo "源码目录：$PWD"
echo "本节无补丁（官方 §8.33 未规定 patch 命令）。"
echo
echo "----- 配置：./configure --prefix=/usr -----"
./configure --prefix=/usr
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
for f in fuser killall peekfd prtstat pslog pstree; do
  test -x "/usr/bin/$f" || { echo "FAIL 缺少安装程序：/usr/bin/$f"; exit 1; }
  echo "OK   /usr/bin/$f"
done
test -L /usr/bin/pstree.x11
test "$(readlink /usr/bin/pstree.x11)" = "pstree"
/usr/bin/pstree --version
/usr/bin/killall --version | head -n1
ls -l /usr/bin/fuser /usr/bin/killall /usr/bin/peekfd /usr/bin/prtstat /usr/bin/pslog /usr/bin/pstree /usr/bin/pstree.x11
echo "OK   本节列出的程序均已安装，pstree.x11 链接正确。"
echo
echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf "$PKG"
test ! -e "/sources/$PKG"
echo "OK   已删除 /sources/$PKG；tarball 保留。"
echo
echo "===== §8.33 Psmisc-23.7 完成：$(date -Is) ====="
