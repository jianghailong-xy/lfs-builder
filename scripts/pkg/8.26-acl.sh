#!/usr/bin/env bash
# LFS 13.0-systemd §8.26 Acl-2.3.2
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.26.1 Installation of Acl 的命令序列（全部 4 条，一条不多一条不少）：
#   ./configure --prefix=/usr    \
#               --disable-static \
#               --docdir=/usr/share/doc/acl-2.3.2
#   make
#   make check
#   make install
#
# 本节没有 sed、没有补丁、没有 mkdir build（in-tree build），也没有 make html /
#   make install-html。与紧邻的 §8.25 Attr 相比少一个 --sysconfdir=/etc（Acl 不装
#   任何 /etc 下的文件），故本节 configure 只有 3 个选项。
# 本节有**一个 Note 提示框**（§8.25 Attr 一个都没有）：
#   「One test named test/cp.test is known to fail because Coreutils is not built
#     with the Acl support yet.」
#   ——> 因此 make check 必然以非零退出码结束，脚本不能把它当成失败；判定标准是
#       「失败项有且只有 test/cp」。
# 手册正文另有一句前置条件：
#   「The Acl tests must be run on a filesystem that supports access controls.」
#   ——> 故下面的前置检查里直接对构建目录所在文件系统写入/读回一条真实的 POSIX ACL。
set -euo pipefail

PKG=acl
VER=2.3.2
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
DOCDIR=/usr/share/doc/acl-$VER
CONFLOG=/sources/.acl-configure.log
MAKELOG=/sources/.acl-make.log
CHECKLOG=/sources/.acl-make-check.log
INSTLOG=/sources/.acl-make-install.log
SUMLOG=/sources/.acl-test-summary.log

echo "===== LFS 13.0-systemd §8.26 Acl-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Acl package contains utilities to administer Access Control Lists,"
echo "  which are used to define fine-grained discretionary access rights for files"
echo "  and directories."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 6.5 MB"
echo
echo "----- chroot 环境自述（手册 §7.4） -----"
echo "PATH      : $PATH"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "TESTSUITEFLAGS: ${TESTSUITEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
esac
echo "  OK   PATH 中不含 /tools/bin（交叉工具链已不再使用）"
echo

# =========================================================================
echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0

echo "1) 上一任务 §8.25 Attr-2.5.2 的产物 —— 与前几节不同，Acl **真的依赖** Attr："
echo "   POSIX ACL 在内核里就是 system.posix_acl_access/default 两个扩展属性，libacl"
echo "   通过 libattr 的 setxattr/getxattr 封装读写它们，故 libacl.so 会 NEEDED"
echo "   libattr.so.1，且 configure 要靠 libattr.pc 找到它。逐项查："
for f in /usr/lib/libattr.so /usr/lib/libattr.so.1 /usr/lib/pkgconfig/libattr.pc \
         /usr/include/attr/libattr.h /usr/include/attr/attributes.h \
         /usr/bin/getfattr /usr/bin/setfattr; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   libattr 实体与 SONAME："
{ ls -l /usr/lib/libattr.so* || true; } | sed 's/^/     /'
{ readelf -d /usr/lib/libattr.so.1 2>/dev/null | grep SONAME || true; } | sed 's/^/     /'
echo "   libattr.pc 内容（configure 用 pkg-config 查的就是它）："
{ cat /usr/lib/pkgconfig/libattr.pc || true; } | sed 's/^/     /'
echo "   不只看文件在不在 —— 用 libattr 链接并运行一个最小程序，确认上一任务产物真的可用："
cat > /tmp/.acl-prereq-attr.c <<'CEOF'
#include <attr/libattr.h>
#include <stdio.h>
int main(void) { printf("attr_copy_file 符号可解析：%p\n", (void *)attr_copy_file); return 0; }
CEOF
if gcc -o /tmp/.acl-prereq-attr /tmp/.acl-prereq-attr.c -lattr 2>/tmp/.acl-prereq-attr.err; then
  echo "     编译 OK"
  { /tmp/.acl-prereq-attr || true; } | sed 's/^/     /'
  { ldd /tmp/.acl-prereq-attr | grep -E 'libattr|libc\.so' || true; } | sed 's/^/     /'
else
  echo "     FAIL 用 -lattr 链接失败："; sed 's/^/     /' /tmp/.acl-prereq-attr.err; rc=1
fi
rm -f /tmp/.acl-prereq-attr /tmp/.acl-prereq-attr.c /tmp/.acl-prereq-attr.err
echo

