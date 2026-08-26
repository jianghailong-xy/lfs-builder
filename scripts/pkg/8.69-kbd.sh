#!/usr/bin/env bash
set -euo pipefail

echo "===== LFS 13.0-systemd §8.69 Kbd-2.9.0 ====="
echo "开始：$(date -Is)"
echo "用户：$(id)"
echo "PATH=$PATH"
echo "MAKEFLAGS=${MAKEFLAGS:-} TESTSUITEFLAGS=${TESTSUITEFLAGS:-}"
cd /sources

echo "----- 前置产物验证（§8.68 IPRoute2-6.18.0）-----"
ip -Version
test "$(ip -Version | sed -n 's/^ip utility, iproute2-\([^, ]*\).*/\1/p')" = 6.18.0
for p in ip ss tc bridge; do
  test -x "/usr/sbin/$p"
done
echo "OK   上一任务 IPRoute2-6.18.0 关键产物可用。"

echo "----- 源码包与补丁检查、解包 -----"
test -s kbd-2.9.0.tar.xz
test -s kbd-2.9.0-backspace-1.patch
sha256sum kbd-2.9.0.tar.xz kbd-2.9.0-backspace-1.patch
test ! -e kbd-2.9.0 || { echo "错误：构建目录 /sources/kbd-2.9.0 已存在，为避免覆盖现场而停止。" >&2; exit 1; }
tar -xvf kbd-2.9.0.tar.xz
cd kbd-2.9.0

echo "----- 补丁：kbd-2.9.0-backspace-1.patch -----"
patch -Np1 -i ../kbd-2.9.0-backspace-1.patch

echo "----- 移除冗余 resizecons 程序及手册页 -----"
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in

echo "----- 配置：./configure --prefix=/usr --disable-vlock -----"
./configure --prefix=/usr --disable-vlock

echo "----- 编译：make -----"
make

echo "----- 测试：make check -----"
make check
echo "OK   make check 退出码为 0。"

echo "----- 安装：make install -----"
make install

echo "----- 安装文档（手册可选步骤，本次执行）-----"
cp -R -v docs/doc -T /usr/share/doc/kbd-2.9.0

echo "----- 安装结果验证 -----"
for p in chvt deallocvt dumpkeys fgconsole getkeycodes kbdinfo kbd_mode kbdrate loadkeys loadunimap mapscrn openvt psfxtable setfont setkeycodes setleds setmetamode setvtrgb showconsolefont showkey unicode_start unicode_stop; do
  command -v "$p"
done
for p in psfaddtable psfgettable psfstriptable; do
  test -L "/usr/bin/$p"
  test "$(readlink "/usr/bin/$p")" = psfxtable
done
test ! -e /usr/bin/resizecons
test ! -e /usr/share/man/man8/resizecons.8
test ! -e /usr/bin/vlock
for d in /usr/share/consolefonts /usr/share/consoletrans /usr/share/keymaps /usr/share/unimaps /usr/share/doc/kbd-2.9.0; do
  test -d "$d"
done
loadkeys --version
test "$(loadkeys --version | awk 'NR==1 {print $NF}')" = 2.9.0
echo "OK   Kbd 2.9.0 程序、链接、数据目录、文档及禁用项验证通过。"

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf kbd-2.9.0
test ! -e kbd-2.9.0
echo "OK   已删除 /sources/kbd-2.9.0；源码包和补丁保留。"
echo "===== §8.69 Kbd-2.9.0 完成：$(date -Is) ====="
