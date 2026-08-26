#!/usr/bin/env bash
# LFS 13.0-systemd §8.29 Shadow-4.19.3
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.29.1 Installation of Shadow 的命令序列（全部）：
#   sed -i 's/groups$(EXEEXT) //' src/Makefile.in
#   find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
#   find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
#   find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
#   sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
#       -e 's:/var/spool/mail:/var/mail:'                   \
#       -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
#       -i etc/login.defs
#   touch /usr/bin/passwd
#   ./configure --sysconfdir=/etc --disable-static --with-{b,yes}crypt \
#               --without-libbsd --disable-logind --with-group-name-max-length=32
#   make
#   （手册原文：This package does not come with a test suite.）
#   make exec_prefix=/usr install
#   make -C man install-man
# §8.29.2 Configuring Shadow：pwconv / grpconv / mkdir -p /etc/default / useradd -D --gid 999
# §8.29.3 Setting the Root Password：passwd root
#
# 手册 §8.29.1 开头的 Important/Note 两个提示框都以 "If you've installed Linux-PAM"
# / "If you would like to enforce the use of strong passwords ... install and configure
# Linux-PAM first" 为前提。本系统尚未安装 Linux-PAM（BLFS 内容，不在 LFS 范围内），
# 故按本页默认路径构建；脚本会在 configure 后实测确认 "PAM support: no"。
# 手册 §8.29.2 末尾的 `sed -i '/MAIL/s/yes/no/' /etc/default/useradd` 是**可选**的
# （原文：If you would rather not create these files, issue the following command），
# 本项目保留手册默认的 CREATE_MAIL_SPOOL=yes，故不执行该命令。
set -euo pipefail

PKG=shadow
VER=4.19.3
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
SEDLOG=/sources/.shadow-sed.log
CONFLOG=/sources/.shadow-configure.log
MAKELOG=/sources/.shadow-make.log
INSTLOG=/sources/.shadow-make-install.log
MANLOG=/sources/.shadow-install-man.log
CFGLOG=/sources/.shadow-configuring.log

# §8.29.3 的 root 口令。手册的 `passwd root` 是交互式的（从 /dev/tty 读两遍口令），
# 而本项目的 chroot 执行是非交互的（docker exec 未分配 tty），因此改用 shadow 自带的
# `passwd --stdin root`（4.19.3 的 passwd(1) 原生选项：-s, --stdin  read new token
# from stdin，仅 root 可用），这与手册命令是**同一个程序、同一条代码路径**，只是口令
# 来源从 tty 换成 stdin。口令明文记录在本日志里，供后续 QEMU 验收任务登录使用。
ROOT_PASSWORD=lfs

echo "===== LFS 13.0-systemd §8.29 Shadow-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Shadow package contains programs for handling passwords in a secure way."
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 115 MB"
echo
echo "----- chroot 环境自述（手册 §7.4） -----"
echo "date      : $(date -Is)"
echo "kernel    : $(uname -srm)"
echo "PATH      : $PATH"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
esac
echo "  OK   PATH 中不含 /tools/bin"
echo

rc=0
fail() { echo "  FAIL $*"; rc=1; }
ok()   { echo "  OK   $*"; }

# =========================================================================
echo "================= 前置检查（上一任务产物与本节依赖） ================="

echo "--- 1. 上一任务 §8.28 Libxcrypt-4.5.2 的产物是否可用"
# 本节**真的**依赖它：--with-{b,yes}crypt 让 shadow 用 Libxcrypt 实现的 bcrypt /
# yescrypt 做口令散列，passwd/login/su 等会链接 libcrypt.so.2。
for f in /usr/lib/libcrypt.so.2.0.0 /usr/lib/libcrypt.so.2 /usr/lib/libcrypt.so /usr/include/crypt.h; do
  if [ -e "$f" ]; then ok "存在 $f"; else fail "缺失 $f（§8.28 产物）"; fi
done
echo "  libcrypt.so.2 的 SONAME 与导出符号数（用于确认 §8.28 产物完好）："
{ readelf -d /usr/lib/libcrypt.so.2.0.0 | grep SONAME || true; } | sed 's/^/    /'
echo "    nm -D --defined-only 计数：$( { nm -D --defined-only /usr/lib/libcrypt.so.2.0.0 || true; } | wc -l )"
echo "  libcrypt 是否提供 yescrypt/bcrypt（本节 --with-{b,yes}crypt 的前提）："
# 注意：nm 打出来的符号带版本后缀（如 crypt@@XCRYPT_2.0），判断前必须先把 @@... 去掉，
# 否则 " crypt " 这种整词匹配永远不成立——这是自检写法的坑，不是产物的问题。
crypt_syms=$( { nm -D --defined-only /usr/lib/libcrypt.so.2.0.0 || true; } | awk '{print $NF}' | sed 's/@@.*//' | sort -u | tr '\n' ' ')
echo "    导出符号（已去掉 @@版本 后缀）：$crypt_syms"
case " $crypt_syms " in
  *" crypt "*) ok "libcrypt 导出 crypt/crypt_r（yescrypt/bcrypt 由其内部 hash 表提供，§8.28 已确认 strong,glibc 含 bcrypt+yescrypt）" ;;
  *) fail "libcrypt 未导出 crypt" ;;
esac

echo "--- 2. 本节真正需要的工具（只列本节确实要用、且此刻必须已装的）"
for t in gcc make sed find tar xz grep awk readelf nm install ln; do
  p=$(command -v "$t" || true)
  if [ -n "$p" ]; then ok "$t -> $p"; else fail "缺少 $t"; fi
done
echo "  说明：autoconf/automake/libtool 不需要（tarball 自带 configure/Makefile.in/libtool）："
for t in autoconf automake libtool; do
  echo "    $t: $(command -v $t || echo '未安装（不影响本节）')"
done
echo "  说明：本节**不需要** man 程序（man-db 在 §8.66 才装），man 页只安装不查看。"

echo "--- 3. configure 会用到的可选库（有则启用，无则关闭；均不是硬性前置）"
for f in /usr/lib/libacl.so /usr/lib/libattr.so; do
  if [ -e "$f" ]; then ok "存在 $f（§8.25 Attr / §8.26 Acl，useradd/usermod 会链接）"
  else echo "  INFO 缺失 $f（configure 会关闭对应支持）"; fi
done
echo "  libbsd：手册显式 --without-libbsd（LFS 无此包），$( [ -e /usr/lib/libbsd.so ] && echo '本机竟然有' || echo '本机确实没有' )"
echo "  libpam：手册的 Important 提示框只对已装 Linux-PAM 的系统生效，$( [ -e /usr/lib/libpam.so ] && echo '本机有 PAM！需改按 BLFS 走' || echo '本机没有 PAM，按本页构建' )"

