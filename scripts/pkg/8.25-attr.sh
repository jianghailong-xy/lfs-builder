#!/usr/bin/env bash
# LFS 13.0-systemd §8.25 Attr-2.5.2
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.25.1 Installation of Attr 的命令序列（全部 4 条，一条不多一条不少）：
#   ./configure --prefix=/usr     \
#               --disable-static  \
#               --sysconfdir=/etc \
#               --docdir=/usr/share/doc/attr-2.5.2
#   make
#   make check
#   make install
#
# 本节没有 sed、没有补丁、没有 mkdir build（in-tree build），也**没有** make html /
#   make install-html（这两条是 §8.22 GMP / §8.23 MPFR / §8.24 MPC 才有的，本节没有）。
# 本节**一个提示框都没有**（无 Note / Important / Caution / Warning）——
#   手册对测试的全部文字是正文里的两句：
#   「The tests must be run on a filesystem that supports extended attributes such as
#     the ext2, ext3, or ext4 filesystems.」「To test the results, issue: make check」
#   前一句是本节独有的**前置条件**，故下面的前置检查里专门实测了构建目录所在
#   文件系统的 user.* 扩展属性读写。
set -euo pipefail

PKG=attr
VER=2.5.2
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
DOCDIR=/usr/share/doc/attr-$VER
CONFLOG=/sources/.attr-configure.log
MAKELOG=/sources/.attr-make.log
CHECKLOG=/sources/.attr-make-check.log
INSTLOG=/sources/.attr-make-install.log
SUMLOG=/sources/.attr-test-summary.log

echo "===== LFS 13.0-systemd §8.25 Attr-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Attr package contains utilities to administer the extended"
echo "  attributes of filesystem objects."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 4.1 MB"
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

echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0
echo "1) 上一任务 §8.24 MPC-1.3.1 的产物 —— Attr 本身**不依赖** MPC，这里查它是为了"
echo "   确认上一任务确实完成、系统状态连续（任务书要求「开始前确认上一任务产物可用」）："
for f in /usr/include/mpc.h /usr/lib/libmpc.so /usr/lib/libmpc.so.3 \
         /usr/lib/libmpc.so.3.3.1 /usr/share/info/mpc.info; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.24 未完成？）\n' "$f"; rc=1; fi
done
mpc_str=$(sed -n 's/^#define MPC_VERSION_STRING *"\(.*\)"$/\1/p' /usr/include/mpc.h | sed -n 1p)
if [ "$mpc_str" = "1.3.1" ]; then
  echo "   OK   MPC 头文件自述版本 $mpc_str = §8.24 的 1.3.1"
else
  echo "   FAIL MPC 头文件自述版本 '$mpc_str' 与 §8.24 的 1.3.1 不符"; rc=1
fi
if [ -d /usr/share/doc/mpc-1.3.1/mpc.html ]; then
  echo "   OK   /usr/share/doc/mpc-1.3.1/mpc.html/（$(find /usr/share/doc/mpc-1.3.1 -type f | wc -l) 个文件）—— §8.24 的 make install-html 产物"
else
  echo "   FAIL /usr/share/doc/mpc-1.3.1/mpc.html/ 缺失"; rc=1
fi
echo "   用已装 MPC 链接运行一个最小程序（确认上一任务产物不只是文件在、而且可用）："
tmpm=$(mktemp /tmp/mpc-pre-XXXXXX.c)
cat > "$tmpm" <<'EOF'
#include <stdio.h>
#include <mpc.h>
int main(void){ printf("mpc=%s\n", mpc_get_version()); return 0; }
EOF
if gcc -o "${tmpm%.c}" "$tmpm" -lmpc -lmpfr -lgmp >/dev/null 2>&1; then
  echo "     $("${tmpm%.c}")"
  echo "     OK   §8.24 的 libmpc 可编译链接并运行"
else
  echo "     FAIL 无法用已装 MPC 编译/链接（§8.24 产物不可用）"; rc=1
fi
rm -f "$tmpm" "${tmpm%.c}"
echo
echo "2) 本节的真实依赖 —— C 库/编译器与 glibc 提供的 xattr 系统调用封装："
echo "   （Attr 只依赖 glibc：libattr 的 attr_get/attr_set 等最终落到 glibc 的"
echo "     getxattr/setxattr/listxattr/removexattr，头文件是 /usr/include/sys/xattr.h。）"
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2 /usr/include/stdio.h \
         /usr/include/sys/xattr.h /usr/include/libintl.h; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   glibc 中的 xattr 符号（configure 不显式探测，但链接期必须有）："
{ readelf --dyn-syms -W /usr/lib/libc.so.6 \
    | grep -E ' (getxattr|setxattr|listxattr|removexattr|lgetxattr|fsetxattr)$' || true; } \
  | awk '{printf "     %s\n", $8}' | sort -u
tmpx=$(mktemp /tmp/xattr-pre-XXXXXX.c)
cat > "$tmpx" <<'EOF'
#include <stdio.h>
#include <sys/xattr.h>
int main(void){ printf("xattr syscalls linkable\n"); return setxattr("/nonexistent", "user.x", "y", 1, 0) == 0; }
EOF
if gcc -o "${tmpx%.c}" "$tmpx" >/dev/null 2>&1; then
  echo "     OK   gcc 可编译并链接 setxattr/getxattr（glibc 封装齐全）"
else
  echo "     FAIL 无法链接 xattr 系统调用封装"; rc=1
fi
rm -f "$tmpx" "${tmpx%.c}"
echo
echo "3) 手册本节的**前置条件实测**（这是本节独有的一句，必须当成硬性前置来验）："
echo "   手册原文：The tests must be run on a filesystem that supports extended"
echo "     attributes such as the ext2, ext3, or ext4 filesystems."
echo "   本节的解包与构建目录在 /sources（= 宿主 /root/lfs/sources 的 bind mount），"
echo "   make check 由 automake 在同一目录下跑，故要验的就是 /sources 所在文件系统。"
echo "   当前挂载表中 / 与 /sources 的条目："
{ grep -E ' (/|/sources) ' /proc/self/mounts || true; } | sed 's/^/     /'
xattr_probe() {   # <目录>
  local d=$1 p rcv=0
  p=$(mktemp "$d/.xattr-probe-XXXXXX") || return 1
  # 用 C 程序直接调 setxattr/getxattr —— 此刻 attr 尚未安装，系统里没有 setfattr
  local c; c=$(mktemp /tmp/xprobe-XXXXXX.c)
  cat > "$c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <sys/xattr.h>
int main(int argc, char **argv){
  char buf[64] = {0};
  if (setxattr(argv[1], "user.lfs_probe", "ok", 2, 0) != 0) { perror("setxattr"); return 1; }
  if (getxattr(argv[1], "user.lfs_probe", buf, sizeof buf) < 0) { perror("getxattr"); return 1; }
  if (strncmp(buf, "ok", 2) != 0) { fprintf(stderr, "value mismatch: %s\n", buf); return 1; }
  if (removexattr(argv[1], "user.lfs_probe") != 0) { perror("removexattr"); return 1; }
  printf("user.lfs_probe 写入/读回/删除均成功\n");
  return 0;
}
EOF
  if gcc -o "${c%.c}" "$c" >/dev/null 2>&1 && "${c%.c}" "$p"; then rcv=0; else rcv=1; fi
  rm -f "$p" "$c" "${c%.c}"
  return $rcv
}
for d in /sources /tmp; do
  fstype=$(awk -v m="$d" '$2==m {print $3}' /proc/self/mounts | sed -n 1p)
  [ -n "$fstype" ] || fstype=$(awk '$2=="/" {print $3}' /proc/self/mounts | sed -n 1p)
  printf '   %-9s 文件系统类型：%s\n' "$d" "$fstype"
  if xattr_probe "$d" | sed "s|^|     $d ：|"; then
    echo "     OK   $d 支持扩展属性，满足手册对 make check 的前置要求"
  else
    echo "     FAIL $d 不支持扩展属性 —— 手册明确要求测试须在支持 xattr 的文件系统上运行"; rc=1
  fi
