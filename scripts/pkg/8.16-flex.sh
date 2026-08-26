#!/usr/bin/env bash
# LFS 13.0-systemd §8.16 Flex-2.6.4
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.16.1 Installation of Flex 的命令序列（全部，一条不多一条不少）：
#   ./configure --prefix=/usr    \
#               --disable-static \
#               --docdir=/usr/share/doc/flex-2.6.4
#   make
#   make check
#   make install
#   ln -sv flex   /usr/bin/lex
#   ln -sv flex.1 /usr/share/man/man1/lex.1
# 本节没有 sed、没有 patch，也没有任何关于允许测试失败的 Note / Caution。
#
# 手册对最后两条命令的解释（§8.16.1 原文）：
#   A few programs do not know about flex yet and try to run its predecessor, lex.
#   To support those programs, create a symbolic link named lex that runs flex in
#   lex emulation mode, and also create the man page of lex as a symlink.
set -euo pipefail

PKG=flex
VER=2.6.4
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
CONFLOG=/sources/.flex-configure.log
MAKELOG=/sources/.flex-make.log
CHECKLOG=/sources/.flex-make-check.log
INSTLOG=/sources/.flex-make-install.log

echo "===== LFS 13.0-systemd §8.16 Flex-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Flex package contains a utility for generating programs that"
echo "  recognize patterns in text."
echo "手册数据：Approximate build time 0.1 SBU，Required disk space 33 MB"
echo "手册存档：/workspace/docs/book/chapter08-flex.html（宿主机 /root/lfs/docs/book/）"
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
esac
echo "  OK   PATH 中不含 /tools/bin（交叉工具链已不再使用）"
echo

echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0
echo "1) 上一任务 §8.15 Bc-7.0.3 的产物（确认其已完成、产物可用）："
for f in /usr/bin/bc /usr/bin/dc /usr/share/man/man1/bc.1 /usr/share/man/man1/dc.1; do
  if [ -e "$f" ]; then printf '   OK   %-32s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失（§8.15 未完成？）\n' "$f"; rc=1; fi
done
echo "   bc 自述版本：$(bc --version 2>&1 | sed -n 1p)"
echo "   dc 自述版本：$(dc --version 2>&1 | sed -n 1p)"
bc_smoke=$(echo '2^100' | bc)
echo "   bc 冒烟：2^100 -> $bc_smoke"
[ "$bc_smoke" = "1267650600228229401496703205376" ] || { echo "   FAIL 上一任务的 bc 计算结果不符"; rc=1; }
dc_smoke=$(printf '5 3 + p\n' | dc)
echo "   dc 冒烟：5 3 + p -> $dc_smoke"
[ "$dc_smoke" = "8" ] || { echo "   FAIL 上一任务的 dc 计算结果不符"; rc=1; }
echo "   说明：Flex 不依赖 Bc，此处只用于确认「上一任务产物可用」。"
echo
echo "2) §8.14 M4-1.4.21（Flex 的**强依赖**：configure 要找「支持 -P 的 m4」，"
echo "   且生成的 flex 在运行时把骨架文件通过 m4 管道展开）："
if [ -x /usr/bin/m4 ]; then printf '   OK   /usr/bin/m4（%s 字节）\n' "$(stat -Lc %s /usr/bin/m4)"
else echo "   FAIL /usr/bin/m4 缺失（§8.14 未完成？）"; rc=1; fi
echo "   m4 版本：$(m4 --version 2>&1 | sed -n 1p)"
m4p=$(echo 'm4_divnum' | m4 -P 2>&1)
echo "   configure 用的探测（echo m4_divnum | m4 -P）-> $m4p"
[ "$m4p" = "0" ] || { echo "   FAIL m4 -P 探测结果不是 0，configure 会找不到合用的 m4"; rc=1; }
echo
echo "3) §7.8 Bison-3.8.2（tests/Makefile.am 的 HAVE_BISON 条件：YACC = 'bison -y' 时"
echo "   bison_nr / bison_yylloc / bison_yylval 三个用例才用真正的语法分析器源码，"
echo "   否则退化为 no_bison_stub.c）："
if [ -x /usr/bin/bison ]; then printf '   OK   /usr/bin/bison（%s 字节）\n' "$(stat -Lc %s /usr/bin/bison)"
else echo "   FAIL /usr/bin/bison 缺失"; rc=1; fi
echo "   bison 版本：$(bison --version 2>&1 | sed -n 1p)"
echo "   yacc      ：$(command -v yacc || echo 无)"
echo
echo "4) §8.5 Glibc-2.43 的 C 库、C++ 运行时与 pthread（tests 里有 C++ 与 pthread 用例）："
for f in /usr/lib/libc.so.6 /usr/lib/libm.so.6 /lib64/ld-linux-x86-64.so.2 \
         /usr/include/stdio.h /usr/include/pthread.h; do
  if [ -e "$f" ]; then printf '   OK   %-38s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   glibc 版本自述：$(/usr/lib/libc.so.6 2>/dev/null | sed -n 1p)"
tmpc=$(mktemp /tmp/sanity-XXXXXX.c)
cat > "$tmpc" <<'EOF'
#include <stdio.h>
int main(void){ printf("glibc sanity ok\n"); return 0; }
EOF
if gcc -o "${tmpc%.c}" "$tmpc" >/dev/null 2>&1 && [ "$("${tmpc%.c}")" = "glibc sanity ok" ]; then
  echo "   OK   gcc 编译并运行最小 C 程序成功"
