#!/usr/bin/env bash
# LFS 13.0-systemd §7.8 Bison-3.8.2（临时工具）
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §7.8.1 的命令序列（全部；本节无补丁、无测试套件）：
#   ./configure --prefix=/usr \
#               --docdir=/usr/share/doc/bison-3.8.2
#   make
#   make install
set -euo pipefail

PKG=bison
VER=3.8.2
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §7.8 Bison-$VER（临时工具） ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 58 MB"
echo "手册简介：The Bison package contains a parser generator."
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
  *) echo "OK        : /tools/bin 不在 PATH（交叉工具链已停用）" ;;
esac
echo "可用空间（手册本节要求 58 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 58 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 58MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§7.7 Gettext-1.0）产物及 chroot 基础必须可用 -----"
rc=0
echo "1) §7.7 装入 /usr/bin 的三个 gettext 程序（Bison 带 NLS，编译时用 msgfmt 生成 .mo）："
for t in msgfmt msgmerge xgettext; do
  if command -v $t >/dev/null 2>&1; then
    printf '   OK   %-9s %-16s %s\n' "$t" "$(command -v $t)" "$($t --version | head -n1)"
  else
    printf '   FAIL %s 不可用（§7.7 未完成？）\n' "$t"; rc=1
  fi
done
echo "2) 编译器与第 6 章工具（§6.17/§6.18 装入 \$LFS/usr）："
for t in gcc cc g++ ld as ar ranlib make sed grep gawk m4 tar xz patch find diff file bash; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
gcc --version | sed -n '1s/^/   gcc: /p'
echo "   m4（Bison 运行期依赖 M4，§6.2 已装）：$(m4 --version | head -n1)"
echo "3) §7.6 建立的基础文件："
for f in /etc/passwd /etc/group /etc/hosts /etc/mtab; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "4) §7.3 虚拟内核文件系统："
for f in /dev/null /dev/zero /dev/urandom /proc/self /sys; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "5) 本节安装前 bison/yacc/liby.a 的状态："
for f in /usr/bin/bison /usr/bin/yacc /usr/lib/liby.a; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在（将被 make install 覆盖）\n' "$f"
  else printf '   OK   %s 尚未安装\n' "$f"; fi
done
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "包自报版本：$(grep -m1 -E "^PACKAGE_STRING=" configure | sed "s/^PACKAGE_STRING=//; s/'//g")"
echo "本节无补丁：手册 §7.8 只有 ./configure、make、make install 三条命令，"
echo "  没有任何 patch/sed 前置改动。"
echo

echo "================= 7.8.1. Installation of Bison ================="
echo "----- configure（手册原文：Prepare Bison for compilation） -----"
echo "手册命令：./configure --prefix=/usr \\"
echo "                      --docdir=/usr/share/doc/bison-3.8.2"
echo "手册对新选项的说明："
echo "  --docdir=/usr/share/doc/bison-3.8.2  This tells the build system to install"
echo "      bison documentation into a versioned directory."
time ./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2
echo
echo "configure 结果确认："
grep -m1 '\$ \./configure' config.log | sed 's/^ *\$ */  实际参数：/'
if grep -qE '^\s*\$ \./configure --prefix=/usr --docdir=/usr/share/doc/bison-3\.8\.2\s*$' config.log; then
  echo "  OK   configure 参数与手册 §7.8 完全一致"
else
  echo "  注意：configure 参数与手册字面不一致，见上一行"
fi
grep -m1 '^docdir = ' Makefile | sed 's/^/  Makefile: /'
grep -m1 '^prefix = ' Makefile | sed 's/^/  Makefile: /'
echo

echo "----- 编译（手册原文：Compile the package） -----"
echo "手册命令：make"
echo "（MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境提供）"
time make
echo

echo "================= 本节测试 ================="
echo "手册 §7.8 未规定任何测试：本节命令只有 ./configure --prefix=/usr"
echo "  --docdir=/usr/share/doc/bison-3.8.2、make 和 make install，没有 make check。"
echo "  第 7 章各小节（Gettext、Bison、Perl、Python、Texinfo、Util-linux）均不跑测试；"
echo "  Bison 的完整测试套件出现在第 8 章 §8.35（make check）。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装（手册原文：Install the package） -----"
echo "手册命令：make install"
time make install
echo

echo "----- 安装结果检查（对照手册 §8.35.2 Contents of Bison） -----"
echo "手册 §8.35.2：Installed programs: bison and yacc；Installed library: liby.a；"
echo "  Installed directory: /usr/share/bison"
rc=0
for p in /usr/bin/bison /usr/bin/yacc; do
  if [ -x "$p" ]; then printf '   OK   %-14s %s\n' "$p" "$(file -b $p | cut -d, -f1-3)"
  else printf '   FAIL %s 缺失或不可执行\n' "$p"; rc=1; fi
