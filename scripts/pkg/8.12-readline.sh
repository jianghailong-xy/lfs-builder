#!/usr/bin/env bash
# LFS 13.0-systemd §8.12 Readline-8.3
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.12.1 Installation of Readline 的命令序列（全部，一条不多一条不少）：
#   sed -i '/MV.*old/d' Makefile.in
#   sed -i '/{OLDSUFF}/c:' support/shlib-install
#   sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
#   sed -e '270a\ ... else ... chars_avail = 1;' -e '288i\   result = -1;' -i.orig input.c
#   ./configure --prefix=/usr --disable-static --with-curses \
#               --docdir=/usr/share/doc/readline-8.3
#   make SHLIB_LIBS="-lncursesw"
#   （手册原文：This package does not come with a test suite.）
#   make install
#   install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.3   ← 手册 "If desired"
set -euo pipefail

PKG=readline
VER=8.3
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
DOCDIR=/usr/share/doc/readline-$VER
CONFLOG=/sources/.readline-configure.log
MAKELOG=/sources/.readline-make.log
INSTLOG=/sources/.readline-make-install.log

echo "===== LFS 13.0-systemd §8.12 Readline-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Readline package is a set of libraries that offer command-line"
echo "  editing and history capabilities."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 17 MB"
echo "手册存档：/workspace/docs/book/chapter08-readline.html（宿主机 /root/lfs/docs/book/）"
echo

echo "----- 环境（手册 §7.4 进入 chroot 后的环境） -----"
echo "id        : $(id)"
echo "whoami    : $(whoami)"
echo "PATH      : $PATH"
echo "HOME      : $HOME"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "TESTSUITEFLAGS: ${TESTSUITEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
  *) echo "OK        : /tools/bin 不在 PATH" ;;
esac
echo "可用空间（手册本节要求 17 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 25 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 17MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.11 File-5.46）产物必须可用 -----"
rc=0
echo "1) §8.11.2 Contents of File 的关键产物："
for f in /usr/bin/file /usr/lib/libmagic.so /usr/lib/libmagic.so.1 \
         /usr/lib/libmagic.so.1.0.0 /usr/include/magic.h \
         /usr/lib/pkgconfig/libmagic.pc /usr/share/misc/magic.mgc \
         /usr/share/man/man1/file.1 /usr/share/man/man3/libmagic.3 \
         /usr/share/man/man4/magic.4; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.11 未完成？）\n' "$f"; rc=1; fi
done
file_ver=$(file --version 2>&1 | sed -n '1s/^file-//p')
if [ "$file_ver" = "5.46" ]; then echo "   OK   file 自述版本 $file_ver"
else echo "   FAIL file 自述版本为 '$file_ver'，应为 5.46"; rc=1; fi
echo "   file 功能自检（本节结束后还要用它确认新装的共享库类型）："
probe=$(file -b /usr/lib/libmagic.so.1.0.0)
case "$probe" in
  *"ELF 64-bit LSB shared object"*) echo "     OK   file 识别共享库：$probe" ;;
  *) echo "     FAIL file 识别结果异常：$probe"; rc=1 ;;
esac
echo
echo "2) 本节的核心依赖 —— Ncurses（§6.3 交叉编译安装的那份；手册第 8 章的 Ncurses"
echo "   排在本节之后，故此刻系统里就是 §6.3 的版本）。手册的 make 参数"
echo "   SHLIB_LIBS=\"-lncursesw\" 要求 libncursesw 必须存在，configure 的"
echo "   --with-curses 也要靠它来判定 termcap 函数所在的库："
for f in /usr/lib/libncursesw.so /usr/lib/libncursesw.so.6 \
         /usr/include/curses.h /usr/include/term.h /usr/include/termcap.h; do
  if [ -e "$f" ]; then printf '   OK   %-30s -> %-24s（%s 字节）\n' \
       "$f" "$(readlink -f "$f")" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§6.3 Ncurses 未完成？）\n' "$f"; rc=1; fi