else echo "   FAIL 无法用 gcc 编译/运行最小 C 程序"; rc=1; fi
rm -f "$tmpc" "${tmpc%.c}"
tmpcc=$(mktemp /tmp/sanity-XXXXXX.cc)
cat > "$tmpcc" <<'EOF'
#include <iostream>
int main(){ std::cout << "libstdc++ sanity ok" << std::endl; return 0; }
EOF
if g++ -o "${tmpcc%.cc}" "$tmpcc" >/dev/null 2>&1 && [ "$("${tmpcc%.cc}")" = "libstdc++ sanity ok" ]; then
  echo "   OK   g++ 编译并运行最小 C++ 程序成功（本节 tests 有 cxx_* 用例，安装物含 FlexLexer.h）"
else echo "   FAIL 无法用 g++ 编译/运行最小 C++ 程序"; rc=1; fi
rm -f "$tmpcc" "${tmpcc%.cc}"
echo
echo "5) §7.13.1 Cleaning 的结果（/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在"; rc=1; else echo "   OK   /tools 已不存在"; fi
echo
echo "6) 本节直接依赖的工具（解包 + configure + make + make check + 安装）："
for t in tar gzip make gcc g++ ld ar ranlib sed grep awk install ln rm mkdir cat sh \
         readlink stat find file ldd nm sort head tail tr wc diff cmp cut install-info \
         msgfmt xgettext help2man makeinfo; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-12s %s\n' "$t" "$(command -v $t)"
  else printf '   INFO %-12s 不可用\n' "$t"; fi
done
echo "   gcc  版本：$(gcc --version | sed -n 1p)"
echo "   make 版本：$(make --version | sed -n 1p)"
for t in tar make gcc g++ sed grep install ln find strings nm timeout cmp; do
  command -v $t >/dev/null 2>&1 || { echo "   FAIL 必需工具 $t 不可用"; rc=1; }
done
echo
echo "7) 安装目标目录（手册 §8.16.2 Contents）："
for d in /usr/bin /usr/lib /usr/include /usr/share/man/man1 /usr/share/info /usr/share/doc; do
  if [ -d "$d" ]; then printf '   OK   %s\n' "$d"
  else printf '   INFO %s 不存在，make install 会创建\n' "$d"; fi
done
echo
echo "8) 源码包（/sources 是宿主机 bind mount）："
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo
echo "9) §7.3 虚拟内核文件系统与 §7.6 基础文件（测试用例要读写 /dev、/proc、/tmp）："
for f in /dev/null /dev/zero /dev/urandom /dev/tty /proc/self /sys \
         /etc/passwd /etc/group /tmp /var/tmp; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo
echo "10) 安装前系统中的 flex / lex 痕迹（Flex 在第 5–7 章从未构建过，预期全部不存在）："
for f in /usr/bin/flex /usr/bin/flex++ /usr/bin/lex /usr/lib/libfl.so /usr/lib/libfl.a \
         /usr/include/FlexLexer.h /usr/share/man/man1/flex.1 /usr/share/man/man1/lex.1 \
         /usr/share/doc/flex-$VER; do
  if [ -e "$f" ] || [ -L "$f" ]; then printf '   INFO %-38s 已存在\n' "$f"
  else printf '   INFO %-38s 不存在（符合预期：本节是首次安装）\n' "$f"; fi
done
echo "   注意：手册最后两条 ln -sv 会创建 /usr/bin/lex 与 /usr/share/man/man1/lex.1，"
echo "     若它们已存在，ln -sv（无 -f）会失败 —— 上面的清单用于事先确认。"
echo
echo "11) 磁盘空间（手册要求 33 MB）："
df -h / | sed 's/^/   /'
avail_k=$(df -Pk / | awk 'NR==2{print $4}')
if [ "$avail_k" -gt 204800 ]; then echo "   OK   可用 $((avail_k/1024)) MB > 手册要求的 33 MB"
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
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "顶层内容："
ls | sed 's/^/  /'
echo "上游版本自述（autoconf 的 AC_INIT）："
{ grep -n '^AC_INIT' configure.ac || true; } | sed 's/^/  /'
src_ver=$(sed -n 's/^AC_INIT(\[[^]]*\],\[\([^]]*\)\].*/\1/p' configure.ac | awk 'NR==1')
echo "  configure.ac：版本 = $src_ver"
if [ "$src_ver" = "$VER" ]; then
  echo "  OK   源码自述版本 $src_ver 与手册 §8.16 的 Flex-$VER 一致"
else echo "  FAIL 源码自述版本为 '$src_ver'，与 $VER 不符" >&2; exit 1; fi
echo "本节无补丁、无 sed：手册 §8.16 只有 configure/make/make check/make install + 2 条 ln -sv"
flex_patches=$(ls /sources | grep -E '^flex.*patch' || true)
echo "  （/sources 中匹配 flex*patch 的文件：${flex_patches:-无}）"
echo