echo "--- 4. 源码包"
cd /sources
if [ -f "$TARBALL" ]; then ok "存在 /sources/$TARBALL（$(stat -c %s "$TARBALL") 字节）"; else fail "缺失 /sources/$TARBALL"; fi
if [ -f /sources/md5sums ]; then
  want=$(awk -v t="$TARBALL" '$2==t || $2=="./"t {print $1}' /sources/md5sums | head -n1)
  got=$(md5sum "$TARBALL" 2>/dev/null | awk '{print $1}')
  echo "  md5 期望：${want:-（md5sums 中未列出）}"
  echo "  md5 实测：$got"
  if [ -n "$want" ]; then
    if [ "$want" = "$got" ]; then ok "md5 校验通过"; else fail "md5 不符"; fi
  fi
fi

echo "--- 5. 安装前系统里不应已有 Shadow（本节是首次安装）"
pre_list=$( { ls -d /usr/bin/passwd /usr/bin/login /usr/bin/su /usr/bin/newgrp /usr/bin/sg \
                   /usr/sbin/useradd /usr/sbin/vipw /usr/sbin/vigr /usr/sbin/nologin \
                   /etc/login.defs /etc/default /usr/lib/libsubid.so* /usr/include/shadow \
                   /etc/shadow /etc/gshadow 2>/dev/null || true; } | tr '\n' ' ')
echo "  安装前匹配到的路径：${pre_list:-（无，符合预期）}"
if [ -z "$pre_list" ]; then ok "系统中尚无 Shadow，属首次安装"; else fail "已存在 Shadow 相关文件，与首次安装的前提不符"; fi

echo "--- 6. §7.6 建立的账户/组文件（§8.29.2 的 pwconv/grpconv/useradd -D 依赖它们）"
for f in /etc/passwd /etc/group; do
  if [ -s "$f" ]; then ok "$f（$(wc -l < "$f") 行）"; else fail "$f 缺失或为空"; fi
done
users_gid=$(awk -F: '$1=="users"{print $3}' /etc/group)
echo "  /etc/group 中 users 组的 GID：${users_gid:-（不存在）}"
if [ "$users_gid" = 999 ]; then ok "users 组 GID=999，与手册 useradd -D --gid 999 一致"
else fail "users 组 GID 不是 999（手册 §7.6 建的 users:x:999:）"; fi
echo "  mail 组：$( { grep '^mail:' /etc/group || true; } )（CREATE_MAIL_SPOOL=yes 时 useradd 用它作邮箱属组）"
echo "  tester 用户（第 8 章测试用，章末删除）：$( { grep '^tester:' /etc/passwd || true; } )"

echo "--- 7. 安装前系统里已有的 setuid 程序（安装后要按差集判断，而不是拿绝对集合硬套）"
pre_suid=$( { find /usr/bin /usr/sbin -maxdepth 1 -type f -perm -4000 -printf '%f\n' 2>/dev/null || true; } | sort | tr '\n' ' ')
echo "  安装前的 setuid 程序：${pre_suid:-（无）}"
echo "    （mount/umount 来自 §7.12 Util-linux，与本节无关）"

echo "--- 7b. /usr/lib64 不应存在（手册 §7.5.1）"
if [ -e /usr/lib64 ]; then fail "/usr/lib64 存在"; else ok "/usr/lib64 不存在"; fi

echo "--- 8. §8.3 Man-pages 已装的同名 man 页（手册第一组 sed 就是为了不覆盖它们）"
# 手册原文：Also, prevent the installation of manual pages that were already installed
# in Section 8.3, "Man-pages-6.17".
for m in /usr/share/man/man3/getspnam.3 /usr/share/man/man5/passwd.5; do
  if [ -e "$m" ]; then
    echo "    $m  md5=$(md5sum "$m" | awk '{print $1}')  $(stat -c '%s 字节 %y' "$m" | cut -d. -f1)"
  else
    fail "缺失 $m（应由 §8.3 Man-pages 提供）"
  fi
done
mp_getspnam_before=$(md5sum /usr/share/man/man3/getspnam.3 2>/dev/null | awk '{print $1}')
mp_passwd5_before=$(md5sum /usr/share/man/man5/passwd.5 2>/dev/null | awk '{print $1}')
echo "  /usr/share/man/man1/groups.1（Coreutils §8.? 尚未安装，手册说 Coreutils provides a better version）："
{ ls -l /usr/share/man/man1/groups.1 2>&1 || true; } | sed 's/^/    /'

echo "--- 9. 构建目录不应有残留"
if [ -e "/sources/$SRCDIR" ]; then
  echo "  发现残留 /sources/$SRCDIR，按手册惯例先删除再解包"
  rm -rf "/sources/$SRCDIR"
fi
ok "构建目录干净"

[ $rc -eq 0 ] || { echo; echo "前置检查未通过，终止（不执行任何手册命令）"; exit 1; }
echo "前置检查全部通过。"
echo

# =========================================================================
echo "================= 8.29.1. Installation of Shadow ================="

echo "----- 解包 -----"
echo "命令：tar -xf /sources/$TARBALL -C /sources"
tar -xf "/sources/$TARBALL" -C /sources
cd "/sources/$SRCDIR"
echo "  解包目录：$(pwd)"
echo "  顶层内容：$(ls | tr '\n' ' ')"
echo "  版本自述：$( { grep -m1 '^AC_INIT' configure.ac || true; } )"
echo

echo "----- 手册命令组 1：去掉 groups 程序及三个重复 man 页 -----"
echo "手册原文：Disable the installation of the groups program and its man pages, as"
echo "  Coreutils provides a better version. Also, prevent the installation of manual"
echo "  pages that were already installed in Section 8.3, \"Man-pages-6.17\"."
echo "手册命令："
echo "  sed -i 's/groups\$(EXEEXT) //' src/Makefile.in"
echo "  find man -name Makefile.in -exec sed -i 's/groups\\.1 / /'   {} \;"
echo "  find man -name Makefile.in -exec sed -i 's/getspnam\\.3 / /' {} \;"
echo "  find man -name Makefile.in -exec sed -i 's/passwd\\.5 / /'   {} \;"
{
  echo "### 命令组 1 执行前后的取证"
  echo "--- sed 前：src/Makefile.in 中 'groups\$(EXEEXT) ' 的匹配行数"
  { grep -c 'groups\$(EXEEXT) ' src/Makefile.in || true; }
  echo "--- sed 前：man 树中含 'groups\.1 ' 的 Makefile.in"
  { grep -rl 'groups\.1 ' man --include='Makefile.in' || true; }
  echo "--- sed 前：man 树中含 'getspnam\.3 ' 的 Makefile.in（文件名列表）"
  { grep -rl 'getspnam\.3 ' man --include='Makefile.in' || true; }
  echo "--- sed 前：man 树中含 'passwd\.5 ' 的 Makefile.in（文件名列表）"
  { grep -rl 'passwd\.5 ' man --include='Makefile.in' || true; }
  echo "--- sed 前：man/Makefile.in 的 man_MANS"
  { sed -n '/^man_MANS = /,/[^\\]$/p' man/Makefile.in || true; }
} > "$SEDLOG" 2>&1
n_groups_exeext=$( { grep -c 'groups\$(EXEEXT) ' src/Makefile.in || true; } )
n_groups_man=$( { grep -rl 'groups\.1 ' man --include='Makefile.in' || true; } | wc -l )
n_getspnam=$( { grep -rl 'getspnam\.3 ' man --include='Makefile.in' || true; } | wc -l )
n_passwd5=$( { grep -rl 'passwd\.5 ' man --include='Makefile.in' || true; } | wc -l )
echo "  执行前的匹配规模（现算，不是猜的）："
echo "    src/Makefile.in 含 'groups\$(EXEEXT) ' 的行数：$n_groups_exeext"
echo "    man 树含 'groups\\.1 ' 的 Makefile.in 个数   ：$n_groups_man"
echo "    man 树含 'getspnam\\.3 ' 的 Makefile.in 个数 ：$n_getspnam"
echo "    man 树含 'passwd\\.5 ' 的 Makefile.in 个数   ：$n_passwd5"
md5_src_before=$(md5sum src/Makefile.in | awk '{print $1}')
cp man/Makefile.in /tmp/.shadow-man-Makefile.in.orig

sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
echo "  四条命令均返回 0"
md5_src_after=$(md5sum src/Makefile.in | awk '{print $1}')
{
  echo
  echo "--- sed 后：man/Makefile.in 的 man_MANS"
  { sed -n '/^man_MANS = /,/[^\\]$/p' man/Makefile.in || true; }
  echo "--- sed 后：man/Makefile.in 的 diff"
  { diff -u /tmp/.shadow-man-Makefile.in.orig man/Makefile.in || true; }
  echo "--- sed 后：man 树 Makefile.in 中仍出现 getspnam.3 / passwd.5 的位置"
  { grep -rn 'getspnam\.3\|passwd\.5' man --include='Makefile.in' || true; }
} >> "$SEDLOG" 2>&1
rm -f /tmp/.shadow-man-Makefile.in.orig

echo "  实测结论（写进日志作为证据，而不是想当然）："
echo "    1) src/Makefile.in md5 前/后 = $md5_src_before / $md5_src_after"
if [ "$n_groups_exeext" -eq 0 ] && [ "$md5_src_before" = "$md5_src_after" ]; then
  ok "第一条 sed 在 shadow-$VER 上是**空操作**：4.19.3 已经不再提供 groups 程序"
  echo "       （src/Makefile.am 里没有任何 groups 目标，故 'groups\$(EXEEXT) ' 匹配 0 行）"
  echo "       手册这条命令仍原样执行了，只是无可改之处——这是事实，不是失败。"
elif [ "$n_groups_exeext" -gt 0 ] && [ "$md5_src_before" != "$md5_src_after" ]; then
  ok "第一条 sed 生效（匹配 $n_groups_exeext 行）"
else
  fail "第一条 sed 的匹配数($n_groups_exeext)与 md5 变化不自洽"
fi
if [ "$n_groups_man" -eq 0 ]; then
  ok "第二条 find/sed 同样是空操作：man 树里没有 groups.1（4.19.3 已删除该 man 页）"
else
  ok "第二条 find/sed 改到了 $n_groups_man 个 Makefile.in"
fi
left_getspnam=$( { grep -rc 'getspnam\.3 ' man/Makefile.in || true; } )
left_passwd5=$( { grep -rc 'passwd\.5 ' man/Makefile.in || true; } )
echo "    2) man/Makefile.in 中 'getspnam\\.3 ' 剩余匹配行：$left_getspnam；'passwd\\.5 ' 剩余：$left_passwd5"
if [ "$n_getspnam" -gt 0 ] && [ "$left_getspnam" -eq 0 ]; then ok "getspnam.3 已从 man_MANS 摘除（原有 $n_getspnam 个 Makefile.in 命中）"
else fail "getspnam.3 未被正确摘除"; fi
if [ "$n_passwd5" -gt 0 ] && [ "$left_passwd5" -eq 0 ]; then ok "passwd.5 已从 man_MANS 摘除（原有 $n_passwd5 个 Makefile.in 命中）"
else fail "passwd.5 未被正确摘除"; fi
echo "    3) 手册的 sed 只删了文件名不删目录前缀，man_MANS 里因此留下 'man3/' 与 'man5/'"
echo "       两个残token。automake 生成的 install-manN 目标用 sed -n '/\\.N[a-z]*\$/p'"
echo "       过滤条目，这两个残 token 不以 .3/.5 结尾，会被直接丢弃；它们同时又是真实"
echo "       存在的目录，作为 \$(man_MANS) 的先决条件也不会让 make 报错。安装阶段会用"
echo "       实际装出的 man 页清单复核这一点。"
echo "  详细取证见 logs/packages/8.29-shadow-$VER.sed.log"
echo

echo "----- 手册命令组 2：login.defs（YESCRYPT / /var/mail / 去掉 PATH 里的 /bin 与 /sbin） -----"
echo "手册原文：Instead of using the default crypt method, use the much more secure"
echo "  YESCRYPT method of password encryption, which also allows passwords longer than"
echo "  8 characters. It is also necessary to change the obsolete /var/spool/mail location"
echo "  for user mailboxes that Shadow uses by default to the /var/mail location used"
echo "  currently. And, remove /bin and /sbin from the PATH, since they are simply"
echo "  symlinks to their counterparts in /usr."
echo "手册 Warning：Including /bin and/or /sbin in the PATH variable may cause some BLFS"
echo "  packages fail to build, so don't do that in the .bashrc file or anywhere else."
echo "手册命令："
echo "  sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \\"
echo "      -e 's:/var/spool/mail:/var/mail:'                   \\"
echo "      -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \\"
echo "      -i etc/login.defs"
cp etc/login.defs /tmp/.shadow-login.defs.orig
echo "  sed 前的相关行："
{ grep -n 'ENCRYPT_METHOD DES\|MAIL_DIR\|ENV_SUPATH\|ENV_PATH' etc/login.defs || true; } | sed 's/^/    /'
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs
echo "  sed 后的相关行："
{ grep -n 'ENCRYPT_METHOD YESCRYPT\|MAIL_DIR\|ENV_SUPATH\|ENV_PATH' etc/login.defs || true; } | sed 's/^/    /'
{
  echo "### login.defs 的完整 diff"
  { diff -u /tmp/.shadow-login.defs.orig etc/login.defs || true; }
} >> "$SEDLOG" 2>&1
rm -f /tmp/.shadow-login.defs.orig
for pat in '^ENCRYPT_METHOD[[:blank:]]+YESCRYPT$' '^MAIL_DIR[[:blank:]]+/var/mail$' '^ENV_SUPATH[[:blank:]]+PATH=/usr/sbin:/usr/bin$' '^ENV_PATH[[:blank:]]+PATH=/usr/bin$'; do
  if { grep -Eq "$pat" etc/login.defs; }; then ok "login.defs 命中 $pat"; else fail "login.defs 未命中 $pat"; fi
done
if { grep -q '/var/spool/mail' etc/login.defs; }; then fail "login.defs 仍含 /var/spool/mail"; else ok "login.defs 已无 /var/spool/mail"; fi
echo

