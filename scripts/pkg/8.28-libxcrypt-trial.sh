#!/usr/bin/env bash
# §8.28 Libxcrypt-4.5.2 —— chroot /tmp 内的试建（不写系统），用于校准正式脚本的自检断言。
set -uo pipefail
VER=4.5.2
T=/tmp/xc-trial
rm -rf "$T"; mkdir -p "$T"; cd "$T"

echo "===== 环境 ====="
echo "date=$(date -Is)  nproc=$(nproc)  MAKEFLAGS=${MAKEFLAGS:-none}"
echo "glibc: $(/usr/bin/ldd --version | head -n1)"
echo "gcc:   $(gcc -dumpfullversion 2>/dev/null)"
echo "现有 libcrypt 相关文件（安装前应为空/仅 glibc 残留）："
{ ls -l /usr/lib/libcrypt* /usr/include/crypt.h /usr/lib/pkgconfig/libcrypt.pc 2>&1 || true; } | sed 's/^/  /'
echo

echo "===== 解包 ====="
tar -xf /sources/libxcrypt-$VER.tar.xz
cd libxcrypt-$VER
echo "顶层：$(ls | tr '\n' ' ')"
echo

echo "===== sed 校准 ====="
for f in lib/crypt-sm3-yescrypt.c lib/crypt-gost-yescrypt.c; do
  echo "--- $f 含 strchr 的行（sed 前）"
  { grep -n strchr "$f" || true; } | sed 's/^/  /'
done
cp lib/crypt-sm3-yescrypt.c /tmp/xc-sm3.orig
cp lib/crypt-gost-yescrypt.c /tmp/xc-gost.orig
sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
sed_rc=$?
echo "sed 退出码：$sed_rc"
for f in lib/crypt-sm3-yescrypt.c lib/crypt-gost-yescrypt.c; do
  echo "--- $f 含 strchr 的行（sed 后）"
  { grep -n strchr "$f" || true; } | sed 's/^/  /'
done
echo "--- 差异（仅展示）"
{ diff -u /tmp/xc-sm3.orig lib/crypt-sm3-yescrypt.c || true; } | sed 's/^/  /'
{ diff -u /tmp/xc-gost.orig lib/crypt-gost-yescrypt.c || true; } | sed 's/^/  /'
echo "全树其它文件是否也含 'const char *' + strchr 组合（确认 sed 只需改这两个）："
{ grep -rln 'strchr' lib/ || true; } | sed 's/^/  /'
echo

echo "===== configure ====="
./configure --prefix=/usr                \
    --enable-hashes=strong,glibc \
    --enable-obsolete-api=no     \
    --disable-static             \
    --disable-failure-tokens     > /tmp/xc-conf.log 2>&1
conf_rc=$?
echo "configure 退出码：$conf_rc"
tail -n 40 /tmp/xc-conf.log | sed 's/^/  /'
echo "--- config.status: creating 行"
{ grep '^config.status: creating' /tmp/xc-conf.log || true; } | sed 's/^/  /'
echo "--- ac_cs_config"
{ grep -m1 '^ac_cs_config=' config.status || true; } | sed 's/^/  /'
echo "--- config.h 里的关键宏"
{ grep -E 'ENABLE_(OBSOLETE_API|FAILURE_TOKENS)|INCLUDE_[a-z0-9_]+|HASH' config.h || true; } | sed 's/^/  /'
echo "--- libtool build_old_libs（前 3 处）"
{ grep -n 'build_old_libs=' libtool || true; } | sed -n '1,3p' | sed 's/^/  /'
echo "--- Makefile 中 obsolete/version 相关"
{ grep -nE '^(ENABLE_OBSOLETE_API|VERSION|SOVERSION|libcrypt_la_LDFLAGS)' Makefile || true; } | sed 's/^/  /'
[ $conf_rc -ne 0 ] && exit 1
echo