echo "2) 本节手册前置条件实测 ——「The Acl tests must be run on a filesystem that"
echo "   supports access controls.」构建目录在 /sources，这里直接往它上面写一条真实的"
echo "   POSIX ACL 再读回。此刻 setfacl 还没有（正是本节要装的），故用上一节装好的"
echo "   setfattr/getfattr 直接读写内核的 system.posix_acl_access："
echo "   （值按内核的 POSIX ACL xattr 格式手工构造，小端：version=2 +"
echo "     USER_OBJ(rw-) USER:1(rwx) GROUP_OBJ(r--) MASK(rwx) OTHER(r--)）"
acl_blob() {
  printf '\x02\x00\x00\x00'
  printf '\x01\x00\x06\x00\xff\xff\xff\xff'
  printf '\x02\x00\x07\x00\x01\x00\x00\x00'
  printf '\x04\x00\x04\x00\xff\xff\xff\xff'
  printf '\x10\x00\x07\x00\xff\xff\xff\xff'
  printf '\x20\x00\x04\x00\xff\xff\xff\xff'
}
probe=/sources/.acl-fs-probe.$$
: > "$probe"
b64=$(acl_blob | base64 -w0)
if setfattr -n system.posix_acl_access -v "0s$b64" "$probe" 2>/tmp/.acl-fs-probe.err; then
  mode=$(ls -l "$probe" | awk '{print $1}')
  echo "   OK   写入成功，ls -l 权限位为 $mode"
  case "$mode" in
    *+) echo "   OK   末尾的 '+' 表示内核确认该文件带有扩展 ACL" ;;
    *)  echo "   FAIL 权限位没有 '+'，内核没把它当成扩展 ACL"; rc=1 ;;
  esac
  # 注意：getfattr --only-values 会把**原始字节**吐出来（本值里含 0xff），一旦进日志
  # 就让整个日志变成 grep 眼中的二进制文件；故这里取带 -e hex 的完整输出。
  back=$({ getfattr -n system.posix_acl_access -e hex "$probe" 2>/dev/null || true; } | { grep -m1 '^system\.posix_acl_access=' || true; })
  echo "   读回：$back"
  if [ "$back" = "system.posix_acl_access=0x0200000001000600ffffffff020007000100000004000400ffffffff10000700ffffffff20000400ffffffff" ]; then
    echo "   OK   读回的字节与写入的完全一致"
  else
    echo "   FAIL 读回的字节与写入的不一致"; rc=1
  fi
else
  echo "   FAIL 无法写入 system.posix_acl_access："
  sed 's/^/     /' /tmp/.acl-fs-probe.err
  echo "     （ext4 需内核带 POSIX ACL 支持且未以 noacl 挂载）"
  rc=1
fi
rm -f "$probe" /tmp/.acl-fs-probe.err
echo "   构建目录所在文件系统："
{ stat -f -c '     /sources 文件系统类型：%T' /sources || true; }
{ grep -E ' /sources ' /proc/mounts || true; } | sed 's/^/     /'
{ grep -E ' / ' /proc/mounts || true; } | sed 's/^/     /'
echo "   注：/proc/mounts 里不出现 noacl 即为默认开启 ACL（ext4 自 2.6.39 起默认 acl）。"
echo

echo "3) 本节构建链所需的工具（configure/make/测试驱动）："
for t in gcc g++ make ld ar sed grep awk perl msgfmt pkg-config xz tar find install; do
  p=$(command -v "$t" 2>/dev/null || true)
  if [ -n "$p" ]; then printf '   OK   %-11s %s\n' "$t" "$p"
  else printf '   FAIL %-11s 未找到\n' "$t"; rc=1; fi
done
echo "   版本："
{ gcc --version | sed -n 1p || true; } | sed 's/^/     /'
{ make --version | sed -n 1p || true; } | sed 's/^/     /'
{ perl --version | sed -n 2p || true; } | sed 's/^/     /'
echo "   perl 是本节硬依赖：make check 由 perl 写的 test/run 驱动（TEST_LOG_COMPILER）。"
echo "   本包 tarball 是 .tar.xz（上一节 attr 是 .tar.gz），故 xz 必须可用。"
echo "   注：这里**不**要求系统里有 libtool —— 手册的 Libtool 要到 §8.42 才装；"
echo "     acl 用的是 configure 自己生成的 ./libtool 脚本（下面核对 --disable-static"
echo "     是否生效，查的就是那个生成出来的 libtool 文件），与系统 libtool 无关。"
echo

echo "4) 目标位置当前状态（本节应当是首次安装，不是覆盖）："
for f in /usr/bin/chacl /usr/bin/getfacl /usr/bin/setfacl /usr/lib/libacl.so \
         /usr/include/acl /usr/include/sys/acl.h "$DOCDIR"; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在（将被覆盖）\n' "$f"
  else printf '   OK   %s 尚不存在\n' "$f"; fi
done
echo

if [ $rc -ne 0 ]; then
  echo "前置检查未通过，按任务要求不继续 §8.26。" >&2
  exit 1
fi
echo "前置检查全部通过。"
echo

