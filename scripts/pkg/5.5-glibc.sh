#!/usr/bin/env bash
# LFS 13.0-systemd §5.5 Glibc-2.43
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册 §5.5.1 的命令序列：
#   case $(uname -m) in ... x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
#                                   ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3 ;; esac
#   patch -Np1 -i ../glibc-fhs-1.patch
#   mkdir -v build; cd build
#   echo "rootsbindir=/usr/sbin" > configparms
#   ../configure --prefix=/usr --host=$LFS_TGT --build=$(../scripts/config.guess) \
#                --disable-nscd libc_cv_slibdir=/usr/lib --enable-kernel=5.4
#   make
#   make DESTDIR=$LFS install
#   sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
#   接着是手册规定的 6 项工具链 sanity check（本节没有 make check 测试套件）。
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=glibc
VER=2.43
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
FHS_PATCH=glibc-fhs-1.patch

echo "===== LFS 13.0-systemd §5.5 Glibc-$VER ====="
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
[ "$(whoami)" = "lfs" ] || { echo "错误：必须以 lfs 用户构建（手册 §5.5 的 make DESTDIR 警告）" >&2; exit 1; }
[ "$LFS" = "/mnt/lfs" ] || { echo "错误：LFS 不是 /mnt/lfs" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点" >&2; exit 1; }
echo "可用空间（手册要求 890 MB）："
df -h "$LFS" | tail -n1
echo

echo "----- 前置检查：§5.2/§5.3/§5.4 的产物必须可用 -----"
for t in ld as ar ranlib gcc g++; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少前置产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS_TGT-gcc --version | head -n1
$LFS_TGT-ld --version | head -n1
for h in linux/version.h asm/unistd.h asm-generic/unistd.h; do
  [ -f "$LFS/usr/include/$h" ] || { echo "错误：§5.4 的内核头文件缺失：$LFS/usr/include/$h" >&2; exit 1; }
  printf 'OK   §5.4 内核头文件 /usr/include/%s\n' "$h"
done
echo "OK   §5.4 头文件总数：$(find $LFS/usr/include -type f -name '*.h' | wc -l)"
echo
echo "本节需要但宿主可能缺失的可选程序（手册说明 msgfmt 缺失无害）："
command -v msgfmt || echo "  msgfmt：不存在 —— 手册明确说明此 configure WARNING 无害"
command -v bison && bison --version | head -n1
command -v python3 && python3 --version
command -v makeinfo && makeinfo --version | head -n1
echo

cd $LFS/sources
echo "----- 源码包与补丁校验（md5sums，手册 §3.1） -----"
grep -E " ($TARBALL|$FHS_PATCH)\$" md5sums
grep -E " ($TARBALL|$FHS_PATCH)\$" md5sums | md5sum -c -
echo

echo "----- 5.5.1 LSB 兼容性符号链接（x86_64 分支） -----"
echo "执行前 \$LFS/lib64："
ls -l $LFS/lib64
case $(uname -m) in
  i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
  ;;
  x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
          ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
  ;;
esac
echo "执行后 \$LFS/lib64（此时目标还不存在，是预期中的悬空链接，Glibc 安装后即生效）："
ls -l $LFS/lib64
echo

echo "----- 解包（手册 iii：只用 tar 解包） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "Glibc 自报版本：$(cat version.h 2>/dev/null | grep VERSION || head -n1 version.h 2>/dev/null || echo '(见下)')"
grep -m1 'define VERSION' version.h || true
echo

echo "----- 5.5.1 应用 FHS 补丁（/var/db -> FHS 合规位置） -----"
patch -Np1 -i ../$FHS_PATCH
echo

echo "----- 5.5.1 在专用 build 目录中构建（Glibc 文档要求） -----"
mkdir -v build
cd       build
echo "构建目录：$PWD"
echo

echo "----- 5.5.1 configparms：把 ldconfig / sln 装进 /usr/sbin -----"
echo "rootsbindir=/usr/sbin" > configparms
cat configparms
echo

echo "----- 5.5.1 configure -----"
echo "build 三元组（../scripts/config.guess）：$(../scripts/config.guess)"
time ../configure                          \
      --prefix=/usr                        \
      --host=$LFS_TGT                      \
      --build=$(../scripts/config.guess)   \
      --disable-nscd                       \
      libc_cv_slibdir=/usr/lib             \
      --enable-kernel=5.4
echo
echo "configure 的 WARNING 汇总（手册：msgfmt 缺失无害）："
grep -i 'WARNING' config.log 2>/dev/null | sort -u | head -n 20 || true
echo

echo "----- 5.5.1 编译：make -----"
time make
echo

echo "----- 5.5.1 安装：make DESTDIR=\$LFS install -----"
echo "安装前再次确认身份与 DESTDIR（手册 Warning：以 root 或 LFS 未设置会毁掉宿主系统）："
echo "  whoami=$(whoami)  DESTDIR=\$LFS=$LFS"
[ "$(whoami)" = "lfs" ] && [ "$LFS" = "/mnt/lfs" ] || { echo "错误：安装前置条件不满足" >&2; exit 1; }
time make DESTDIR=$LFS install
echo

echo "----- 5.5.1 修正 ldd 脚本里硬编码的 loader 路径 -----"
echo "修正前：$(grep '^RTLDLIST=' $LFS/usr/bin/ldd)"
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo "修正后：$(grep '^RTLDLIST=' $LFS/usr/bin/ldd)"
echo

echo "================= 本节测试 ================="
echo "手册 §5.5 没有规定任何测试套件（无 make check / make test）——"
echo "交叉编译阶段的 Glibc 无法在宿主上运行测试。手册在本节规定的是 6 项"
echo "工具链 sanity check，下面逐项执行，任何一项不符即视为失败并中止。"
echo

echo "----- sanity 0：生成 dummy.log -----"
echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
echo "OK   已生成 a.out 与 dummy.log（$(wc -l < dummy.log) 行）"
echo

fail=0
check() { # check <编号> <说明> <期望> <实际>
  local n="$1" desc="$2" exp="$3" act="$4"
  echo "----- sanity $n：$desc -----"
  echo "实际输出："; printf '%s\n' "$act" | sed 's/^/  /'
  if [ "$act" = "$exp" ]; then
    echo "结果：PASS（与手册期望输出完全一致）"
  else
    echo "期望输出："; printf '%s\n' "$exp" | sed 's/^/  /'
    echo "结果：FAIL"; fail=1
  fi
  echo
}

A1=$(readelf -l a.out | grep ': /lib' || true)
check 1 "程序解释器路径（readelf -l a.out | grep ': /lib'）" \
  "      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]" "$A1"
case "$A1" in
  *"$LFS"*) echo "错误：解释器路径里出现了 $LFS，不符合手册要求" >&2; fail=1 ;;
  *) echo "附加确认：解释器路径中不含 $LFS（手册强调的一点）"; echo ;;
