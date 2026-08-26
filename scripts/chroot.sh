#!/usr/bin/env bash
# LFS 13.0-systemd 第 7 章 chroot 环境管理（在构建容器内以 root 执行）
#
#   chroot.sh prep            手册 §7.2 / §7.3（chroot 外）+ §7.5 / §7.6（chroot 内），幂等
#   chroot.sh run <脚本路径>  把脚本送进 chroot 执行（手册 §7.4 的 env -i 环境）
#   chroot.sh status          只读查看 chroot 前置状态
#
# 约定见 docs/conventions.md：容器内 $LFS=/mnt/lfs，源码在 $LFS/sources，
# 日志由宿主机侧 run-*.sh 收集到 $LFS_ROOT/logs/。
set -euo pipefail
export LC_ALL=C LANG=C

LFS="${LFS:-/mnt/lfs}"

die() { echo "错误：$*" >&2; exit 1; }

require_root_and_lfs() {
  [ "$(id -u)" -eq 0 ] || die "必须以 root 执行（手册 §7.2 Note：本书其余部分均以 root 身份执行）"
  [ -n "$LFS" ] || die "LFS 未设置"
  mountpoint -q "$LFS" || die "$LFS 不是挂载点（镜像根分区未挂载）"
}

# ---------------------------------------------------------------- §7.2 -----
sec_7_2_changing_owner() {
  echo "================= 7.2. Changing Ownership ================="
  echo "手册原文：Currently, the whole directory hierarchy in \$LFS is owned by the user"
  echo "  lfs, a user that exists only on the host system. If the directories and files"
  echo "  under \$LFS are kept as they are, they will be owned by a user ID without a"
  echo "  corresponding account. This is dangerous because a user account created later"
  echo "  could get this same user ID and would own all the files under \$LFS, thus"
  echo "  exposing these files to possible malicious manipulation."
  echo "手册命令："
  echo "  chown --from lfs -R root:root \$LFS/{usr,var,etc,tools}"
  echo "  case \$(uname -m) in"
  echo "    x86_64) chown --from lfs -R root:root \$LFS/lib64 ;;"
  echo "  esac"
  echo "执行前 \$LFS 顶层属主："
  ls -la "$LFS" | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
  echo "  容器内 lfs 用户：$(id lfs)"
  # 手册这条命令写死了 $LFS/tools，但 §7.13.1 Cleaning 会执行 rm -rf /tools。
  # 本函数是幂等的、第 8 章每次进入 chroot 前都会再跑一遍，因此在 §7.13 之后
  # $LFS/tools 必然不存在，原样执行会让 chown 报 "cannot access" 而中止。
  # 故只对当前实际存在的目标执行手册的 chown，并把跳过的目标明确打出来。
  local targets=() skipped=()
  for d in usr var etc tools; do
    if [ -e "$LFS/$d" ]; then targets+=("$LFS/$d"); else skipped+=("\$LFS/$d"); fi
  done
  case $(uname -m) in
    x86_64) [ -e "$LFS/lib64" ] && targets+=("$LFS/lib64") || skipped+=("\$LFS/lib64") ;;
  esac
  if [ ${#skipped[@]} -gt 0 ]; then
    echo "  跳过不存在的目标：${skipped[*]}"
    echo "    （\$LFS/tools 在手册 §7.13.1 \"rm -rf /tools\" 之后就不存在了，属预期）"
  fi
  echo "  实际执行：chown --from lfs -R root:root ${targets[*]}"
  chown --from lfs -R root:root "${targets[@]}"
  echo "执行后 \$LFS 顶层属主："
  ls -la "$LFS" | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
  echo "校验：上述目标下不应再有属主为 lfs(uid $(id -u lfs)) 的文件"
  local left
  left=$(find "${targets[@]}" -uid "$(id -u lfs)" 2>/dev/null | head -n5)
  if [ -n "$left" ]; then
    echo "$left" | sed 's/^/  残留：/'
    die "仍有文件属主为 lfs"
  fi
  echo "  OK   无 lfs 属主残留（\$LFS/sources 是宿主机 bind mount，不在手册的 chown 范围内）"
  echo
}

# ---------------------------------------------------------------- §7.3 -----
mnt_if_needed() {   # <描述> <mountpoint> <mount 命令...>
  local desc=$1 mp=$2; shift 2
  if mountpoint -q "$mp"; then
    echo "  已挂载，跳过：$desc -> $(echo "$mp" | sed "s|$LFS|\$LFS|")"
  else
    echo "  手册命令：$*"
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# devpts 的 ptmx 多路复用器必须对非 root 可开——这是手册 §7.3.2 那句 "mode=0620 ...
# to satisfy the requirements of grantpt()" 想要的效果，但它在**容器里**默认拿不到。
#
# 为什么容器里会坏（这不是手册的错，是宿主 /dev 形态不同）：
#   - 真实宿主上 /dev 是 devtmpfs，/dev/ptmx 是内核建的真字符设备 (5,2)，权限 0666，
#     打开它会去「默认 devpts 实例」分配 pty，谁都能开；
#   - 容器（Docker）里 /dev/ptmx 是**符号链接** -> pts/ptmx。手册 §7.3.1 又要求把宿主
#     /dev 原样 bind 进 $LFS，于是 chroot 内 /dev/ptmx 也是这个符号链接，实际打开的是
#     $LFS/dev/pts/ptmx；
#   - 而手册 §7.3.2 的挂载命令只给了 gid=5,mode=0620，devpts 的 ptmxmode 取默认值 000，
#     所以 $LFS/dev/pts/ptmx 是 c---------。root 无视权限位照样能开，**非 root 开不了**。
#
# 后果（本项目实际踩到）：第 8 章里凡是手册要求「以非特权用户 tester 运行」的测试，只要
# 用到 Expect/DejaGnu 的 spawn（GCC 测试套件每个用例都要 spawn 编译器），就会全部报
# "The system has no more ptys." / "spawn failed" 而瞬间失败——§8.30 GCC 第一次跑出
# 245730 个 FAIL、整套只花 126 秒，就是这个原因，而不是编译器有问题。
#
# 修法：把 ptmxmode 设成 0666，与真实宿主上 /dev/ptmx 的权限一致。gid=5 与 mode=0620
# （管的是 pty **从设备** /dev/pts/N，也就是 grantpt() 关心的那个）保持手册原值不变。
ensure_ptmx_usable() {
  local ptmx="$LFS/dev/pts/ptmx" mode
  echo "  ---- ptmx 可用性（手册 §7.3.2 的 grantpt() 前提，在容器内需要补一个挂载选项）"
  echo "    \$LFS/dev/ptmx      : $(ls -ld "$LFS/dev/ptmx" 2>&1 | sed 's/  */ /g')"
  if [ ! -e "$ptmx" ]; then
    echo "    \$LFS/dev/pts/ptmx : 不存在，跳过（该 devpts 实例未提供 ptmx 节点）"
    return 0
  fi
  mode=$(stat -c %a "$ptmx")
  echo "    \$LFS/dev/pts/ptmx : mode=$mode $(ls -l "$ptmx" | sed 's/  */ /g')"
  if [ "$mode" = 666 ]; then
    echo "    已是 0666，无需处理"
  else
    echo "    手册命令之外的一条补救（原因见 scripts/chroot.sh 中本函数上方的注释）："
    echo "      mount -o remount,gid=5,mode=0620,ptmxmode=0666 \$LFS/dev/pts"
    mount -o remount,gid=5,mode=0620,ptmxmode=0666 "$LFS/dev/pts"
    mode=$(stat -c %a "$ptmx")
    echo "    remount 后 mode=$mode"
  fi
  [ "$(stat -c %a "$ptmx")" = 666 ] || die "\$LFS/dev/pts/ptmx 权限仍不是 0666，非 root 无法分配 pty"
  echo "    OK   ptmx 对非 root 可开（第 8 章 tester 身份的测试依赖它）"
}

sec_7_3_kernfs() {
  echo "================= 7.3. Preparing Virtual Kernel File Systems ================="
  echo "手册原文：Applications running in userspace utilize various file systems created"
  echo "  by the kernel to communicate with the kernel itself. ... These file systems must"
  echo "  be mounted in the \$LFS directory tree so the applications can find them in the"
  echo "  chroot environment."
  echo "手册命令：mkdir -pv \$LFS/{dev,proc,sys,run}"
  mkdir -pv $LFS/{dev,proc,sys,run}
  echo
  echo "----- 7.3.1. Mounting and Populating /dev -----"
  echo "手册原文：the only host-agnostic way to populate the \$LFS/dev directory is by bind"
  echo "  mounting the host system's /dev directory."
  mnt_if_needed "bind /dev" "$LFS/dev" mount -v --bind /dev "$LFS/dev"
  echo
  echo "----- 7.3.2. Mounting Virtual Kernel File Systems -----"
  echo "手册对 devpts 选项的说明：gid=5 使 devpts 创建的设备节点属于 GID 5（稍后的 tty 组）；"
  echo "  mode=0620 使其权限为 0620，满足 grantpt() 的要求。"
  mnt_if_needed "devpts" "$LFS/dev/pts" mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
  ensure_ptmx_usable
  mnt_if_needed "proc"   "$LFS/proc"    mount -vt proc   proc   "$LFS/proc"
  mnt_if_needed "sysfs"  "$LFS/sys"     mount -vt sysfs  sysfs  "$LFS/sys"
  mnt_if_needed "tmpfs"  "$LFS/run"     mount -vt tmpfs  tmpfs  "$LFS/run"
  echo "手册命令（/dev/shm 在宿主上可能是符号链接，也可能是 tmpfs 挂载点）："
  echo "  if [ -h \$LFS/dev/shm ]; then install -v -d -m 1777 \$LFS\$(realpath /dev/shm)"
  echo "  else mount -vt tmpfs -o nosuid,nodev tmpfs \$LFS/dev/shm; fi"
  echo "  本容器内 /dev/shm 是：$(ls -ld /dev/shm | sed 's/^/  /')"
  if [ -h $LFS/dev/shm ]; then
    install -v -d -m 1777 $LFS$(realpath /dev/shm)
  else
    mnt_if_needed "tmpfs(/dev/shm)" "$LFS/dev/shm" mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
  fi
  echo
  echo "findmnt 确认（手册 §7.1：You may want to verify that they are mounted by issuing"
  echo "  the findmnt command）："
  findmnt -R "$LFS" | sed "s|$LFS|\$LFS|" | sed 's/^/  /'
  local rc=0
  for mp in "$LFS/dev" "$LFS/dev/pts" "$LFS/proc" "$LFS/sys" "$LFS/run"; do
    if mountpoint -q "$mp"; then printf '  OK   %s 已挂载\n' "$(echo "$mp" | sed "s|$LFS|\$LFS|")"
    else printf '  FAIL %s 未挂载\n' "$(echo "$mp" | sed "s|$LFS|\$LFS|")"; rc=1; fi
  done
  [ $rc -eq 0 ] || die "虚拟内核文件系统未就绪"
  for n in null zero full random urandom tty ptmx; do
    [ -e "$LFS/dev/$n" ] || die "\$LFS/dev/$n 缺失"
  done
  echo "  OK   \$LFS/dev 下 null/zero/full/random/urandom/tty/ptmx 均可见"
  # /dev/console 由内核在真实启动时通过 devtmpfs 创建；Docker 提供给容器的 /dev 里
  # 没有它，而第 7/8 章的构建与测试都不需要它，故只作提示不作硬性要求。
  if [ -e "$LFS/dev/console" ]; then echo "  OK   \$LFS/dev/console 可见"
  else echo "  INFO \$LFS/dev/console 不存在（容器 /dev 未提供；真实启动时由 devtmpfs 创建，第 7/8 章不需要）"; fi
  echo
}

# ------------------------------------------------- §7.4 chroot 执行封装 -----
# 手册 §7.4 的原始命令：
#   chroot "$LFS" /usr/bin/env -i   \
#       HOME=/root                  \
#       TERM="$TERM"                \
#       PS1='(lfs chroot) \u:\w\$ ' \
#       PATH=/usr/bin:/usr/sbin     \
#       MAKEFLAGS="-j$(nproc)"      \
#       TESTSUITEFLAGS="-j$(nproc)" \
#       /bin/bash --login
# 非交互执行时把要跑的脚本放到 chroot 内的 /tmp 再运行，其余环境与手册完全一致。
chroot_run_file() {
  local script=$1
  [ -f "$script" ] || die "脚本不存在：$script"
  mkdir -p "$LFS/tmp"
  local inner=/tmp/.lfs-chroot-job.sh
  install -m 0755 "$script" "$LFS$inner"
  local rc=0
  chroot "$LFS" /usr/bin/env -i   \
      HOME=/root                  \
      TERM="${TERM:-xterm}"       \
      PS1='(lfs chroot) \u:\w\$ ' \
      PATH=/usr/bin:/usr/sbin     \
      MAKEFLAGS="-j$(nproc)"      \
      TESTSUITEFLAGS="-j$(nproc)" \
      /bin/bash --login "$inner" || rc=$?
  rm -f "$LFS$inner"
  return $rc
}

# ------------------------------------------------------- §7.5 / §7.6 -------
sec_7_5_7_6_inside_chroot() {
  echo "================= 7.4. Entering the Chroot Environment ================="
  echo "手册命令（本项目以非交互方式执行同一环境，见 scripts/chroot.sh 中 chroot_run_file）："
  echo "  chroot \"\$LFS\" /usr/bin/env -i HOME=/root TERM=\"\$TERM\" PS1='(lfs chroot) \\u:\\w\\\$ ' \\"
  echo "      PATH=/usr/bin:/usr/sbin MAKEFLAGS=\"-j\$(nproc)\" TESTSUITEFLAGS=\"-j\$(nproc)\" /bin/bash --login"
  echo "  手册说明：Notice that /tools/bin is not in the PATH. This means that the cross"
  echo "  toolchain will no longer be used."
  echo "  nproc = $(nproc)，故 MAKEFLAGS=TESTSUITEFLAGS=-j$(nproc)"
  echo
  local tmp rc=0; tmp=$(mktemp /tmp/chroot-init-XXXXXX.sh)
  cat > "$tmp" <<'INNER'
set -euo pipefail
echo "----- chroot 内自检 -----"
echo "  chroot 根目录内容：$(ls / | tr '\n' ' ')"
echo "  id     ：$(id)"
echo "  PATH   ：$PATH"
echo "  MAKEFLAGS=$MAKEFLAGS  TESTSUITEFLAGS=$TESTSUITEFLAGS"
echo "  bash   ：$(/bin/bash --version | head -n1)"
echo "  /tools/bin 不在 PATH（交叉工具链不再使用）：$(case ":$PATH:" in *:/tools/bin:*) echo NO;; *) echo YES;; esac)"
echo

echo "================= 7.5. Creating Directories ================="
echo "手册命令：mkdir -pv /{boot,home,mnt,opt,srv}"
mkdir -pv /{boot,home,mnt,opt,srv}
echo "手册命令：其余子目录"
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{include,src}
mkdir -pv /usr/lib/locale
mkdir -pv /usr/local/{bin,lib,sbin}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}
# 手册命令 ln -sfv /run /var/run 与 ln -sfv /run/lock /var/lock 不是幂等的：
# 若 /var/run 已是指向目录的符号链接，ln -sf 会跟随它在 /run 里再建一个 run。
# 因此仅在尚未正确建立时执行手册原命令。
if [ "$(readlink /var/run 2>/dev/null)" = /run ]; then
  echo "  已存在且正确，跳过：/var/run -> /run"
else
  ln -sfv /run /var/run
fi
if [ "$(readlink /var/lock 2>/dev/null)" = /run/lock ]; then
  echo "  已存在且正确，跳过：/var/lock -> /run/lock"
else
  ln -sfv /run/lock /var/lock
fi
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp
echo "手册 §7.5.1 Warning：The FHS does not mandate the existence of the directory"
echo "  /usr/lib64, and the LFS editors have decided not to use it. ... it is imperative"
echo "  that this directory be non-existent."
if [ -e /usr/lib64 ]; then echo "  FAIL /usr/lib64 存在"; exit 1; else echo "  OK   /usr/lib64 不存在"; fi
echo "权限确认（/root 应为 0750，/tmp 与 /var/tmp 应为 1777）："
stat -c '  %A %U:%G %n' /root /tmp /var/tmp
echo

echo "================= 7.6. Creating Essential Files and Symlinks ================="
echo "手册命令：ln -sv /proc/self/mounts /etc/mtab"
mtab_target="$(readlink /etc/mtab 2>/dev/null || true)"
if [ "$mtab_target" = /proc/self/mounts ] || [ "$mtab_target" = ../proc/self/mounts ]; then
  echo "  已存在且正确，跳过：/etc/mtab -> /proc/self/mounts"
else
  ln -sv /proc/self/mounts /etc/mtab
fi
echo "手册命令：cat > /etc/hosts << EOF ... EOF"
cat > /etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF
cat /etc/hosts | sed 's/^/  /'
echo "手册命令：cat > /etc/passwd << \"EOF\" ... EOF"
cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF
echo "手册命令：cat > /etc/group << \"EOF\" ... EOF"
cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF
echo "手册原文：Some tests in Chapter 8 need a regular user. We add this user here and"
echo "  delete this account at the end of that chapter."
echo "手册命令：echo \"tester:x:101:101::/home/tester:/bin/bash\" >> /etc/passwd"
echo "          echo \"tester:x:101:\" >> /etc/group"
echo "          install -o tester -d /home/tester"
if grep -q '^tester:' /etc/passwd; then echo "  已存在，跳过 tester 用户行"; else
  echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd; fi
if grep -q '^tester:' /etc/group; then echo "  已存在，跳过 tester 组行"; else
  echo "tester:x:101:" >> /etc/group; fi
install -o tester -d /home/tester
echo "手册命令：exec /usr/bin/bash --login"
echo "  说明：该命令的唯一作用是让交互式 shell 重新读取刚创建的 /etc/passwd、去掉"
echo "  \"I have no name!\" 提示符。本项目每条 chroot 命令都在 /etc/passwd 建好之后"
echo "  由新的 bash 启动，因此不执行 exec（执行它会直接替换掉当前脚本进程）。"
echo "  等效验证——用户名/组名解析是否已生效："
echo "    id     ：$(id)"
echo "    whoami ：$(whoami)"
[ "$(whoami)" = root ] || { echo "  FAIL whoami 不是 root"; exit 1; }
echo "    OK   root 名字解析正常（不再是 I have no name!）"
echo "手册命令：touch /var/log/{btmp,lastlog,faillog,wtmp}"
echo "          chgrp -v utmp /var/log/lastlog"
echo "          chmod -v 664  /var/log/lastlog"
echo "          chmod -v 600  /var/log/btmp"
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp
stat -c '  %A %U:%G %n' /var/log/{btmp,lastlog,faillog,wtmp}
echo
echo "----- §7.5/§7.6 结果检查 -----"
rc=0
for d in /boot /home /mnt /opt /srv /etc/opt /etc/sysconfig /usr/lib/locale \
         /usr/local/bin /usr/local/lib /usr/local/sbin /usr/share/man/man1 \
         /usr/share/man/man8 /var/cache /var/log /var/mail /var/spool \
         /var/lib/color /var/lib/misc /var/lib/locate /root /tmp /var/tmp /home/tester; do
  [ -d "$d" ] || { echo "  FAIL 目录缺失：$d"; rc=1; }
done
if [ $rc -eq 0 ]; then echo "  OK   §7.5 要求的目录齐全"; fi
for l in "/var/run:/run" "/var/lock:/run/lock" "/etc/mtab:/proc/self/mounts"; do
  p=${l%%:*}; t=${l##*:}
  actual="$(readlink "$p")"
  if [ "$actual" = "$t" ] || { [ "$p" = /etc/mtab ] && [ "$actual" = ../proc/self/mounts ]; }; then echo "  OK   $p -> $actual"
  else echo "  FAIL $p 不是指向 $t 的符号链接"; rc=1; fi
done
for f in /etc/hosts /etc/passwd /etc/group; do
  if [ -s "$f" ]; then echo "  OK   $f（$(wc -l < "$f") 行）"; else echo "  FAIL $f 缺失或为空"; rc=1; fi
done
echo "  /etc/mtab 可读性（依赖已挂载的 /proc）：$(wc -l < /etc/mtab) 行"

# 第 8 章多处要求「以非特权用户 tester 运行测试」，其中用到 Expect/DejaGnu 的
# （GCC、Binutils、Bash、Coreutils…）每个用例都要 spawn 一个 pty。若 tester 打不开
# ptmx，这些测试会**全部瞬间失败**却不报告真实原因（§8.30 第一次就这么烧掉了一整轮）。
# 这里把它作为硬性前置断言：宁可在 chroot 准备阶段就停下，也不要跑出一堆假失败。
echo "----- tester 能否分配 pty（第 8 章非特权测试的前提）-----"
echo "  /dev/ptmx      ：$(ls -ld /dev/ptmx | sed 's/  */ /g')"
if [ -e /dev/pts/ptmx ]; then
  echo "  /dev/pts/ptmx  ：$(ls -l /dev/pts/ptmx | sed 's/  */ /g')"
fi
# Shadow（提供 su）要到 §8.29 才安装，此时不能在 chroot 内用
# `su tester` 做检查。实际的 UID/GID 切换打开测试由 chroot 外层完成。
exit $rc
INNER
  chroot_run_file "$tmp" || rc=$?
  rm -f "$tmp"
  [ $rc -eq 0 ] || die "§7.5/§7.6 在 chroot 内执行失败（退出码 $rc）"
  if chroot --userspec=101:101 "$LFS" /bin/bash -c 'exec 3<> /dev/ptmx' 2>/dev/null; then
    echo "  OK   tester(uid=101,gid=101) 可以打开 /dev/ptmx（Expect 的 spawn 能工作）"
  else
    die "tester(uid=101,gid=101) 无法打开 /dev/ptmx —— 以 tester 身份跑的测试会全部假失败"
  fi
  echo
}

cmd_prep() {
  require_root_and_lfs
  echo "##### LFS 13.0-systemd 第 7 章 chroot 环境准备（§7.2 / §7.3 / §7.5 / §7.6）"
  echo "##### 容器内时间：$(date -Is)   \$LFS=$LFS"
  echo "##### 手册 §7.1：Until Section 7.4, the commands must be run as root, with the"
  echo "#####   LFS variable set. After entering chroot, all commands are run as root."
  echo
  sec_7_2_changing_owner
  sec_7_3_kernfs
  sec_7_5_7_6_inside_chroot
  echo "##### chroot 环境已就绪，可执行第 7 章各 package 小节"
}

cmd_status() {
  echo "\$LFS=$LFS"
  findmnt -R "$LFS" 2>/dev/null || echo "(未挂载)"
  echo "顶层："; ls -la "$LFS"
}

case "${1:-status}" in
  prep)   cmd_prep ;;
  run)    require_root_and_lfs; shift; [ $# -ge 1 ] || die "用法：chroot.sh run <脚本路径>"; chroot_run_file "$1" ;;
  status) cmd_status ;;
  *)      die "未知子命令：$1" ;;
esac