done
if [ -f /usr/lib/liby.a ]; then
  printf '   OK   %-14s %s\n' /usr/lib/liby.a "$(file -b /usr/lib/liby.a)"
  echo "        成员：$(ar t /usr/lib/liby.a | tr '\n' ' ')"
else
  echo "   FAIL /usr/lib/liby.a 缺失"; rc=1
fi
if [ -d /usr/share/bison ]; then
  echo "   OK   /usr/share/bison（$(find /usr/share/bison -type f | wc -l) 个文件）"
else
  echo "   FAIL /usr/share/bison 缺失"; rc=1
fi
echo "   --docdir 生效检查（手册要求装到带版本号的目录）："
if [ -d /usr/share/doc/bison-3.8.2 ]; then
  echo "     OK   /usr/share/doc/bison-3.8.2 存在，内容："
  ls /usr/share/doc/bison-3.8.2 | sed 's/^/       /'
else
  echo "     FAIL /usr/share/doc/bison-3.8.2 不存在"; rc=1
fi
if [ -e /usr/share/doc/bison ]; then
  echo "     FAIL 存在未带版本号的 /usr/share/doc/bison（--docdir 未生效）"; rc=1
else
  echo "     OK   不存在未带版本号的 /usr/share/doc/bison"
fi
echo "   手册 §8.35.2 的简短描述："
echo "     bison  Generates, from a series of rules, a program for analyzing the"
echo "            structure of text files; Bison is a replacement for Yacc"
echo "     yacc   A wrapper for bison, meant for programs that still call yacc instead"
echo "            of bison; it calls bison with the -y option"
echo "     liby   The Yacc library containing implementations of Yacc-compatible"
echo "            yyerror and main functions"
echo "   实际运行（--version）："
bison_ver=$(bison --version | head -n1)
echo "     bison: $bison_ver"
case "$bison_ver" in *"$VER"*) ;; *) echo "   FAIL bison 报告的版本不含 $VER"; rc=1 ;; esac
yacc_ver=$(yacc --version | head -n1)
echo "     yacc : $yacc_ver"
echo "   yacc 确实是 bison -y 的包装（手册 §8.35.2）："
grep -n 'exec .*bison.* -y' /usr/bin/yacc | sed 's/^/     /' \
  || { echo "     FAIL /usr/bin/yacc 中未找到调用 bison -y 的行"; rc=1; }
echo "   功能性冒烟测试（用 bison 生成解析器并编译运行）："
mkdir -p /tmp/.bison-smoke && cd /tmp/.bison-smoke
cat > calc.y <<'YEOF'
%{
#include <stdio.h>
int yylex(void);
void yyerror(const char *s);
static const char *p;
%}
%token NUM
%%
line: expr        { printf("%d\n", $1); }
    ;
expr: expr '+' NUM { $$ = $1 + $3; }
    | NUM          { $$ = $1; }
    ;
%%
void yyerror(const char *s) { fprintf(stderr, "%s\n", s); }
int yylex(void) {
  while (*p == ' ') p++;
  if (*p >= '0' && *p <= '9') { yylval = 0;
    while (*p >= '0' && *p <= '9') yylval = yylval * 10 + (*p++ - '0');
    return NUM; }
  return *p ? *p++ : 0;
}
int main(void) { p = "20 + 22"; return yyparse(); }
YEOF
bison -o calc.c calc.y
echo "     bison 生成：$(ls -l calc.c | awk '{print $9, $5 " 字节"}')"
gcc -o calc calc.c
out=$(./calc)
if [ "$out" = "42" ]; then
  echo "     OK   生成的解析器计算 \"20 + 22\" = $out"
else
  echo "     FAIL 解析器输出为 \"$out\"（期望 42）"; rc=1
fi
echo "     yacc -d 冒烟（走 bison -y 兼容路径 + 链接 liby.a）："
yacc -d calc.y && [ -f y.tab.c ] && [ -f y.tab.h ] \
  && gcc -o calc_y y.tab.c -ly \
  && [ "$(./calc_y)" = "42" ] \
  && echo "     OK   yacc 生成 y.tab.c/y.tab.h，链接 -ly 后运行正确" \
  || { echo "     FAIL yacc/-ly 路径失败"; rc=1; }
cd /sources
rm -rf /tmp/.bison-smoke
[ $rc -eq 0 ] || { echo "错误：Bison 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
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
echo "===== §7.8 完成，结束时间：$(date -Is) ====="