done
echo "   libncursesw 链接自检（-lncursesw 编译并运行一个只调 termcap 函数的程序，"
echo "   与 configure 的 bash_cv_termcap_lib 探测方式一致）："
tmpc=$(mktemp /tmp/tcap-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
extern int tgetent(char *, const char *);
int main(void){ char buf[4096]; int r = tgetent(buf, "dumb");
  printf("tgetent(dumb) = %d\n", r); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" -lncursesw >/dev/null 2>&1; then
  echo "     OK   -lncursesw 链接成功：$("${tmpc%.c}")"
else
  echo "     FAIL 无法用 -lncursesw 链接 tgetent，configure 会退回 -lncurses/-ltermcap"; rc=1
fi
rm -f "$tmpc" "${tmpc%.c}"
echo "   INFO /usr/lib/pkgconfig/ncursesw.pc：$( [ -e /usr/lib/pkgconfig/ncursesw.pc ] && echo 存在 || echo 不存在 )"
echo "        （§6.3 的交叉编译 Ncurses 未装 .pc；本节生成的 readline.pc 只是在"
echo "        Requires.private 里写下 ncursesw 这个名字，不需要它此刻存在。）"
echo
echo "3) §8.5 Glibc-2.43 的 C 库与工具链可用（本节要 configure + 编译 C 代码）："
for f in /usr/lib/libc.so.6 /lib64/ld-linux-x86-64.so.2; do
  if [ -e "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("glibc sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && \
   [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
echo "4) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo "5) 本节直接依赖的工具（解包 + sed 补丁 + configure + make + 安装）："
for t in tar gzip make gcc ld ar ranlib sed grep awk install ln rm mkdir cmp diff \
         md5sum readelf objdump find stat bash sort head tail install-info; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-12s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
echo "   sed  版本：$(sed --version | sed -n 1p)"
echo "   说明：install-info 来自 §7.11 Texinfo，doc/Makefile 的 install 会调用它把"
echo "     readline/history/rluserman 三个 info 页登记进 /usr/share/info/dir。"
echo "6) 安装目标目录："
for d in /usr/lib /usr/include /usr/share/man/man3 /usr/share/info /usr/lib/pkgconfig; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo "   INFO $DOCDIR：$( [ -d "$DOCDIR" ] && echo 已存在 || echo 不存在，make install 会创建 )"
echo "7) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "8) §7.3 虚拟内核文件系统与 §7.6 基础文件："
for f in /dev/null /dev/zero /dev/urandom /proc/self /sys /etc/passwd /etc/group /tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "9) 安装前系统中的 Readline 痕迹（本节是 Readline 在本系统的首次安装：第 5/6/7 章"
echo "   都没有 Readline 这一节，§6.4 的 Bash 也没有链接它）："
pre_existing=0
for f in /usr/lib/libreadline.so /usr/lib/libhistory.so /usr/include/readline \
         /usr/lib/pkgconfig/readline.pc "$DOCDIR"; do
  if [ -e "$f" ]; then printf '   INFO %-34s 已存在（重装场景）\n' "$f"; pre_existing=1
  else printf '   INFO %-34s 不存在（首次安装，符合预期）\n' "$f"; fi
done
if [ "$pre_existing" -eq 0 ]; then
  echo "   结论：首次安装。手册开头两条 sed（避免旧库被改名成 <libraryname>.old 而触发"
  echo "     ldconfig 的链接 bug）此刻没有旧库可改名，但仍按手册原样执行 —— 手册的命令"
  echo "     一条都不能少，且它们改的是构建规则本身。"
else
  echo "   结论：系统里已有 Readline 痕迹，手册开头两条 sed 正好用于避免旧库改名。"
fi
echo "   INFO 残留的 *.old 文件（应为空，两条 sed 的目的就是让它们永远不产生）："
pre_old=$(find /usr/lib -maxdepth 1 \( -name 'libreadline*.old' -o -name 'libhistory*.old' \) 2>/dev/null || true)
echo "     ${pre_old:-（无）}"
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls -l | sed 's/^/  /'
echo "上游版本自述："
echo "  readline.h 中的版本宏："
grep -nE '^#define (RL_READLINE_VERSION|RL_VERSION_MAJOR|RL_VERSION_MINOR)' readline.h | sed 's/^/    /'
lib_ver=$(sed -n 's/^#define RL_READLINE_VERSION.*Readline \([0-9.]*\).*/\1/p' readline.h | head -n1)
conf_ver=$(sed -n 's/^LIBVERSION=//p' configure | head -n1)
echo "  readline.h 注释中的版本：$lib_ver"
echo "  configure   LIBVERSION  ：$conf_ver"
if [ "$lib_ver" = "$VER" ] && [ "$conf_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $lib_ver 与手册 §8.12 的 Readline-$VER 一致"
else echo "  FAIL 源码自述版本为 '$lib_ver'/'$conf_ver'，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁文件（patch 命令）：手册 §8.12 的命令序列里只有 sed，没有 patch"
rl_patches=$(ls /sources | grep -Ei '^readline.*patch' || true)
echo "  （/sources 中匹配 readline*patch 的文件：${rl_patches:-无}）"
echo

echo "================= 8.12.1. Installation of Readline ================="
echo
echo "----- 手册命令 1/2：避免旧库被改名为 <libraryname>.old -----"
echo "手册原文：Reinstalling Readline will cause the old libraries to be moved to"
echo "  <libraryname>.old. While this is normally not a problem, in some cases it can"
echo "  trigger a linking bug in ldconfig. This can be avoided by issuing the following"
echo "  two seds:"
echo "手册命令：sed -i '/MV.*old/d' Makefile.in"
echo "         sed -i '/{OLDSUFF}/c:' support/shlib-install"
echo "改前 Makefile.in 中匹配 /MV.*old/ 的行："
mv_before=$(grep -nE 'MV.*old' Makefile.in || true)
[ -n "$mv_before" ] || { echo "  FAIL Makefile.in 中没有匹配 /MV.*old/ 的行，sed 将成为空操作" >&2; exit 1; }
echo "$mv_before" | sed 's/^/  /'
echo "改前 support/shlib-install 中匹配 {OLDSUFF} 的行："
old_before=$(grep -nF '{OLDSUFF}' support/shlib-install || true)
[ -n "$old_before" ] || { echo "  FAIL support/shlib-install 中没有匹配 {OLDSUFF} 的行" >&2; exit 1; }
echo "$old_before" | sed 's/^/  /'
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
echo "改后 Makefile.in 中匹配 /MV.*old/ 的行（应为空）："
mv_left=$(grep -nE 'MV.*old' Makefile.in || true)
if [ -z "$mv_left" ]; then echo "  OK   已全部删除"
else echo "$mv_left" | sed 's/^/  /'; echo "  FAIL 仍有残留" >&2; exit 1; fi
echo "改后 support/shlib-install 中匹配 {OLDSUFF} 的行（应为空）："
old_left=$(grep -nF '{OLDSUFF}' support/shlib-install || true)
if [ -z "$old_left" ]; then echo "  OK   已全部替换为 ':'（shell 空操作）"
else echo "$old_left" | sed 's/^/  /'; echo "  FAIL 仍有残留" >&2; exit 1; fi
echo "替换后的上下文（原第 50-56 行附近，确认 if/fi 结构仍然合法）："
sed -n '48,58p' support/shlib-install | cat -n | sed 's/^/  /'
echo "  语法检查：bash -n support/shlib-install"
bash -n support/shlib-install && echo "  OK   shlib-install 语法合法"
echo

echo "----- 手册命令 2/2 之 rpath -----"
echo "手册原文：Prevent hard coding library search paths (rpath) into the shared"
echo "  libraries. This package does not need rpath for an installation into the"
echo "  standard location, and rpath may sometimes cause unwanted effects or even"
echo "  security issues:"
echo "手册命令：sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf"
echo "改前 support/shobj-conf 中含 -Wl,-rpath 的行："
rpath_before=$(grep -n -- '-Wl,-rpath' support/shobj-conf || true)
[ -n "$rpath_before" ] || { echo "  FAIL support/shobj-conf 中没有 -Wl,-rpath，sed 将成为空操作" >&2; exit 1; }
echo "$rpath_before" | sed 's/^/  /'
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
echo "改后 support/shobj-conf 中含 -Wl,-rpath 的行（应为空）："
rpath_left=$(grep -n -- '-Wl,-rpath' support/shobj-conf || true)
if [ -z "$rpath_left" ]; then echo "  OK   已全部去除"
else echo "$rpath_left" | sed 's/^/  /'; echo "  FAIL 仍有残留" >&2; exit 1; fi
echo "  Linux 分支现在的 SHLIB_XLDFLAGS："
{ grep -n 'SHLIB_XLDFLAGS=' support/shobj-conf || true; } | sed -n '1,4p' | sed 's/^/  /'
echo

echo "----- 手册命令：修正上游针对本版本的已知问题 -----"
echo "手册原文：Fix a problem identified upstream specifically for this version of"
echo "  readline:"
echo "手册命令：sed -e '270a\\'"
echo "              '     else\\'"
echo "              '       chars_avail = 1;'      \\"
echo "             -e '288i\\   result = -1;' \\"
echo "             -i.orig input.c"
echo "改前 input.c 第 265-292 行："
sed -n '265,292p' input.c | cat -n | sed 's/^/  /'
sed -e '270a\
     else\
       chars_avail = 1;'      \
    -e '288i\   result = -1;' \
    -i.orig input.c
echo "改后 input.c 第 265-296 行（新增行以 >>> 标出）："
{ diff -u input.c.orig input.c || true; } | sed -n '1,40p' | sed 's/^/  /'
echo "  新旧文件行数：input.c.orig=$(wc -l < input.c.orig)  input.c=$(wc -l < input.c)"
added=$(( $(wc -l < input.c) - $(wc -l < input.c.orig) ))
echo "  净增行数：$added（手册的 sed 追加 2 行 + 插入 1 行 = 3 行）"
if [ "$added" -eq 3 ]; then echo "  OK   行数变化与手册的 sed 一致"
else echo "  FAIL 行数变化为 $added，应为 3" >&2; exit 1; fi
echo "  改动落点确认（sed 的行号针对*输入*计数：270a 追加的 2 行使其后所有行号 +2，"
echo "    因此 288i 插入的那行在输出文件中位于第 290 行）："
sed -n '269,272p' input.c | sed 's/^/    输出第269-272行: /'
sed -n '288,291p' input.c | sed 's/^/    输出第288-291行: /'
if [ "$(sed -n '271p' input.c)" = "     else" ] && \
   [ "$(sed -n '272p' input.c)" = "       chars_avail = 1;" ] && \
   [ "$(sed -n '290p' input.c)" = "   result = -1;" ]; then
  echo "  OK   两处改动落在手册指定的位置上（270a -> 输出 271/272 行，288i -> 输出 290 行）"
else
  echo "  FAIL 改动落点与预期不符" >&2; exit 1
fi
echo "  语义确认：第一处给 rl_input_available_hook 返回非 0 的分支补上 chars_avail = 1;"
echo "    第二处在 select 分支末尾把 result 复位为 -1，使后面的 FIONREAD 分支继续执行。"
echo "  说明：-i.orig 会把原文件留成 input.c.orig，它在源码树内，随本节末尾"
echo "    删除整个 $SRCDIR 一并清理。"
echo

echo "手册原文：Prepare Readline for compilation:"
echo "手册命令：./configure --prefix=/usr    \\"
echo "                     --disable-static \\"
echo "                     --with-curses    \\"
echo "                     --docdir=$DOCDIR"
echo "手册对新选项的说明：--with-curses —— This option tells Readline that it can find"
echo "  the termcap library functions in the curses library, not a separate termcap"
echo "  library. This will generate the correct readline.pc file."
set +e
./configure --prefix=/usr    \
            --disable-static \
            --with-curses    \
            --docdir=$DOCDIR 2>&1 | tee "$CONFLOG"
conf_rc=${PIPESTATUS[0]}
set -e
echo "configure 退出码：$conf_rc"
[ "$conf_rc" -eq 0 ] || { echo "错误：configure 失败" >&2; exit "$conf_rc"; }
echo
echo "----- configure 结果确认 -----"
echo "  termcap 库探测结果（--with-curses 的直接效果）："
grep -E 'termcap functions' "$CONFLOG" | sed 's/^/    /' || echo "    （configure 输出中未匹配到 termcap 探测行）"
tcap_lib=$(sed -n 's/^TERMCAP_LIB *= *//p' Makefile | head -n1)
tcap_pc=$(sed -n 's/^Requires.private: *//p' readline.pc | head -n1)
echo "    Makefile   TERMCAP_LIB       = $tcap_lib"
echo "    readline.pc Requires.private = $tcap_pc"
if [ "$tcap_lib" = "-lncursesw" ]; then echo "    OK   TERMCAP_LIB 为 -lncursesw"
else echo "    FAIL TERMCAP_LIB 为 '$tcap_lib'，应为 -lncursesw" >&2; exit 1; fi
if [ "$tcap_pc" = "ncursesw" ]; then
  echo "    OK   readline.pc 的 Requires.private 为 ncursesw —— 即手册所说的"
  echo "         「the correct readline.pc file」"
else echo "    FAIL readline.pc 的 Requires.private 为 '$tcap_pc'，应为 ncursesw" >&2; exit 1; fi
echo "  安装路径（Makefile 变量）："
for v in prefix exec_prefix libdir includedir docdir infodir man3dir pkgconfigdir; do
  printf '    %-13s = %s\n' "$v" "$(sed -n "s/^$v *= *//p" Makefile | head -n1)"
done
conf_prefix=$(sed -n 's/^prefix *= *//p' Makefile | head -n1)
conf_docdir=$(sed -n 's/^docdir *= *//p' Makefile | head -n1)
[ "$conf_prefix" = "/usr" ] || { echo "    FAIL prefix 为 '$conf_prefix'，应为 /usr" >&2; exit 1; }
echo "    OK   --prefix=/usr 生效"
[ "$conf_docdir" = "$DOCDIR" ] || { echo "    FAIL docdir 为 '$conf_docdir'，应为 $DOCDIR" >&2; exit 1; }
echo "    OK   --docdir=$DOCDIR 生效"
echo "  --disable-static 的效果（Makefile 的 INSTALL_TARGETS / STATIC_LIBS）："
inst_targets=$(sed -n 's/^INSTALL_TARGETS *= *//p' Makefile | head -n1)
static_libs=$(sed -n 's/^STATIC_LIBS *= *//p' Makefile | head -n1)
shared_libs=$(sed -n 's/^SHARED_LIBS *= *//p' shlib/Makefile | head -n1)
echo "    INSTALL_TARGETS         = ${inst_targets:-（空）}"
echo "    STATIC_LIBS（顶层）     = ${static_libs:-（空）}"
echo "    SHARED_LIBS（shlib/）   = ${shared_libs:-（空）}"
echo "    说明：STATIC_LIBS 在 Makefile.in 里是写死的名字列表，--disable-static 的作用"
echo "      体现在 INSTALL_TARGETS 上（只保留 @SHARED_INSTALL_TARGET@）。"
case "$inst_targets" in
  *install-static*) echo "    FAIL INSTALL_TARGETS 仍含 install-static，--disable-static 未生效" >&2; exit 1 ;;
  *install-shared*) echo "    OK   只安装共享库（install-shared），不安装 .a 静态库" ;;
  *) echo "    FAIL INSTALL_TARGETS 异常" >&2; exit 1 ;;
