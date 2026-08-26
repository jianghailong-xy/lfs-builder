#!/usr/bin/env bash
# 预演：把 8.31 脚本里「功能验证」用到的手法先在 §6.3 已装的 ncurses 上试一遍
set -uo pipefail
work=/tmp/.ncurses-probe.$$; mkdir -p "$work"; cd "$work"
echo "== 1) 程序 -V =="
for p in tic infocmp toe tput tset clear tabs captoinfo infotocap reset; do
  out=$("/usr/bin/$p" -V 2>&1); prc=$?
  printf '%-12s rc=%s out=%s\n' "$p" "$prc" "$(echo "$out"|head -1)"
done
echo "ncursesw6-config --version: $(/usr/bin/ncursesw6-config --version 2>&1) rc=$?"
echo "--cflags: $(/usr/bin/ncursesw6-config --cflags 2>&1)"
echo "--libs  : $(/usr/bin/ncursesw6-config --libs 2>&1)"
echo "--abi   : $(/usr/bin/ncursesw6-config --abi-version 2>&1)"
echo "== 2) terminfo =="
echo "cols=$(TERM=xterm tput -T xterm cols 2>&1) rc=$?"
echo "colors=$(tput -T xterm-256color colors 2>&1) rc=$?"
echo "longname=$(tput -T vt100 longname 2>&1) rc=$?"
infocmp -T xterm 2>&1 | head -3
echo "toe 行数: $(toe 2>/dev/null | wc -l)"
mkdir -p ti
cat > mini.src <<'TIEOF'
minitest|a minimal terminfo entry for verification,
	cols#80, lines#24,
	clear=\E[H\E[2J, cup=\E[%i%p1%d;%p2%dH,
TIEOF
tic -o "$work/ti" mini.src 2>tic.err; echo "tic rc=$?"; find ti -type f
TERMINFO=$work/ti infocmp -T minitest 2>&1 | head -4
echo "== 3) C 程序（不带任何 XOPEN 宏）=="
cat > t.c <<'CEOF'
#include <curses.h>
#include <stdio.h>
int main(void) {
    FILE *out = fopen("/dev/null", "w");
    SCREEN *sp = newterm("xterm", out, stdin);
    if (!sp) { printf("newterm failed\n"); return 1; }
    printf("curses_version = %s\n", curses_version());
    printf("COLS=%d LINES=%d\n", COLS, LINES);
    printf("has_colors=%d start_color=%d\n", has_colors(), start_color() == OK);
    cchar_t cc; wchar_t w[2] = { L'A', L'\0' };
    printf("setcchar=%d\n", setcchar(&cc, w, A_NORMAL, 0, NULL) == OK);
    endwin(); delscreen(sp); return 0;
}
CEOF
gcc -o t t.c -lncursesw 2>t.err; echo "gcc rc=$?"; cat t.err
readelf -d t 2>/dev/null | grep NEEDED
./t; echo "run rc=$?"
echo "== 3b) 同一程序 stdin 来自 /dev/null =="
./t < /dev/null; echo "rc=$?"
echo "== 4) 兼容链接（当前只有 libncurses.so，其余应失败——正是 8.31 要补的）=="
for l in curses ncurses form menu panel; do
  case $l in curses|ncurses) h=curses.h;; form) h=form.h;; menu) h=menu.h;; panel) h=panel.h;; esac
  printf '#include <%s>\nint main(void){return 0;}\n' "$h" > l.c
  gcc -o l l.c -l$l -lncursesw 2>l.err; echo "-l$l rc=$? $(head -1 l.err)"
done
echo "== 5) C++ =="
printf '#include <cursesw.h>\nint main(){return 0;}\n' > c.cc
g++ -o c c.cc -lncurses++w -lncursesw 2>c.err; echo "g++ rc=$?"; head -3 c.err
readelf -d c 2>/dev/null | grep NEEDED
echo "== 6) pkg-config（此刻应全部失败）=="
for m in ncursesw ncurses; do echo "$m: $(pkg-config --modversion $m 2>&1) rc=$?"; done
echo "== 7) bash =="
/usr/bin/bash -c 'echo bash-ok $BASH_VERSION'; echo "rc=$?"
cd /; rm -rf "$work"