echo "----- 上游结构预读（先读上游再写自检） -----"
echo "a) 顶层 Makefile.am：flex++ 是由 install-exec-hook 建的符号链接，不是单独程序"
{ grep -nA3 '^install-exec-hook:' Makefile.am || true; } | sed 's/^/    /'
echo "b) 顶层 Makefile.am：docdir 下安装哪些文件（dist_doc_DATA）"
{ sed -n '/^dist_doc_DATA = /,/^$/p' Makefile.am || true; } | sed 's/^/    /'
echo "c) src/Makefile.am：程序与库"
{ grep -nE '^(bin_PROGRAMS|lib_LTLIBRARIES|libfl_la_SOURCES|libfl_la_LDFLAGS) ' src/Makefile.am || true; } | sed 's/^/    /'
echo "d) tests/Makefile.am：TESTS 的构成（check_PROGRAMS + options.cn）"
{ grep -nE '^(TESTS|check_PROGRAMS) = ' tests/Makefile.am || true; } | sed 's/^/    /'
echo "e) src/main.c：argv[0] 只决定 C++ 模式（结尾是 '+'），**不**决定 lex 兼容模式"
{ grep -nB2 -A4 "Enable C++ if program name ends with '+'" src/main.c || true; } | sed 's/^/    /'
echo "    lex 兼容（lex emulation）由命令行选项 -l 打开，见 main.c 中 lex_compat = true 的位置："
{ grep -n 'lex_compat = true' src/main.c || true; } | sed 's/^/      /'
echo "    结论（本脚本据此写断言）：手册建的 /usr/bin/lex 符号链接使「只会调用 lex 的程序」"
echo "      能用上 flex；同一份输入下 lex 与 flex 的输出逐字节相同，真正的 lex 仿真语义"
echo "      来自 -l 选项（生成文件里会多出 #define YY_FLEX_LEX_COMPAT）。本脚本两者都验。"
echo "f) 运行时依赖 m4：flex 把骨架经 m4 管道展开，m4 路径在 configure 时写死进二进制"
{ grep -n 'AC_DEFINE_UNQUOTED(\[M4\]' configure.ac || true; } | sed 's/^/    /'
echo

echo "================= 8.16.1. Installation of Flex ================="
echo
echo "----- 手册命令 1/6：configure -----"
echo "手册原文：Prepare Flex for compilation:"
echo "手册命令：./configure --prefix=/usr    \\"
echo "                     --disable-static \\"
echo "                     --docdir=/usr/share/doc/flex-$VER"
echo "完整输出写入 $CONFLOG，下面只摘要。"
set +e
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/flex-2.6.4 > "$CONFLOG" 2>&1
conf_rc=$?
set -e
echo "configure 退出码：$conf_rc（输出 $(wc -l < "$CONFLOG") 行）"
if [ $conf_rc -ne 0 ]; then
  echo "configure 失败，末尾 40 行："; tail -n 40 "$CONFLOG" | sed 's/^/  /'
  exit $conf_rc
fi
echo "configure 关键探测行："
{ grep -nE 'checking for (gcc|g\+\+|bison|m4 that supports|pthread_mutex_lock)|^checking for (yacc|byacc)|config\.status: creating' "$CONFLOG" || true; } \
  | head -n 40 | sed 's/^/  /'
echo

echo "----- 核对手册的 3 个 configure 选项确实生效 -----"
crc=0
if [ ! -f Makefile ]; then echo "  FAIL configure 未生成 Makefile"; exit 1; fi
echo "a) --prefix=/usr —— 生成的 Makefile 中的安装路径变量："
{ grep -nE '^(prefix|exec_prefix|bindir|libdir|includedir|mandir|infodir|datarootdir) = ' Makefile || true; } | sed 's/^/    /'
got_prefix=$(sed -n 's/^prefix = //p' Makefile | awk 'NR==1')
if [ "$got_prefix" = /usr ]; then echo "    OK   prefix = /usr"
else echo "    FAIL prefix 为 '$got_prefix'"; crc=1; fi
echo "b) --docdir=/usr/share/doc/flex-$VER —— 文档安装目录："
{ grep -nE '^docdir = ' Makefile || true; } | sed 's/^/    /'
got_docdir=$(sed -n 's/^docdir = //p' Makefile | awk 'NR==1')
if [ "$got_docdir" = "/usr/share/doc/flex-$VER" ]; then
  echo "    OK   docdir = /usr/share/doc/flex-$VER（若不给此选项，autoconf 默认是 /usr/share/doc/flex）"
else echo "    FAIL docdir 为 '$got_docdir'"; crc=1; fi
echo "c) --disable-static —— libtool 是否还生成静态库："
{ grep -nE '^(build_libtool_libs|build_old_libs)=' libtool || true; } | head -n 2 | sed 's/^/    /'
lt_old=$(sed -n 's/^build_old_libs=//p' libtool | awk 'NR==1')
lt_shared=$(sed -n 's/^build_libtool_libs=//p' libtool | awk 'NR==1')
if [ "$lt_old" = no ]; then echo "    OK   build_old_libs=no（不再生成 libfl.a，正是 --disable-static 的作用）"
else echo "    FAIL build_old_libs='$lt_old'，--disable-static 未生效"; crc=1; fi
if [ "$lt_shared" = yes ]; then echo "    OK   build_libtool_libs=yes（仍生成共享库 libfl.so）"
else echo "    FAIL build_libtool_libs='$lt_shared'"; crc=1; fi
echo "d) 其它由 configure 决定、影响本节结果的变量："
{ grep -nE '^(M4|YACC|LN_S|LIBS|SHARED_VERSION_INFO|CC|CXX) = ' Makefile || true; } | sed 's/^/    /'
got_m4=$(sed -n 's/^M4 = //p' Makefile | awk 'NR==1')
got_yacc=$(sed -n 's/^YACC = //p' Makefile | awk 'NR==1')
got_svi=$(sed -n 's/^SHARED_VERSION_INFO = //p' Makefile | awk 'NR==1')
if [ "$got_m4" = /usr/bin/m4 ]; then echo "    OK   M4 = /usr/bin/m4（§8.14 装的那个）"
else echo "    FAIL M4 = '$got_m4'"; crc=1; fi
if [ "$got_yacc" = "bison -y" ]; then
  echo "    OK   YACC = 'bison -y' —— tests/Makefile.am 的 HAVE_BISON 条件成立，"
  echo "         bison_nr / bison_yylloc / bison_yylval 三个用例会用真正的 .y 语法文件"