esac
echo "  共享库版本号（shlib/Makefile）："
shlib_libversion=$(sed -n 's/^SHLIB_LIBVERSION *= *//p' shlib/Makefile | head -n1)
shlib_major=$(sed -n 's/^SHLIB_MAJOR=[[:space:]]*//p' shlib/Makefile | head -n1)
shlib_minor=$(sed -n 's/^SHLIB_MINOR=[[:space:]]*//p' shlib/Makefile | head -n1)
shlib_ver="${shlib_major}${shlib_minor}"
echo "    SHLIB_LIBVERSION = $shlib_libversion"
echo "      （这是 make 变量的字面值，展开后即 so.\$SHLIB_MAJOR\$SHLIB_MINOR）"
echo "    SHLIB_MAJOR      = $shlib_major"
echo "    SHLIB_MINOR      = $shlib_minor"
echo "    => 共享库实体文件名将是 libreadline.so.$shlib_ver / libhistory.so.$shlib_ver，"
echo "       符号链接为 lib*.so.$shlib_major 与 lib*.so（support/shlib-install 的 linux 分支）"
if [ "$shlib_ver" = "$VER" ]; then echo "    OK   共享库版本 $shlib_ver 与 Readline-$VER 一致"
else echo "    FAIL 共享库版本解析为 '$shlib_ver'，应为 $VER" >&2; exit 1; fi
echo "  shlib/Makefile 的 SHLIB_XLDFLAGS（应已无 -Wl,-rpath）："
xld=$(sed -n 's/^SHLIB_XLDFLAGS *= *//p' shlib/Makefile | head -n1)
echo "    SHLIB_XLDFLAGS = $xld"
case "$xld" in
  *-rpath*) echo "    FAIL 仍含 -rpath" >&2; exit 1 ;;
  *) echo "    OK   已无 -rpath（第三条 sed 生效到了 configure 的产物上）" ;;