done
echo
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "5) 本节直接依赖的外部命令（第 8 章的 chroot 是半成品系统，宿主机上顺手就有的"
echo "   命令不一定存在；本包的 make check 由 perl 写的 test/run 驱动，故 perl 是硬依赖）："
for t in tar gzip make gcc ld as ar ranlib sed grep awk tee install ln rm mkdir \
         cmp diff md5sum readelf objdump ldd find stat bash sort tail perl \
         msgfmt xgettext msgmerge file du df env tr wc cat cp mktemp date pkg-config; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-12s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   perl 版本   ：$(perl --version | sed -n '2p')"
echo "   msgfmt 版本 ：$(msgfmt --version | sed -n 1p)"
echo "   说明：configure 会做 'checking for GNU gettext in libc'（本系统答 yes，翻译走"
echo "     glibc 内建的 gettext，不需要外部 libintl），但 po/ 下 10 种语言的 .mo 仍由"
echo "     §7.7 装的 msgfmt 生成；make check 的 TEST_LOG_COMPILER 是 test/run（perl）。"
echo "   注意：本包的 tarball 是 .tar.gz（不是 .tar.xz），解包靠 gzip 而非 xz。"
echo
echo "6) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then
  echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "   本节无补丁（手册 §8.25 未引用任何 patch）；/sources 中匹配 attr*patch 的文件："
attr_patches=$({ ls /sources 2>/dev/null | grep -E '^attr.*patch' || true; })
echo "     ${attr_patches:-无}"
echo
echo "7) §7.3 虚拟内核文件系统与 §7.6 基础文件（测试脚本要读写 /dev、/proc、临时目录）："
for f in /dev/null /dev/zero /dev/full /dev/urandom /dev/tty /proc/self /sys \
         /etc/passwd /etc/group /tmp /var/tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "8) 安装目标目录与安装前的 Attr 痕迹（Attr 是第一次装进本系统）："
for d in /usr/bin /usr/lib /usr/include /usr/share/doc /usr/share/man/man1 \
         /usr/share/man/man3 /usr/share/locale /etc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
pre=$({ ls -d /usr/bin/attr /usr/bin/getfattr /usr/bin/setfattr /usr/lib/libattr* \
              /usr/include/attr /etc/xattr.conf "$DOCDIR" 2>/dev/null || true; })
if [ -z "$pre" ]; then
  echo "   INFO 系统中当前没有任何 Attr 文件 —— 符合预期：第 5/6/7 章从未构建过 attr，"
  echo "     本节是首次安装（下一节 §8.26 Acl 会用到本节装出的 libattr）。"
else
  echo "   INFO 安装前已存在的 Attr 相关文件（本节会覆盖）："; echo "$pre" | sed 's/^/     /'
