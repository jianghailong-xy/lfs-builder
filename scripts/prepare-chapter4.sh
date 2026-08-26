#!/usr/bin/env bash
# 手册 §4.2 / §4.3 / §4.4 的准备工作（在构建容器内以 root 执行，幂等）
#   §4.2 Creating a Limited Directory Layout in the LFS Filesystem
#   §4.3 Adding the LFS User（用户/组已在镜像里建好，这里做 $LFS 属主）
#   §4.4 Setting Up the Environment（lfs 用户的 .bash_profile / .bashrc）
# 只写 $LFS 与 /home/lfs，不触碰宿主机。
set -euo pipefail
export LC_ALL=C LANG=C

: "${LFS:=/mnt/lfs}"
[ -d "$LFS" ] || { echo "错误：$LFS 不存在" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "错误：$LFS 不是挂载点，镜像分区未传入容器" >&2; exit 1; }
id lfs >/dev/null 2>&1 || { echo "错误：容器内没有 lfs 用户" >&2; exit 1; }

echo "== §4.2 Creating a Limited Directory Layout =="
mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}
for i in bin lib sbin; do
  if [ -L $LFS/$i ]; then echo "已存在符号链接 $LFS/$i"; else ln -sv usr/$i $LFS/$i; fi
done
case $(uname -m) in
  x86_64) mkdir -pv $LFS/lib64 ;;
esac
mkdir -pv $LFS/tools

echo "== §4.3 Adding the LFS User（$LFS 属主移交 lfs） =="
chown -v lfs $LFS/{usr{,/*},var,etc,tools}
case $(uname -m) in
  x86_64) chown -v lfs $LFS/lib64 ;;
esac

echo "== §4.4 Setting Up the Environment =="
cat > /home/lfs/.bash_profile << "BASH_PROFILE_EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
BASH_PROFILE_EOF

cat > /home/lfs/.bashrc << "BASHRC_EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
BASHRC_EOF

cat >> /home/lfs/.bashrc << "MAKEFLAGS_EOF"
export MAKEFLAGS=-j$(nproc)
MAKEFLAGS_EOF

chown lfs:lfs /home/lfs/.bash_profile /home/lfs/.bashrc

# §4.4 Important：/etc/bash.bashrc 会污染 lfs 用户环境（仅容器内）
[ ! -e /etc/bash.bashrc ] || mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE

echo "== 结果 =="
ls -la $LFS
echo "--- /home/lfs/.bashrc ---"
cat /home/lfs/.bashrc
echo "§4.2/§4.3/§4.4 准备完成"