esac
echo

echo "手册原文：Compile the package:"
echo "手册命令：make SHLIB_LIBS=\"-lncursesw\""
echo "手册对该选项的说明：SHLIB_LIBS=\"-lncursesw\" —— This option forces Readline to"
echo "  link against the libncursesw library. For details see the \"Shared Libraries\""
echo "  section in the package's README file."
set +e
make SHLIB_LIBS="-lncursesw" 2>&1 | tee "$MAKELOG"
make_rc=${PIPESTATUS[0]}
set -e
echo "make 退出码：$make_rc"
[ "$make_rc" -eq 0 ] || { echo "错误：make 失败，完整输出见 $MAKELOG" >&2; exit "$make_rc"; }
echo
echo "----- 编译结果确认 -----"
for f in "shlib/libreadline.so.$shlib_ver" "shlib/libhistory.so.$shlib_ver"; do
  if [ -e "$f" ]; then printf '  OK   %-34s %s 字节\n' "$f" "$(stat -Lc %s "$f")"
  else printf '  FAIL %s 未生成\n' "$f"; exit 1; fi
done
if [ -e libreadline.a ] || [ -e libhistory.a ]; then
  echo "  INFO 构建目录中存在 .a（--disable-static 只是不安装它们）："
  { ls -l libreadline.a libhistory.a 2>/dev/null || true; } | sed 's/^/    /'