echo "----- 手册命令：touch /usr/bin/passwd -----"
echo "手册解释：The file /usr/bin/passwd needs to exist because its location is hardcoded"
echo "  in some programs; if it does not already exist, the installation script will"
echo "  create it in the wrong place."
touch /usr/bin/passwd
{ ls -l /usr/bin/passwd || true; } | sed 's/^/    /'
[ -e /usr/bin/passwd ] && ok "/usr/bin/passwd 已就位（当前是 0 字节占位，稍后被真正的 passwd 覆盖）" || fail "touch 失败"
echo

echo "----- 手册命令：configure -----"
echo "手册命令：./configure --sysconfdir=/etc --disable-static --with-{b,yes}crypt \\"
echo "                     --without-libbsd --disable-logind --with-group-name-max-length=32"
echo "手册对各选项的解释："
echo "  --with-{b,yes}crypt：The shell expands this to two switches, --with-bcrypt and"
echo "    --with-yescrypt. They allow shadow to use the Bcrypt and Yescrypt algorithms"
echo "    implemented by Libxcrypt for hashing passwords."
echo "  --with-group-name-max-length=32：The longest permissible user name is 32 characters."
echo "    Make the maximum length of a group name the same."
echo "  --disable-logind：makes Shadow (specifically, the login and who programs) use the"
echo "    /run/utmp file instead of logind, as logind isn't available yet in the incomplete"
echo "    LFS system."
echo "  --without-libbsd：Do not use the readpassphrase function from libbsd which is not"
echo "    in LFS. Use the internal copy instead."
set +e
./configure --sysconfdir=/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --disable-logind    \
            --with-group-name-max-length=32 > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "  configure 退出码：$conf_rc（完整输出见 logs/packages/8.29-shadow-$VER.configure.log）"
[ $conf_rc -eq 0 ] || { echo "configure 失败，终止"; tail -n 40 "$CONFLOG" | sed 's/^/    /'; exit 1; }
echo "  configure 自报的特性摘要（手册没列，但这是本节所有 --with/--disable 是否生效的直接证据）："
{ sed -n '/has been configured with the following features/,$p' "$CONFLOG" || true; } | sed 's/^/    /'
echo "  config.h 中的关键宏："
{ grep -E '^#define (PASSWD_PROGRAM|USE_YESCRYPT|USE_BCRYPT|USE_SHA_CRYPT|ENABLE_SUBIDS|GROUP_NAME_MAX_LENGTH|SHADOWGRP|WITH_LIBBSD)' config.h || true; } | sed 's/^/    /'
for m in 'USE_YESCRYPT 1' 'USE_BCRYPT 1' 'GROUP_NAME_MAX_LENGTH 32'; do
  if { grep -q "^#define $m\$" config.h; }; then ok "config.h 有 #define $m"; else fail "config.h 缺 #define $m"; fi
done
if { grep -q '^#define WITH_LIBBSD 0$' config.h; }; then ok "config.h 有 #define WITH_LIBBSD 0（--without-libbsd 生效）"; else fail "WITH_LIBBSD 不是 0"; fi
if { grep -q 'PAM support:			no' "$CONFLOG"; }; then ok "configure 自报 PAM support: no（符合本页默认路径，不走 BLFS）"; else echo "  INFO configure 的 PAM 行：$( { grep 'PAM support' "$CONFLOG" || true; } )"; fi
if { grep -q 'enable logind:			no' "$CONFLOG"; }; then ok "configure 自报 enable logind: no（--disable-logind 生效）"; else fail "logind 未被关闭"; fi
if { grep -q 'yescrypt passwords encryption:	yes' "$CONFLOG"; }; then ok "configure 自报 yescrypt passwords encryption: yes"; else fail "yescrypt 未启用"; fi
if { grep -q 'bcrypt passwords encryption:	yes' "$CONFLOG"; }; then ok "configure 自报 bcrypt passwords encryption: yes"; else fail "bcrypt 未启用"; fi
echo "  路径变量（解释为什么安装要写 exec_prefix=/usr）："
{ grep -E '^(prefix|exec_prefix|bindir|sbindir|libdir|mandir|sysconfdir) =' Makefile || true; } | sed 's/^/    /'
{ grep -E '^(ubindir|usbindir) =' src/Makefile || true; } | sed 's/^/    /'
echo "    configure.ac 里有 'test \"X\$prefix\" = \"X/usr\" && exec_prefix=\"\"'，所以 configure"
echo "    之后 exec_prefix 为空、bindir=/bin、sbindir=/sbin；手册用 make exec_prefix=/usr"
echo "    install 把它们改回 /usr/bin、/usr/sbin。ubindir/usbindir 用的是 \$prefix，本来就是 /usr。"
echo "  libtool build_old_libs（--disable-static 的直接证据，取**首个**）："
{ grep -n 'build_old_libs=' libtool || true; } | sed -n '1,3p' | sed 's/^/    /'
first_bol=$( { grep -m1 'build_old_libs=' libtool || true; } )
case "$first_bol" in
  build_old_libs=no) ok "libtool 首个 build_old_libs=no（--disable-static 生效）" ;;
  *) fail "libtool 首个 build_old_libs 不是 no：$first_bol" ;;
esac
echo

echo "----- 手册命令：make -----"
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "  make 退出码：$make_rc（完整输出见 logs/packages/8.29-shadow-$VER.make.log）"
[ $make_rc -eq 0 ] || { echo "make 失败，终止"; tail -n 60 "$MAKELOG" | sed 's/^/    /'; exit 1; }
echo "  编译告警条数：$( { grep -c 'warning:' "$MAKELOG" || true; } )"
echo "  错误行（应为空）："
{ grep -n 'Error \|error:' "$MAKELOG" || true; } | sed 's/^/    /' | head -20
n_a=$( { find . -name '*.a' || true; } | wc -l )
echo "  源码树内 .a 文件数：$n_a"
{ find . -name '*.a' || true; } | sed 's/^/    /'
if [ "$n_a" -eq 1 ] && [ -f ./lib/.libs/libshadow.a ]; then
  ok "唯一的 .a 是 lib/.libs/libshadow.a —— 它是 noinst 便利库（只在链接期用，不安装）"
  echo "       --disable-static 关的是**要安装**的静态库；便利库由 libtool 无条件产出，"
  echo "       安装阶段会复核系统里一个 .a 都没多出来。"
else
  fail "源码树内 .a 数量($n_a)与校准结果(1，lib/.libs/libshadow.a)不符"
fi
echo

echo "----- 测试（手册规定） -----"
echo "手册原文（§8.29.1，紧跟 make 之后的一整句）："
echo "  \"This package does not come with a test suite.\""
echo "  因此本节**没有**手册规定的测试步骤，不执行 make check / make test。"
echo "  为不留空白，下面给出 tarball 里 tests/ 目录的实际情况作为佐证："
{ ls tests || true; } | sed 's|^|    tests/: |'
echo "    tests/unit 的 make check 是上游自带的单元测试，需要 cmocka（LFS 未安装），"
echo "    且手册明确说本包 does not come with a test suite，故不执行。cmocka 探测结果："
{ grep -i 'cmocka' "$CONFLOG" || true; } | sed 's/^/      /'
{ grep -n 'HAVE_CMOCKA\|USE_CMOCKA' config.h || echo "      config.h 中无 cmocka 相关宏"; } | sed 's/^/      /'
echo