# =========================================================================
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
cd /sources
echo "官方 md5sums 中本包一行：$({ grep -F "$TARBALL" /sources/md5sums || true; })"
echo "实测：$(md5sum $TARBALL)"
{ grep -F "$TARBALL" /sources/md5sums || true; } | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
[ -d "$SRCDIR" ] && { echo "发现上次遗留的 $SRCDIR，先删除以保证从干净源码开始"; rm -rf "$SRCDIR"; }
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "构建目录：$(pwd)（in-tree build，本节手册没有 mkdir build）"
echo "源码树顶层：$(ls | tr '\n' ' ')"
echo "VERSION 文件："; { cat VERSION 2>/dev/null || true; } | sed 's/^/  /'
echo

echo "----- 本包的结构性事实（开工前已在 chroot /tmp 的完整试建中逐条确认） -----"
echo "本包 <0.1 SBU / 6.5 MB，故正式开工前先在 /tmp 里做过一次完整试建"
echo "（configure + make + make check + make DESTDIR=... install，不写系统），"
echo "本脚本下面每一条数字断言都是在那次试建的产物上验过的，试建目录已删除。"
echo "几条与紧邻的 §8.25 Attr 不同、照抄必然扑空的点："
echo "  a) 共享库实体是 libacl.so.1.1.2302、SONAME libacl.so.1。三段数字都不是包版本："
echo "     libacl/Makemodule.am 里 LT_CURRENT=2、LT_AGE=1，LT_REVISION 由 configure.ac"
echo "     用 printf \"%d%d%02d\" 2 3 2 算成 2302，-version-info 2:2302:1 →"
echo "     主号 = CURRENT-AGE = 1，实体名 = libacl.so.1.1.2302。"
echo "  b) 本节 configure **没有** --sysconfdir=/etc：Acl 不装任何 /etc 下的文件"
echo "     （对照 §8.25 Attr 的 /etc/xattr.conf）。"
echo "  c) 头文件装到**两个**地方：/usr/include/acl/libacl.h 与 /usr/include/sys/acl.h。"
echo "     手册 Contents 只列了目录 /usr/include/acl，sys/acl.h 未列但确实会装。"
echo "  d) 本节装 pkg-config 文件 libacl.pc（后面 §8.72 Coreutils 等要靠它找 libacl）。"
echo "  e) 测试共 15 项：TESTS 13 项 + XFAIL_TESTS 2 项（test/nfs/nfsacl.test 与"
echo "     test/nfs/nfs-dir.test 在 Makefile 里明写为 XFAIL_TESTS，即预期失败）。"
echo "  f) test/root/ 下 4 项永远 SKIP（exit 77），原因与「是不是 root」无关："
echo "     测试由 test/runwrapper 预载 .libs/libtestlookup.so 接管 getpwnam 等；"
echo "     该库的 getpwnam_r 在 buflen < 170000 时**故意**返回 ERANGE（用来考验调用方"
echo "     是否会扩大缓冲区重试），而同库的 getpwnam() 包装只给了 16384 字节的静态"
echo "     缓冲区，于是预载后 getpwnam(\"root\") 恒为 NULL；test/run 的 su() 因此报"
echo "     \"su: user root does not exist\"，require_root 随即 exit 77。这是上游测试"
echo "     套件的固有行为，在任何系统上都一样，不是本环境的缺陷。"
echo "  g) 测试日志开头的 \"Possible precedence issue with control flow operator (exit)"
echo "     at ./test/run line 147\" 是 test/run 这个 perl 脚本自身的写法告警，不是失败。"
echo

