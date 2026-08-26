#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.46 Intltool-0.51.0 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.45 XML::Parser-2.47 产物 -----"
test -x /usr/bin/perl
test ! -e /sources/XML-Parser-2.47
/usr/bin/perl -MXML::Parser -e 'print "XML::Parser version=$XML::Parser::VERSION\n"'
test "$(/usr/bin/perl -MXML::Parser -e 'print $XML::Parser::VERSION')" = 2.47
/usr/bin/perl -MXML::Parser::Expat -e 'print "XML::Parser::Expat load OK\n"'
echo "OK   XML::Parser 2.47 可加载，且上一节源码构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum intltool-0.51.0.tar.gz
echo '12e517cac2b57a0121cda351570f1e63  intltool-0.51.0.tar.gz' | md5sum -c -
test ! -e /sources/intltool-0.51.0
tar -xvf intltool-0.51.0.tar.gz
cd intltool-0.51.0
echo "源码目录：$PWD"
echo

echo "----- 修正 Perl 5.22 及更高版本触发的警告（手册 sed 命令） -----"
sed -i 's:\\\${:\\$\\{:' intltool-update.in
echo

echo "----- 配置（手册命令：./configure --prefix=/usr） -----"
./configure --prefix=/usr
echo

echo "----- 编译（手册命令：make） -----"
make
echo

echo "----- 测试（手册命令：make check） -----"
make check
echo "OK   make check 退出码为 0。"
echo

echo "----- 安装（手册命令） -----"
make install
install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
echo

echo "----- 安装结果验证 -----"
for program in intltool-extract intltool-merge intltool-prepare intltool-update intltoolize; do
    test -x "/usr/bin/$program"
    echo "OK   /usr/bin/$program"
done
test -d /usr/share/intltool
test -f /usr/share/doc/intltool-0.51.0/I18N-HOWTO
/usr/bin/intltool-update --version
ls -ld /usr/share/intltool /usr/share/doc/intltool-0.51.0
ls -l /usr/share/doc/intltool-0.51.0/I18N-HOWTO
echo "OK   五个程序、共享数据目录及 I18N-HOWTO 均已安装。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/intltool-0.51.0
test ! -e /sources/intltool-0.51.0
test -f /sources/intltool-0.51.0.tar.gz
echo "OK   已删除 /sources/intltool-0.51.0；tarball 保留。"
echo
echo "===== §8.46 Intltool-0.51.0 完成：$(date -Is) ====="