echo "----- 手册命令：安装（两条） -----"
echo "手册命令：make exec_prefix=/usr install"
echo "          make -C man install-man"
set +e
make exec_prefix=/usr install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "  make exec_prefix=/usr install 退出码：$inst_rc"
[ $inst_rc -eq 0 ] || { echo "安装失败，终止"; tail -n 60 "$INSTLOG" | sed 's/^/    /'; exit 1; }
set +e
make -C man install-man > "$MANLOG" 2>&1
man_rc=$?
set -e
echo "  make -C man install-man 退出码：$man_rc"
[ $man_rc -eq 0 ] || { echo "man 安装失败，终止"; tail -n 60 "$MANLOG" | sed 's/^/    /'; exit 1; }
echo "  说明：man 页要单独装，是因为顶层 Makefile.am 只在 ENABLE_REGENERATE_MAN 时才把 man"
echo "        放进 SUBDIRS；本次 SUBDIRS 实际为："
{ grep -m1 '^SUBDIRS = ' Makefile || true; } | sed 's/^/    /'
echo "  install-man 实际执行的 install 命令（来自 8.29-shadow-$VER.install-man.log）："
{ grep -E '^ /usr/bin/install' "$MANLOG" || true; } | sed 's/^/    /'
echo

# =========================================================================
echo "================= 8.29.2. Configuring Shadow ================="
echo "手册原文：To enable shadowed passwords, run the following command: pwconv"
echo "          To enable shadowed group passwords, run: grpconv"
{
  echo "### §8.29.2 Configuring Shadow"
  echo "--- pwconv 前 /etc/passwd 第二字段统计"
  awk -F: '{print $1": "$2}' /etc/passwd
} > "$CFGLOG" 2>&1
echo "  pwconv 前：/etc/shadow $( [ -e /etc/shadow ] && echo 存在 || echo 不存在 )，/etc/gshadow $( [ -e /etc/gshadow ] && echo 存在 || echo 不存在 )"
echo "命令：pwconv"
pwconv
echo "  pwconv 退出码：0"
echo "命令：grpconv"
grpconv
echo "  grpconv 退出码：0"
{
  echo "--- pwconv/grpconv 后 /etc/passwd"
  cat /etc/passwd
  echo "--- /etc/shadow（口令域已用 x 化，此处原样留档：本机是全新系统，除 root 外均为 ! 或 *）"
  cat /etc/shadow
  echo "--- /etc/group"
  cat /etc/group
  echo "--- /etc/gshadow"
  cat /etc/gshadow
} >> "$CFGLOG" 2>&1
for f in /etc/shadow /etc/gshadow; do
  if [ -s "$f" ]; then ok "$f 已生成（$(wc -l < "$f") 行，权限 $(stat -c '%A %U:%G' "$f")）"; else fail "$f 未生成或为空"; fi
done
echo "  /etc/passwd 中口令域是否已全部换成 x（pwconv 的作用）："
notx=$( { awk -F: '$2!="x"{print $1"("$2")"}' /etc/passwd || true; } | tr '\n' ' ')
if [ -z "$notx" ]; then ok "全部账户的口令域均为 x"; else fail "仍有账户口令域不是 x：$notx"; fi
echo "  /etc/group 中口令域是否已全部换成 x（grpconv 的作用）："
gnotx=$( { awk -F: '$2!="x"{print $1"("$2")"}' /etc/group || true; } | tr '\n' ' ')
if [ -z "$gnotx" ]; then ok "全部组的口令域均为 x"; else fail "仍有组口令域不是 x：$gnotx"; fi
echo "  /etc/shadow 与 /etc/passwd 的账户数一致性：passwd=$(wc -l < /etc/passwd) shadow=$(wc -l < /etc/shadow)"
echo "  /etc/gshadow 与 /etc/group 的组数一致性：group=$(wc -l < /etc/group) gshadow=$(wc -l < /etc/gshadow)"
echo

echo "手册命令：mkdir -p /etc/default"
echo "          useradd -D --gid 999"
echo "手册解释：GROUP=999 —— This parameter sets the beginning of the group numbers used"
echo "  in the /etc/group file. The particular value 999 comes from the --gid parameter"
echo "  above. ... That is why we created the group users with this group ID in Section 7.6."
echo "  CREATE_MAIL_SPOOL=yes —— This parameter causes useradd to create a mailbox file for"
echo "  each new user."
mkdir -p /etc/default
useradd -D --gid 999
echo "  useradd -D --gid 999 退出码：0"
echo "  生成的 /etc/default/useradd："
{ cat /etc/default/useradd || true; } | sed 's/^/    /'
{ echo "--- /etc/default/useradd"; cat /etc/default/useradd; } >> "$CFGLOG" 2>&1
if [ -f /etc/default/useradd ]; then ok "/etc/default/useradd 已生成"; else fail "/etc/default/useradd 未生成"; fi
if { grep -q '^GROUP=999$' /etc/default/useradd; }; then ok "GROUP=999"; else fail "GROUP 不是 999"; fi
if { grep -q '^CREATE_MAIL_SPOOL=yes$' /etc/default/useradd; }; then
  ok "CREATE_MAIL_SPOOL=yes（保留手册默认值）"
  echo "       手册末尾的 sed -i '/MAIL/s/yes/no/' /etc/default/useradd 是**可选**命令"
  echo "       （原文：If you would rather not create these files），本项目不执行。"
else
  echo "  INFO CREATE_MAIL_SPOOL 当前值：$( { grep '^CREATE_MAIL_SPOOL=' /etc/default/useradd || true; } )"
fi
echo

# =========================================================================
echo "================= 8.29.3. Setting the Root Password ================="
echo "手册原文：Choose a password for user root and set it by running: passwd root"
echo "本项目的执行方式：手册的 passwd root 是交互式的（从 /dev/tty 读两遍口令），而本项目"
echo "  的 chroot 执行是非交互的（docker exec 未分配 tty，chroot 内无可用控制终端），直接跑"
echo "  会因拿不到 tty 而失败。shadow-$VER 的 passwd(1) 自带 '-s, --stdin  read new token"
echo "  from stdin'（src/passwd.c 中走 agetpass_stdin()，仅 root 可用），是**同一个程序的**"
echo "  另一个口令输入路径，因此改用："
echo "    printf '%s\\n' '<口令>' | passwd --stdin root"
echo "  本次设置的 root 口令明文：$ROOT_PASSWORD  （供后续 §10/§11 QEMU 验收任务登录用；"
echo "  这是构建产物磁盘镜像内的口令，不是宿主机口令）"
set +e
printf '%s\n' "$ROOT_PASSWORD" | passwd --stdin root > /tmp/.shadow-passwd-root.log 2>&1
pw_rc=$?
set -e
echo "  passwd --stdin root 退出码：$pw_rc"
{ cat /tmp/.shadow-passwd-root.log || true; } | sed 's/^/    /'
{ echo "--- passwd --stdin root 输出"; cat /tmp/.shadow-passwd-root.log; } >> "$CFGLOG" 2>&1
rm -f /tmp/.shadow-passwd-root.log
[ $pw_rc -eq 0 ] || fail "root 口令设置失败"
root_hash=$(awk -F: '$1=="root"{print $2}' /etc/shadow)
root_algo=$(printf '%s' "$root_hash" | awk -F'$' '{print $2}')
echo "  /etc/shadow 中 root 的散列：算法标识 = \$${root_algo}\$，总长度 ${#root_hash} 字符（完整散列不写进日志）"
case "$root_hash" in
  '$y$'*) ok "root 口令散列以 \$y\$ 开头 —— 正是 yescrypt，证明 login.defs 的 ENCRYPT_METHOD YESCRYPT 与 Libxcrypt 的 yescrypt 实现都在真正工作" ;;
  '$2b$'*) fail "散列是 bcrypt(\$2b\$) 而非 yescrypt，ENCRYPT_METHOD 未生效" ;;
  '$6$'*)  fail "散列是 sha512crypt(\$6\$) 而非 yescrypt，ENCRYPT_METHOD 未生效" ;;
  *)       fail "root 散列前缀异常" ;;