else echo "    INFO YACC = '$got_yacc'（非 bison -y，bison 相关用例会退化为 no_bison_stub.c）"; fi
echo "    SHARED_VERSION_INFO = $got_svi（libtool 由此得出 libfl.so.2.0.0）"
[ $crc -eq 0 ] || { echo "错误：configure 结果与手册的选项要求不符" >&2; exit 1; }
echo "  OK   configure 结果符合手册的 --prefix=/usr + --disable-static + --docdir=..."
echo

echo "----- 手册命令 2/6：make -----"
echo "手册原文：Compile the package:"
echo "手册命令：make"
echo "完整输出写入 $MAKELOG，下面只摘要。"
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "make 退出码：$make_rc（输出 $(wc -l < "$MAKELOG") 行）"
if [ $make_rc -ne 0 ]; then
  echo "make 失败，末尾 40 行："; tail -n 40 "$MAKELOG" | sed 's/^/  /'
  exit $make_rc
fi
echo "make 输出末尾 8 行："
tail -n 8 "$MAKELOG" | sed 's/^/  /'
echo
echo "----- 编译结果确认 -----"
mrc=0
if [ -x src/flex ] && [ ! -L src/flex ]; then
  printf '  OK   %-16s %s 字节，%s\n' "src/flex" "$(stat -Lc %s src/flex)" "$(file -b src/flex | cut -d, -f1-2)"
else echo "  FAIL src/flex 未生成"; mrc=1; fi
echo "  共享库（--disable-static 后只应有 .so，不应有 .a）："
{ ls -l src/.libs/libfl.so* 2>/dev/null || true; } | sed 's/^/    /'
if [ -f src/.libs/libfl.so.2.0.0 ]; then echo "    OK   src/.libs/libfl.so.2.0.0（$(stat -Lc %s src/.libs/libfl.so.2.0.0) 字节）"
else echo "    FAIL src/.libs/libfl.so.2.0.0 未生成"; mrc=1; fi
a_files=$(find . -name '*.a' -not -path './tests/*' || true)
if [ -z "$a_files" ]; then echo "    OK   构建树中没有任何 .a 静态库（--disable-static 的效果）"
else echo "    FAIL 出现静态库："; printf '%s\n' "$a_files" | sed 's/^/      /'; mrc=1; fi
echo "  构建产物自述版本："
build_ver=$(./src/flex --version 2>&1 | sed -n 1p)
echo "    $build_ver"
case "$build_ver" in "flex $VER") echo "    OK   自述为 'flex $VER'" ;; *) echo "    FAIL 自述不是 'flex $VER'"; mrc=1 ;; esac
echo "  src/flex 的动态依赖（不得含 /tools）："
ldd src/flex | sed 's/^/    /'
ldd_build=$(ldd src/flex)
case "$ldd_build" in *"/tools/"*) echo "    FAIL 仍链接 /tools 下的库"; mrc=1 ;; *) echo "    OK   未链接任何 /tools 路径" ;; esac
echo "  二进制里写死的 m4 路径（configure 的 AC_DEFINE_UNQUOTED([M4], ...)）："
m4_in_bin=$({ strings src/flex | grep -E '^/usr/bin/m4$' || true; } | head -n1)
echo "    $m4_in_bin"
[ "$m4_in_bin" = /usr/bin/m4 ] || { echo "    FAIL 二进制中未找到 /usr/bin/m4"; mrc=1; }
echo "  man page / info 文档是否已生成："
for f in doc/flex.1 doc/flex.info; do
  if [ -f "$f" ]; then printf '    OK   %-16s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '    INFO %s 不存在\n' "$f"; fi
done
[ $mrc -eq 0 ] || { echo "错误：编译产物不完整" >&2; exit 1; }
echo

echo "----- 手册命令 3/6：make check（本节的测试） -----"
echo "手册原文：To test the results, issue:  make check"
echo "（手册 §8.16 全节没有任何关于测试结果的 Note / Caution，即要求测试全部通过。"
echo "  本包用 automake 的 parallel-tests，判定以其自带汇总为准："
echo "  退出码 0 且 '# FAIL: 0'、'# ERROR: 0'、'# XPASS: 0'，且 PASS == TOTAL。）"
echo "完整输出写入 $CHECKLOG。"
set +e
make check > "$CHECKLOG" 2>&1
check_rc=$?
set -e
echo
echo "----- make check 的 automake 汇总块 -----"
{ sed -n '/^=====*$/,$p' "$CHECKLOG" || true; } | head -n 20 | sed 's/^/  /'
echo
echo "----- make check 结论 -----"
echo "make check 退出码：$check_rc"
sum_total=$(sed -n 's/^# TOTAL: *//p' "$CHECKLOG" | awk 'NR==1')
sum_pass=$(sed -n 's/^# PASS: *//p'  "$CHECKLOG" | awk 'NR==1')
sum_skip=$(sed -n 's/^# SKIP: *//p'  "$CHECKLOG" | awk 'NR==1')
sum_xfail=$(sed -n 's/^# XFAIL: *//p' "$CHECKLOG" | awk 'NR==1')
sum_fail=$(sed -n 's/^# FAIL: *//p'  "$CHECKLOG" | awk 'NR==1')
sum_xpass=$(sed -n 's/^# XPASS: *//p' "$CHECKLOG" | awk 'NR==1')
sum_error=$(sed -n 's/^# ERROR: *//p' "$CHECKLOG" | awk 'NR==1')
echo "  automake 汇总：TOTAL=$sum_total PASS=$sum_pass SKIP=$sum_skip XFAIL=$sum_xfail FAIL=$sum_fail XPASS=$sum_xpass ERROR=$sum_error"
echo "  逐行 PASS: 计数：$({ grep -cE '^PASS: ' "$CHECKLOG" || true; })"
echo "  非 PASS 的结果行（FAIL/ERROR/SKIP/XFAIL/XPASS，应为空）："
{ grep -nE '^(FAIL|ERROR|SKIP|XFAIL|XPASS): ' "$CHECKLOG" || true; } | sed 's/^/    /'
echo "  三个 bison 相关用例的结果（YACC=$got_yacc）："
{ grep -nE '^(PASS|FAIL|SKIP): bison_' "$CHECKLOG" || true; } | sed 's/^/    /'
echo "  pthread 与 C++ 用例的结果："
{ grep -nE '^(PASS|FAIL|SKIP): (pthread|cxx_)' "$CHECKLOG" || true; } | sed 's/^/    /'
echo
if [ "$check_rc" -ne 0 ]; then
  echo "错误：make check 退出码非 0（$check_rc）—— 手册对本节没有允许失败的说明" >&2
  echo "  make check 末尾 60 行：" >&2
  tail -n 60 "$CHECKLOG" | sed 's/^/  /' >&2
  exit "$check_rc"