fi
echo
echo "9) 磁盘空间（手册要求 4.1 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 51200 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 4.1 MB"
else echo "   FAIL 可用空间不足：$((avail_k/1024)) MB"; rc=1; fi
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
echo "手册 §8.25 全节没有 mkdir build —— Attr 在源码目录内直接 configure（in-tree build）。"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
echo "上游版本自述："
conf_ver=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'\$/\1/p" configure | sed -n 1p)
conf_str=$(sed -n "s/^PACKAGE_STRING='\(.*\)'\$/\1/p" configure | sed -n 1p)
echo "  configure ：PACKAGE_VERSION=$conf_ver  PACKAGE_STRING='$conf_str'"
if [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $conf_ver 与手册 §8.25 的 Attr-$VER 一致"
else echo "  FAIL 源码自述版本为 '$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo

echo "----- 本包的四个结构性事实（开工前已在 chroot /tmp 的完整试建中确认；写在这里是"
echo "      为了让下面的核对方式有据可依，其中前三条与紧邻的 §8.22–§8.24 那三个数学库"
echo "      **都不一样**，照抄上一节的判据必然扑空） -----"
echo "  a) 共享库文件名是 libattr.so.1.1.2502，SONAME 是 libattr.so.1 —— 三段数字都不是"
echo "     包版本 2.5.2，而是 libtool -version-info 算出来的："
{ grep -nE '^LT_(CURRENT|AGE) *=|version-info' libattr/Makemodule.am || true; } | sed 's/^/       /'
{ grep -nE 'LT_REVISION=\$\(printf' configure.ac || true; } | sed 's/^/       /'
echo "     LT_CURRENT=2、LT_AGE=1、LT_REVISION 由 configure.ac 用 printf \"%d%d%02d\" 2 5 2"
echo "     算成 2502 → -version-info 2:2502:1 → SONAME 主号 = CURRENT-AGE = 2-1 = 1，"
echo "     实体名 libattr.so.<主号>.<AGE>.<REVISION> = libattr.so.1.1.2502。"
echo "  b) 本节**有** --sysconfdir=/etc，前三节都没有。它唯一的作用是决定 xattr.conf 的"
echo "     安装位置（Makefile.am 里的 dist_sysconf_DATA）："
{ grep -nE 'dist_sysconf_DATA' Makefile.am || true; } | sed 's/^/       /'
echo "     所以「--sysconfdir=/etc 是否生效」的可观测判据就是 /etc/xattr.conf 是否装出来。"
echo "  c) 本节**装** pkg-config 文件 libattr.pc（源码树里有 libattr.pc.in，由 configure"
echo "     生成），这点与 §8.24 MPC 相反、与 §8.22 GMP/§8.23 MPFR 相同："
{ ls libattr.pc.in 2>/dev/null || echo "（无 libattr.pc.in）"; } | sed 's/^/       /'
echo "  d) include/attr 是 configure 用 AC_CONFIG_COMMANDS 建的**符号链接**（指向源码树的"
echo "     include/），而安装到系统的 /usr/include/attr 是**真目录**（装 3 个头文件）："
{ grep -nA4 'AC_CONFIG_COMMANDS(\[include/attr\]' configure.ac || true; } | sed 's/^/       /'
echo

echo "----- 测试结构预读（决定 make check 的判定标准） -----"
echo "test/Makemodule.am 的测试声明（automake parallel-tests 框架）："
{ grep -nE '^(TESTS|EXTRA_DIST|AM_TESTS_ENVIRONMENT|TEST_LOG_COMPILER)' -A4 test/Makemodule.am || true; } \
  | sed 's/^/  /'
echo "解包后 test/ 下的文件："
{ find test -type f | sort || true; } | sed 's/^/  /'
echo "结论：TESTS 只有 2 项 —— test/attr.test 与 test/root/getfattr.test，"
echo "  两者都由 test/run（perl）解释执行，故预期 TOTAL=2。"
echo "  AM_TESTS_ENVIRONMENT 会把 abs_top_builddir 放进 PATH 并置 LC_MESSAGES=C，"
echo "  因此测试用的是**刚编出来的** attr/getfattr/setfattr，而不是系统里已装的版本"
echo "  （本节安装在 make check 之后，系统里此刻也还没有）。"
echo

echo "================= 8.25.1. Installation of Attr ================="

echo "----- 手册命令 1/4：configure -----"
echo "手册原文：Prepare Attr for compilation:"
echo "手册命令："
echo "  ./configure --prefix=/usr     \\"
echo "              --disable-static  \\"
echo "              --sysconfdir=/etc \\"
echo "              --docdir=/usr/share/doc/attr-$VER"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr     \
            --disable-static  \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/attr-$VER > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 60 行："; tail -n 60 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "configure 关键结论摘录："
{ grep -E '^checking (for gcc|whether the C compiler works|for C compiler default output|for suffix of executables|whether we are cross compiling|for msgfmt|for GNU gettext in libc|whether to use NLS|for shared library run path origin|for ld used by gcc)' "$CONFLOG" || true; } \
  | sed 's/^/  /'
echo "config.status 生成的文件："
{ grep -E '^config\.status: creating' "$CONFLOG" || true; } | sed 's/^/  /'
echo

echo "----- 核对手册给的 4 个选项确实生效（configure 记录 + 生成的 Makefile/libtool 双重核对） -----"
orc=0
echo "config.status 里记录的本次配置串："
{ grep -n '^ac_cs_config=' config.status || true; } | sed 's/^/  /'
cs=$(sed -n "s/^ac_cs_config='\(.*\)'\$/\1/p" config.status | sed -n 1p)
for opt in "--prefix=/usr" "--disable-static" "--sysconfdir=/etc" "--docdir=/usr/share/doc/attr-$VER"; do
  case " $cs " in
    *" $opt "*) printf '  OK   ac_cs_config 中含 %s\n' "$opt" ;;
    *)          printf '  FAIL ac_cs_config 中缺 %s\n' "$opt"; orc=1 ;;
  esac
done
echo "生成的 Makefile 中的安装路径变量（--prefix / --sysconfdir / --docdir 的直接落点）："
{ grep -nE '^(prefix|exec_prefix|libdir|includedir|bindir|sysconfdir|docdir|mandir|localedir) *=' Makefile || true; } \
  | sed 's/^/  /'
mk_get() { sed -n "s/^$1 *= *//p" Makefile | sed -n 1p; }
[ "$(mk_get prefix)" = "/usr" ] \
  && echo "  OK   Makefile: prefix = /usr" \
  || { echo "  FAIL Makefile: prefix = $(mk_get prefix)"; orc=1; }
[ "$(mk_get sysconfdir)" = "/etc" ] \
  && echo "  OK   Makefile: sysconfdir = /etc（若不给 --sysconfdir，autoconf 默认是 \${prefix}/etc = /usr/etc）" \
  || { echo "  FAIL Makefile: sysconfdir = $(mk_get sysconfdir)"; orc=1; }
[ "$(mk_get docdir)" = "$DOCDIR" ] \
  && echo "  OK   Makefile: docdir = $DOCDIR" \
  || { echo "  FAIL Makefile: docdir = $(mk_get docdir)"; orc=1; }
echo "生成的 libtool 中的静态库开关（--disable-static 的直接落点）："
{ grep -nE '^(build_old_libs|build_libtool_libs)=' libtool || true; } | sed -n '1,4p' | sed 's/^/  /'
lt_old=$(sed -n 's/^build_old_libs=//p' libtool | sed -n 1p)
lt_shared=$(sed -n 's/^build_libtool_libs=//p' libtool | sed -n 1p)
[ "$lt_old" = "no" ] \
  && echo "  OK   libtool: build_old_libs=no（不建 .a，--disable-static 生效）" \
  || { echo "  FAIL libtool: build_old_libs=$lt_old"; orc=1; }
[ "$lt_shared" = "yes" ] \
  && echo "  OK   libtool: build_libtool_libs=yes（建共享库）" \
  || { echo "  FAIL libtool: build_libtool_libs=$lt_shared"; orc=1; }
[ $orc -eq 0 ] || { echo "错误：手册给的选项未全部生效" >&2; exit 1; }
echo

echo "----- 手册命令 2/4：make -----"
echo "手册原文：Compile the package:"
echo "手册命令：make"
echo "完整输出写入 $MAKELOG，下面只摘要。"
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "make 退出码：$make_rc（输出 $(wc -l < "$MAKELOG") 行）"
if [ $make_rc -ne 0 ]; then
  echo "make 失败，末尾 80 行："; tail -n 80 "$MAKELOG" | sed 's/^/  /'
  exit $make_rc
fi
echo "编译动作统计（automake silent-rules，每行一个动作）："
printf '  CC   %s 次\n'   "$({ grep -cE '^  CC ' "$MAKELOG" || true; })"
printf '  CCLD %s 次\n'   "$({ grep -cE '^  CCLD ' "$MAKELOG" || true; })"
printf '  GEN  %s 次\n'   "$({ grep -cE '^  GEN ' "$MAKELOG" || true; })"
echo "编译/链接告警（warning/error 行，应为空）："
warns=$({ grep -nE 'warning:|error:' "$MAKELOG" || true; })
if [ -n "$warns" ]; then echo "$warns" | sed -n '1,30p' | sed 's/^/  /'; else echo "  （无）"; fi
echo
echo "----- 编译结果确认 -----"
brc=0
echo "构建出的可执行文件（libtool wrapper 与 .libs 下的真实 ELF）："
for p in attr getfattr setfattr; do
  if [ -x "$p" ]; then printf '  OK   ./%-10s（%s 字节）\n' "$p" "$(stat -c %s "$p")"
  else printf '  FAIL ./%s 未生成\n' "$p"; brc=1; fi
