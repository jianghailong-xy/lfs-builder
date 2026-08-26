#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.66 GRUB-2.14 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.65 Groff-1.23.0 产物 -----"
test -x /usr/bin/groff
test -x /usr/bin/troff
test -d /usr/lib/groff
test -d /usr/share/groff
test ! -e /sources/groff-1.23.0
groff --version | head -n 1
echo "OK   Groff 1.23.0 关键产物可用，上一节构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
echo '383f9effad01c235d2535357ff717543  grub-2.14.tar.xz' | md5sum -c -
if [ -e /sources/grub-2.14 ]; then
  echo "发现上次失败保留的源码目录；重试前清理该目录。"
  rm -rf /sources/grub-2.14
fi
tar -xvf grub-2.14.tar.xz
cd grub-2.14
echo "源码目录：$PWD"
echo

echo "----- 修复 GRUB-2.14 引入的错误（手册 sed 命令） -----"
sed 's/--image-base/--nonexist-linker-option/' -i configure
grep -q -- '--nonexist-linker-option' configure
echo "OK   configure 中的 --image-base 已按手册替换。"
echo

echo "----- 配置（手册命令） -----"
unset {C,CPP,CXX,LD}FLAGS
./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --disable-efiemu  \
            --disable-werror
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试结论 -----"
echo "SKIP 手册明确不推荐运行本包测试套件：多数测试依赖有限 LFS 环境中不可用的软件包。"
echo "     因此未执行可选的 make check，符合 §8.66 的规定。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 安装结果验证 -----"
for program in grub-bios-setup grub-editenv grub-file grub-fstest grub-install \
               grub-mkconfig grub-mkimage grub-mkrescue grub-probe \
               grub-script-check; do
  test -x "/usr/bin/$program" || test -x "/usr/sbin/$program"
done
test -d /usr/lib/grub
test -d /etc/grub.d
test -d /usr/share/grub
grub-install --version
grub-mkconfig --version
grub-script-check --help | head -n 1
ls -ld /usr/lib/grub /etc/grub.d /usr/share/grub
echo "OK   GRUB 2.14 关键程序和目录均已安装且可执行。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/grub-2.14
test ! -e /sources/grub-2.14
test -f /sources/grub-2.14.tar.xz
echo "OK   已删除 /sources/grub-2.14；源码包保留。"
echo

echo "----- 清理后最终验证 -----"
grub-install --version
test -x /usr/sbin/grub-install
test -d /usr/lib/grub
echo "OK   清理后 GRUB 2.14 关键产物仍可用。"
echo "===== §8.66 GRUB-2.14 完成：$(date -Is) ====="