esac
echo "  root 账户状态（passwd -S，字段：用户 状态 上次改期 min max warn inactive）："
{ passwd -S root || true; } | sed 's/^/    /'
echo

# =========================================================================
echo "================= 安装结果检查（8.29.4 Contents of Shadow） ================="

echo "--- 1. 手册列出的 34 个 Installed programs 是否全部就位"
ubin="chage chfn chsh expiry faillog getsubids gpasswd login newgidmap newgrp newuidmap passwd su"
usbin="chgpasswd chpasswd groupadd groupdel groupmems groupmod grpck grpconv grpunconv logoutd newusers nologin pwck pwconv pwunconv useradd userdel usermod vipw"
n_prog=0
for p in $ubin; do
  if [ -f "/usr/bin/$p" ]; then n_prog=$((n_prog+1)); else fail "缺失 /usr/bin/$p"; fi
done
for p in $usbin; do
  if [ -f "/usr/sbin/$p" ]; then n_prog=$((n_prog+1)); else fail "缺失 /usr/sbin/$p"; fi
done
for l in /usr/bin/sg /usr/sbin/vigr; do
  if [ -L "$l" ]; then n_prog=$((n_prog+1)); else fail "缺失符号链接 $l"; fi
done
echo "  /usr/bin 下的普通文件 $( echo $ubin | wc -w ) 个 + /usr/sbin 下的普通文件 $( echo $usbin | wc -w ) 个 + 2 个链接(sg, vigr) = $n_prog"
if [ "$n_prog" -eq 34 ] ; then ok "34 个程序全部就位，与手册 Installed programs 列表逐个对上"; else fail "程序数 $n_prog ≠ 34"; fi
if [ -e /usr/bin/groups ]; then
  echo "  /usr/bin/groups：存在，但**不是本包装的** —— 手册 §8.29.1 开头就说 Coreutils"
  echo "    provides a better version，这里的 groups 来自第 6 章 §6.5 的临时 Coreutils："
  echo "      groups --version 首行：$( { groups --version 2>/dev/null | head -n1 || true; } )"
  echo "      时间戳对比（与同批安装的 id/ls 应完全相同）："
  { stat -c '        %y %n' /usr/bin/groups /usr/bin/id /usr/bin/ls 2>/dev/null | cut -d. -f1 || true; }
  echo "    且 shadow-$VER 本就不提供 groups（第一条 sed 匹配 0 行），不存在覆盖的可能。"
else
  echo "  /usr/bin/groups：不存在（shadow-$VER 本就不提供；后续 §8.61 Coreutils 会提供）"
fi