fi
trc=0
for pair in "FAIL:$sum_fail" "ERROR:$sum_error" "XPASS:$sum_xpass"; do
  k=${pair%%:*}; v=${pair#*:}
  if [ "$v" = 0 ]; then echo "  OK   # $k: 0"
  else echo "  FAIL # $k: $v（手册未允许任何失败）"; trc=1; fi
done
if [ -n "$sum_total" ] && [ "$sum_total" -ge 100 ]; then echo "  OK   # TOTAL: $sum_total（用例总数量级正常）"
else echo "  FAIL # TOTAL: '$sum_total'，测试疑似未真正运行"; trc=1; fi
if [ "$sum_pass" = "$sum_total" ]; then echo "  OK   # PASS ($sum_pass) == # TOTAL ($sum_total)，无跳过、无预期失败"
else echo "  INFO # PASS ($sum_pass) != # TOTAL ($sum_total)：SKIP=$sum_skip XFAIL=$sum_xfail"; fi
[ $trc -eq 0 ] || { echo "错误：测试结果不符合手册要求" >&2; exit 1; }
echo
echo "结论：§8.16 的 make check 退出码 0，automake 汇总 TOTAL=$sum_total / PASS=$sum_pass /"
echo "  FAIL=$sum_fail / ERROR=$sum_error / SKIP=$sum_skip / XFAIL=$sum_xfail / XPASS=$sum_xpass。"
echo "  手册 §8.16 未列出任何允许的失败项，本次也确无失败项。"
echo

echo "----- 手册命令 4/6：make install -----"
echo "手册原文：Install the package:"
echo "手册命令：make install"
echo "完整输出写入 $INSTLOG，下面只摘要。"
set +e
make install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "make install 退出码：$inst_rc（输出 $(wc -l < "$INSTLOG") 行）"
if [ $inst_rc -ne 0 ]; then
  echo "make install 失败，末尾 40 行："; tail -n 40 "$INSTLOG" | sed 's/^/  /'
  exit $inst_rc
fi
echo "make install 中与 /usr 写入相关的行（摘要）："
{ grep -nE ' /usr/(bin|lib|include|share)' "$INSTLOG" || true; } | head -n 30 | sed 's/^/  /'
echo

echo "----- 手册命令 5/6 与 6/6：为只认识 lex 的程序建符号链接 -----"
echo "手册原文：A few programs do not know about flex yet and try to run its predecessor,"
echo "  lex. To support those programs, create a symbolic link named lex that runs flex"
echo "  in lex emulation mode, and also create the man page of lex as a symlink:"
echo "手册命令：ln -sv flex   /usr/bin/lex"
echo "手册命令：ln -sv flex.1 /usr/share/man/man1/lex.1"
ln -sv flex   /usr/bin/lex
ln -sv flex.1 /usr/share/man/man1/lex.1
echo

echo "----- 安装后检查（手册 §8.16.2 Contents of Flex） -----"
echo "手册列出的内容："
echo "  Installed programs : flex, flex++ (link to flex), and lex (link to flex)"
echo "  Installed libraries: libfl.so"
echo "  Installed directory: /usr/share/doc/flex-$VER"
rc=0
echo
echo "1) Installed program：/usr/bin/flex"
if [ -x /usr/bin/flex ] && [ ! -L /usr/bin/flex ]; then
  printf '   OK   /usr/bin/flex（%s 字节，%s）\n' "$(stat -Lc %s /usr/bin/flex)" "$(file -b /usr/bin/flex | cut -d, -f1-2)"
else echo "   FAIL /usr/bin/flex 缺失或不是普通可执行文件"; rc=1; fi
inst_ver=$(flex --version 2>&1 | sed -n 1p)
echo "   已安装 flex 自述版本：$inst_ver"
case "$inst_ver" in "flex $VER") echo "   OK   自述为 'flex $VER'" ;; *) echo "   FAIL 自述不是 'flex $VER'"; rc=1 ;; esac
echo "   命令来源（PATH 解析）：$(command -v flex)"
echo "   动态依赖（不得含 /tools）："
ldd /usr/bin/flex | sed 's/^/     /'
ldd_out=$(ldd /usr/bin/flex)
case "$ldd_out" in *"/tools/"*) echo "     FAIL 仍链接 /tools 下的库"; rc=1 ;; *) echo "     OK   未链接任何 /tools 路径" ;; esac
case "$ldd_out" in *libc.so.6*) echo "     OK   链接到 libc.so.6" ;; *) echo "     FAIL 未链接 libc.so.6"; rc=1 ;; esac
echo "   说明：flex 自身不链接 libfl（libfl 只给 flex **生成的**扫描器用），故 ldd 里没有 libfl 是正常的。"
echo
echo "2) Installed program：/usr/bin/flex++（link to flex，由顶层 Makefile.am 的 install-exec-hook 建）"
if [ -L /usr/bin/flex++ ]; then
  echo "   OK   /usr/bin/flex++ 是符号链接 -> $(readlink /usr/bin/flex++)"
  if [ "$(readlink /usr/bin/flex++)" = flex ]; then echo "   OK   指向 flex（与手册 'link to flex' 一致）"
  else echo "   FAIL 指向的不是 flex"; rc=1; fi