else
  echo "  OK   构建目录中没有 libreadline.a / libhistory.a（--disable-static）"
fi
echo "  共享库 SONAME："
for f in "shlib/libreadline.so.$shlib_ver" "shlib/libhistory.so.$shlib_ver"; do
  printf '    %-34s %s\n' "$f" "$(objdump -p "$f" | awk '/SONAME/{print $2}')"
done
echo "  刚编译出的 libreadline 依赖的共享库（SHLIB_LIBS=\"-lncursesw\" 的直接效果）："
rl_needed=$(objdump -p "shlib/libreadline.so.$shlib_ver" | awk '/NEEDED/{print $2}')
echo "$rl_needed" | sed 's/^/    NEEDED /'
case "$rl_needed" in
  *libncursesw.so*) echo "    OK   libreadline 直接链接了 libncursesw" ;;
  *) echo "    FAIL libreadline 未链接 libncursesw" >&2; exit 1 ;;
esac
echo "  RPATH / RUNPATH 检查（手册第三条 sed 的最终目的：共享库里不应写死搜索路径）："
dyn=$(mktemp /tmp/rl-dyn-XXXXXX)
for f in "shlib/libreadline.so.$shlib_ver" "shlib/libhistory.so.$shlib_ver"; do
  readelf -d "$f" > "$dyn"
  if grep -E 'RPATH|RUNPATH' "$dyn" > /dev/null; then
    echo "    FAIL $f 含 RPATH/RUNPATH："
    grep -E 'RPATH|RUNPATH' "$dyn" | sed 's/^/      /'
    rm -f "$dyn"; exit 1
  else
    printf '    OK   %-34s 无 RPATH/RUNPATH\n' "$f"
  fi
done
rm -f "$dyn"
echo

