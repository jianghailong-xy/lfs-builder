#!/usr/bin/env bash
# LFS 13.0-systemd §8.4 Iana-Etc-20260202
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.4.1 Installation of Iana-Etc 的命令序列（全部）：
#   cp -v services protocols /etc
# 本节没有补丁、没有 configure、没有编译步骤、没有测试套件——手册原文只有
# “For this package, we only need to copy the files into place:” 加上面这一条命令。
set -euo pipefail

PKG=iana-etc
VER=20260202
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §8.4 Iana-Etc-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Iana-Etc package provides data for network services and protocols."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 4.8 MB"
echo "手册存档：/workspace/docs/book/chapter08-iana-etc.html（宿主机 \$LFS_ROOT/docs/book/）"
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
echo "可用空间（手册本节要求 4.8 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 5 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 4.8MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§8.3 Man-pages-6.17）产物必须可用 -----"
rc=0
echo "1) §8.3 的安装结果（手册 §8.3.2 Contents：/usr/share/man 下的手册页）："
for f in /usr/share/man/man7/man-pages.7 /usr/share/man/man2/open.2 /usr/share/man/man3/printf.3; do
  if [ -s "$f" ]; then printf '   OK   %-36s（%s 字节）\n' "$f" "$(stat -c %s "$f")"
  else printf '   FAIL %s 缺失或为空（§8.3 未完成？）\n' "$f"; rc=1; fi
done
echo "   §8.3 手册命令 rm -v man3/crypt* 的效果（这两个页面应当没有被安装，"
echo "   由后面的 §8.28 Libxcrypt 提供）："
for f in /usr/share/man/man3/crypt.3 /usr/share/man/man3/crypt_r.3; do
  if [ -e "$f" ]; then printf '   INFO %s 存在（非本节关注点）\n' "$f"
  else printf '   OK   %s 未安装，符合 §8.3\n' "$f"; fi
done
echo "   /usr/share/man 下文件总数：$(find /usr/share/man -type f | wc -l)"
echo "2) §7.13.1 Cleaning 的结果（临时工具已并入 /usr，/tools 已删除）："
if [ -e /tools ]; then echo "   FAIL /tools 仍存在（§7.13.1 未完成？）"; rc=1
else echo "   OK   /tools 已不存在"; fi
echo "3) 本节直接依赖的工具（解包 + 复制）："
for t in tar gzip cp install rm mkdir md5sum grep awk sed find stat diff; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-8s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "   tar  版本：$(tar --version | sed -n 1p)"
echo "   gzip 版本：$(gzip --version | sed -n 1p)"
echo "4) 安装目标目录（手册 §8.4.2 Installed files：/etc/protocols 和 /etc/services）："
if [ -d /etc ]; then echo "   OK   /etc 存在（现有 $(find /etc -maxdepth 1 -type f | wc -l) 个顶层文件）"
else echo "   FAIL /etc 缺失"; rc=1; fi
echo "5) 源码目录（/sources 是宿主机 bind mount）："
if [ -d /sources ]; then echo "   OK   /sources 存在，共 $(find /sources -maxdepth 1 -type f | wc -l) 个文件"
else echo "   FAIL /sources 缺失"; rc=1; fi
if [ -f "/sources/$TARBALL" ]; then echo "   OK   /sources/$TARBALL 存在（$(stat -c %s "/sources/$TARBALL") 字节）"
else echo "   FAIL /sources/$TARBALL 缺失"; rc=1; fi
echo "6) §7.3 虚拟内核文件系统与 §7.6 基础文件："
for f in /dev/null /proc/self /sys /etc/passwd /etc/group; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "7) 本节安装前 /etc/services 与 /etc/protocols 的状态："
for f in /etc/services /etc/protocols; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在（%s 字节），本节的 cp 会覆盖它\n' "$f" "$(stat -c %s "$f")"
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
echo "手册原文：In Chapter 8 ... the packages are unpacked as root."
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "归档内容（全部条目）："
tar -tf "/sources/$TARBALL" | sed 's/^/  /'
echo "顶层内容："
ls -l | sed 's/^/  /'
echo "本节无补丁：手册 §8.4 只有一条 cp -v services protocols /etc；"
echo "  /sources 下也没有 iana-etc 相关补丁（匹配数：$(ls /sources | grep -ci 'iana.*patch')）。"
echo "本节无 configure、无编译：Iana-Etc 只是 IANA 官方 XML 注册表"
echo "  （service-names-port-numbers.xml、protocol-numbers.xml）经上游转换后的"
echo "  纯文本数据文件 services 与 protocols，随包直接提供，无需构建。"
echo "本节无测试套件：手册 §8.4 未给出任何测试命令，上游包内也不含测试目标。"
echo "  下方「安装后检查」为本项目自加的产物校验，不是手册要求的测试。"
echo

echo "----- 待安装数据文件概览 -----"
for f in services protocols; do
  echo "  $f：$(stat -c %s "$f") 字节，$(wc -l < "$f") 行"
done
echo "  services 前 5 行："
sed -n 1,5p services | sed 's/^/    /'
echo "  protocols 前 5 行："
sed -n 1,5p protocols | sed 's/^/    /'
echo

