#!/usr/bin/env bash
# §8.29 Shadow-4.19.3 —— chroot /tmp 内的试建（DESTDIR，不写系统），
# 用于校准正式脚本里每一条自检断言。本包无测试套件（手册原文：
# "This package does not come with a test suite."）。
set -uo pipefail
VER=4.19.3
T=/tmp/sh-trial
D=/tmp/sh-dest
rm -rf "$T" "$D"; mkdir -p "$T" "$D"; cd "$T"

echo "===== 环境 ====="
echo "date=$(date -Is)  nproc=$(nproc)  MAKEFLAGS=${MAKEFLAGS:-none}"
echo "glibc: $(/usr/bin/ldd --version | head -n1)"
echo "gcc:   $(gcc -dumpfullversion 2>/dev/null)"
echo "libcrypt(§8.28)：$( { ls -l /usr/lib/libcrypt.so.2 2>&1 || true; } | tr -s ' ')"
echo "已存在的 shadow 相关文件（安装前应基本为空）："
{ ls -l /usr/bin/passwd /usr/bin/login /usr/sbin/useradd /etc/login.defs \
        /etc/default /usr/lib/libsubid* /usr/include/shadow 2>&1 || true; } | sed 's/^/  /'
echo

echo "===== 解包 ====="
tar -xf /sources/shadow-$VER.tar.xz
cd shadow-$VER
echo "顶层：$(ls | tr '\n' ' ')"
echo

echo "===== 手册 sed/find 组 1（去掉 groups 及三个重复 man 页）校准 ====="
echo "--- src/Makefile.in 中是否存在 'groups\$(EXEEXT) '"
{ grep -c 'groups\$(EXEEXT) ' src/Makefile.in || true; } | sed 's/^/  匹配行数：/'
{ grep -n 'groups' src/Makefile.in || true; } | sed 's/^/  含 groups 的行：/' | head -5
echo "--- man 树中含 'groups\.1 ' 的 Makefile.in"
{ grep -rl 'groups\.1 ' man --include='Makefile.in' || true; } | sed 's/^/  /'
echo "--- man 树中含 'getspnam\.3 ' 的 Makefile.in"
{ grep -rl 'getspnam\.3 ' man --include='Makefile.in' || true; } | sed 's/^/  /' | tr '\n' ' '; echo
{ grep -rl 'getspnam\.3 ' man --include='Makefile.in' || true; } | wc -l | sed 's/^/  文件数：/'
echo "--- man 树中含 'passwd\.5 ' 的 Makefile.in"
{ grep -rl 'passwd\.5 ' man --include='Makefile.in' || true; } | wc -l | sed 's/^/  文件数：/'
echo "--- man/Makefile.in 的 man_MANS（sed 前）"
{ sed -n '/^man_MANS = /,/[^\\]$/p' man/Makefile.in || true; } | sed 's/^/  /'
md5_src_before=$(md5sum src/Makefile.in | awk '{print $1}')
cp man/Makefile.in /tmp/sh-man-Makefile.in.orig

sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
echo "四条命令退出码：$?"
md5_src_after=$(md5sum src/Makefile.in | awk '{print $1}')
echo "  src/Makefile.in md5 前/后：$md5_src_before / $md5_src_after"
echo "--- man/Makefile.in 的 man_MANS（sed 后）"
{ sed -n '/^man_MANS = /,/[^\\]$/p' man/Makefile.in || true; } | sed 's/^/  /'
echo "--- man/Makefile.in diff"
{ diff -u /tmp/sh-man-Makefile.in.orig man/Makefile.in || true; } | sed 's/^/  /'
echo "--- sed 后 man 树中残留的 getspnam.3 / passwd.5 / groups.1（Makefile.in）"
{ grep -rn 'getspnam\.3\|passwd\.5\|groups\.1' man --include='Makefile.in' || true; } | sed 's/^/  /' | head -20
echo

echo "===== 手册 sed 组 2（login.defs）校准 ====="
cp etc/login.defs /tmp/sh-login.defs.orig
{ grep -n 'ENCRYPT_METHOD\|/var/spool/mail\|^ENV_\(SU\)\?PATH\|PATH=' etc/login.defs || true; } | sed 's/^/  前：/'
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs
echo "sed 退出码：$?"
{ grep -n 'ENCRYPT_METHOD\|/var/mail\|/var/spool/mail\|PATH=' etc/login.defs || true; } | sed 's/^/  后：/'
echo "--- login.defs diff"
{ diff -u /tmp/sh-login.defs.orig etc/login.defs || true; } | sed 's/^/  /'
echo

echo "===== touch /usr/bin/passwd（手册要求；试建后若仍为空文件会被删除）====="
had_passwd=no; [ -e /usr/bin/passwd ] && had_passwd=yes
echo "  touch 前 /usr/bin/passwd 存在：$had_passwd"
touch /usr/bin/passwd
{ ls -l /usr/bin/passwd || true; } | sed 's/^/  /'
echo

echo "===== configure ====="
./configure --sysconfdir=/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --disable-logind    \
            --with-group-name-max-length=32 > /tmp/sh-conf.log 2>&1