echo "----- 测试 -----"
echo "手册原文：This package does not come with a test suite."
echo "结论：本节手册明确说明 Readline 不带测试套件，因此没有 make check / make test"
echo "  这一步可执行。核对源码树以佐证："
echo "  1) 顶层 Makefile 中是否存在 check / test 目标："
chk=$(grep -nE '^(check|test):' Makefile || true)
if [ -z "$chk" ]; then echo "     OK   Makefile 中没有 check: / test: 目标"
else echo "$chk" | sed 's/^/     /'; echo "     INFO 存在上述目标（与手册说明不一致，已记录）"; fi
echo "  2) 源码树中是否有 tests/ 目录："
if [ -d tests ]; then echo "     INFO tests/ 存在：$(ls tests | tr '\n' ' ')"
else echo "     OK   源码树中没有 tests/ 目录"; fi
echo "  3) 上游 README 中关于测试的说明（若有）："
grep -niE 'test suite' README | sed 's/^/     /' || echo "     （README 中无 'test suite' 字样）"
echo "  代替测试的验证：本脚本在安装后会用 -lreadline / -lhistory 编译并运行一个"
echo "    调用 readline/history API 的程序（见下方「功能验证」），以证明装好的库可用。"
echo

echo "手册原文：Install the package:"
echo "手册命令：make install"
set +e
make install 2>&1 | tee "$INSTLOG"
inst_rc=${PIPESTATUS[0]}
set -e
echo "make install 退出码：$inst_rc"
[ "$inst_rc" -eq 0 ] || { echo "错误：make install 失败，完整输出见 $INSTLOG" >&2; exit "$inst_rc"; }
echo "  说明：安装输出里的 'install: you may need to run ldconfig' 是 shlib/Makefile"
echo "    的固定提示。手册本节没有 ldconfig 这条命令，故不执行；/usr/lib 属于动态"
echo "    链接器的默认搜索目录，无需缓存即可找到。"
echo

