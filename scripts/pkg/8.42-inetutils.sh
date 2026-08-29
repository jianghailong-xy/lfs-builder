#!/usr/bin/env bash
set -euo pipefail

cd /sources

echo "===== LFS 13.0-systemd §8.42 Inetutils-2.7 ====="
echo "开始时间：$(date -Is)"
echo "执行环境：chroot，用户=$(id -un)，PATH=$PATH，MAKEFLAGS=${MAKEFLAGS:-<unset>}"
echo

echo "----- 前置检查：§8.41 Expat-2.7.4 产物 -----"
test -x /usr/bin/xmlwf
test -e /usr/lib/libexpat.so
test -f /usr/include/expat.h
test -d /usr/share/doc/expat-2.7.4
test ! -e /sources/expat-2.7.4
/usr/bin/xmlwf -h 2>&1 | head -n3 || true
echo "OK   Expat-2.7.4 程序、共享库、头文件与文档可用，上一构建目录已清理。"
echo

echo "----- 源码校验与解包 -----"
md5sum inetutils-2.7.tar.gz
echo 'eed294e7b170cbbb0ff86493ef4c1273  inetutils-2.7.tar.gz' | md5sum -c -
test ! -e /sources/inetutils-2.7
tar -xvf inetutils-2.7.tar.gz
cd inetutils-2.7
echo "源码目录：$PWD"
echo

echo "----- GCC 14.1+ 兼容性修改（手册命令） -----"
sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
test "$(grep -c 'def HAVE_TERMCAP_TGETENT' telnet/telnet.c)" -eq 0
echo "OK   HAVE_TERMCAP_TGETENT 条件宏已按手册替换。"
echo

echo "----- 配置（手册命令） -----"
./configure --prefix=/usr        \
            --bindir=/usr/bin    \
            --localstatedir=/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers
echo

echo "----- 编译（手册命令） -----"
make
echo

echo "----- 测试（手册命令：make check） -----"
set +e
make check
check_rc=$?
set -e
if [ "$check_rc" -eq 0 ]; then
  echo "OK   make check 退出码为 0。"
else
  echo "注意 make check 退出码为 $check_rc，逐项核对失败清单。"
  fails=$(sed -n 's/^FAIL: //p' tests/test-suite.log 2>/dev/null | sort -u)
  echo "     失败项：${fails:-（未能解析）}"
  # libls.sh 是上游 flaky 测试：它断言 ls -C 与 ls -Cf 输出必须不同，
  # 但只建 3 个条目；ext4 目录项顺序由 mkfs 时随机生成的 dir_index 哈希种子决定，
  # 种子恰好使 readdir 顺序等于字典序时，排序与不排序输出相同，断言必然失败。
  # 手册未把本项列为已知失败。因此不直接放行，而是独立复测 -f 是否真的关闭排序：
  # 在一个 readdir 顺序不等于字典序的目录上，-C 必须排序、-Cf 必须跟随 readdir。
  if [ "$fails" = "libls.sh" ]; then
    echo "     仅 libls.sh 失败，执行 -f 功能独立复测……"
    d=$(mktemp -d)
    for n in zulu alpha mike bravo yankee charlie; do : > "$d/$n"; done
    raw=$(/usr/bin/ls -f "$d" | grep -v '^\.') 
    srt=$(/usr/bin/ls "$d")
    if [ "$raw" = "$srt" ]; then
      echo "     复测环境无效：该目录 readdir 顺序恰等于字典序，无法判定，视为失败。"
      rm -rf "$d"; exit "$check_rc"
    fi
    got_f=$(./tests/ls -Cf "$d" | tr -s ' \n' ' ' | sed 's/ $//')
    got_C=$(./tests/ls -C  "$d" | tr -s ' \n' ' ' | sed 's/ $//')
    want_f=$(printf '%s' "$raw" | tr '\n' ' ' | sed 's/ $//')
    want_C=$(printf '%s' "$srt" | tr '\n' ' ' | sed 's/ $//')
    rm -rf "$d"
    echo "     -Cf 期望(readdir)：$want_f"
    echo "     -Cf 实际        ：$got_f"
    echo "     -C  期望(字典序)：$want_C"
    echo "     -C  实际        ：$got_C"
    if [ "$got_f" = "$want_f" ] && [ "$got_C" = "$want_C" ]; then
      echo "OK   -f 确实关闭排序、-C 确实排序，功能正确。"
      echo "     判定：libls.sh 属上游 flaky（依赖 mkfs 随机哈希种子），功能已独立验证通过，本节按通过处理。"
    else
      echo "FAIL -f/-C 行为与预期不符，属真实缺陷，不予放行。"
      exit "$check_rc"
    fi
  else
    echo "FAIL 失败项不止 libls.sh 或无法解析，按失败处理。"
    exit "$check_rc"
  fi
fi
echo

echo "----- 安装（手册命令） -----"
make install
echo

echo "----- 移动 ifconfig 到正确位置（手册命令） -----"
mv -v /usr/{,s}bin/ifconfig
echo

echo "----- 安装结果验证 -----"
for p in dnsdomainname ftp hostname ping ping6 talk telnet tftp traceroute; do
  test -x "/usr/bin/$p"
done
test -x /usr/sbin/ifconfig
test ! -e /usr/bin/ifconfig
ls -l /usr/bin/{dnsdomainname,ftp,hostname,ping,ping6,talk,telnet,tftp,traceroute} /usr/sbin/ifconfig
/usr/bin/hostname --version 2>&1 | head -n2 || true
/usr/sbin/ifconfig --version 2>&1 | head -n2 || true
echo "OK   手册列出的 10 个程序均已安装，ifconfig 位于 /usr/sbin。"
echo

echo "----- 清理源码构建目录 -----"
cd /sources
rm -rf /sources/inetutils-2.7
test ! -e /sources/inetutils-2.7
test -f /sources/inetutils-2.7.tar.gz
echo "OK   已删除 /sources/inetutils-2.7；tarball 保留。"
echo
echo "===== §8.42 Inetutils-2.7 完成：$(date -Is) ====="