echo "================= 8.4.1. Installation of Iana-Etc ================="
echo "手册原文：For this package, we only need to copy the files into place:"
echo "手册命令：cp -v services protocols /etc"
cp -v services protocols /etc
echo "（set -e 生效：cp 若失败脚本立即中止，能走到这里即表示 cp 退出码为 0）"
echo

echo "----- 安装后检查（手册 §8.4.2 Contents of Iana-Etc） -----"
rc=0
echo "手册 §8.4.2 Installed files：/etc/protocols and /etc/services"
echo "1) 两个已安装文件存在且非空："
for f in /etc/protocols /etc/services; do
  if [ -s "$f" ]; then printf '   OK   %-16s %s 字节，%s 行\n' "$f" "$(stat -c %s "$f")" "$(wc -l < "$f")"
  else printf '   FAIL %s 缺失或为空\n' "$f"; rc=1; fi
done
echo "2) 与源码目录中的文件逐字节一致（cp 未截断/未改写）："
for f in services protocols; do
  if diff -q "/sources/$SRCDIR/$f" "/etc/$f" >/dev/null; then
    printf '   OK   /etc/%s 与 /sources/%s/%s 内容一致\n' "$f" "$SRCDIR" "$f"
  else
    printf '   FAIL /etc/%s 与源文件不一致\n' "$f"; rc=1
  fi
done
echo "3) 内容抽查 —— /etc/services（手册短描述：a mapping between friendly textual"
echo "   names for internet services, and their underlying assigned port numbers"
echo "   and protocol types）："
for e in 'ssh[[:space:]]\+22/tcp' 'domain[[:space:]]\+53/udp' 'http[[:space:]]\+80/tcp' 'https[[:space:]]\+443/tcp'; do
  line=$(grep -m1 "^$e" /etc/services || true)
  if [ -n "$line" ]; then printf '   OK   %s\n' "$line"
  else printf '   FAIL /etc/services 中未找到匹配 ^%s 的条目\n' "$e"; rc=1; fi
done
echo "4) 内容抽查 —— /etc/protocols（手册短描述：Describes the various DARPA Internet"
echo "   protocols that are available from the TCP/IP subsystem）："
for e in 'hopopt[[:space:]]\+0' 'icmp[[:space:]]\+1' 'tcp[[:space:]]\+6' 'udp[[:space:]]\+17'; do
  line=$(grep -m1 "^$e" /etc/protocols || true)
  if [ -n "$line" ]; then printf '   OK   %s\n' "$line"
  else printf '   FAIL /etc/protocols 中未找到匹配 ^%s 的条目\n' "$e"; rc=1; fi
done
echo "5) 格式可被 libc 的 getservbyname/getprotobyname 解析所需的基本结构："
echo "   （每条非注释行形如 name  value[/proto]  [aliases...]）"
bad_srv=$(grep -v '^[[:space:]]*#' /etc/services | grep -v '^[[:space:]]*$' \
          | grep -vc '^[^[:space:]]\+[[:space:]]\+[0-9]\+/[a-z]\+' || true)
bad_prt=$(grep -v '^[[:space:]]*#' /etc/protocols | grep -v '^[[:space:]]*$' \
          | grep -vc '^[^[:space:]]\+[[:space:]]\+[0-9]\+' || true)
echo "   /etc/services  非注释非空行：$(grep -v '^[[:space:]]*#' /etc/services | grep -vc '^[[:space:]]*$')，其中不符合上述形状的：$bad_srv"
echo "   /etc/protocols 非注释非空行：$(grep -v '^[[:space:]]*#' /etc/protocols | grep -vc '^[[:space:]]*$')，其中不符合上述形状的：$bad_prt"
[ "$bad_srv" -eq 0 ] || { echo "   FAIL /etc/services 存在格式异常行"; rc=1; }
[ "$bad_prt" -eq 0 ] || { echo "   FAIL /etc/protocols 存在格式异常行"; rc=1; }
echo "6) 属主与权限（cp 到 /etc 后应为 root:root，权限由 umask 0022 决定）："
ls -l /etc/services /etc/protocols | sed 's/^/     /'
for f in /etc/services /etc/protocols; do
  own=$(stat -c '%U:%G' "$f")
  if [ "$own" = "root:root" ]; then printf '   OK   %s 属主 %s\n' "$f" "$own"
  else printf '   FAIL %s 属主为 %s，应为 root:root\n' "$f" "$own"; rc=1; fi
done
echo "7) 安装位置确认（手册只要求这两个文件，不应有别的东西被写进 /etc）："
echo "   本节写入的文件：/etc/services、/etc/protocols"
echo "   源码目录里的 XML 原始注册表（service-names-port-numbers.xml、"
echo "   protocol-numbers.xml）按手册不安装，确认未出现在 /etc："
for f in /etc/service-names-port-numbers.xml /etc/protocol-numbers.xml; do
  if [ -e "$f" ]; then printf '   FAIL %s 不该存在\n' "$f"; rc=1
  else printf '   OK   %s 未安装，符合手册\n' "$f"; fi
done
echo "8) /etc 当前占用：$(du -sh /etc | cut -f1)"
[ $rc -eq 0 ] || { echo "错误：Iana-Etc 安装结果不符合手册要求" >&2; exit 1; }
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
echo "===== §8.4 完成，结束时间：$(date -Is) ====="
