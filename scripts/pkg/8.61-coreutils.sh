#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.61 Coreutils-9.10 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.60 Kmod-34.2 产物 -----"
test -x /usr/bin/kmod
test "$(pkg-config --modversion libkmod)" = "34.2"
test ! -e /sources/kmod-34.2
/usr/bin/kmod --version
echo "OK   Kmod 34.2 与 libkmod 元数据可用，上一节构建目录已清理。"
echo

echo "----- 源码与补丁校验、解包 -----"
echo 'b0482ebec42fd48e95cb9187d566b9e4  coreutils-9.10.tar.xz' | md5sum -c -
echo '6e9aea31b1662176101e6438a39fdad4  coreutils-9.10-i18n-1.patch' | md5sum -c -
if [ -e /sources/coreutils-9.10 ]; then
  echo "发现上次失败保留的源码目录；重试前清理该目录。"
  rm -rf /sources/coreutils-9.10
fi
tar -xvf coreutils-9.10.tar.xz
cd coreutils-9.10
echo "源码目录：$PWD"
echo

echo "----- 应用 i18n 补丁（手册命令） -----"
patch -Np1 -i ../coreutils-9.10-i18n-1.patch
echo

echo "----- 配置（手册命令） -----"
autoreconf -fv
automake -af
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=/usr
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试：root 测试（手册命令） -----"
make NON_ROOT_USERNAME=tester check-root
echo

echo "----- 测试：tester 测试（手册命令） -----"
groupadd -g 102 dummy -U tester
chown -R tester .
set +e
su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" < /dev/null
test_rc=$?
set -e
groupdel dummy
echo "tester 测试退出码：$test_rc"
if [ "$test_rc" -ne 0 ]; then
  echo "错误：Coreutils 测试套件存在失败；停止于安装前并保留源码目录与完整日志。" >&2
  exit "$test_rc"
fi
echo "OK   root 与 tester 测试全部通过。"
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 按 FHS 移动 chroot 与手册页（手册命令） -----"
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
echo

echo "----- 安装结果验证 -----"
test -x /usr/bin/ls
test -x /usr/sbin/chroot
test ! -e /usr/bin/chroot
test -f /usr/share/man/man8/chroot.8
test ! -e /usr/share/man/man1/chroot.1
head -n 3 /usr/share/man/man8/chroot.8 | grep -q '"8"'
test -f /usr/libexec/coreutils/libstdbuf.so
/usr/bin/ls --version | head -n 1
/usr/sbin/chroot --version | head -n 1
ls -l /usr/bin/ls /usr/sbin/chroot \
      /usr/share/man/man8/chroot.8 /usr/libexec/coreutils/libstdbuf.so
echo "OK   Coreutils 9.10 程序、FHS chroot 路径、man8 手册页及 libstdbuf.so 均已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/coreutils-9.10
test ! -e /sources/coreutils-9.10
test -f /sources/coreutils-9.10.tar.xz
test -f /sources/coreutils-9.10-i18n-1.patch
echo "OK   已删除 /sources/coreutils-9.10；源码包与补丁保留。"
echo

echo "----- 清理后最终验证 -----"
/usr/bin/ls --version | head -n 1
/usr/sbin/chroot --version | head -n 1
test -f /usr/libexec/coreutils/libstdbuf.so
echo "OK   清理后 Coreutils 关键产物仍可用。"
echo "===== §8.61 Coreutils-9.10 完成：$(date -Is) ====="