echo "----- 测试结构预读（决定 make check 的判定标准） -----"
echo "源码 test/Makemodule.am 里声明的 TESTS / XFAIL_TESTS："
{ sed -n '/^TESTS[ +]*=/,/^$/p;/^XFAIL_TESTS[ +]*=/,/^$/p' test/Makemodule.am || true; } | sed 's/^/  /'
echo "test/ 下的 .test 文件（共 $({ ls test/*.test test/root/*.test test/nfs/*.test 2>/dev/null | wc -l; }) 个）："
{ ls test/*.test test/root/*.test test/nfs/*.test 2>/dev/null || true; } | sed 's/^/  /'
echo

# =========================================================================
echo "================= 8.26.1. Installation of Acl ================="
echo
echo "----- 手册命令 1/4：configure -----"
echo "手册原文：Prepare Acl for compilation:"
echo "手册命令："
echo "  ./configure --prefix=/usr    \\"
echo "              --disable-static \\"
echo "              --docdir=/usr/share/doc/acl-$VER"
echo "（完整输出另存到 $CONFLOG）"
set +e
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/acl-$VER > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
[ $conf_rc -eq 0 ] || { echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG"; exit $conf_rc; }
echo "configure 末尾 15 行："
tail -n 15 "$CONFLOG" | sed 's/^/  /'
echo
echo "----- 核对手册给的 3 个选项确实生效 -----"
echo "configure 自己记录的调用行（config.log 第 5 行附近）："
{ grep -m1 '^  \$ \./configure' config.log || true; } | sed 's/^/  /'
opt_rc=0
chk() { # <描述> <期望> <实测>
  if [ "$2" = "$3" ]; then printf '  OK   %-34s = %s\n' "$1" "$3"
  else printf '  FAIL %-34s 期望 %s，实测 %s\n' "$1" "$2" "$3"; opt_rc=1; fi
}
chk "--prefix=/usr → prefix"        "/usr"      "$({ grep -m1 '^prefix = ' Makefile || true; } | sed 's/^prefix = //')"
chk "  （随之）bindir"              "/usr/bin"  "$({ grep -m1 '^bindir = ' Makefile || true; } | sed 's/^bindir = //' | sed 's|\${exec_prefix}|/usr|')"
chk "  （随之）libdir"              "/usr/lib"  "$({ grep -m1 '^libdir = ' Makefile || true; } | sed 's/^libdir = //' | sed 's|\${exec_prefix}|/usr|')"
chk "--docdir=... → docdir"         "$DOCDIR"   "$({ grep -m1 '^docdir = ' Makefile || true; } | sed 's/^docdir = //')"
chk "--disable-static → build_old_libs" "no"    "$({ grep -m1 '^build_old_libs=' libtool || true; } | sed 's/^build_old_libs=//')"
chk "  （对照）build_libtool_libs"   "yes"      "$({ grep -m1 '^build_libtool_libs=' libtool || true; } | sed 's/^build_libtool_libs=//')"
echo "  另：本节手册**没有** --sysconfdir，故 sysconfdir 保持 configure 的默认值"
echo "      Makefile 里 sysconfdir = $({ grep -m1 '^sysconfdir = ' Makefile || true; } | sed 's/^sysconfdir = //')（prefix=/usr，即 /usr/etc）"
echo "      —— Acl 不装任何 /etc 下的文件，安装后会核对 /usr/etc 确实没被建出来。"
echo "  configure 找到的 libattr（本节对 §8.25 产物的实际使用）："
{ grep -iE 'attr/(libattr|xattr|error_context)\.h|in -lattr' "$CONFLOG" || true; } | sed 's/^/    /'
[ $opt_rc -eq 0 ] || { echo "选项核对未通过" >&2; exit 1; }
echo

echo "----- 手册命令 2/4：make -----"
echo "手册原文：Compile the package:"
echo "手册命令：make"
echo "（并行度来自手册 §7.4 设定的 MAKEFLAGS=${MAKEFLAGS:-}；完整输出另存到 $MAKELOG）"
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "make 退出码：$make_rc（输出 $(wc -l < "$MAKELOG") 行）"
[ $make_rc -eq 0 ] || { echo "make 失败，末尾 40 行："; tail -n 40 "$MAKELOG"; exit $make_rc; }
echo "make 末尾 5 行："
tail -n 5 "$MAKELOG" | sed 's/^/  /'
echo
echo "----- 编译结果确认 -----"
echo "编译告警统计（仅统计，不作判据）：$({ grep -cE 'warning:' "$MAKELOG" || true; }) 条 warning，$({ grep -cE ' error:' "$MAKELOG" || true; }) 条 error"
echo "构建出的共享库与程序："
{ ls -l .libs/libacl.so* 2>/dev/null || true; } | sed 's/^/  /'
{ ls -l .libs/chacl .libs/getfacl .libs/setfacl 2>/dev/null || ls -l chacl getfacl setfacl 2>/dev/null || true; } | sed 's/^/  /'
echo "libacl.so 的 SONAME 与依赖（应 NEEDED libattr.so.1，即上一节的产物）："
{ readelf -d .libs/libacl.so.1.1.2302 2>/dev/null | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/  /'
echo "--disable-static 的可观测结果：不应生成 libacl.a"
if [ -e .libs/libacl.a ] || [ -e libacl.a ]; then echo "  FAIL 生成了静态库 libacl.a"; exit 1
else echo "  OK   没有 libacl.a"; fi

# =========================================================================
echo "----- 手册命令 3/4：make check（本节的测试） -----"
echo "手册原文（本节关于测试的全部文字，正文两句 + 一个 Note 提示框）："
echo "  「The Acl tests must be run on a filesystem that supports access controls."
echo "    To test the results, issue:」  make check"
echo "  Note：「One test named test/cp.test is known to fail because Coreutils is not"
echo "         built with the Acl support yet.」"
echo "  前一句的前置条件已在上面「前置检查」第 2 项实测确认（/sources 是 ext4，且真实"
echo "    POSIX ACL 写入/读回成功、ls -l 出现 '+'）。"
echo "  Note 直接决定判定方式：既然手册明说有一项已知失败，make check 必然以非零退出码"
echo "    结束，**退出码本身不能作为判据**；判据是「失败项有且只有 test/cp」。"
echo "（手册这条不带 tee，本节按原样直接执行；完整输出另存到 $CHECKLOG 供留档。）"
set +e
make check > "$CHECKLOG" 2>&1
check_rc=$?
set -e
echo "make check 退出码：$check_rc（输出 $(wc -l < "$CHECKLOG") 行）"
echo "  —— 非零属预期，见上面的 Note；下面按逐项结果判定。"
echo
echo "----- make check 结论 -----"
echo "automake 汇总块（Testsuite summary）原文："
{ grep -E '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary|=====)' "$CHECKLOG" || true; } \
  | sed 's/^/  /'
echo
sum_of() { awk -v k="$1" '$0 ~ "^# "k": " {s += $3} END {print s+0}' "$CHECKLOG"; }
t_total=$(sum_of TOTAL); t_pass=$(sum_of PASS);   t_fail=$(sum_of FAIL)
t_skip=$(sum_of SKIP);   t_xfail=$(sum_of XFAIL); t_xpass=$(sum_of XPASS)
t_err=$(sum_of ERROR)
echo "汇总合计："
printf '  TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
  "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
echo "逐项结果（automake 的 .trs 文件是权威来源，这里两边都列）："
echo "  make check 输出里的逐项行："
{ grep -E '^(PASS|FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; } | sed 's/^/    /'
echo "  各 .trs 记录的 global-test-result："
trs_list=$({ find . -name '*.trs' | sort || true; })
for f in $trs_list; do
  r=$({ grep -m1 '^:global-test-result:' "$f" || true; } | awk '{print $2}')
  printf '    %-32s %s\n' "${f#./}" "${r:-?}"
done
echo
echo "失败项（FAIL）明细："
fails=$(for f in $trs_list; do
          r=$({ grep -m1 '^:global-test-result:' "$f" || true; } | awk '{print $2}')
          [ "$r" = "FAIL" ] && echo "${f#./}"
        done || true)
if [ -n "$fails" ]; then echo "$fails" | sed 's/^/  /'; else echo "  （无）"; fi
echo "跳过项（SKIP）明细与各自给出的原因："
for f in $trs_list; do
  r=$({ grep -m1 '^:global-test-result:' "$f" || true; } | awk '{print $2}')
  if [ "$r" = "SKIP" ]; then
    printf '  %-32s %s\n' "${f#./}" \
      "$({ grep -m1 'skipping test\|SKIP ' "${f%.trs}.log" || true; } | sed 's/^ *//')"
  fi
done
echo "测试用的预载库（决定 test/root/ 4 项 SKIP 的那一个；它是 check_LTLIBRARIES，"
echo "  make 阶段还不存在，要到 make check 才构建出来）："
{ ls -l .libs/libtestlookup.so* 2>/dev/null || true; } | sed 's/^/  /'
echo "预期失败项（XFAIL，Makefile 里 XFAIL_TESTS 明写的两项）："
{ grep -A3 '^XFAIL_TESTS' Makefile || true; } | sed 's/^/  /'
echo
echo "判定："
chk_rc=0
tchk() { if [ "$2" = "$3" ]; then printf '  OK   %-8s = %s\n' "$1" "$3"
         else printf '  FAIL %-8s 期望 %s，实测 %s\n' "$1" "$2" "$3"; chk_rc=1; fi; }
tchk TOTAL 15 "$t_total"
tchk PASS   8 "$t_pass"
tchk FAIL   1 "$t_fail"
tchk SKIP   4 "$t_skip"
tchk XFAIL  2 "$t_xfail"
tchk XPASS  0 "$t_xpass"
tchk ERROR  0 "$t_err"
if [ "$fails" = "test/cp.trs" ]; then
  echo "  OK   唯一的失败项就是手册 Note 点名的 test/cp"
else
  echo "  FAIL 失败项不是「有且只有 test/cp」，实测：${fails:-（无）}"; chk_rc=1
fi
echo "test/cp 的失败细节（应当是 cp 没有保留 ACL —— 正是手册说的 Coreutils 尚未带 Acl 支持）："
{ sed -n '/^FAIL: test\/cp$/,/^SKIP:/p' test-suite.log || true; } | sed -n '1,32p' | sed 's/^/    /'
echo "  对照：本节装好 Acl 之后，§8.72 Coreutils 会重新构建并链接 libacl，届时 cp -p"
echo "        才会保留 ACL；手册把这一项的失败写进 Note，就是这个先后顺序造成的。"
[ $chk_rc -eq 0 ] || { echo "测试结果不符合手册允许的范围" >&2; exit 1; }
echo
{
  echo "===== §8.26 Acl-$VER 测试汇总 ====="
  echo "手册命令：make check"
  echo "手册判据（本节关于测试的全部文字）："
  echo "  正文：「The Acl tests must be run on a filesystem that supports access controls."
  echo "         To test the results, issue: make check」"
  echo "  Note：「One test named test/cp.test is known to fail because Coreutils is not"
  echo "         built with the Acl support yet.」"
  echo "  手册没有给出期望的测试数量，故除「失败项只有 test/cp」直接来自手册 Note 外，"
  echo "  TOTAL/PASS/SKIP/XFAIL 的数字判据均为本项目自加，来源是源码 test/Makemodule.am"
  echo "  的 TESTS(13)+XFAIL_TESTS(2) 声明，以及开工前同源码同选项的 chroot /tmp 完整试建。"
  echo
  echo "make check 退出码：$check_rc（非零属预期：automake 对 FAIL 项返回非零）"
  printf 'TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
    "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
  echo
  echo "逐项："
  for f in $trs_list; do
    r=$({ grep -m1 '^:global-test-result:' "$f" || true; } | awk '{print $2}')
    printf '  %-32s %s\n' "${f#./}" "${r:-?}"
  done
  echo
  echo "FAIL  : test/cp —— 手册 Note 点名的已知失败（Coreutils 尚未带 Acl 支持，"
  echo "        cp -p / cp -rp 不保留 ACL）。"
  echo "XFAIL : test/nfs/nfsacl、test/nfs/nfs-dir —— Makefile 的 XFAIL_TESTS 明写的"
  echo "        预期失败（针对 NFS 的 ACL 行为，本环境无 NFS）。"
  echo "SKIP  : test/root/{getfacl,permissions,restore,setfacl} —— 全部 exit 77。"
  echo "        原因与「是不是 root」无关：test/runwrapper 预载 .libs/libtestlookup.so"
  echo "        接管 getpwnam*，其 getpwnam_r 在 buflen<170000 时故意返回 ERANGE，而同库"
  echo "        的 getpwnam() 只给 16384 字节静态缓冲区，于是 getpwnam(\"root\") 恒为 NULL，"
  echo "        test/run 的 su() 报 \"su: user root does not exist\"，require_root exit 77。"
  echo "        这是上游测试套件的固有行为，任何系统上都一样。"
  echo "PASS  : 其余 8 项（cp 之外的全部非 root、非 nfs 测试）。"
  echo
  echo "测试所在文件系统：/sources = ext4，实测可写入并读回真实 POSIX ACL"
  echo "  （system.posix_acl_access，写后 ls -l 出现 '+'），满足手册的前置条件。"
  echo "结论：符合手册允许的结果，无未解释的意外失败。"
} > "$SUMLOG"
echo "测试汇总已写入 $SUMLOG"
echo

# =========================================================================
echo "----- 手册命令 4/4：make install -----"
echo "手册原文：Install the package:"
echo "手册命令：make install"
echo "（完整输出另存到 $INSTLOG）"
set +e
make install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "make install 退出码：$inst_rc（输出 $(wc -l < "$INSTLOG") 行）"
[ $inst_rc -eq 0 ] || { echo "make install 失败，末尾 40 行："; tail -n 40 "$INSTLOG"; exit $inst_rc; }
echo

echo "----- 安装后检查（手册 §8.26.2 Contents of Acl） -----"
inst_rc=0
echo "手册 Installed programs: chacl, getfacl, and setfacl"
for p in chacl getfacl setfacl; do
  if [ -x "/usr/bin/$p" ]; then printf '  OK   /usr/bin/%-8s %s\n' "$p" "$(file -b /usr/bin/$p 2>/dev/null | cut -c1-60)"
  else printf '  FAIL /usr/bin/%s 缺失\n' "$p"; inst_rc=1; fi
done
echo "手册 Installed library: libacl.so"
if [ -L /usr/lib/libacl.so ]; then
  echo "  OK   /usr/lib/libacl.so -> $(readlink /usr/lib/libacl.so)"
else echo "  FAIL /usr/lib/libacl.so 缺失或不是符号链接"; inst_rc=1; fi
{ ls -l /usr/lib/libacl.so* || true; } | sed 's/^/    /'
soname=$({ readelf -d /usr/lib/libacl.so.1.1.2302 2>/dev/null | grep SONAME || true; })
echo "    SONAME/依赖：$(echo "$soname" | sed 's/^ *//')"
{ readelf -d /usr/lib/libacl.so.1.1.2302 2>/dev/null | grep NEEDED || true; } | sed 's/^/    /'
echo "手册 Installed directories: /usr/include/acl 和 $DOCDIR"
for d in /usr/include/acl "$DOCDIR"; do
  if [ -d "$d" ] && [ ! -L "$d" ]; then
    printf '  OK   %s（真目录，%s 项）\n' "$d" "$({ ls -A "$d" | wc -l; })"
    { ls -A "$d" || true; } | sed 's/^/      /'
  else printf '  FAIL %s 不是目录\n' "$d"; inst_rc=1; fi
done
echo "手册未列但确实装出的东西（如实记录，便于日后核对）："
for f in /usr/include/sys/acl.h /usr/lib/pkgconfig/libacl.pc /usr/lib/libacl.la; do
  if [ -e "$f" ]; then printf '  INFO %s\n' "$f"; else printf '  INFO %s（未装出）\n' "$f"; fi
done
n_man1=$({ ls /usr/share/man/man1/{chacl,getfacl,setfacl}.1 2>/dev/null | wc -l; })
n_man3=$({ ls /usr/share/man/man3/acl_*.3 2>/dev/null | wc -l; })
n_man5=$({ ls /usr/share/man/man5/acl.5 2>/dev/null | wc -l; })
n_mo=$({ find /usr/share/locale -name acl.mo 2>/dev/null | wc -l; })
echo "  INFO man1 $n_man1 页、man3 $n_man3 页、man5 $n_man5 页"
echo "  INFO 本地化 acl.mo $n_mo 个语言"
echo "--disable-static 的可观测结果：系统里不应有 libacl.a"
if [ -e /usr/lib/libacl.a ]; then echo "  FAIL /usr/lib/libacl.a 存在"; inst_rc=1
else echo "  OK   /usr/lib/libacl.a 不存在"; fi
echo "本节没有 --sysconfdir，Acl 也不装 /etc 下的文件，核对没有误装到 /usr/etc："
if [ -e /usr/etc ]; then echo "  FAIL /usr/etc 被建出来了：$({ ls -A /usr/etc || true; } | tr '\n' ' ')"; inst_rc=1
else echo "  OK   /usr/etc 不存在"; fi
echo "手册 §7.5.1 Warning：/usr/lib64 必须不存在"
if [ -e /usr/lib64 ]; then echo "  FAIL /usr/lib64 存在"; inst_rc=1; else echo "  OK   /usr/lib64 不存在"; fi
[ $inst_rc -eq 0 ] || { echo "安装后检查未通过" >&2; exit 1; }
echo

echo "----- 功能验证（对照手册 §8.26.2 的 Short Descriptions，用已安装的程序与库） -----"
fn_rc=0
work=$(mktemp -d /tmp/acl-verify-XXXXXX)
cd "$work"
touch f
echo "手册：setfacl —— Sets file access control lists"
if setfacl -m u:daemon:rwx,g:tty:rx f; then echo "  OK   setfacl -m u:daemon:rwx,g:tty:rx f"
else echo "  FAIL setfacl 执行失败"; fn_rc=1; fi
echo "  ls -l 的 '+' 标记：$(ls -l f | awk '{print $1}')"
case "$(ls -l f | awk '{print $1}')" in *+) echo "  OK   内核确认该文件带扩展 ACL" ;; *) echo "  FAIL 没有 '+' 标记"; fn_rc=1 ;; esac
echo "手册：getfacl —— Gets file access control lists"
echo "  getfacl f 输出："
{ getfacl --omit-header f || true; } | sed 's/^/    /'
got=$({ getfacl --omit-header f 2>/dev/null || true; })
for want in 'user:daemon:rwx' 'group:tty:r-x' 'mask::rwx'; do
  case "$got" in *"$want"*) printf '  OK   含 %s\n' "$want" ;; *) printf '  FAIL 缺 %s\n' "$want"; fn_rc=1 ;; esac