echo "--- 2. 符号链接指向"
for pair in "/usr/bin/sg:newgrp" "/usr/sbin/vigr:vipw" \
            "/usr/lib/libsubid.so:libsubid.so.5.0.0" "/usr/lib/libsubid.so.5:libsubid.so.5.0.0"; do
  p=${pair%%:*}; t=${pair##*:}
  a=$(readlink "$p" 2>/dev/null || true)
  if [ "$a" = "$t" ]; then ok "$p -> $t"; else fail "$p -> ${a:-（不是链接）}，期望 $t"; fi
done

echo "--- 3. setuid 位（用「安装前后的差集」判断，试建校准值：shadow 恰好装出 10 个 suid 程序）"
post_suid=$( { find /usr/bin /usr/sbin -maxdepth 1 -type f -perm -4000 -printf '%f\n' 2>/dev/null || true; } | sort | tr '\n' ' ')
echo "  安装前：${pre_suid:-（无）}"
echo "  安装后：$post_suid"
printf '%s\n' $pre_suid  > /tmp/.shadow-suid-pre
printf '%s\n' $post_suid > /tmp/.shadow-suid-post
added=$( { comm -13 /tmp/.shadow-suid-pre /tmp/.shadow-suid-post || true; } | tr '\n' ' ')
removed=$( { comm -23 /tmp/.shadow-suid-pre /tmp/.shadow-suid-post || true; } | tr '\n' ' ')
rm -f /tmp/.shadow-suid-pre /tmp/.shadow-suid-post
echo "  新增：$added"
echo "  消失：${removed:-（无）}"
expect_suid="chage chfn chsh expiry gpasswd newgidmap newgrp newuidmap passwd su "
if [ "$added" = "$expect_suid" ]; then
  ok "新增的 setuid 程序恰好是 shadow 的 10 个，与试建校准结果完全一致"
else
  fail "新增的 setuid 集合与校准结果不一致（期望：$expect_suid）"
fi
if [ -z "$removed" ]; then ok "原有的 setuid 程序（mount/umount）未受影响"; else fail "原有 setuid 程序丢失：$removed"; fi

echo "--- 4. 手册列出的 Installed directories 与 Installed libraries"
for d in /etc/default /usr/include/shadow; do
  if [ -d "$d" ]; then ok "目录 $d 存在"; else fail "目录 $d 缺失"; fi
done
{ ls -l /usr/lib/libsubid.so* /usr/lib/libsubid.la || true; } | sed 's/^/    /'
if [ -f /usr/lib/libsubid.so.5.0.0 ]; then ok "libsubid.so.5.0.0 已安装（ABI 5.0.0 来自 configure.ac 的 libsubid_abi_major/minor/micro = 5/0/0，与包版本无关）"; else fail "缺失 /usr/lib/libsubid.so.5.0.0"; fi
echo "  libsubid 的 SONAME / NEEDED："
{ readelf -d /usr/lib/libsubid.so.5.0.0 | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/    /'
soname_line=$( { readelf -d /usr/lib/libsubid.so.5.0.0 2>/dev/null | grep 'SONAME' || true; } )
if [ "${soname_line#*\[}" = "libsubid.so.5]" ]; then ok "SONAME = libsubid.so.5"; else fail "SONAME 不是 libsubid.so.5（实测行：$soname_line）"; fi
echo "  /usr/include/shadow 下的头文件："
{ find /usr/include/shadow -type f -printf '    %P\n' || true; }
echo "  /usr/lib/libsubid.la 是 libtool 惯例产物（其 old_library 为空，说明确无静态库），手册未要求删除："
{ grep -E "^(old_library|dlname|library_names)=" /usr/lib/libsubid.la || true; } | sed 's/^/    /'

echo "--- 5. 系统里不应多出 shadow 的静态库"
n_sys_a=$( { find /usr/lib -maxdepth 1 -name 'libsubid*.a' -o -maxdepth 1 -name 'libshadow*.a' || true; } | wc -l )
if [ "$n_sys_a" -eq 0 ]; then ok "/usr/lib 下没有 libsubid*.a / libshadow*.a（--disable-static 的最终判据）"; else fail "系统里出现了 $n_sys_a 个 shadow 静态库"; fi

echo "--- 6. /etc 下装出的配置文件"
for f in /etc/login.defs /etc/limits /etc/login.access; do
  if [ -f "$f" ]; then ok "$f（$(stat -c %s "$f") 字节）"; else fail "缺失 $f"; fi
done
echo "  安装后的 login.defs 关键项（复核命令组 2 的 sed 结果确实进了系统）："
{ grep -E '^ENCRYPT_METHOD|^MAIL_DIR|^ENV_SUPATH|^ENV_PATH' /etc/login.defs || true; } | sed 's/^/    /'
if { grep -Eq '^ENCRYPT_METHOD[[:blank:]]+YESCRYPT$' /etc/login.defs; }; then ok "/etc/login.defs 的 ENCRYPT_METHOD 是 YESCRYPT"; else fail "/etc/login.defs 的 ENCRYPT_METHOD 不对"; fi
if { grep -q '/var/spool/mail' /etc/login.defs; }; then fail "/etc/login.defs 仍含 /var/spool/mail"; else ok "/etc/login.defs 无 /var/spool/mail"; fi
bad_path=$( { grep -E '^ENV_(SU)?PATH' /etc/login.defs || true; } | grep -E '(^|[=:])/s?bin(:|$)' || true)
if [ -z "$bad_path" ]; then ok "ENV_PATH/ENV_SUPATH 已去掉 /bin 与 /sbin"; else fail "ENV_PATH/ENV_SUPATH 仍含 /bin 或 /sbin：$bad_path"; fi

echo "--- 7. man 页：应装 45 个，且不得覆盖 §8.3 Man-pages 的 getspnam.3 / passwd.5"
echo "  本次安装的 shadow man 页（按 §8.29 的 man_MANS 逐个核对，不用时间戳猜）："
shadow_man1="chage.1 chfn.1 chsh.1 expiry.1 getsubids.1 gpasswd.1 login.1 newgidmap.1 newgrp.1 newuidmap.1 passwd.1 sg.1 su.1"
shadow_man3="shadow.3"
shadow_man5="faillog.5 gshadow.5 limits.5 login.access.5 login.defs.5 porttime.5 shadow.5 suauth.5 subgid.5 subuid.5"
shadow_man8="chgpasswd.8 chpasswd.8 faillog.8 groupadd.8 groupdel.8 groupmems.8 groupmod.8 grpck.8 grpconv.8 grpunconv.8 logoutd.8 newusers.8 nologin.8 pwck.8 pwconv.8 pwunconv.8 useradd.8 userdel.8 usermod.8 vigr.8 vipw.8"
n_ok=0; n_bad=0
for s in 1 3 5 8; do
  eval "list=\$shadow_man$s"
  for m in $list; do
    if [ -f "/usr/share/man/man$s/$m" ]; then n_ok=$((n_ok+1)); else echo "    缺失 man$s/$m"; n_bad=$((n_bad+1)); fi
  done
done
echo "  逐项核对：存在 $n_ok 个，缺失 $n_bad 个（期望 13+1+10+21 = 45 个全部存在）"
if [ "$n_ok" -eq 45 ] && [ "$n_bad" -eq 0 ]; then ok "45 个 man 页全部就位"; else fail "man 页数量不对（$n_ok/45）"; fi
echo "  手册第一组 sed 要保护的三个 man 页："
mp_getspnam_after=$(md5sum /usr/share/man/man3/getspnam.3 2>/dev/null | awk '{print $1}')
mp_passwd5_after=$(md5sum /usr/share/man/man5/passwd.5 2>/dev/null | awk '{print $1}')
echo "    man3/getspnam.3 md5 安装前/后：$mp_getspnam_before / $mp_getspnam_after"
echo "    man5/passwd.5   md5 安装前/后：$mp_passwd5_before / $mp_passwd5_after"
if [ -n "$mp_getspnam_before" ] && [ "$mp_getspnam_before" = "$mp_getspnam_after" ]; then ok "§8.3 的 getspnam.3 未被 shadow 覆盖"; else fail "getspnam.3 被改动了"; fi
if [ -n "$mp_passwd5_before" ] && [ "$mp_passwd5_before" = "$mp_passwd5_after" ]; then ok "§8.3 的 passwd.5 未被 shadow 覆盖"; else fail "passwd.5 被改动了"; fi
if [ -e /usr/share/man/man1/groups.1 ]; then
  echo "  INFO man1/groups.1 存在：$(md5sum /usr/share/man/man1/groups.1 | awk '{print $1}')（不是本包装的，4.19.3 没有这个 man 页）"
else
  ok "man1/groups.1 不存在（shadow-$VER 本就不提供，留给后续 Coreutils）"
fi
echo "  man 页里是否混进了目录名残 token（'man3/' 'man5/' 那两个）："
{ ls -d /usr/share/man/man3/man3 /usr/share/man/man5/man5 2>/dev/null || true; } | sed 's/^/    /'
if [ -e /usr/share/man/man3/man3 ] || [ -e /usr/share/man/man5/man5 ]; then fail "残 token 被当成 man 页装进来了"; else ok "没有残 token 被安装（automake 的节号过滤按预期丢弃了它们）"; fi

echo "--- 8. 本地化 .mo 文件"
n_mo=$( { find /usr/share/locale -name 'shadow.mo' || true; } | wc -l )
echo "  shadow.mo 个数：$n_mo（试建校准值 39）"
if [ "$n_mo" -eq 39 ]; then ok "39 个 shadow.mo，与试建一致"; else fail "shadow.mo 个数 $n_mo ≠ 39"; fi

echo "--- 9. 关键二进制的动态依赖（yescrypt 走的是 §8.28 的 libcrypt.so.2）"
for b in /usr/bin/passwd /usr/bin/login /usr/bin/su /usr/sbin/chpasswd /usr/sbin/useradd; do
  echo "  $b:"
  { readelf -d "$b" 2>/dev/null | grep NEEDED | sed 's/.*Shared library: //' || true; } | tr -d '[]' | tr '\n' ' ' | sed 's/^/      /'
  echo
done
for b in /usr/bin/passwd /usr/bin/login /usr/bin/su /usr/sbin/chpasswd; do
  hit=$( { readelf -d "$b" 2>/dev/null | grep 'libcrypt.so.2' || true; } )
  if [ -n "$hit" ]; then ok "$b 链接 libcrypt.so.2"; else fail "$b 未链接 libcrypt.so.2"; fi
done
echo "  ldd 解析（确认没有 not found）："
for b in /usr/bin/passwd /usr/bin/login /usr/bin/su /usr/sbin/useradd /usr/lib/libsubid.so.5.0.0; do
  out=$( { ldd "$b" 2>&1 || true; } )
  case "$out" in
    *"not found"*) fail "$b 有未解析的依赖"; echo "$out" | sed 's/^/      /' ;;
    *) ok "$b 的依赖全部可解析（$(printf '%s' "$out" | wc -l) 项）" ;;
  esac
