#!/usr/bin/env bash
# LFS 13.0-systemd §5.6 Libstdc++ from GCC-15.2.0
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §5.6.1 的命令序列（Note：Libstdc++ 是 GCC 源码的一部分，先解包 GCC 并进入 gcc-15.2.0）：
#   mkdir -v build
#   cd       build
#   ../libstdc++-v3/configure            \
#       --host=$LFS_TGT                  \
#       --build=$(../config.guess)       \
#       --prefix=/usr                    \
#       --disable-multilib               \
#       --disable-nls                    \
#       --disable-libstdcxx-pch          \
#       --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
#   make
#   make DESTDIR=$LFS install
#   rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
# 本节没有任何测试套件（交叉编译，测试无法在宿主上运行）。
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=gcc
VER=15.2.0
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §5.6 Libstdc++ from GCC-$VER ====="
echo "开始时间：$(date -Is)"
echo
echo "----- 环境（手册 §4.4 / iii. General Compilation Instructions） -----"
echo "whoami   : $(whoami)"
echo "LFS      : $LFS"
echo "LFS_TGT  : $LFS_TGT"
echo "PATH     : $PATH"
echo "LC_ALL   : $LC_ALL"
echo "CONFIG_SITE: $CONFIG_SITE"
echo "MAKEFLAGS: ${MAKEFLAGS:-（未设置）}"
echo "umask    : $(umask)"
echo "hash 关闭: $(set -o | grep hashall)"
echo "uname -m : $(uname -m)"
[ "$(whoami)" = "lfs" ] || { echo "错误：必须以 lfs 用户构建（手册 make DESTDIR 警告）" >&2; exit 1; }
[ "$LFS" = "/mnt/lfs" ] || { echo "错误：LFS 不是 /mnt/lfs" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点" >&2; exit 1; }
echo "可用空间（手册要求 1.3 GB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：§5.2/§5.3/§5.4/§5.5 的产物必须可用 -----"
for t in ld as ar ranlib gcc g++; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少前置产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS_TGT-gcc --version | head -n1
$LFS_TGT-g++ --version | head -n1
echo "§5.5 Glibc 产物（本节的直接依赖，手册说明 Libstdc++ 依赖 Glibc）："
for f in usr/lib/libc.so.6 usr/lib/ld-linux-x86-64.so.2 usr/lib/crt1.o usr/include/stdio.h; do
  [ -e "$LFS/$f" ] || { echo "错误：§5.5 产物缺失：\$LFS/$f" >&2; exit 1; }
  printf 'OK   $LFS/%s\n' "$f"
done
strings $LFS/usr/lib/libc.so.6 2>/dev/null | grep -m1 'GNU C Library' || true
echo "验证交叉工具链现在能链接出可执行文件（Glibc 已就位）："
tmpd=$(mktemp -d); echo 'int main(){return 0;}' > "$tmpd/t.c"
$LFS_TGT-gcc "$tmpd/t.c" -o "$tmpd/t" && echo "OK   \$LFS_TGT-gcc 可正常编译链接"
readelf -l "$tmpd/t" | grep ': /lib' || true
rm -rf "$tmpd"
echo

cd $LFS/sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 §5.6 Note：Libstdc++ 是 GCC 源码的一部分，先解包 GCC 并进入 $SRCDIR） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "GCC 自报版本：$(cat gcc/BASE-VER)"
echo "Libstdc++ 源码：$(ls -d libstdc++-v3)"
echo "本节无补丁（手册 §5.6 未规定任何 patch）"
echo

echo "----- 5.6.1 建立独立 build 目录 -----"
mkdir -v build
cd       build
echo "构建目录：$PWD"
echo

echo "----- 5.6.1 configure -----"
echo "build 三元组（../config.guess）：$(../config.guess)"
time ../libstdc++-v3/configure           \
    --host=$LFS_TGT                      \
    --build=$(../config.guess)           \
    --prefix=/usr                        \
    --disable-multilib                   \
    --disable-nls                        \
    --disable-libstdcxx-pch              \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/$VER
echo
echo "configure 关键结果确认："
grep -E '^(host|build|target)_alias *=' Makefile | sed 's/^/  /' || true
grep -E '^gxx_include_dir *=' Makefile | sed 's/^/  /' || true
echo

echo "----- 5.6.1 编译：make -----"
time make
echo

echo "----- 5.6.1 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 Warning：以 root 或 LFS 未设置会毁掉宿主系统）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 5.6.1 删除 libtool 归档文件（.la 对交叉编译有害） -----"
ls -l $LFS/usr/lib/*.la 2>/dev/null || true
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
echo "删除后 \$LFS/usr/lib 下残留的 .la 文件（应为空）："
ls -l $LFS/usr/lib/*.la 2>/dev/null || echo "  （无 .la 文件）"
echo

echo "================= 本节测试 ================="
echo "手册 §5.6 未规定任何测试套件（无 make check / make test）——"
echo "本节是交叉编译出的目标库，无法在宿主上运行其测试，手册也未要求。"
echo "因此本节的验证以手册本节安装结果的关键文件检查为准，见下。"
echo

echo "----- 安装结果检查（关键文件） -----"
rc=0
for f in usr/lib/libstdc++.so usr/lib/libstdc++.so.6 usr/lib/libstdc++.a \
         usr/lib/libsupc++.a \
         tools/$LFS_TGT/include/c++/$VER/vector \
         tools/$LFS_TGT/include/c++/$VER/string \
         tools/$LFS_TGT/include/c++/$VER/$LFS_TGT/bits/c++config.h; do
  if [ -e "$LFS/$f" ]; then printf 'OK   $LFS/%s\n' "$f"
  else printf 'FAIL $LFS/%s 缺失\n' "$f"; rc=1; fi
done
[ $rc -eq 0 ] || { echo "错误：Libstdc++ 关键文件缺失" >&2; exit 1; }
echo
echo "libstdc++ 共享库版本："
ls -l $LFS/usr/lib/libstdc++.so*
$LFS_TGT-readelf -d $LFS/usr/lib/libstdc++.so.6 | grep -E 'SONAME|NEEDED' | sed 's/^/  /'
echo
echo "头文件安装目录（--with-gxx-include-dir 的作用，须与 g++ 的搜索路径一致）："
ls -d $LFS/tools/$LFS_TGT/include/c++/$VER
echo "  头文件数：$(find $LFS/tools/$LFS_TGT/include/c++/$VER -type f | wc -l)"
echo
echo "验证 \$LFS_TGT-g++ 现在能编译并链接 C++ 程序（本节的实际目的）："
tmpd=$(mktemp -d)
cat > "$tmpd/t.cpp" <<'EOF'
#include <string>
#include <vector>
int main() { std::vector<std::string> v{"lfs"}; return v[0].size() == 3 ? 0 : 1; }
EOF
$LFS_TGT-g++ "$tmpd/t.cpp" -o "$tmpd/t" && echo "OK   C++ 程序编译链接成功"
$LFS_TGT-readelf -d "$tmpd/t" | grep NEEDED | sed 's/^/  /'
echo "g++ 实际使用的 C++ 头文件搜索路径："
echo | $LFS_TGT-g++ -x c++ -E -v - 2>&1 | sed -n '/#include <...> search starts here:/,/End of search list/p' | sed 's/^/  /'
rm -rf "$tmpd"
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
[ -d "$LFS/sources/$SRCDIR" ] && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR（含其中的 build 目录）"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"
echo "$LFS 占用：$(du -sh $LFS 2>/dev/null | cut -f1)"

echo
echo "===== §5.6 完成，结束时间：$(date -Is) ====="