done
echo "  与底层扩展属性对照（ACL 就是 system.posix_acl_access，由 libattr 读写）："
{ getfattr -m- -d -e hex f 2>/dev/null || true; } | sed 's/^/    /'
echo "手册：chacl —— Changes the access control list of a file or directory"
if chacl -l f >/dev/null 2>&1 || chacl u::rw-,g::r--,o::r-- f; then
  echo "  OK   chacl 可执行：$({ chacl -l f 2>/dev/null || true; })"
else echo "  FAIL chacl 执行失败"; fn_rc=1; fi
echo "手册：libacl —— Contains the library functions for manipulating Access Control Lists"
cat > t.c <<'CEOF'
#include <sys/acl.h>
#include <acl/libacl.h>
#include <stdio.h>
int main(void) {
  acl_t a = acl_get_file("f", ACL_TYPE_ACCESS);
  if (!a) { perror("acl_get_file"); return 1; }
  char *s = acl_to_text(a, NULL);
  printf("acl_get_file + acl_to_text 成功，条目数 %d：\n%s", acl_entries(a), s ? s : "(null)");
  acl_free(s); acl_free(a);
  return 0;
}
CEOF
if gcc -o t t.c -lacl 2>t.err; then
  echo "  OK   用 -lacl 链接成功（头文件 sys/acl.h + acl/libacl.h 均可用）"
  if ./t > t.out 2> t.run.err; then sed 's/^/    /' t.out
  else echo "  FAIL 运行失败："; sed 's/^/    /' t.run.err; fn_rc=1; fi
  { ldd t | grep -E 'libacl|libattr' || true; } | sed 's/^/    /'
  echo "  上一行同时证明：可执行文件经 libacl 间接依赖上一节的 libattr。"
