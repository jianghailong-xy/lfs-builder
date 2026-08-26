#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.45 XML::Parser-2.47 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.44 Perl-5.42.0 产物及 Expat -----"
test -x /usr/bin/perl
test -f /usr/include/expat.h
test ! -e /sources/perl-5.42.0
/usr/bin/perl -V:version -V:archname -V:useshrplib
/usr/bin/perl -MExtUtils::MakeMaker -e 'print "ExtUtils::MakeMaker OK\n"'
echo "OK   Perl-5.42.0 可运行、MakeMaker 可加载、Expat 开发头存在，上一构建目录已清理。"
echo

echo "----- 源码校验、解包与补丁 -----"
md5sum XML-Parser-2.47.tar.gz
echo '89a8e82cfd2ad948b349c0a69c494463  XML-Parser-2.47.tar.gz' | md5sum -c -
test ! -e /sources/XML-Parser-2.47
tar -xvf XML-Parser-2.47.tar.gz
cd XML-Parser-2.47
echo "源码目录：$PWD"
echo "补丁：本节无补丁命令。"
echo

echo "----- 配置（手册命令：perl Makefile.PL） -----"
perl Makefile.PL
echo

echo "----- 编译（手册命令：make） -----"
make
echo

echo "----- 测试（手册命令：make test） -----"
make test
echo "OK   make test 退出码为 0。"
echo

echo "----- 安装（手册命令：make install） -----"
make install
echo

echo "----- 安装结果验证 -----"
/usr/bin/perl -MXML::Parser -e 'print "XML::Parser version=$XML::Parser::VERSION\n"'
/usr/bin/perl -MXML::Parser::Expat -e 'print "XML::Parser::Expat load OK\n"'
test "$(/usr/bin/perl -MXML::Parser -e 'print $XML::Parser::VERSION')" = 2.47
expat_so=$(/usr/bin/perl -MConfig -e 'print "$Config{installsitearch}/auto/XML/Parser/Expat/Expat.so"')
test -f "$expat_so"
ls -l "$expat_so"
echo "OK   XML::Parser 2.47 与 Expat.so 均已安装并可加载。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/XML-Parser-2.47
test ! -e /sources/XML-Parser-2.47
test -f /sources/XML-Parser-2.47.tar.gz
echo "OK   已删除 /sources/XML-Parser-2.47；tarball 保留。"
echo
echo "===== §8.45 XML::Parser-2.47 完成：$(date -Is) ====="