done

echo "--- 10. 冒烟：程序能跑、能读账户库"
echo "  chage -l root："
{ chage -l root || true; } | sed 's/^/    /'
echo "  pwck -r（只读检查 /etc/passwd 与 /etc/shadow；系统里多数系统账户的 home 是 /dev/null，"
echo "    因此有 'directory ... does not exist' 之类的提示属正常，仅作信息展示）："
set +e
pwck_out=$(pwck -r 2>&1); pwck_rc=$?
grpck_out=$(grpck -r 2>&1); grpck_rc=$?
set -e
echo "$pwck_out" | sed 's/^/    /'
echo "    pwck -r 退出码：$pwck_rc"
echo "  grpck -r："
echo "$grpck_out" | sed 's/^/    /'
echo "    grpck -r 退出码：$grpck_rc"
echo "  getsubids root（subid 支持已启用，root 未配置 subid 范围时报错属正常）："
{ getsubids root 2>&1 || true; } | sed 's/^/    /'
echo "  groupadd/groupdel 往返（真正验证写路径；用完即删，不留痕）："
set +e
groupadd -g 998 lfs_smoke_8_29 > /tmp/.shadow-smoke.log 2>&1; ga_rc=$?
set -e
echo "    groupadd -g 998 lfs_smoke_8_29 退出码：$ga_rc"
{ cat /tmp/.shadow-smoke.log || true; } | sed 's/^/      /'
if [ $ga_rc -eq 0 ]; then
  echo "    /etc/group 新行：$( { grep '^lfs_smoke_8_29:' /etc/group || true; } )"
  echo "    /etc/gshadow 新行：$( { grep '^lfs_smoke_8_29:' /etc/gshadow || true; } )"
  set +e
  groupdel lfs_smoke_8_29 >> /tmp/.shadow-smoke.log 2>&1; gd_rc=$?
  set -e
  echo "    groupdel lfs_smoke_8_29 退出码：$gd_rc"
  if [ $gd_rc -eq 0 ] && ! { grep -q '^lfs_smoke_8_29:' /etc/group; } && ! { grep -q '^lfs_smoke_8_29:' /etc/gshadow; }; then
    ok "groupadd/groupdel 往返成功，/etc/group 与 /etc/gshadow 均已复原"
  else
    fail "groupdel 未能清理干净"
  fi
else
  fail "groupadd 失败"
fi
rm -f /tmp/.shadow-smoke.log
echo "  --with-group-name-max-length=32 的实测（33 字符的组名应被拒绝，32 字符应被接受）："
set +e
long32=$(printf 'g%.0s' $(seq 1 32))
long33=$(printf 'g%.0s' $(seq 1 33))
o33=$(groupadd "$long33" 2>&1); r33=$?
set -e
echo "    33 字符组名：退出码 $r33  输出：$( printf '%s' "$o33" | head -n1 )"
if [ $r33 -ne 0 ]; then ok "33 字符组名被拒绝，符合 --with-group-name-max-length=32"; else
  fail "33 字符组名竟被接受"; groupdel "$long33" || true; fi
set +e
o32=$(groupadd "$long32" 2>&1); r32=$?
set -e
echo "    32 字符组名：退出码 $r32  输出：$( printf '%s' "$o32" | head -n1 )"
if [ $r32 -eq 0 ]; then ok "32 字符组名被接受"; groupdel "$long32"; echo "      （已删除该临时组）"; else fail "32 字符组名被拒绝（实测输出：$o32）"; fi

echo "--- 11. /etc/passwd、/etc/shadow 最终状态"
echo "  /etc/passwd（$(wc -l < /etc/passwd) 行）、/etc/shadow（$(wc -l < /etc/shadow) 行）、"
echo "  /etc/group（$(wc -l < /etc/group) 行）、/etc/gshadow（$(wc -l < /etc/gshadow) 行）"
{ stat -c '    %A %U:%G %n' /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/login.defs /etc/default/useradd || true; }
echo "  完整内容留档见 logs/packages/8.29-shadow-$VER.configuring.log"
echo

# =========================================================================
echo "================= 清理构建目录 ================="
cd /sources
echo "命令：rm -rf /sources/$SRCDIR"
rm -rf "/sources/$SRCDIR"
if [ -e "/sources/$SRCDIR" ]; then fail "构建目录未删除"; else ok "/sources/$SRCDIR 已删除"; fi
echo "  /sources 下与 shadow 相关的残留（只应剩 tarball 与本次的阶段日志）："
{ ls -d /sources/shadow* /sources/.shadow-* 2>/dev/null || true; } | sed 's/^/    /'
echo "  /tmp 下的残留：$( { ls -A /tmp | grep -i shadow || true; } | tr '\n' ' ' )"
echo

# =========================================================================
echo "================= 本节结论 ================="
echo "手册命令执行情况："
echo "  §8.29.1  sed -i 's/groups\$(EXEEXT) //' src/Makefile.in          已执行（空操作，4.19.3 无 groups）"
echo "  §8.29.1  find man ... groups.1 / getspnam.3 / passwd.5           已执行（后两条各改 $n_getspnam / $n_passwd5 个 Makefile.in）"
echo "  §8.29.1  sed ... -i etc/login.defs                               已执行（YESCRYPT / /var/mail / PATH 三处均生效）"
echo "  §8.29.1  touch /usr/bin/passwd                                   已执行"
echo "  §8.29.1  ./configure（6 个选项）                                  退出码 $conf_rc"
echo "  §8.29.1  make                                                    退出码 $make_rc"
echo "  §8.29.1  测试                                                    手册原文 \"This package does not come with a test suite.\"，无测试可跑"
echo "  §8.29.1  make exec_prefix=/usr install                           退出码 $inst_rc"
echo "  §8.29.1  make -C man install-man                                 退出码 $man_rc"
echo "  §8.29.2  pwconv / grpconv / mkdir -p /etc/default / useradd -D --gid 999   已执行"
echo "  §8.29.2  sed -i '/MAIL/s/yes/no/' /etc/default/useradd           手册标注为可选，未执行（保留 CREATE_MAIL_SPOOL=yes）"
echo "  §8.29.3  passwd root                                             以 passwd --stdin root 等价执行，退出码 $pw_rc，散列为 yescrypt(\$y\$)"
echo "  清理     rm -rf /sources/$SRCDIR                                  已执行"
echo
if [ $rc -eq 0 ]; then
  echo "===== §8.29 Shadow-$VER 全部完成，所有检查通过 ====="
  echo "结束时间：$(date -Is)"
  exit 0
else
  echo "===== §8.29 Shadow-$VER 存在未通过的检查（见上面的 FAIL 行） ====="
  echo "结束时间：$(date -Is)"
  exit 1
fi