echo "===== make ====="
make > /tmp/xc-make.log 2>&1
make_rc=$?
echo "make 退出码：$make_rc"
tail -n 20 /tmp/xc-make.log | sed 's/^/  /'
[ $make_rc -ne 0 ] && { echo "make 失败，尾部日志："; tail -n 60 /tmp/xc-make.log; exit 1; }
echo "--- .libs 产物"
{ ls -l .libs/ | grep -E 'libcrypt|\.a$' || true; } | sed 's/^/  /'
echo "--- 树内 .a 文件"
{ find . -name '*.a' || true; } | sed 's/^/  /'
echo "--- SONAME"
sofile=$(find .libs -maxdepth 1 -name 'libcrypt.so.*' -type f | head -n1)
echo "  实体：$sofile"
{ readelf -d "$sofile" | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/  /'
echo "--- 导出符号数与 crypt/crypt_r 是否存在"
nm -D --defined-only "$sofile" > /tmp/xc-syms.txt 2>&1
echo "  导出符号数：$(wc -l < /tmp/xc-syms.txt)"
{ grep -E ' (crypt|crypt_r|crypt_rn|crypt_ra|crypt_gensalt|fcrypt|encrypt|setkey)$' /tmp/xc-syms.txt || true; } | sed 's/^/  /'
echo "--- 版本符号（obsolete-api=no 时应只有 XCRYPT_2.0 一族，无 XCRYPT_1.0/GLIBC_*）"
{ readelf --version-info "$sofile" 2>/dev/null | grep -oE 'Name: [A-Za-z0-9_.]+' | sort -u || true; } | sed 's/^/  /'
echo "--- libcrypt.pc"
{ cat libcrypt.pc 2>/dev/null || true; } | sed 's/^/  /'
echo

echo "===== make check ====="
make check > /tmp/xc-check.log 2>&1
check_rc=$?
echo "make check 退出码：$check_rc"
{ grep -E '^# (TOTAL|PASS|SKIP|XFAIL|FAIL|XPASS|ERROR):' /tmp/xc-check.log || true; } | sed 's/^/  /'
echo "--- FAIL/ERROR 行"
{ grep -E '^(FAIL|ERROR|XPASS):' /tmp/xc-check.log || true; } | sed 's/^/  /'
echo "--- .trs 汇总"
{ grep -h '^:global-test-result:' $(find . -name '*.trs') 2>/dev/null | sort | uniq -c || true; } | sed 's/^/  /'
echo "--- 尾部"
tail -n 25 /tmp/xc-check.log | sed 's/^/  /'
echo

echo "===== DESTDIR 安装 ====="
D=/tmp/xc-dest
rm -rf "$D"
make DESTDIR="$D" install > /tmp/xc-inst.log 2>&1
inst_rc=$?
echo "make install 退出码：$inst_rc"
[ $inst_rc -ne 0 ] && { tail -n 40 /tmp/xc-inst.log; exit 1; }
echo "--- 完整安装清单"
{ find "$D" -mindepth 1 | sed "s|$D||" | sort || true; } | sed 's/^/  /'
echo "--- 文件数：$(find "$D" -type f | wc -l)  链接数：$(find "$D" -type l | wc -l)"
echo "--- 库文件详细"
{ ls -l "$D"/usr/lib/ || true; } | sed 's/^/  /'
echo "--- man 页数：$(find "$D" -path '*/man/*' -type f 2>/dev/null | wc -l)"
echo "--- pkgconfig"
{ cat "$D"/usr/lib/pkgconfig/libcrypt.pc 2>/dev/null || true; } | sed 's/^/  /'
echo "--- 是否有 .a / .la"
{ find "$D" \( -name '*.a' -o -name '*.la' \) || true; } | sed 's/^/  /'
echo

echo "===== 功能验证（用 DESTDIR 里的库） ====="
cat > /tmp/xc-t.c <<'EOF'
#include <crypt.h>
#include <stdio.h>
#include <string.h>
int main(void) {
  struct crypt_data d; memset(&d, 0, sizeof d);
  const char *cases[][2] = {
    {"$6$saltstring", "yescrypt/sha512-glibc"},
    {"$y$j9T$LdJMENpBABJJ3hIHjB1Bi.", "yescrypt"},
    {"$5$saltstring", "sha256-glibc"},
    {"$1$saltstri", "md5-glibc"},
    {"$2b$05$abcdefghijklmnopqrstuu", "bcrypt"},
  };
  for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
    char *h = crypt_r("password", cases[i][0], &d);
    printf("  %-24s setting=%-40s -> %s\n", cases[i][1], cases[i][0],
           h ? h : "(NULL)");
  }
  char *gs = crypt_gensalt("$y$", 0, NULL, 0);
  printf("  crypt_gensalt(\"$y$\") -> %s\n", gs ? gs : "(NULL)");
  return 0;
}
EOF
gcc /tmp/xc-t.c -o /tmp/xc-t -I"$D/usr/include" -L"$D/usr/lib" -lcrypt -Wl,-rpath,"$D/usr/lib" 2>&1 | sed 's/^/  /'
if [ -x /tmp/xc-t ]; then
  echo "--- 运行结果"
  /tmp/xc-t
  echo "--- 该程序链接的库"
  { ldd /tmp/xc-t | grep -i crypt || true; } | sed 's/^/  /'
fi
echo
echo "===== 试建完成 ====="
echo "conf=$conf_rc make=$make_rc check=$check_rc inst=$inst_rc"