else
  echo "  FAIL 用 -lacl 链接失败："; sed 's/^/    /' t.err; fn_rc=1
fi
echo "pkg-config 可用性（后续包靠它找 libacl）："
{ pkg-config --modversion libacl && pkg-config --libs libacl; } 2>&1 | sed 's/^/  /'
cd /sources/$SRCDIR
rm -rf "$work"
[ $fn_rc -eq 0 ] || { echo "功能验证未通过" >&2; exit 1; }
echo

# =========================================================================
echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.26.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make check   完整输出：$CHECKLOG"
echo "  make install 完整输出：$INSTLOG"
echo "  测试汇总     ：$SUMLOG"
cp -f test-suite.log /sources/.acl-test-suite.log 2>/dev/null || true
echo "  automake 的 test-suite.log 也一并留档：/sources/.acl-test-suite.log"
cd /sources
echo "清理前 /sources 下的 acl 相关条目："
{ ls -d /sources/acl* 2>/dev/null || true; } | sed 's/^/  /'
echo "  待删除：$(du -sh /sources/$SRCDIR 2>/dev/null | awk '{print $1"\t"$2}')"
rm -rf "/sources/$SRCDIR"
echo "已删除 /sources/$SRCDIR"
echo "清理后 /sources 下的 acl 相关条目（应只剩 tarball）："
{ ls -d /sources/acl* 2>/dev/null || true; } | sed 's/^/  /'
if [ -e "/sources/$SRCDIR" ]; then echo "  FAIL 源码构建目录仍存在"; exit 1
else echo "  OK   源码构建目录已删除"; fi
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -type d -name 'acl*' || true; } | sed 's/^/  /'
echo "/sources 文件数：$({ ls -A /sources | wc -l; })"
echo "/tmp 下本节留下的临时目录/文件（应为空）："
{ find /tmp -maxdepth 1 -name 'acl-*' -o -maxdepth 1 -name '.acl-*' || true; } | sed 's/^/  /'
echo "根文件系统占用："
{ df -h / | tail -n1 || true; } | sed 's/^/  /'
echo

