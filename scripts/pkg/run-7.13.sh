#!/usr/bin/env bash
# 宿主机侧驱动：LFS 13.0-systemd §7.13 Cleaning up and Saving the Temporary System
#
#   1. 在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）
#   2. 在 chroot 内执行 §7.13.1 Cleaning（scripts/pkg/7.13-cleanup.sh），
#      其中包含第 5–7 章全部产物的清理前核对与清理后复核
#   3. 退出 chroot 后按手册 §7.13.2 Backup 卸载虚拟内核文件系统并打包临时系统
#   4. 打包完成后重新挂载虚拟内核文件系统，让第 8 章可以直接继续
#
# 完整输出落到 logs/packages/7.13-cleanup-and-backup.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LFS=$LFS_ROOT/mnt/lfs                 # 宿主机上的 $LFS（容器内同为 /mnt/lfs）
LOG=$LFS_ROOT/logs/packages/7.13-cleanup-and-backup.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
BACKUP_DIR=${BACKUP_DIR:-$LFS_ROOT/backups}
BACKUP=$BACKUP_DIR/lfs-temp-tools-13.0-systemd.tar.xz
CONTAINER=${CONTAINER:-lfs-build}
SKIP_BACKUP=${SKIP_BACKUP:-0}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages" "$BACKUP_DIR"

# ---------------------------------------------------------------- 1 -------
echo "===== 第 7 章 chroot 环境准备（§7.2/§7.3/§7.5/§7.6，幂等）====="
{ echo "##### chroot 准备 —— 宿主机时间：$(date -Is)"; echo; } >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，不继续 §7.13；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §7.13 Cleaning up and Saving the Temporary System"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### §7.13.1 在 chroot 内执行（手册 §7.4 环境），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 $LFS = loop 挂载的镜像根分区"
  echo "##### §7.13.2 在 chroot 之外、宿主机上执行"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，完整输出见 $PREP_LOG"
  echo
} > "$LOG"

# ---------------------------------------------------------------- 2 -------
echo "===== §7.13.1 Cleaning（chroot 内）====="
docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/7.13-cleanup.sh >> "$LOG" 2>&1
rc=$?
echo "##### §7.13.1 exec 退出码：$rc" >> "$LOG"
echo "§7.13.1 退出码：$rc（日志：$LOG）"
if [ $rc -ne 0 ]; then
  echo "§7.13.1 失败，不进行 §7.13.2 备份" >&2
  exit $rc
fi