echo "手册原文：If desired, install the documentation:"
echo "手册命令：install -v -m644 doc/*.{ps,pdf,html,dvi} $DOCDIR"
echo "（手册标注为 If desired 的可选命令。本节照做，以便 $DOCDIR 内容完整；"
echo "  手册 §8.12.2 的 Installed directories 本来就包含该目录。）"
echo "待安装的文件："
ls -l doc/*.ps doc/*.pdf doc/*.html doc/*.dvi | sed 's/^/  /'
install -v -m644 doc/*.{ps,pdf,html,dvi} $DOCDIR
echo

echo "----- 安装后检查（手册 §8.12.2 Contents of Readline） -----"
rc=0
echo "1) Installed libraries：libhistory.so 与 libreadline.so"
for base in libreadline libhistory; do
  for suffix in ".so" ".so.$shlib_major" ".so.$shlib_ver"; do
    f=/usr/lib/$base$suffix
    if [ -e "$f" ]; then
      if [ -L "$f" ]; then
        printf '   OK   %-32s -> %s\n' "$f" "$(readlink "$f")"
      else
        printf '   OK   %-32s（%s 字节，实体文件，权限 %s）\n' \
          "$f" "$(stat -Lc %s "$f")" "$(stat -Lc %a "$f")"
      fi
    else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
  done
done
ls -l /usr/lib/libreadline* /usr/lib/libhistory* | sed 's/^/     /'
echo "   SONAME 与依赖："
for base in libreadline libhistory; do
  f=/usr/lib/$base.so.$shlib_ver
  printf '     %-28s SONAME=%s\n' "$base" "$(objdump -p "$f" | awk '/SONAME/{print $2}')"
  objdump -p "$f" | awk '/NEEDED/{print "       NEEDED "$2}'
done
so_name=$(objdump -p /usr/lib/libreadline.so.$shlib_ver | awk '/SONAME/{print $2}')
if [ "$so_name" = "libreadline.so.$shlib_major" ]; then
  echo "     OK   libreadline 的 SONAME 为 libreadline.so.$shlib_major"
else echo "     FAIL libreadline 的 SONAME 为 '$so_name'"; rc=1; fi
echo "   静态库不应被安装（--disable-static）："
for f in /usr/lib/libreadline.a /usr/lib/libhistory.a; do
  if [ -e "$f" ]; then echo "     FAIL $f 存在，--disable-static 未生效"; rc=1
  else echo "     OK   $f 不存在"; fi
done
echo "   *.old 残留检查（手册开头两条 sed 的目的）："
oldfiles=$(find /usr/lib -maxdepth 1 \( -name 'libreadline*.old' -o -name 'libhistory*.old' \) 2>/dev/null || true)
if [ -z "$oldfiles" ]; then echo "     OK   /usr/lib 下没有 libreadline*.old / libhistory*.old"
else echo "$oldfiles" | sed 's/^/     FAIL 残留 /'; rc=1; fi
echo "   共享库的 RPATH/RUNPATH（第三条 sed 的目的）："
dyn=$(mktemp /tmp/rl-dyn2-XXXXXX)
for f in /usr/lib/libreadline.so.$shlib_ver /usr/lib/libhistory.so.$shlib_ver; do
  readelf -d "$f" > "$dyn"
  if grep -E 'RPATH|RUNPATH' "$dyn" > /dev/null; then
    echo "     FAIL $f 含 RPATH/RUNPATH"; rc=1
  else printf '     OK   %-40s 无 RPATH/RUNPATH\n' "$f"; fi
done
rm -f "$dyn"
echo "   动态符号抽查（先落盘再匹配，避免管道 SIGPIPE 误判）："
readelf --dyn-syms -W /usr/lib/libreadline.so.$shlib_ver > "${dyn}.rl"
for s in readline rl_initialize rl_bind_key rl_variable_bind rl_readline_version \
         rl_completion_matches; do
  if grep -E "[[:space:]]$s\$|[[:space:]]$s@" "${dyn}.rl" > /dev/null; then
    printf '     OK   libreadline: %s\n' "$s"
  else printf '     FAIL libreadline 缺少动态符号 %s\n' "$s"; rc=1; fi
done
readelf --dyn-syms -W /usr/lib/libhistory.so.$shlib_ver > "${dyn}.hs"
for s in add_history history_get history_length using_history read_history \
         write_history; do
  if grep -E "[[:space:]]$s\$|[[:space:]]$s@" "${dyn}.hs" > /dev/null; then
    printf '     OK   libhistory : %s\n' "$s"
  else printf '     FAIL libhistory 缺少动态符号 %s\n' "$s"; rc=1; fi
done
rm -f "${dyn}.rl" "${dyn}.hs"
echo "   file(1) 对两个库的识别（用 §8.11 刚装好的 file）："
file -b /usr/lib/libreadline.so.$shlib_ver | sed 's/^/     libreadline: /'
file -b /usr/lib/libhistory.so.$shlib_ver  | sed 's/^/     libhistory : /'
echo
echo "2) Installed directory：/usr/include/readline"
if [ -d /usr/include/readline ]; then echo "   OK   /usr/include/readline 存在"
else echo "   FAIL /usr/include/readline 缺失"; rc=1; fi
echo "   头文件（Makefile.in 的 INSTALLED_HEADERS）："
for h in readline.h chardefs.h keymaps.h history.h tilde.h rlstdc.h rlconf.h rltypedefs.h; do
  f=/usr/include/readline/$h
  if [ -s "$f" ]; then printf '     OK   %-28s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '     FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
echo "     已安装 readline.h 中的版本宏："
grep -E '^#define (RL_READLINE_VERSION|RL_VERSION_MAJOR|RL_VERSION_MINOR)' \
     /usr/include/readline/readline.h | sed 's/^/       /'
echo
echo "3) Installed directory：$DOCDIR"
if [ -d "$DOCDIR" ]; then echo "   OK   $DOCDIR 存在"
else echo "   FAIL $DOCDIR 缺失"; rc=1; fi
echo "   make install 装入的文档（Makefile.in 的 OTHER_DOCS = CHANGES INSTALL README）："
for f in CHANGES INSTALL README; do
  if [ -s "$DOCDIR/$f" ]; then printf '     OK   %-12s（%s 字节）\n' "$f" "$(stat -Lc %s "$DOCDIR/$f")"
  else printf '     FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
echo "   可选文档命令装入的文件（*.ps/*.pdf/*.html/*.dvi）："
for ext in ps pdf html dvi; do
  n=$(find "$DOCDIR" -maxdepth 1 -name "*.$ext" | wc -l)
  printf '     %-4s %s 个\n' ".$ext" "$n"
  if [ "$n" -eq 0 ]; then echo "     FAIL 没有 .$ext 文件"; rc=1; fi
done
echo "   $DOCDIR 内容："
ls -l "$DOCDIR" | sed 's/^/     /'
echo
echo "4) pkg-config 描述文件（Makefile.in 的 install-pc）："
for f in /usr/lib/pkgconfig/readline.pc /usr/lib/pkgconfig/history.pc; do
  if [ -s "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
echo "   readline.pc："
sed 's/^/     /' /usr/lib/pkgconfig/readline.pc
echo "   history.pc："
sed 's/^/     /' /usr/lib/pkgconfig/history.pc
pc_prefix=$(sed -n 's/^prefix=//p' /usr/lib/pkgconfig/readline.pc | head -n1)
pc_req=$(sed -n 's/^Requires.private: *//p' /usr/lib/pkgconfig/readline.pc | head -n1)
pc_ver=$(sed -n 's/^Version: *//p' /usr/lib/pkgconfig/readline.pc | head -n1)
if [ "$pc_prefix" = "/usr" ]; then echo "     OK   readline.pc prefix=/usr"
else echo "     FAIL readline.pc prefix 为 '$pc_prefix'"; rc=1; fi
if [ "$pc_req" = "ncursesw" ]; then
  echo "     OK   readline.pc Requires.private=ncursesw（--with-curses 的效果）"