echo "================= 本节结论 ================="
echo "手册 §8.26 的 4 条命令全部按原样执行完毕："
echo "  1. ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/acl-$VER"
echo "                                     —— 完成，3 个选项逐条核对生效"
echo "  2. make                            —— 完成"
echo "  3. make check                      —— 完成，退出码 $check_rc（非零属预期，见 Note）"
echo "  4. make install                    —— 完成"
echo "本节无 sed、无补丁、无 build 目录（in-tree build），无 make html/install-html。"
echo "本节唯一的提示框是那个 Note（test/cp.test 已知失败），已按它判定测试。"
echo
echo "测试结论："
printf '  TOTAL : %s\n  PASS  : %s\n  FAIL  : %s（手册 Note 允许，且实测就是 test/cp）\n' "$t_total" "$t_pass" "$t_fail"
printf '  SKIP  : %s（test/root/ 4 项，上游测试套件固有行为，见汇总日志的解释）\n' "$t_skip"
printf '  XFAIL : %s（Makefile 的 XFAIL_TESTS 明写的 test/nfs 两项）\n  XPASS : %s（要求 0）\n  ERROR : %s（要求 0）\n' "$t_xfail" "$t_xpass" "$t_err"
echo "  测试所在文件系统：/sources = ext4，实测可写入/读回真实 POSIX ACL"
echo "  无未解释的意外失败。"
echo
echo "手册 §8.26.2 Contents 逐项确认："
echo "  Installed programs   : chacl, getfacl, setfacl —— 均已装入 /usr/bin"
echo "  Installed library    : libacl.so —— 已装（-> libacl.so.1.1.2302，SONAME libacl.so.1，"
echo "                         NEEDED libattr.so.1）"
echo "  Installed directories: /usr/include/acl、$DOCDIR"
echo "  手册未列但确实装出：/usr/include/sys/acl.h、/usr/lib/pkgconfig/libacl.pc、"
echo "                      /usr/lib/libacl.la、man1 $n_man1 页 + man3 $n_man3 页 + man5 $n_man5 页、acl.mo $n_mo 种语言"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.26 Acl-$VER 完成 ====="