esac

A2=$(grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log || true)
check 2 "启动文件（grep -E -o \"\$LFS/lib.*/S?crt[1in].*succeeded\"）" \
  "/mnt/lfs/lib/../lib/Scrt1.o succeeded
/mnt/lfs/lib/../lib/crti.o succeeded
/mnt/lfs/lib/../lib/crtn.o succeeded" "$A2"

A3=$(grep -B3 "^ $LFS/usr/include" dummy.log || true)
check 3 "头文件搜索路径（grep -B3 \"^ \$LFS/usr/include\"）" \
  "#include <...> search starts here:
 /mnt/lfs/tools/lib/gcc/x86_64-lfs-linux-gnu/15.2.0/include
 /mnt/lfs/tools/lib/gcc/x86_64-lfs-linux-gnu/15.2.0/include-fixed
 /mnt/lfs/usr/include" "$A3"

A4=$(grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\n|g' || true)
check 4 "链接器搜索路径（grep 'SEARCH.*/usr/lib' | sed 's|; |\\n|g'）" \
  'SEARCH_DIR("=/mnt/lfs/tools/x86_64-lfs-linux-gnu/lib64")
SEARCH_DIR("=/usr/local/lib64")
SEARCH_DIR("=/lib64")
SEARCH_DIR("=/usr/lib64")
SEARCH_DIR("=/mnt/lfs/tools/x86_64-lfs-linux-gnu/lib")
SEARCH_DIR("=/usr/local/lib")
SEARCH_DIR("=/lib")
SEARCH_DIR("=/usr/lib");' "$A4"

A5=$(grep "/lib.*/libc.so.6 " dummy.log || true)
check 5 "使用正确的 libc（grep \"/lib.*/libc.so.6 \"）" \
  "attempt to open /mnt/lfs/usr/lib/libc.so.6 succeeded" "$A5"

A6=$(grep found dummy.log || true)
check 6 "使用正确的动态链接器（grep found）" \
  "found ld-linux-x86-64.so.2 at /mnt/lfs/usr/lib/ld-linux-x86-64.so.2" "$A6"

echo "----- sanity check 汇总 -----"
if [ $fail -ne 0 ]; then
  echo "结论：有 sanity check 未通过 —— 手册要求在解决之前不得继续后续包。"
  echo "保留构建目录 $PWD 以供排查。"
  exit 1
fi
echo "结论：手册 §5.5 规定的 6 项 sanity check 全部 PASS，无意外失败。"
echo

echo "----- 5.5.1 清理测试文件 -----"
rm -v a.out dummy.log
echo

echo "----- 安装结果检查（关键文件） -----"
rc=0
for f in usr/lib/libc.so.6 usr/lib/ld-linux-x86-64.so.2 usr/lib/libm.so.6 \
         usr/lib/libc.so usr/lib/crt1.o usr/lib/crti.o usr/lib/crtn.o \
         usr/bin/ldd usr/sbin/ldconfig usr/sbin/sln usr/include/stdio.h; do
  if [ -e "$LFS/$f" ]; then printf 'OK   $LFS/%s\n' "$f"
  else printf 'FAIL $LFS/%s 缺失\n' "$f"; rc=1; fi
done
[ $rc -eq 0 ] || { echo "错误：Glibc 关键文件缺失" >&2; exit 1; }
echo
echo "ldconfig / sln 确实在 /usr/sbin（configparms 的作用）："
ls -l $LFS/usr/sbin/ldconfig $LFS/usr/sbin/sln
echo
echo "\$LFS/lib64 中的兼容链接现在指向真实文件："
ls -l $LFS/lib64
for l in ld-linux-x86-64.so.2 ld-lsb-x86-64.so.3; do
  [ -e "$LFS/lib64/$l" ] && printf 'OK   $LFS/lib64/%s 可解析\n' "$l" \
    || { printf 'FAIL $LFS/lib64/%s 仍是悬空链接\n' "$l"; exit 1; }
done
echo
echo "FHS 补丁效果（不应存在 /var/db）："
[ -d "$LFS/var/db" ] && { echo "FAIL 仍存在 \$LFS/var/db"; exit 1; } || echo "OK   \$LFS/var/db 不存在"
echo
echo "Glibc 版本自述："
$LFS_TGT-gcc -print-file-name=libc.so.6
strings $LFS/usr/lib/libc.so.6 2>/dev/null | grep -m1 'GNU C Library' || true
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
echo "===== §5.5 完成，结束时间：$(date -Is) ====="
