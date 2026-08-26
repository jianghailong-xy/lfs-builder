#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.60 Kmod-34.2 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.59 Meson-1.10.1 产物 -----"
test -x /usr/bin/meson
test "$(meson --version)" = "1.10.1"
test -x /usr/bin/ninja
test "$(ninja --version)" = "1.13.2"
test ! -e /sources/meson-1.10.1
echo "OK   Meson 1.10.1 与 Ninja 1.13.2 可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum kmod-34.2.tar.xz
echo '36f2cc483745e81ede3406fa55e1065a  kmod-34.2.tar.xz' | md5sum -c -
if [ -e /sources/kmod-34.2 ]; then
  echo "发现上次失败保留的源码目录；重试前清理该目录。"
  rm -rf /sources/kmod-34.2
fi
tar -xvf kmod-34.2.tar.xz
cd kmod-34.2
echo "源码目录：$PWD"
echo "本节无补丁。"
echo

echo "----- 配置（手册命令） -----"
mkdir -p build
cd build
meson setup --prefix=/usr ..    \
            --buildtype=release \
            -D manpages=false
echo

echo "----- 编译（手册命令） -----"
ninja
echo

echo "----- 测试 -----"
echo "手册说明：该测试套件需要原始（非 sanitized）内核头文件，超出 LFS 范围，因此本节不运行测试套件。"
echo

echo "----- 安装（手册命令） -----"
ninja install
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/kmod
test -x /usr/sbin/lsmod
test -e /usr/lib/libkmod.so
test -f /usr/lib/pkgconfig/libkmod.pc
/usr/bin/kmod --version
ls -l /usr/bin/kmod /usr/sbin/lsmod /usr/sbin/depmod /usr/sbin/insmod \
      /usr/sbin/modinfo /usr/sbin/modprobe /usr/sbin/rmmod \
      /usr/lib/libkmod.so /usr/lib/pkgconfig/libkmod.pc
test "$(pkg-config --modversion libkmod)" = "34.2"
echo "libkmod pkg-config version: $(pkg-config --modversion libkmod)"
echo "OK   Kmod 程序、管理命令、共享库及 pkg-config 元数据已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/kmod-34.2
test ! -e /sources/kmod-34.2
test -f /sources/kmod-34.2.tar.xz
echo "OK   已删除 /sources/kmod-34.2；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
/usr/bin/kmod --version
test "$(pkg-config --modversion libkmod)" = "34.2"
echo "OK   清理后 Kmod 与 libkmod 元数据仍可用。"
echo "===== §8.60 Kmod-34.2 完成：$(date -Is) ====="