else echo "   FAIL /usr/bin/flex++ 不是符号链接或不存在"; rc=1; fi
echo "   flex++ --version：$(flex++ --version 2>&1 | sed -n 1p)（argv[0] 结尾是 '+' → 自动进入 C++ 模式）"
echo
echo "3) Installed program：/usr/bin/lex（link to flex，由手册命令 5/6 建）"
if [ -L /usr/bin/lex ]; then
  echo "   OK   /usr/bin/lex 是符号链接 -> $(readlink /usr/bin/lex)"
  if [ "$(readlink /usr/bin/lex)" = flex ]; then echo "   OK   指向 flex（与手册 'link to flex' 一致）"
  else echo "   FAIL 指向的不是 flex"; rc=1; fi
else echo "   FAIL /usr/bin/lex 不是符号链接或不存在"; rc=1; fi
echo "   lex --version：$(lex --version 2>&1 | sed -n 1p)"
echo "   三者是否解析到同一个可执行文件（inode）："
i_flex=$(stat -Lc %i /usr/bin/flex); i_pp=$(stat -Lc %i /usr/bin/flex++); i_lex=$(stat -Lc %i /usr/bin/lex)
echo "     flex=$i_flex  flex++=$i_pp  lex=$i_lex"
if [ "$i_flex" = "$i_pp" ] && [ "$i_flex" = "$i_lex" ]; then echo "     OK   同一 inode（两个链接都指向同一个 flex）"
else echo "     FAIL 三者不是同一个文件"; rc=1; fi
echo
echo "4) Installed library：/usr/lib/libfl.so"
for f in /usr/lib/libfl.so /usr/lib/libfl.so.2 /usr/lib/libfl.so.2.0.0; do
  if [ -e "$f" ]; then
    if [ -L "$f" ]; then printf '   OK   %-26s -> %s\n' "$f" "$(readlink "$f")"
    else printf '   OK   %-26s（%s 字节，%s）\n' "$f" "$(stat -Lc %s "$f")" "$(file -b "$f" | cut -d, -f1-2)"; fi
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   libfl.so 导出的符号（libmain.c 的 main + libyywrap.c 的 yywrap）："
{ nm -D --defined-only /usr/lib/libfl.so.2.0.0 || true; } | sed 's/^/     /'
nm_out=$({ nm -D --defined-only /usr/lib/libfl.so.2.0.0 || true; })
case "$nm_out" in *" T main"*) echo "     OK   导出 main" ;; *) echo "     FAIL 未导出 main"; rc=1 ;; esac
case "$nm_out" in *" T yywrap"*) echo "     OK   导出 yywrap" ;; *) echo "     FAIL 未导出 yywrap"; rc=1 ;; esac
echo "   --disable-static 的效果：不应存在 /usr/lib/libfl.a"
if [ -e /usr/lib/libfl.a ]; then echo "     FAIL /usr/lib/libfl.a 存在（--disable-static 未生效）"; rc=1
else echo "     OK   /usr/lib/libfl.a 不存在"; fi
echo "   （/usr/lib/libfl.la 是 libtool 归档，手册 §8.16 未要求删除，此处只记录：$( [ -e /usr/lib/libfl.la ] && echo 存在 || echo 不存在 )）"
echo
echo "5) Installed directory：/usr/share/doc/flex-$VER（--docdir 的成果）"
if [ -d "/usr/share/doc/flex-$VER" ]; then
  echo "   OK   目录存在，内容："
  ls -l "/usr/share/doc/flex-$VER" | sed 's/^/     /'
  for f in AUTHORS COPYING NEWS ONEWS README.md; do
    if [ -f "/usr/share/doc/flex-$VER/$f" ]; then printf '     OK   %-10s（%s 字节）\n' "$f" "$(stat -Lc %s "/usr/share/doc/flex-$VER/$f")"
    else printf '     FAIL %s 缺失\n' "$f"; rc=1; fi
  done
else echo "   FAIL /usr/share/doc/flex-$VER 不存在"; rc=1; fi
if [ -d /usr/share/doc/flex ]; then echo "   FAIL 出现了未加版本号的 /usr/share/doc/flex（说明 --docdir 未生效）"; rc=1
else echo "   OK   不存在未加版本号的 /usr/share/doc/flex"; fi
echo
echo "6) 手册 Contents 未逐条列出、但由 make install 一并安装的文件："
for f in /usr/include/FlexLexer.h /usr/share/man/man1/flex.1 /usr/share/info/flex.info; do
  if [ -e "$f" ]; then printf '   OK   %-34s（%s 字节）\n' "$f" "$(stat -Lc %s "$f")"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
