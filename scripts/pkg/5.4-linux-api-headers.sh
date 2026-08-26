#!/usr/bin/env bash
# LFS 13.0-systemd §5.4 Linux-6.18.10 API Headers
# 在构建容器内以 lfs 用户、手册 §4.4 的干净环境执行（由 lfs-container.sh exec-lfs 调用）。
#
# 手册本节没有补丁、没有 configure、也没有规定任何测试套件：
#   make mrproper
#   make headers
#   find usr/include -type f ! -name '*.h' -delete
#   cp -rv usr/include $LFS/usr
# （手册注明不能用 headers_install 目标，因为它依赖 rsync。）
set -euo pipefail
set +h          # 手册 §4.4：关闭 bash 的路径哈希，保证新装的工具立即被找到

PKG=linux
VER=6.18.10
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §5.4 Linux-$VER API Headers ====="
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
[ "$LFS" = "/mnt/lfs" ] || { echo "错误：LFS 不是 /mnt/lfs" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点" >&2; exit 1; }
echo
echo "手册说明 headers_install 依赖 rsync，本环境的 rsync 情况："
command -v rsync || echo "  （无 rsync —— 正是手册改用 make headers 的原因）"
echo

echo "----- 前置检查：§5.2 Binutils / §5.3 GCC Pass 1 的产物必须可用 -----"
for t in ld as ar ranlib gcc g++; do
  f=$LFS/tools/bin/$LFS_TGT-$t
  [ -x "$f" ] || { echo "错误：缺少前置产物 $f" >&2; exit 1; }
  printf 'OK   %s\n' "$f"
done
$LFS_TGT-gcc --version | head -n1
LIMITS_H=$(dirname $($LFS_TGT-gcc -print-libgcc-file-name))/include/limits.h
[ -f "$LIMITS_H" ] && grep -q '#include_next' "$LIMITS_H" \
  && echo "OK   §5.3 生成的完整版内部 limits.h：$LIMITS_H" \
  || { echo "错误：§5.3 的完整版内部 limits.h 不可用" >&2; exit 1; }
echo "OK   \$LFS/usr 目录（§4.2 建立的目标布局）：$(ls -ld $LFS/usr)"
echo

cd $LFS/sources
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep " $TARBALL\$" md5sums
grep " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii：只用 tar 解包） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "内核自报版本：$(make -s kernelversion)"
echo "本节无补丁需要应用。"
echo

echo "----- 5.4.1 确认包内没有陈旧文件：make mrproper -----"
time make mrproper
echo

echo "----- 5.4.1 抽取用户可见的内核头文件：make headers -----"
echo "（手册：推荐的 headers_install 目标不可用，因为它需要 rsync；"
echo "  headers 先把头文件放到 ./usr，再手工复制到目标位置。）"
time make headers
echo
echo "make headers 产出的 ./usr/include 顶层内容："
ls -l usr/include
echo

echo "----- 5.4.1 删除非 .h 文件 -----"
echo "删除前 usr/include 下的非 .h 文件："
find usr/include -type f ! -name '*.h' | sed 's/^/  /'
find usr/include -type f ! -name '*.h' -delete
echo "删除后残留的非 .h 文件（应为空）："
find usr/include -type f ! -name '*.h' | sed 's/^/  /'
echo "usr/include 下 .h 文件数：$(find usr/include -type f -name '*.h' | wc -l)"
echo

echo "----- 5.4.1 安装到 \$LFS/usr -----"
cp -rv usr/include $LFS/usr
echo

echo "----- 本节测试：手册 §5.4 未规定任何测试套件 -----"
echo "手册 §5.4 只有 make mrproper / make headers / find / cp 四条命令，"
echo "既无 configure 也无 make check|test，因此本节无测试可跑（无失败项）。"
echo "改为执行 §5.4.2 Contents of Linux API Headers 的安装内容检查："
echo

echo "----- 5.4.2 内容检查：安装目录 -----"
rc=0
for d in asm asm-generic drm linux misc mtd rdma scsi sound video xen; do
  if [ -d "$LFS/usr/include/$d" ]; then
    printf 'OK   /usr/include/%-12s %5s 个 .h\n' "$d" "$(find $LFS/usr/include/$d -type f -name '*.h' | wc -l)"
  else
    printf 'FAIL /usr/include/%s 缺失\n' "$d"; rc=1
  fi
done
[ $rc -eq 0 ] || { echo "错误：§5.4.2 规定的安装目录不完整" >&2; exit 1; }
echo

echo "----- 5.4.2 内容检查：关键头文件与非 .h 残留 -----"
for f in linux/version.h asm/unistd.h asm-generic/unistd.h linux/limits.h; do
  [ -f "$LFS/usr/include/$f" ] && printf 'OK   /usr/include/%s\n' "$f" \
    || { printf 'FAIL /usr/include/%s 缺失\n' "$f"; exit 1; }
done
echo
echo "\$LFS/usr/include 下的非 .h 文件（应为空）："
find $LFS/usr/include -type f ! -name '*.h' | sed 's/^/  /'
[ -z "$(find $LFS/usr/include -type f ! -name '*.h')" ] \
  && echo "  （空，符合 find ... -delete 的预期）" \
  || { echo "错误：\$LFS/usr/include 内仍有非 .h 文件" >&2; exit 1; }
echo
echo "安装的头文件总数：$(find $LFS/usr/include -type f -name '*.h' | wc -l)"
echo "\$LFS/usr/include 占用：$(du -sh $LFS/usr/include | cut -f1)"
echo
echo "linux/version.h 内容（应与 $VER 对应）："
cat $LFS/usr/include/linux/version.h
echo
echo "\$LFS/usr/include 顶层："
ls -l $LFS/usr/include
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd $LFS/sources
rm -rf "$SRCDIR"
ls -d $LFS/sources/$SRCDIR 2>/dev/null && { echo "错误：源码目录未清理"; exit 1; }
echo "已删除 $LFS/sources/$SRCDIR"
echo "$LFS/sources 下的解包残留（应为空）："
find $LFS/sources -maxdepth 1 -type d ! -path $LFS/sources | sed 's/^/  /' || true
echo "$LFS/sources 文件数：$(find $LFS/sources -maxdepth 1 -type f | wc -l)"

echo
echo "===== §5.4 完成，结束时间：$(date -Is) ====="