done
echo "构建出的共享库（.libs/）："
{ ls -l .libs/libattr.so* 2>/dev/null || true; } | sed 's/^/  /'
if [ -f .libs/libattr.so.1.1.2502 ]; then
  echo "  OK   .libs/libattr.so.1.1.2502 已生成（$(stat -c %s .libs/libattr.so.1.1.2502) 字节）"
else
  echo "  FAIL .libs/libattr.so.1.1.2502 未生成"; brc=1
fi
echo "共享库的 SONAME 与依赖（结构性事实 a 的验证）："
{ readelf -d .libs/libattr.so.1.1.2502 | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/  /'
soname=$(readelf -d .libs/libattr.so.1.1.2502 | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')
[ "$soname" = "libattr.so.1" ] \
  && echo "  OK   SONAME = libattr.so.1（= CURRENT-AGE = 2-1 = 1，不是包版本 2.5.2）" \
  || { echo "  FAIL SONAME = $soname，应为 libattr.so.1"; brc=1; }
echo "静态库检查（--disable-static 的作用范围 —— 这里第一次跑时判错过，故写清楚）："
a_files=$({ find . -name '*.a' || true; })
echo "  源码树内所有 .a："
if [ -n "$a_files" ]; then echo "$a_files" | sed 's/^/    /'; else echo "    （无）"; fi
echo "  说明：--disable-static 只作用于**要安装的**库（lib_LTLIBRARIES 里的 libattr.la）；"
echo "    libmisc 是 noinst_LTLIBRARIES 声明的 convenience library（见 libmisc/Makemodule.am"
echo "    第 1 行），libtool 对这类只在树内使用、从不安装的库**总是**产出 .a，与"
echo "    --disable-static 无关。因此 .libs/libmisc.a 存在是正常的，不能据此判失败。"
{ grep -nE 'noinst_LTLIBRARIES' Makefile.am libmisc/Makemodule.am 2>/dev/null || true; } | sed 's/^/    /'
echo "  真正的判据：要安装的 libattr 不得有任何 .a（树内与稍后的 /usr/lib 都要查）："
attr_a=$({ find . -name 'libattr*.a' || true; })
if [ -z "$attr_a" ]; then echo "  OK   树内没有 libattr*.a（--disable-static 生效）"
else echo "$attr_a" | sed 's/^/  FAIL 残留 libattr 静态库：/'; brc=1; fi
unexpected_a=$({ find . -name '*.a' ! -name 'libmisc.a' || true; })
if [ -z "$unexpected_a" ]; then echo "  OK   树内除 convenience library libmisc.a 外没有其它 .a"
else echo "$unexpected_a" | sed 's/^/  FAIL 意料之外的 .a：/'; brc=1; fi
echo "刚编出的程序自述版本（此刻系统里还没装 attr，用的一定是构建产物）："
for p in getfattr setfattr; do
  printf '  ./%-10s --version -> %s\n' "$p" "$(./$p --version 2>&1 | sed -n 1p)"
done
echo "  ./attr 的用法自述（attr 无 --version，打印 usage 到 stderr）："
{ ./attr 2>&1 || true; } | sed -n '1,3p' | sed 's/^/    /'
echo "生成的翻译文件（gettext 在 po/ 下产出的是 .gmo，安装时才改名成 <lang>/LC_MESSAGES/attr.mo；"
echo "  第一次跑时这里按 po/*.mo 找，找到的是空 —— 名字看错了）："
gmo_list=$({ ls po/*.gmo 2>/dev/null || true; })
echo "$gmo_list" | xargs -r -n1 basename | tr '\n' ' ' | sed 's/^/  /'; echo
gmo_n=$(printf '%s\n' "$gmo_list" | grep -c '\.gmo$' || true)
echo "  共 $gmo_n 个 .gmo（po/LINGUAS 声明的语言：$({ cat po/LINGUAS 2>/dev/null || true; } | grep -v '^#' | tr '\n' ' '))"
[ "$gmo_n" = "11" ] && echo "  OK   11 个 .gmo（cs de en@boldquot en@quot es fr gl ka nl pl sv）" \
  || { echo "  FAIL .gmo 有 $gmo_n 个，试建实测应为 11"; brc=1; }
echo "生成的 libattr.pc（结构性事实 c）："
{ cat libattr.pc 2>/dev/null || true; } | sed 's/^/  /'
[ $brc -eq 0 ] || { echo "错误：编译结果不符合预期" >&2; exit 1; }
echo

echo "----- 手册命令 3/4：make check（本节的测试） -----"
echo "手册原文（本节关于测试的全部文字，两句，没有任何提示框）："
echo "  The tests must be run on a filesystem that supports extended attributes such as"
echo "  the ext2, ext3, or ext4 filesystems. To test the results, issue:"
echo "手册命令：make check"
echo "  前一句的前置条件已在上面「前置检查」第 3 项实测确认（构建目录所在的 /sources"
echo "  是 ext4，user.* 扩展属性写入/读回/删除均成功）。"
echo "（手册这条**不带** tee，本节按原样直接执行；完整输出另存到 $CHECKLOG 供留档。）"
set +e
make check > "$CHECKLOG" 2>&1
check_rc=$?
set -e
echo "make check 退出码：$check_rc（输出 $(wc -l < "$CHECKLOG") 行）"
echo
echo "----- make check 结论 -----"
echo "automake 汇总块（Testsuite summary）原文："
{ grep -nE '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary|=====)' "$CHECKLOG" || true; } \
  | sed 's/^/  /'
echo
sum_of() { awk -v k="$1" '$0 ~ "^# "k": " {s += $3} END {print s+0}' "$CHECKLOG"; }
t_total=$(sum_of TOTAL); t_pass=$(sum_of PASS);   t_fail=$(sum_of FAIL)
t_skip=$(sum_of SKIP);   t_xfail=$(sum_of XFAIL); t_xpass=$(sum_of XPASS)
t_err=$(sum_of ERROR)
echo "汇总合计："
printf '  TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
  "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
echo "逐项结果："
{ grep -E '^(PASS|FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; } | sed 's/^/  /'
echo "非 PASS 的逐项结果（FAIL/XFAIL/XPASS/ERROR/SKIP）："
nonpass=$({ grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; })
if [ -n "$nonpass" ]; then echo "$nonpass" | sed 's/^/  /'; else echo "  （无）"; fi
echo "两个测试各自的 .log 里执行了多少条断言（test/run 每条命令一行 '-- ok'）："
for l in test/attr.log test/root/getfattr.log; do
  if [ -f "$l" ]; then
    printf '  %-26s 断言 %s 条，失败标记（-- failed）%s 条\n' "$l" \
      "$({ grep -cE ' -- ok$' "$l" || true; })" \
      "$({ grep -cE ' -- failed' "$l" || true; })"
  else
    printf '  %-26s 缺失\n' "$l"
  fi
done
echo "  说明：测试日志开头的 \"Possible precedence issue with control flow operator (exit)"
echo "    at ./test/run line 150\" 是 test/run 这个 perl 脚本自身的写法告警（perl 对"
echo "    'exit' 优先级的提示），不是测试失败，automake 也不据此判定结果。"
echo
{
  echo "===== §8.25 Attr-$VER 测试汇总 ====="
  echo "手册命令：make check"
  echo "手册判据：手册对本节测试只有两句话 —— 「The tests must be run on a filesystem"
  echo "  that supports extended attributes such as the ext2, ext3, or ext4 filesystems.」"
  echo "  与「To test the results, issue: make check」，没有给出期望的测试数量，"
  echo "  也没有任何提示框/允许失败的例外。故除「退出码 0」外的数字判据均为本项目自加，"
  echo "  其中 TOTAL=2 既来自源码 test/Makemodule.am 的 TESTS 声明（两项），"
  echo "  也来自开工前同源码、同选项在 chroot /tmp 内的完整试建实测。"
  echo "make check 退出码：$check_rc"
  printf 'TOTAL=%s PASS=%s FAIL=%s SKIP=%s XFAIL=%s XPASS=%s ERROR=%s\n' \
    "$t_total" "$t_pass" "$t_fail" "$t_skip" "$t_xfail" "$t_xpass" "$t_err"
  echo "----- 非 PASS 项 -----"
  { grep -E '^(FAIL|XFAIL|XPASS|ERROR|SKIP): ' "$CHECKLOG" || true; }
  echo "----- 汇总块 -----"
  { grep -E '^(# (TOTAL|PASS|FAIL|SKIP|XFAIL|XPASS|ERROR):|Testsuite summary)' "$CHECKLOG" || true; }
  echo "----- 逐项 PASS -----"
  { grep -E '^PASS: ' "$CHECKLOG" || true; }
  echo "----- test/attr.log 全文 -----"
  { cat test/attr.log 2>/dev/null || true; }
  echo "----- test/root/getfattr.log 全文 -----"
  { cat test/root/getfattr.log 2>/dev/null || true; }
} > "$SUMLOG"
trc=0
echo "判据核对："
if [ "$check_rc" -eq 0 ]; then
  echo "  OK   硬判据 1（手册「To test the results, issue: make check」）：make check 完整跑完且退出码 0"
else
  echo "  FAIL 硬判据 1：make check 退出码 $check_rc"; trc=1
fi
if [ "$t_total" = 2 ]; then
  echo "  OK   硬判据 2（自加，源码 TESTS 声明 + 试建校准）：TOTAL = 2"
else
  echo "  FAIL 硬判据 2（自加）：TOTAL = $t_total，应为 2"; trc=1
fi
if [ "$t_pass" = 2 ]; then
  echo "  OK   硬判据 2（自加，源码 TESTS 声明 + 试建校准）：PASS = 2（全过）"
else
  echo "  FAIL 硬判据 2（自加）：PASS = $t_pass，应为 2"; trc=1
fi
if [ "$t_fail" = 0 ] && [ "$t_err" = 0 ] && [ "$t_xpass" = 0 ] && [ "$t_skip" = 0 ]; then
  echo "  OK   硬判据 3（自加）：FAIL=0、XPASS=0、ERROR=0、SKIP=0"
  echo "       （SKIP=0 也是硬判据：本包唯一会导致跳过的原因就是文件系统不支持 xattr，"
  echo "         而那正是手册那句前置条件；跳过即等于测试没真跑，故不接受。）"
else
  echo "  FAIL 硬判据 3（自加）：FAIL=$t_fail XPASS=$t_xpass ERROR=$t_err SKIP=$t_skip"; trc=1
fi
if [ "$t_total" -gt 0 ] && [ "$((t_pass + t_skip + t_xfail + t_fail + t_xpass + t_err))" = "$t_total" ]; then
  echo "  OK   硬判据 4（自加）：PASS+SKIP+XFAIL+FAIL+XPASS+ERROR = TOTAL($t_total)"
else
  echo "  FAIL 硬判据 4（自加）：各项之和 != TOTAL($t_total)"; trc=1
fi
if [ "$({ grep -cE ' -- failed' test/attr.log test/root/getfattr.log 2>/dev/null | awk -F: '{s+=$2} END{print s+0}' || true; })" = "0" ]; then
  echo "  OK   硬判据 5（自加）：两个测试日志里没有任何 '-- failed' 断言"
else
  echo "  FAIL 硬判据 5（自加）：测试日志中存在 '-- failed' 断言"; trc=1
fi
if [ $trc -ne 0 ]; then
  echo "错误：测试结果不符合要求；完整输出见 $CHECKLOG" >&2
  echo "  make check 末尾 80 行：" >&2
  tail -n 80 "$CHECKLOG" | sed 's/^/  /' >&2
  exit 1
fi
echo
echo "测试结论：手册 §8.25 要求 make check（且要求在支持扩展属性的文件系统上跑），"
echo "  本次已在 ext4 上完整跑完，退出码 $check_rc。"
echo "  TOTAL=$t_total、PASS=$t_pass —— 全过；FAIL=0、XPASS=0、ERROR=0、SKIP=0、XFAIL=$t_xfail。"
echo "  无未解释的意外失败。"
echo

echo "----- 手册命令 4/4：make install -----"
echo "手册原文：Install the package:"
echo "手册命令：make install"
echo "完整输出写入 $INSTLOG，下面只摘要。"
set +e
make install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "make install 退出码：$inst_rc（输出 $(wc -l < "$INSTLOG") 行）"
if [ $inst_rc -ne 0 ]; then
  echo "make install 失败，末尾 60 行："; tail -n 60 "$INSTLOG" | sed 's/^/  /'
  exit $inst_rc
fi
echo "安装到系统的条目（摘自 install 日志）："
{ grep -oE '(/usr/(bin|share|lib|include)|/etc)[^ "'"'"']*' "$INSTLOG" || true; } | sort -u | sed 's/^/  /'
echo "libtool 在 install 阶段的告警（若有）："
{ grep -E 'libtool: warning' "$INSTLOG" || true; } | sort -u | sed 's/^/  /'
echo

echo "----- 安装后检查（手册 §8.25.2 Contents of Attr） -----"
echo "手册列出的内容："
echo "  Installed programs   : attr, getfattr, and setfattr"
echo "  Installed library    : libattr.so"
echo "  Installed directories: /usr/include/attr and /usr/share/doc/attr-$VER"
irc=0
echo
echo "1) Installed programs（手册逐条）："
for p in attr getfattr setfattr; do
  if [ -x "/usr/bin/$p" ]; then
    printf '   OK   /usr/bin/%-10s（%s 字节，%s）\n' "$p" "$(stat -c %s "/usr/bin/$p")" \
      "$(file -b "/usr/bin/$p" | cut -d, -f1-2)"
  else printf '   FAIL /usr/bin/%s 缺失\n' "$p"; irc=1; fi
done
echo "   三个程序的动态依赖（应都链到刚装的 /usr/lib/libattr.so.1）："
for p in attr getfattr setfattr; do
  printf '     %-10s -> %s\n' "$p" \
    "$({ ldd "/usr/bin/$p" | grep -E 'libattr' || echo '（未链接 libattr）'; } | tr -s ' ' | sed 's/^ //')"
done
echo
echo "2) Installed library（手册写 libattr.so，实际是符号链接 + SONAME 链接 + 实体三件）："
for f in /usr/lib/libattr.so /usr/lib/libattr.so.1 /usr/lib/libattr.so.1.1.2502; do
  if [ -e "$f" ]; then
    if [ -L "$f" ]; then printf '   OK   %-34s -> %s\n' "$f" "$(readlink "$f")"
    else printf '   OK   %-34s（%s 字节，实体）\n' "$f" "$(stat -c %s "$f")"; fi
  else printf '   FAIL %s 缺失\n' "$f"; irc=1; fi
done
inst_soname=$(readelf -d /usr/lib/libattr.so.1.1.2502 2>/dev/null | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p')
[ "$inst_soname" = "libattr.so.1" ] \
  && echo "   OK   已装库的 SONAME = libattr.so.1" \
  || { echo "   FAIL 已装库的 SONAME = '$inst_soname'"; irc=1; }
echo "   静态库（--disable-static，应不存在）："
if [ -e /usr/lib/libattr.a ]; then echo "   FAIL /usr/lib/libattr.a 存在"; irc=1
else echo "   OK   /usr/lib/libattr.a 不存在"; fi
echo "   libtool 归档 /usr/lib/libattr.la："
if [ -f /usr/lib/libattr.la ]; then
  echo "   INFO 存在（$(stat -c %s /usr/lib/libattr.la) 字节）—— 手册 §8.25.2 未列出，"
  echo "        但它是 libtool 安装共享库时的常规产物，手册本节也没有删除它的命令，故保留。"
  { grep -E '^(dlname|library_names|old_library|installed)=' /usr/lib/libattr.la || true; } | sed 's/^/        /'
else
  echo "   INFO /usr/lib/libattr.la 不存在"
fi
echo
echo "3) Installed directories（手册逐条）："
for d in /usr/include/attr "$DOCDIR"; do
  if [ -d "$d" ] && [ ! -L "$d" ]; then
    printf '   OK   %-30s（真目录，%s 个文件）\n' "$d" "$(find "$d" -type f | wc -l)"
  elif [ -L "$d" ]; then
    printf '   FAIL %s 是符号链接（应为真目录）\n' "$d"; irc=1
  else printf '   FAIL %s 缺失\n' "$d"; irc=1; fi
done
echo "   /usr/include/attr 下的头文件（结构性事实 d：装出来的是真目录，不是 configure"
echo "     在源码树里建的那个同名符号链接）："
{ ls -l /usr/include/attr/ || true; } | sed 's/^/     /'
for h in attributes.h error_context.h libattr.h; do
  if [ -f "/usr/include/attr/$h" ]; then printf '     OK   %s（%s 字节）\n' "$h" "$(stat -c %s "/usr/include/attr/$h")"
  else printf '     FAIL %s 缺失\n' "$h"; irc=1; fi
done
echo "   $DOCDIR 下的文件："
{ ls -l "$DOCDIR/" || true; } | sed 's/^/     /'
for f in CHANGES COPYING COPYING.LGPL; do
  if [ -f "$DOCDIR/$f" ]; then printf '     OK   %s（%s 字节）\n' "$f" "$(stat -c %s "$DOCDIR/$f")"
  else printf '     FAIL %s 缺失\n' "$f"; irc=1; fi
done
echo
echo "4) 手册 §8.25.2 没有单独列、但本节确实装出来的东西（逐项说明，避免\"漏装\"与"
echo "   \"手册没列\"混为一谈）："
echo "   a) /etc/xattr.conf —— 来自 --sysconfdir=/etc（结构性事实 b），"
echo "      它是「--sysconfdir=/etc 生效」的唯一可观测判据："
if [ -f /etc/xattr.conf ]; then
  echo "      OK   /etc/xattr.conf 存在（$(stat -c %s /etc/xattr.conf) 字节，$(wc -l < /etc/xattr.conf) 行）"
  echo "      前 6 行："
  sed -n '1,6p' /etc/xattr.conf | sed 's/^/        /'
  if [ -e /usr/etc/xattr.conf ]; then
    echo "      FAIL /usr/etc/xattr.conf 也存在 —— 说明 --sysconfdir 没吃进去"; irc=1
  else
    echo "      OK   /usr/etc/xattr.conf 不存在（未给 --sysconfdir 时才会装到那里）"
  fi
else
  echo "      FAIL /etc/xattr.conf 缺失 —— --sysconfdir=/etc 未生效"; irc=1
fi
echo "   b) /usr/lib/pkgconfig/libattr.pc —— 结构性事实 c；下一节 §8.26 Acl 的 configure"
echo "      会用 pkg-config 找 libattr："
if [ -f /usr/lib/pkgconfig/libattr.pc ]; then
  echo "      OK   存在（$(stat -c %s /usr/lib/pkgconfig/libattr.pc) 字节）"
  cat /usr/lib/pkgconfig/libattr.pc | sed 's/^/        /'
  echo "      pkg-config 实测："
  printf '        --modversion : %s\n' "$(pkg-config --modversion libattr 2>&1)"
  printf '        --cflags     : %s\n' "$(pkg-config --cflags libattr 2>&1)"
  printf '        --libs       : %s\n' "$(pkg-config --libs libattr 2>&1)"
  if [ "$(pkg-config --modversion libattr 2>/dev/null)" = "$VER" ]; then
    echo "        OK   pkg-config 报告的版本 = $VER"
  else
    echo "        FAIL pkg-config 报告的版本与 $VER 不符"; irc=1
  fi
else
  echo "      FAIL /usr/lib/pkgconfig/libattr.pc 缺失"; irc=1
fi
echo "   c) man 手册页（man1 三页对应三个程序，man3 十页对应 libattr 的 attr_* 接口）："
{ ls /usr/share/man/man1/attr.1 /usr/share/man/man1/getfattr.1 /usr/share/man/man1/setfattr.1 2>/dev/null || true; } \
  | sed 's/^/      /'
man3_n=$({ ls /usr/share/man/man3/attr_*.3 2>/dev/null || true; } | wc -l)
echo "      man3 下 attr_*.3 共 $man3_n 页：$({ ls /usr/share/man/man3/attr_*.3 2>/dev/null || true; } | xargs -r -n1 basename | tr '\n' ' ')"
for m in /usr/share/man/man1/attr.1 /usr/share/man/man1/getfattr.1 /usr/share/man/man1/setfattr.1; do
  [ -f "$m" ] || { echo "      FAIL $m 缺失"; irc=1; }
done
[ "$man3_n" = "10" ] && echo "      OK   man3 下 10 页 attr_*.3 齐全" \
  || { echo "      FAIL man3 下 attr_*.3 有 $man3_n 页，试建实测应为 10"; irc=1; }
echo "   d) 翻译文件 /usr/share/locale/*/LC_MESSAGES/attr.mo："
mo_n=$({ find /usr/share/locale -name attr.mo || true; } | wc -l)
echo "      共 $mo_n 个：$({ find /usr/share/locale -name attr.mo || true; } | sed 's|/usr/share/locale/||; s|/LC_MESSAGES/attr.mo||' | sort | tr '\n' ' ')"
[ "$mo_n" = "11" ] && echo "      OK   11 种语言的 attr.mo 齐全（= po/ 下 11 个 .gmo 一一对应）" \
  || { echo "      FAIL attr.mo 有 $mo_n 个，应为 11（po/ 下有 11 个 .gmo）"; irc=1; }
echo
echo "5) 动态链接器缓存与库可见性（本节手册没有 ldconfig 命令；LFS 此时还没有"
echo "   /etc/ld.so.conf，/usr/lib 属默认搜索路径，故不需要）："
if [ -f /etc/ld.so.conf ]; then echo "   INFO /etc/ld.so.conf 存在"; else echo "   INFO /etc/ld.so.conf 不存在（属预期，§8 后续小节才创建）"; fi
echo "   ldconfig 视角下的 libattr（-p 需要缓存文件，缺失时报错属正常，故只作参考）："
{ ldconfig -p 2>/dev/null | grep -E 'libattr' || echo '（ld.so.cache 尚未生成或无条目 —— 不影响，/usr/lib 是默认搜索路径）'; } | sed 's/^/     /'
[ $irc -eq 0 ] || { echo "错误：安装后检查未通过" >&2; exit 1; }
echo

echo "----- 功能验证（对照手册 §8.25.2 的 Short Descriptions，用已安装的程序与库逐项验证） -----"
echo "手册的四条描述："
echo "  attr     ：Extends attributes on filesystem objects"
echo "  getfattr ：Gets the extended attributes of filesystem objects"
echo "  setfattr ：Sets the extended attributes of filesystem objects"
echo "  libattr  ：Contains the library functions for manipulating extended attributes"
frc=0
work=$(mktemp -d /tmp/attr-verify-XXXXXX)
echo "验证用临时目录：$work（位于 $(df -PT "$work" | awk 'NR==2{print $2}') 文件系统，支持 xattr）"
touch "$work/f"
echo
echo "1) setfattr / getfattr（手册第 2、3 条）—— 设置、列出、按名取、删除："
if /usr/bin/setfattr -n user.lfs.section -v "8.25" "$work/f"; then
  echo "   OK   setfattr -n user.lfs.section -v 8.25 成功"
else echo "   FAIL setfattr 失败"; frc=1; fi
if /usr/bin/setfattr -n user.lfs.pkg -v "attr-$VER" "$work/f"; then
  echo "   OK   setfattr -n user.lfs.pkg -v attr-$VER 成功"
else echo "   FAIL setfattr 第二次失败"; frc=1; fi
echo "   getfattr -d 输出："
{ /usr/bin/getfattr -d "$work/f" 2>&1 || true; } | sed 's/^/     /'
got=$({ /usr/bin/getfattr --only-values -n user.lfs.section "$work/f" 2>/dev/null || true; })
if [ "$got" = "8.25" ]; then
  echo "   OK   getfattr --only-values -n user.lfs.section 取回 '$got'（与写入一致）"
else echo "   FAIL getfattr 取回 '$got'，应为 '8.25'"; frc=1; fi
n_attr=$({ /usr/bin/getfattr -d "$work/f" 2>/dev/null | grep -cE '^user\.' || true; })
if [ "$n_attr" = "2" ]; then echo "   OK   该文件上有 2 条 user.* 扩展属性"
else echo "   FAIL 该文件上有 $n_attr 条 user.* 扩展属性，应为 2"; frc=1; fi
if /usr/bin/setfattr -x user.lfs.pkg "$work/f"; then
  left=$({ /usr/bin/getfattr -d "$work/f" 2>/dev/null | grep -cE '^user\.' || true; })
  if [ "$left" = "1" ]; then echo "   OK   setfattr -x 删除一条后只剩 1 条"
  else echo "   FAIL 删除后剩 $left 条，应为 1"; frc=1; fi
else echo "   FAIL setfattr -x 失败"; frc=1; fi
echo
echo "2) attr（手册第 1 条）—— attr 是 IRIX 风格的前端，属性名不带 user. 前缀："
if /usr/bin/attr -s irixstyle -V hello "$work/f" > /dev/null 2>&1; then
  echo "   OK   attr -s irixstyle -V hello 成功"
else echo "   FAIL attr -s 失败"; frc=1; fi
echo "   attr -g irixstyle 输出："
{ /usr/bin/attr -g irixstyle "$work/f" 2>&1 || true; } | sed 's/^/     /'
gval=$({ /usr/bin/attr -q -g irixstyle "$work/f" 2>/dev/null || true; })
if [ "$gval" = "hello" ]; then echo "   OK   attr -q -g 取回 'hello'"
else echo "   FAIL attr -q -g 取回 '$gval'，应为 'hello'"; frc=1; fi
echo "   attr 写的属性在 getfattr 眼里带 user. 前缀（两个前端操作同一套 xattr）："
{ /usr/bin/getfattr -d "$work/f" 2>&1 || true; } | sed 's/^/     /'
gf_dump=$({ /usr/bin/getfattr -d "$work/f" 2>/dev/null || true; })
if printf '%s\n' "$gf_dump" | grep -qE '^user\.irixstyle='; then
  echo "   OK   getfattr 看得到 user.irixstyle —— attr 与 getfattr/setfattr 一致"
else echo "   FAIL getfattr 看不到 user.irixstyle"; frc=1; fi
echo "   attr -l 列出（IRIX 风格列表）："
{ /usr/bin/attr -l "$work/f" 2>&1 || true; } | sed 's/^/     /'
echo "   attr -r 删除后再列出（应只剩 setfattr 写的那条，attr 视角下看不到 lfs.section？"
echo "     —— 能看到，因为它同样在 user 命名空间）："
{ /usr/bin/attr -r irixstyle "$work/f" 2>&1 || true; } | sed 's/^/     /'
{ /usr/bin/attr -l "$work/f" 2>&1 || true; } | sed 's/^/     /'
echo
echo "3) libattr（手册第 4 条）—— 用已装的头文件与共享库编译一个程序，"
echo "   直接调用 libattr 的 attr_set/attr_get/attr_list 接口："
tmpl=$(mktemp /tmp/libattr-XXXXXX.c)
cat > "$tmpl" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <attr/attributes.h>
int main(int argc, char **argv) {
  char val[64]; int len = sizeof val - 1;
  if (attr_set(argv[1], "libattrtest", "viaLibattr", 10, 0) != 0) { perror("attr_set"); return 1; }
  if (attr_get(argv[1], "libattrtest", val, &len, 0) != 0) { perror("attr_get"); return 1; }
  val[len] = '\0';
  printf("attr_get 取回：%s（%d 字节）\n", val, len);
  if (strcmp(val, "viaLibattr") != 0) { fprintf(stderr, "值不符\n"); return 1; }
  attr_multiop_t ops[1];
  char list[512]; attrlist_cursor_t cur; memset(&cur, 0, sizeof cur);
  if (attr_list(argv[1], list, sizeof list, 0, &cur) != 0) { perror("attr_list"); return 1; }
  attrlist_t *al = (attrlist_t *)list;
  printf("attr_list 报告该文件上有 %d 条属性：", al->al_count);
  for (int i = 0; i < al->al_count; i++)
    printf("%s ", ATTR_ENTRY(list, i)->a_name);
  printf("\n");
  (void)ops;
  if (attr_remove(argv[1], "libattrtest", 0) != 0) { perror("attr_remove"); return 1; }
  printf("attr_remove 成功\n");
  return 0;
}
EOF
echo "   注：attributes.h 里的 attr_get/attr_set/attr_list/attr_remove 都带"
echo "     __attribute__((deprecated))（上游建议改用 glibc 的 getxattr/setxattr），"
echo "     因此编译时必然出现 deprecated-declarations 告警，属预期，不是错误。"
if gcc -o "${tmpl%.c}" "$tmpl" -lattr 2>/tmp/libattr-build.err; then
  echo "   OK   gcc -lattr 编译成功（头文件 /usr/include/attr/attributes.h，库 /usr/lib/libattr.so）"
  echo "   编译期告警（应全部是 deprecated-declarations）："
  { grep -cE 'deprecated' /tmp/libattr-build.err || true; } | sed 's/^/     deprecated 告警行数：/'
  { grep -E 'warning:' /tmp/libattr-build.err | grep -vE 'deprecated' || true; } | sed 's/^/     非 deprecated 告警：/'
  echo "   该程序链接到的 libattr："
  { ldd "${tmpl%.c}" | grep libattr || true; } | sed 's/^/     /'
  if "${tmpl%.c}" "$work/f" | sed 's/^/     /'; then
    echo "   OK   attr_set / attr_get / attr_list / attr_remove 全部按预期工作"
  else
    echo "   FAIL libattr 接口调用失败"; frc=1
  fi
else
  echo "   FAIL 无法用已装的 libattr 编译："; sed -n '1,20p' /tmp/libattr-build.err | sed 's/^/     /'; frc=1
fi
rm -f "$tmpl" "${tmpl%.c}" /tmp/libattr-build.err
echo
echo "4) 收尾：删除验证用临时目录"
rm -rf "$work"
[ -d "$work" ] && { echo "   FAIL $work 未删除"; frc=1; } || echo "   OK   $work 已删除"
[ $frc -eq 0 ] || { echo "错误：功能验证未通过" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.25.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make check   完整输出：$CHECKLOG"
echo "  make install 完整输出：$INSTLOG"
echo "  测试汇总     ：$SUMLOG"
echo "清理前 /sources 下的 attr 相关条目："
{ ls -d /sources/attr* 2>/dev/null || true; } | sed 's/^/  /'
echo "  待删除：$(du -sh "/sources/$SRCDIR" 2>/dev/null | cut -f1)	/sources/$SRCDIR"
cd /sources
rm -rf "$SRCDIR"
if [ -d "/sources/$SRCDIR" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCDIR"
echo "清理后 /sources 下的 attr 相关条目（应只剩 tarball）："
{ ls -d /sources/attr* 2>/dev/null || true; } | sed 's/^/  /'
echo "  OK   源码构建目录已删除"
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -mindepth 1 -type d || true; } | sed 's/^/  /'
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "/tmp 下本节留下的临时目录/文件（应为空）："
{ ls -d /tmp/attr-* /tmp/libattr-* /tmp/xprobe-* 2>/dev/null || true; } | sed 's/^/  /'
echo "根文件系统占用："
df -h / | tail -n1
echo

echo "================= 本节结论 ================="
echo "手册 §8.25 的 4 条命令全部按原样执行完毕："
echo "  1. ./configure --prefix=/usr --disable-static --sysconfdir=/etc --docdir=$DOCDIR"
echo "                                     —— 完成，4 个选项逐条核对生效"
echo "  2. make                            —— 完成"
echo "  3. make check                      —— 完成，退出码 $check_rc"
echo "  4. make install                    —— 完成"
echo "本节无 sed、无补丁、无 build 目录（in-tree build），无 make html/install-html，"
echo "  全节一个提示框都没有。"
echo
echo "测试结论（手册对本节测试的全部要求是「须在支持扩展属性的文件系统上」+"
echo "  「To test the results, issue: make check」，未给数量判据；下列数字与源码 TESTS"
echo "  声明及试建实测一致）："
echo "  TOTAL : $t_total"
echo "  PASS  : $t_pass"
echo "  FAIL  : $t_fail（要求 0）"
echo "  SKIP  : $t_skip（要求 0）"
echo "  XFAIL : $t_xfail"
echo "  XPASS : $t_xpass（要求 0）"
echo "  ERROR : $t_err（要求 0）"
echo "  测试所在文件系统：/sources = ext4（手册要求 ext2/ext3/ext4 一类支持 xattr 的）"
echo
echo "手册 §8.25.2 Contents 逐项确认："
echo "  Installed programs   : attr, getfattr, setfattr —— 均已装入 /usr/bin"
echo "  Installed library    : libattr.so —— 已装（-> $(readlink /usr/lib/libattr.so 2>/dev/null)，SONAME libattr.so.1）"
echo "  Installed directories: /usr/include/attr（$(find /usr/include/attr -type f | wc -l) 个头文件）、"
echo "                         $DOCDIR（$(find "$DOCDIR" -type f | wc -l) 个文件）"
echo "  手册未列但确实装出：/etc/xattr.conf、/usr/lib/pkgconfig/libattr.pc、"
echo "                      /usr/lib/libattr.la、man1 3 页 + man3 10 页、11 个 attr.mo"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.25 Attr-$VER 完成 ====="