if [ -L /usr/share/man/man1/lex.1 ]; then
  echo "   OK   /usr/share/man/man1/lex.1 -> $(readlink /usr/share/man/man1/lex.1)（手册命令 6/6）"
  if [ -e /usr/share/man/man1/lex.1 ]; then echo "   OK   该符号链接可解析到实际文件"
  else echo "   FAIL lex.1 是断链"; rc=1; fi
else echo "   FAIL /usr/share/man/man1/lex.1 不是符号链接"; rc=1; fi
echo "   info 目录项（install-info 是否登记了 flex）："
{ grep -n 'flex' /usr/share/info/dir || true; } | sed 's/^/     /'
echo "   flex.info 分卷："
{ ls -l /usr/share/info/flex.info* || true; } | sed 's/^/     /'
echo "   po 消息目录（本节安装的 .mo 数量）："
mo_n=$(find /usr/share/locale -name 'flex.mo' -type f 2>/dev/null | wc -l)
echo "     flex.mo 文件数：$mo_n"
echo

echo "----- 功能验证（对照手册 §8.16.2 的 Short Descriptions，用已安装的 /usr/bin 程序） -----"
tmpd=$(mktemp -d /tmp/flex-verify-XXXXXX)
cd "$tmpd"
echo "A. flex —— A tool for generating programs that recognize patterns in text"
echo "a1) 由规则文件生成扫描器，编译后真的能识别文本中的模式"
cat > wc.l <<'EOF'
%option noyywrap
%{
int nchar = 0, nword = 0, nline = 0;
%}
%%
[a-zA-Z]+   { nword++; nchar += yyleng; }
\n          { nline++; nchar++; }
.           { nchar++; }
%%
int main(void) { yylex(); printf("%d %d %d\n", nline, nword, nchar); return 0; }
EOF
if flex -o wc.c wc.l; then echo "     OK   flex -o wc.c wc.l 生成 $(wc -l < wc.c) 行 C 代码"
else echo "     FAIL flex 生成扫描器失败"; rc=1; fi
gcc -o wc wc.c
cat > input.txt <<'EOF'
hello flex world
second line
EOF
out_a1=$(./wc < input.txt)
echo "     输入 2 行 / 5 个单词 / 29 字符 -> 扫描器输出：$out_a1"
if [ "$out_a1" = "2 5 29" ]; then echo "     OK   生成的程序正确识别了行/单词/字符模式"
else echo "     FAIL 期望 '2 5 29'"; rc=1; fi
echo "a2) 规则的「可定制性」（手册：allows for the versatility to specify the rules）"
cat > tok.l <<'EOF'
%option noyywrap
%%
[0-9]+          { printf("INT(%s) ", yytext); }
[A-Za-z_]+      { printf("ID(%s) ", yytext); }
"+"|"-"|"*"|"/" { printf("OP(%s) ", yytext); }
[ \t\n]+        { }
.               { printf("?(%s) ", yytext); }
%%
int main(void) { yylex(); printf("\n"); return 0; }
EOF
flex -o tok.c tok.l && gcc -o tok tok.c
out_a2=$(echo 'x1 + 42 * foo' | ./tok)
echo "     'x1 + 42 * foo' -> $out_a2"
if [ "$out_a2" = "ID(x) INT(1) OP(+) INT(42) OP(*) ID(foo) " ]; then
  echo "     OK   按自定义规则分词（最长匹配 + 规则优先级）正确"
else echo "     FAIL 分词结果与预期不符"; rc=1; fi
echo "a3) 运行时确实经过 m4（§8.14 的产物）：把 M4 环境变量指向不存在的程序应失败"
set +e
M4=/nonexistent-m4 timeout 60 flex -o m4test.c wc.l > m4test.err 2>&1
m4_rc=$?
set -e
echo "     M4=/nonexistent-m4 flex ... 退出码：$m4_rc"
echo "     诊断：$({ grep -m1 . m4test.err || echo '（无输出）'; })"
if [ "$m4_rc" -ne 0 ]; then echo "     OK   缺少 m4 时 flex 失败 —— 证明其代码生成确实经由 m4 管道"
else echo "     INFO 未失败（上游可能回退到编译期写死的 $m4_in_bin）"; fi
echo
echo "B. flex++ —— An extension of flex, used for generating C++ code and classes"
cat > cpp.l <<'EOF'
%option noyywrap c++
%%
[0-9]+   { std::cout << "INT " << YYText() << std::endl; }
.|\n     { }
%%
EOF
if flex++ -o cpp.cc cpp.l; then echo "     OK   flex++ -o cpp.cc cpp.l 成功"
else echo "     FAIL flex++ 生成失败"; rc=1; fi
yyfl_n=$({ grep -c 'yyFlexLexer' cpp.cc || true; })
echo "     生成文件中 yyFlexLexer 出现次数：$yyfl_n（C++ 类，而非 C 函数 yylex）"
if [ "$yyfl_n" -gt 0 ]; then echo "     OK   生成的是 C++ 代码与类"
else echo "     FAIL 生成的不是 C++ 代码"; rc=1; fi
cat > cppmain.cc <<'EOF'
#include <FlexLexer.h>
#include <iostream>
#include <sstream>
int main(){ std::istringstream in("x 42 y 7"); yyFlexLexer lex(&in, &std::cout); lex.yylex(); return 0; }
EOF
g++ -o cppscan cpp.cc cppmain.cc
out_b=$(./cppscan | tr '\n' ' ')
echo "     用 /usr/include/FlexLexer.h 编译并运行 -> $out_b"
if [ "$out_b" = "INT 42 INT 7 " ]; then echo "     OK   C++ 扫描器类工作正常（同时验证了 FlexLexer.h 已正确安装）"
else echo "     FAIL C++ 扫描器输出不符"; rc=1; fi
echo
echo "C. lex —— A symbolic link that runs flex（手册措辞：in lex emulation mode）"
echo "c1) 通过 lex 这个名字调用同样能生成扫描器"
if lex -o by-lex.c wc.l; then echo "     OK   lex -o by-lex.c wc.l 成功（$(wc -l < by-lex.c) 行）"
else echo "     FAIL 通过 lex 调用失败"; rc=1; fi
flex -o same.c wc.l; mv same.c by-flex-same.c
lex  -o same.c wc.l; mv same.c by-lex-same.c
if cmp -s by-flex-same.c by-lex-same.c; then
  echo "     OK   相同输入、相同输出文件名时，lex 与 flex 的产物逐字节一致"