else echo "     FAIL readline.pc Requires.private 为 '$pc_req'"; rc=1; fi
if [ "$pc_ver" = "$VER" ]; then echo "     OK   readline.pc Version=$pc_ver"
else echo "     FAIL readline.pc Version 为 '$pc_ver'"; rc=1; fi
echo
echo "5) 手册页与 info 页（doc/Makefile 的 install 目标）："
for f in /usr/share/man/man3/readline.3 /usr/share/man/man3/history.3; do
  if [ -s "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
for f in /usr/share/info/readline.info /usr/share/info/history.info \
         /usr/share/info/rluserman.info; do
  if [ -s "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
echo "   /usr/share/info/dir 中的登记项（install-info 的效果）："
if [ -f /usr/share/info/dir ]; then
  grep -nE 'Readline|History|RLuserman|rluserman' /usr/share/info/dir | sed 's/^/     /' \
    || echo "     INFO dir 中未匹配到 Readline/History 条目"
else
  echo "     INFO /usr/share/info/dir 不存在"
fi
echo
echo "6) 功能验证（自加检查，非手册命令；本包无测试套件，用它证明装好的库可用）："
tmpd=$(mktemp -d /tmp/readline-verify-XXXXXX)
cat > "$tmpd/t.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <readline/readline.h>
#include <readline/history.h>

int main(void)
{
    HIST_ENTRY *e;
    char *expansion = NULL;
    int r;

    printf("rl_library_version   = %s\n", rl_library_version);
    printf("rl_readline_version  = 0x%04x\n", rl_readline_version);

    /* history 库 */
    using_history();
    add_history("first line");
    add_history("second line");
    printf("history_length       = %d\n", history_length);
    e = history_get(history_base + 1);
    printf("history_get(2)       = %s\n", e ? e->line : "(null)");
    r = history_expand("!!", &expansion);
    printf("history_expand(!!)   = %d -> %s\n", r, expansion ? expansion : "(null)");
    if (expansion) free(expansion);
    if (history_length != 2) { printf("FAIL: history_length\n"); return 1; }
    if (!e || strcmp(e->line, "second line") != 0) { printf("FAIL: history_get\n"); return 1; }

    /* readline 库（非交互，只用不需要 tty 的 API） */
    rl_initialize();
    printf("rl_readline_name     = %s\n", rl_readline_name ? rl_readline_name : "(null)");
    if (rl_bind_key('\t', rl_insert) != 0) { printf("FAIL: rl_bind_key\n"); return 1; }
    if (rl_variable_bind("editing-mode", "vi") != 0) { printf("FAIL: rl_variable_bind\n"); return 1; }
    printf("editing-mode=vi      -> rl_editing_mode = %d\n", rl_editing_mode);
    printf("OK: readline/history API 调用全部成功\n");
    return 0;
}
EOF
echo "   编译：gcc -o t t.c -lreadline -lhistory"
if gcc -o "$tmpd/t" "$tmpd/t.c" -lreadline -lhistory; then
  echo "     OK   -lreadline -lhistory 链接成功"
  echo "     可执行文件依赖："
  ldd "$tmpd/t" | sed 's/^/       /'
  t_ldd=$(ldd "$tmpd/t")
  for want in libreadline.so libhistory.so libncursesw.so libc.so.6; do
    case "$t_ldd" in
      *"$want"*) printf '       OK   链接到 %s\n' "$want" ;;
      *) printf '       FAIL 未链接到 %s\n' "$want"; rc=1 ;;
    esac
  done
  echo "     运行输出："
  if TERM=dumb "$tmpd/t" < /dev/null > "$tmpd/out" 2>&1; then
    sed 's/^/       /' "$tmpd/out"
    if grep -F 'OK: readline/history API 调用全部成功' "$tmpd/out" > /dev/null; then
      echo "     OK   readline / history API 运行正常"
    else echo "     FAIL 运行输出中没有成功标记"; rc=1; fi
    rlv=$(sed -n 's/^rl_library_version   = //p' "$tmpd/out")
    if [ "$rlv" = "$VER" ]; then echo "     OK   运行期自述版本 rl_library_version = $rlv"
    else echo "     FAIL 运行期自述版本为 '$rlv'，应为 $VER"; rc=1; fi
  else
    echo "     FAIL 程序运行失败："; sed 's/^/       /' "$tmpd/out"; rc=1
  fi
else
  echo "     FAIL 无法用 -lreadline -lhistory 编译"; rc=1
fi
echo "   pkg-config 可用性（若 chroot 内已有 pkg-config）："
if command -v pkg-config >/dev/null 2>&1; then
  echo "     pkg-config --cflags --libs readline：$(pkg-config --cflags --libs readline 2>&1)"
else
  echo "     INFO pkg-config 尚未安装（手册第 8 章更靠后的小节才安装），跳过"
fi
rm -rf "$tmpd"
echo
echo "7) 本节写入系统的文件清单："
{ ls -l /usr/lib/libreadline* /usr/lib/libhistory* \
      /usr/lib/pkgconfig/readline.pc /usr/lib/pkgconfig/history.pc \
      /usr/share/man/man3/readline.3 /usr/share/man/man3/history.3 \
      /usr/share/info/readline.info /usr/share/info/history.info \
      /usr/share/info/rluserman.info 2>/dev/null || true; } | sed 's/^/     /'
echo "   /usr/include/readline/："
ls -l /usr/include/readline/ | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Readline 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留构建摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.12.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make install 完整输出：$INSTLOG"
cd /sources
rm -rf "$SRCDIR"
[ -d "/sources/$SRCDIR" ] && { echo "错误：源码目录未清理" >&2; exit 1; }
echo "已删除 /sources/$SRCDIR"
echo "/sources 下的解包残留（应为空）："
find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.12 完成，结束时间：$(date -Is) ====="
