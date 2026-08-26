#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.37 Bash-5.3 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.36 Grep-3.12 产物 -----"
test -x /usr/bin/grep
test -x /usr/bin/egrep
test -x /usr/bin/fgrep
grep --version | head -n1
test ! -e /sources/grep-3.12
echo "OK   Grep-3.12 关键产物可用，且上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum bash-5.3.tar.gz
echo '977c8c0c5ae6309191e7768e28ebc951  bash-5.3.tar.gz' | md5sum -c -
test ! -e /sources/bash-5.3
tar -xvf bash-5.3.tar.gz
cd bash-5.3
echo "源码目录：$PWD"
echo "INFO 本节手册没有要求应用补丁。"
echo

echo "----- 配置 -----"
./configure --prefix=/usr             \
            --without-bash-malloc     \
            --with-installed-readline \
            --docdir=/usr/share/doc/bash-5.3
echo

echo "----- 编译 -----"
make
echo

echo "----- 测试准备（手册命令：chown -R tester .） -----"
chown -R tester .
echo

echo "----- 测试（手册规定：tester 用户、Expect 伪终端、LC_ALL=C.UTF-8） -----"
LC_ALL=C.UTF-8 su -s /usr/bin/expect tester << "EOF"
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
EOF
echo "OK   手册规定的 make tests 退出码为 0。"
echo "INFO 手册说明：diff 输出代表失败（明确标注可忽略者除外）；run-builtins 在部分宿主可有已知差异，缺少 zh_TW.BIG5/ja_JP.SJIS 也可导致已知失败。"
echo

echo "----- 安装 -----"
make install
echo

echo "----- 运行新安装的 Bash、验证并清理 -----"
echo "手册命令：exec /usr/bin/bash --login"
exec /usr/bin/bash --login -c '
set -euo pipefail
echo "当前 Bash：$BASH_VERSION；可执行文件：$(readlink -f /proc/$$/exe)"
test -x /usr/bin/bash
test -x /usr/bin/bashbug
test -L /usr/bin/sh
test "$(readlink /usr/bin/sh)" = "bash"
/usr/bin/bash --version | head -n1
ls -l /usr/bin/bash /usr/bin/bashbug /usr/bin/sh
test -d /usr/include/bash
test -d /usr/lib/bash
test -d /usr/share/doc/bash-5.3
printf "Bash %s OK\n" "$BASH_VERSION"
echo "OK   新安装 Bash 已运行；bash、bashbug、sh 链接及本节目录均已验证。"
echo
echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/bash-5.3
test ! -e /sources/bash-5.3
test -f /sources/bash-5.3.tar.gz
echo "OK   已删除 /sources/bash-5.3；tarball 保留。"
echo
echo "===== §8.37 Bash-5.3 完成：$(date -Is) ====="
'