else echo "     FAIL lex 与 flex 的产物不一致"; rc=1; fi
echo "c2) 真正的 lex 兼容语义由 -l 选项打开（读 src/main.c 得知：argv[0] 只决定 C++ 模式，"
echo "    不决定 lex_compat；手册所说的 emulation mode 对应 flex 的 -l）："
flex    -o nol.c wc.l
lex  -l -o withl.c wc.l
n_nol=$({ grep -c 'define YY_FLEX_LEX_COMPAT' nol.c   || true; })
n_wl=$({ grep -c 'define YY_FLEX_LEX_COMPAT' withl.c || true; })
echo "     不带 -l 的生成文件中 YY_FLEX_LEX_COMPAT 定义数：$n_nol"
echo "     lex -l 的生成文件中 YY_FLEX_LEX_COMPAT 定义数：$n_wl"
if [ "$n_nol" -eq 0 ] && [ "$n_wl" -ge 1 ]; then
  echo "     OK   -l 确实切换到 lex 兼容（仿真）模式"
else echo "     FAIL -l 的效果与预期不符"; rc=1; fi
echo
echo "D. libfl —— The flex library"
echo "d1) 不写 main、不写 yywrap 的扫描器，靠 -lfl 补齐这两个符号"
cat > tiny.l <<'EOF'
%%
[0-9]+   { printf("NUM(%s)\n", yytext); }
.|\n     { }
%%
EOF
flex -o tiny.c tiny.l
if gcc -o tiny tiny.c -lfl; then echo "     OK   gcc ... -lfl 链接成功（main 与 yywrap 由 libfl.so 提供）"
else echo "     FAIL 链接 -lfl 失败"; rc=1; fi
out_d=$(printf 'a 12 b 345\n' | ./tiny | tr '\n' ' ')
echo "     'a 12 b 345' -> $out_d"
if [ "$out_d" = "NUM(12) NUM(345) " ]; then echo "     OK   由 libfl 提供 main 的扫描器运行正确"
else echo "     FAIL 输出不符"; rc=1; fi
echo "     tiny 的动态依赖（应含 libfl.so.2）："
ldd ./tiny | sed 's/^/       /'
ldd_tiny=$(ldd ./tiny)
case "$ldd_tiny" in
  *libfl.so.2*) echo "       OK   动态链接到 /usr/lib/libfl.so.2" ;;
  *) echo "       FAIL 未动态链接 libfl"; rc=1 ;;
esac
echo
echo "E. 错误路径（诊断信息与非 0 退出码）"
set +e
flex -o nofile.c /sources/no-such-file.l > e1.out 2>&1; e1=$?
flex --no-such-option -o e2.c wc.l      > e2.out 2>&1; e2=$?
printf 'foo\n' > bad.l
flex -o e3.c bad.l                       > e3.out 2>&1; e3=$?
set -e
echo "     输入文件不存在  -> 退出码 $e1，诊断：$({ grep -m1 . e1.out || true; })"
echo "     非法选项        -> 退出码 $e2，诊断：$({ grep -m1 . e2.out || true; })"
echo "     规则文件语法错误 -> 退出码 $e3，诊断：$({ grep -m1 . e3.out || true; })"
if [ $e1 -ne 0 ] && [ $e2 -ne 0 ] && [ $e3 -ne 0 ]; then echo "     OK   三类错误都返回非 0 并给出诊断"
else echo "     FAIL 存在错误情形却返回 0"; rc=1; fi
cd /sources
rm -rf "$tmpd"
echo
echo "7) 本节写入系统的文件清单（不含 locale/*.mo 与 info 分卷）："
{ ls -ld /usr/bin/flex /usr/bin/flex++ /usr/bin/lex \
        /usr/lib/libfl.so /usr/lib/libfl.so.2 /usr/lib/libfl.so.2.0.0 /usr/lib/libfl.la \
        /usr/include/FlexLexer.h \
        /usr/share/man/man1/flex.1 /usr/share/man/man1/lex.1 \
        /usr/share/info/flex.info "/usr/share/doc/flex-$VER" 2>/dev/null || true; } | sed 's/^/     /'
[ $rc -eq 0 ] || { echo "错误：Flex 安装结果不符合手册要求" >&2; exit 1; }
echo

echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.16.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure    完整输出：$CONFLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make check   完整输出：$CHECKLOG"
echo "  make install 完整输出：$INSTLOG"
cd /sources
rm -rf "$SRCDIR"
if [ -d "/sources/$SRCDIR" ]; then echo "错误：源码目录未清理" >&2; exit 1; fi
echo "已删除 /sources/$SRCDIR"
echo "/sources 下的解包残留（应为空）："
find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §8.16 完成，结束时间：$(date -Is) ====="