echo "configure 退出码：$?"
echo "--- configure 结尾的配置摘要"
tail -n 40 /tmp/sh-conf.log | sed 's/^/  /'
echo "--- config.h 关键宏"
{ grep -E '^#define (PASSWD_PROGRAM|USE_YESCRYPT|USE_BCRYPT|USE_SHA_CRYPT|ENABLE_SUBIDS|GROUP_NAME_MAX_LENGTH|SHADOWGRP|WITH_LIBBSD|USE_LOGIND|HAVE_LIBECONF|HAVE_LIBCRYPT)' config.h || true; } | sed 's/^/  /'
echo "--- prefix / exec_prefix / bindir / ubindir"
{ grep -E '^(prefix|exec_prefix|bindir|sbindir|libdir|mandir|sysconfdir) =' Makefile || true; } | sed 's/^/  /'
{ grep -E '^(ubindir|usbindir) =' src/Makefile || true; } | sed 's/^/  /'
echo "--- libtool build_old_libs（前 3 处）"
{ grep -n 'build_old_libs=' libtool || true; } | sed -n '1,3p' | sed 's/^/  /'
echo "--- man 是否进入 SUBDIRS（ENABLE_REGENERATE_MAN）"
{ grep -n '^SUBDIRS = ' Makefile || true; } | sed 's/^/  /'
echo

echo "===== make ====="
make > /tmp/sh-make.log 2>&1
echo "make 退出码：$?"
tail -n 15 /tmp/sh-make.log | sed 's/^/  /'
echo "  警告条数：$( { grep -c 'warning:' /tmp/sh-make.log || true; } )"
echo "  源码树内 .a 文件数：$( { find . -name '*.a' || true; } | wc -l )"
{ find . -name '*.a' || true; } | sed 's/^/    /' | head
echo

echo "===== DESTDIR 安装（手册两条 install 命令）====="
make exec_prefix=/usr DESTDIR=$D install > /tmp/sh-inst.log 2>&1
echo "make exec_prefix=/usr install 退出码：$?"
tail -n 10 /tmp/sh-inst.log | sed 's/^/  /'
make -C man DESTDIR=$D install-man > /tmp/sh-instman.log 2>&1
echo "make -C man install-man 退出码：$?"
tail -n 10 /tmp/sh-instman.log | sed 's/^/  /'
echo

echo "===== 安装产物清单（校准正式脚本的判据）====="
echo "--- 非 man 的全部文件与符号链接"
{ find $D -path "$D/usr/share/man" -prune -o \( -type f -o -type l \) -printf '%y %M %10s %P\n' 2>/dev/null || true; } | sort -k4 | sed 's/^/  /'
echo "--- 计数"
echo "  普通文件：$( { find $D -path "$D/usr/share/man" -prune -o -type f -print || true; } | wc -l )"
echo "  符号链接：$( { find $D -path "$D/usr/share/man" -prune -o -type l -print || true; } | wc -l )"
echo "  man 页：  $( { find $D/usr/share/man -type f || true; } | wc -l )"
echo "--- man 页按节统计"
{ find $D/usr/share/man -type f -printf '%P\n' || true; } | sed 's|/.*||' | sort | uniq -c | sed 's/^/  /'
echo "--- man 页完整列表"
{ find $D/usr/share/man -type f -printf '%P\n' || true; } | sort | sed 's/^/  /'
echo "--- 目录"
{ find $D -type d -printf '%P\n' || true; } | sort | sed 's/^/  /'
echo "--- suid/sgid 位"
{ find $D -type f -perm /6000 -printf '%M %P\n' || true; } | sort | sed 's/^/  /'
echo "--- 符号链接目标"
{ find $D -type l -printf '%P -> %l\n' || true; } | sort | sed 's/^/  /'
echo "--- libsubid"
{ ls -l $D/usr/lib/libsubid* 2>&1 || true; } | sed 's/^/  /'
{ readelf -d $D/usr/lib/libsubid.so.5.0.0 2>/dev/null | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/  /'
echo "--- 安装的 /etc 文件"
{ find $D/etc -type f -printf '%P\n' || true; } | sort | sed 's/^/  /'
echo "--- 安装后的 login.defs 关键项"
{ grep -E '^ENCRYPT_METHOD|MAIL_DIR|^ENV_PATH|^ENV_SUPATH' $D/etc/login.defs || true; } | sed 's/^/  /'
echo

echo "===== 关键二进制的动态依赖与 yescrypt 支持 ====="
for b in usr/bin/passwd usr/bin/login usr/sbin/useradd usr/bin/chage usr/sbin/pwconv; do
  if [ -f "$D/$b" ]; then
    echo "  $b:"
    { readelf -d "$D/$b" 2>/dev/null | grep NEEDED || true; } | sed 's/^/      /'
  else
    echo "  $b: 不存在！"
  fi
done
echo "--- 版本号自报"
{ $D/usr/bin/chage --version 2>&1 || true; } | sed 's/^/  /'
{ $D/usr/sbin/useradd --version 2>&1 || true; } | sed 's/^/  /'
echo

echo "===== 清理试建 ====="
cd /
rm -rf "$T" "$D"
if [ "$had_passwd" = no ] && [ -f /usr/bin/passwd ] && [ ! -s /usr/bin/passwd ]; then
  rm -f /usr/bin/passwd
  echo "  已删除试建期间 touch 出来的空 /usr/bin/passwd（恢复试建前状态）"
fi
{ ls -l /usr/bin/passwd 2>&1 || true; } | sed 's/^/  /'
echo "试建结束：$(date -Is)"