# ---------------------------------------------------------------- 3 -------
{
echo
echo "================= 7.13.2. Backup ================="
echo "##### 宿主机时间：$(date -Is)"
echo "手册原文：At this point the essential programs and libraries have been created and"
echo "  your current LFS system is in a good state. Your system can now be backed up for"
echo "  later reuse. ... All the remaining steps in this section are optional."
echo "手册原文：The following steps are performed from outside the chroot environment."
echo "  ... to get access to file system locations outside of the chroot environment to"
echo "  store/read the backup archive, which ought not be placed within the \$LFS hierarchy."
echo "手册 Important：All of the following instructions are executed by root on your host"
echo "  system. ... Whenever commands are to be executed by root, make sure you have set LFS."
echo
echo "本项目对应关系（见 docs/conventions.md）："
echo "  手册的「exit 退出 chroot」   → 本项目每条 chroot 命令都是非交互的一次性进入，"
echo "                                 §7.13.1 的 chroot 进程已在上一步正常退出。"
echo "  手册的「host system 上的 root」→ 本脚本，运行在宿主机 /root/lfs 下。"
echo "  \$LFS                        → $LFS"
echo "  手册的 \$HOME/lfs-temp-tools-13.0-systemd.tar.xz"
echo "                               → $BACKUP"
echo "                                 （手册允许：Replace \$HOME by a directory of your"
echo "                                 choice；该目录在 \$LFS 之外，符合手册要求）"
echo
echo "----- 备份前确认 \$LFS 与磁盘空间 -----"
echo "LFS=$LFS"
if ! mountpoint -q "$LFS"; then echo "错误：$LFS 不是挂载点"; exit 1; fi
echo "手册要求：Make sure you have at least 1 GB free disk space ... on the file system"
echo "  containing the directory where you create the backup archive."
df -hT "$BACKUP_DIR" | sed 's/^/  /'
avail_mb=$(df -Pm "$BACKUP_DIR" | tail -n1 | awk '{print $4}')
if [ "$avail_mb" -lt 1024 ]; then echo "错误：$BACKUP_DIR 可用 ${avail_mb}MB 少于 1 GB"; exit 1; fi
echo "  OK   可用 ${avail_mb} MB"
echo
echo "----- 卸载虚拟内核文件系统（手册 §7.13.2） -----"
echo "手册命令：mountpoint -q \$LFS/dev/shm && umount \$LFS/dev/shm"
echo "          umount \$LFS/dev/pts"
echo "          umount \$LFS/{sys,proc,run,dev}"
echo "卸载前 findmnt -R \$LFS："
findmnt -R "$LFS" | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
mountpoint -q $LFS/dev/shm && umount -v $LFS/dev/shm
umount -v $LFS/dev/pts
umount -v $LFS/{sys,proc,run,dev}
echo
echo "----- 项目特有的一处偏离：\$LFS/sources -----"
echo "手册里 \$LFS/sources 是根分区上的普通目录，所以备份天然包含源码包（手册："
echo "  Since the sources are located under \$LFS, they are included in the backup archive"
echo "  as well, so they do not need to be downloaded again）。"
echo "本项目按 docs/conventions.md 把宿主机的 /root/lfs/sources 以 bind mount 的形式"
echo "  挂到 \$LFS/sources，源码包并不在镜像里，重建镜像也不会丢失，因此："
echo "    · 打包时用 tar --exclude=./sources 排除该挂载点（否则 604 MB 已压缩的 tarball"
echo "      会被再压一遍，既拖慢打包又毫无收益）；"
echo "    · 手册「不必重新下载」的效果由宿主机上常驻的 /root/lfs/sources 直接提供；"
echo "    · 相应地，§7.13.3 Restore 也必须改用先卸载 sources 再清空 \$LFS 的顺序，"
echo "      否则手册的 rm -rf ./* 会穿过 bind mount 删掉宿主机上的源码缓存。"
echo "      可执行的还原步骤见 docs/checkpoint-ch5-7.md。"
echo "  卸载 \$LFS/sources（bind mount 由 docker run -v 建立，稍后随 chroot.sh prep"
echo "  所依赖的容器一并保持；这里只在打包期间让它离开 \$LFS 视图）："
TAR_EXCLUDE=()
if mountpoint -q "$LFS/sources"; then
  if umount -v "$LFS/sources"; then
    echo "  OK   已卸载，\$LFS/sources 现在是根分区上的一个空目录，"
    echo "       打包会把它作为空目录收进归档（还原后仍是可用的挂载点）。"
  else
    echo "  警告：卸载失败，改用 tar --exclude=./sources/* 兜底（保留目录项本身）"
    TAR_EXCLUDE=(--exclude=./sources/*)
  fi
else
  echo "  （未挂载，无需卸载）"
fi
echo
echo "卸载后 findmnt -R \$LFS（应只剩根分区本身）："
findmnt -R "$LFS" | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
n=$(findmnt -R -n "$LFS" | wc -l)
if [ "$n" -ne 1 ]; then echo "错误：\$LFS 下仍有 $((n-1)) 个子挂载，拒绝打包"; exit 1; fi
echo "  OK   \$LFS 下只剩 ext4 根分区本身，可以安全打包"
echo
echo "----- 打包（手册 §7.13.2） -----"
echo "手册命令：cd \$LFS"
echo "          tar -cJpf \$HOME/lfs-temp-tools-13.0-systemd.tar.xz ."
echo "手册 Note：Because the backup archive is compressed, it takes a relatively long time"
echo "  (over 10 minutes) even on a reasonably fast system."
echo "本次实际执行（仅两处已说明的适配：输出路径、打包前卸掉 bind mount 的 ./sources；"
echo "  另设 XZ_OPT=-T0 让 xz 用满 $(nproc) 个核，只影响耗时不影响归档格式）："
echo "  cd $LFS && XZ_OPT=-T0 tar -cJpf $BACKUP ${TAR_EXCLUDE[*]:-} ."
echo "待打包内容（\$LFS 顶层）："
ls -la "$LFS" | sed 's/^/  /'
echo "待打包大小：$(du -sh --exclude="*/sources" "$LFS" | cut -f1)（不含 ./sources）"
rm -f "$BACKUP"
start=$(date +%s)
cd "$LFS" || exit 1
XZ_OPT=-T0 tar -cJpf "$BACKUP" "${TAR_EXCLUDE[@]}" .
tar_rc=$?
end=$(date +%s)
echo "tar 退出码：$tar_rc，耗时 $((end-start)) 秒"
[ $tar_rc -eq 0 ] || { echo "错误：打包失败"; exit 1; }
echo
echo "----- 备份校验 -----"
ls -lh "$BACKUP" | sed 's/^/  /'
echo "  xz 完整性校验（xz -t）："
xz -t "$BACKUP" && echo "    OK   压缩流完好"
echo "  归档条目数：$(tar -tJf "$BACKUP" | wc -l)"
echo "  归档顶层内容："
tar -tJf "$BACKUP" | awk -F/ 'NF<=2 && $2!=""{print $2}' | sort -u | sed 's/^/    /'
echo "  抽样确认关键文件在归档内："
for f in ./usr/bin/gcc ./usr/bin/bash ./usr/lib/libc.so.6 ./etc/passwd ./usr/bin/perl \
         ./usr/bin/python3 ./usr/bin/mount; do
  if tar -tJf "$BACKUP" "$f" >/dev/null 2>&1; then printf '    OK   %s\n' "$f"
  else printf '    FAIL %s 不在归档内\n' "$f"; fi
done
echo "  确认 /tools 未被打包（§7.13.1 已删除）："
if tar -tJf "$BACKUP" | grep -q '^\./tools/'; then echo "    FAIL 归档里仍有 ./tools"; else echo "    OK   归档中无 ./tools"; fi
echo "  确认 ./sources 未被打包（本项目适配）："
if tar -tJf "$BACKUP" | grep -q '^\./sources/.'; then echo "    INFO 归档里含 ./sources 内容"; else echo "    OK   归档中无 ./sources 内容"; fi
echo "  校验和："
sha256sum "$BACKUP" | tee "$BACKUP.sha256" | sed 's/^/    /'
echo
} >> "$LOG" 2>&1
backup_rc=$?
echo "§7.13.2 退出码：$backup_rc"

# ---------------------------------------------------------------- 4 -------
{
echo "================= 备份后恢复挂载（供第 8 章继续） ================="
echo "手册 §7.13.2 Note：If continuing to chapter 8, don't forget to reenter the chroot"
echo "  environment as explained in the Important box below."
echo "手册 Important：remember to check that the virtual file systems are still mounted"
echo "  (findmnt | grep \$LFS should show at least \$LFS/dev, \$LFS/proc, and \$LFS/sys as"
echo "  mounted). If they are not mounted, remount them now as described in Section 7.3."
echo
echo "本项目做法：\$LFS/sources 的 bind mount 与虚拟内核文件系统都由容器与"
echo "  scripts/chroot.sh prep 负责重建 —— 重启容器即可恢复 -v 建立的 sources 挂载，"
echo "  chroot.sh prep 再幂等地补齐 §7.3 的 dev/pts/proc/sys/run。"
} >> "$LOG" 2>&1

echo "===== 恢复 \$LFS 下的各挂载点 ====="
if ! mountpoint -q "$LFS/sources"; then
  echo "重启容器以恢复 docker -v 建立的 sources bind mount ..." | tee -a "$LOG"
  docker restart "$CONTAINER" >> "$LOG" 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    mountpoint -q "$LFS/sources" && break
    docker inspect -f '{{.State.Running}}' "$CONTAINER" >/dev/null 2>&1 || true
    sleep 1
  done
fi
if ! mountpoint -q "$LFS/sources"; then
  echo "容器重启后 sources 仍未挂载，直接在宿主机上补 bind mount ..." | tee -a "$LOG"
  mount -v --bind "$LFS_ROOT/sources" "$LFS/sources" >> "$LOG" 2>&1
fi
{
  echo "##### 恢复挂载 —— 宿主机时间：$(date -Is)"
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
re_rc=$?
{
echo "chroot.sh prep（恢复挂载）退出码：$re_rc"
echo "恢复后 findmnt -R \$LFS："
findmnt -R "$LFS" | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
for mp in "$LFS/dev" "$LFS/dev/pts" "$LFS/proc" "$LFS/sys" "$LFS/run" "$LFS/sources"; do
  if mountpoint -q "$mp"; then printf '  OK   %s 已挂载\n' "$(echo "$mp" | sed "s|$LFS|\$LFS|")"
  else printf '  FAIL %s 未挂载\n' "$(echo "$mp" | sed "s|$LFS|\$LFS|")"; fi
done
echo "  \$LFS/sources 文件数：$(find "$LFS/sources" -maxdepth 1 -type f | wc -l)"
echo
echo "===== §7.13 全部完成，宿主机时间：$(date -Is) ====="
} >> "$LOG" 2>&1

echo "恢复挂载退出码：$re_rc"
echo "日志：$LOG"
[ $backup_rc -eq 0 ] && [ $re_rc -eq 0 ]
