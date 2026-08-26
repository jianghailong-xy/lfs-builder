# 阶段检查点：第 5–7 章（交叉工具链与临时工具）

> LFS 13.0-systemd · 汇总节点「第 5–7 章工具链与临时工具」的收尾记录。
> 本文件描述**第 7 章结束、第 8 章开始之前**这一时刻的系统状态，
> 以及如何从该状态的备份恢复。

## 1. 覆盖范围

| 章 | 小节数 | 内容 | 构建位置 |
| --- | --- | --- | --- |
| 第 5 章 | 5 | 交叉工具链（Binutils/GCC pass 1、内核头、Glibc、Libstdc++） | 容器内以 `lfs` 用户，交叉编译到 `$LFS` |
| 第 6 章 | 17 | 交叉编译的临时工具（M4 … GCC pass 2） | 容器内以 `lfs` 用户，交叉编译到 `$LFS` |
| 第 7 章 | 6 | chroot 内构建的临时工具（Gettext … Util-linux） | chroot 内以 `root` |
| **合计** | **28** | 每节一个独立的 package-build 子任务 | — |

第 7 章的非 package 小节（§7.2 属主变更、§7.3 虚拟内核文件系统、§7.4 进入 chroot、
§7.5 建目录、§7.6 建基础文件与符号链接）由 `scripts/chroot.sh prep` 幂等实现，
日志在 `logs/host/chroot-prep.log`；§7.13 由本次汇总节点执行。

## 2. 各节产物与版本（清理前实测自报）

| 小节 | 包 | 实测版本自报 |
| --- | --- | --- |
| §5.2 / §6.17 | Binutils | `GNU ld (GNU Binutils) 2.46.0.20260210` |
| §5.3 / §6.18 | GCC | `gcc (GCC) 15.2.0` / `g++ (GCC) 15.2.0` |
| §5.4 | Linux API Headers | 6.18.10（`/usr/include/linux/version.h`） |
| §5.5 | Glibc | 2.43 |
| §5.6 | Libstdc++ | 随 GCC-15.2.0 |
| §6.2 | M4 | `m4 (GNU M4) 1.4.21` |
| §6.3 | Ncurses | `ncurses 6.6.20251230` |
| §6.4 | Bash | `GNU bash, version 5.3.0(1)-release (x86_64-lfs-linux-gnu)` |
| §6.5 | Coreutils | `ls (GNU coreutils) 9.10` |
| §6.6 | Diffutils | 3.12 |
| §6.7 | File | 5.46 |
| §6.8 | Findutils | 4.10.0 |
| §6.9 | Gawk | `GNU Awk 5.3.2, API 4.0, PMA Avon 8-g1` |
| §6.10 | Grep | `grep (GNU grep) 3.12` |
| §6.11 | Gzip | 1.14 |
| §6.12 | Make | `GNU Make 4.4.1` |
| §6.13 | Patch | 2.8 |
| §6.14 | Sed | `sed (GNU sed) 4.9` |
| §6.15 | Tar | `tar (GNU tar) 1.35` |
| §6.16 | Xz | `xz (XZ Utils) 5.8.2` |
| §7.7 | Gettext | `msgfmt (GNU gettext-tools) 1.0` |
| §7.8 | Bison | `bison (GNU Bison) 3.8.2` |
| §7.9 | Perl | `perl v5.42.0` |
| §7.10 | Python | `Python 3.14.3` |
| §7.11 | Texinfo | `texi2any (GNU texinfo) 7.2` |
| §7.12 | Util-linux | `mount from util-linux 2.41.3 (libmount 2.41.3)` |

每节的完整构建日志在 `logs/packages/<节号>-<包名>-<版本>.log`。

## 3. 工具链一致性验证

在 §7.13 清理**之前**与**之后**各跑一次手册 §6.18 GCC Pass 2 的 sanity check
（`cc dummy.c -v -Wl,--verbose`），两次结果都与手册期望完全一致：

```
[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
/usr/lib/gcc/x86_64-lfs-linux-gnu/15.2.0/../../../../lib/Scrt1.o succeeded
/usr/lib/gcc/x86_64-lfs-linux-gnu/15.2.0/../../../../lib/crti.o succeeded
/usr/lib/gcc/x86_64-lfs-linux-gnu/15.2.0/../../../../lib/crtn.o succeeded
attempt to open /usr/lib/libc.so.6 succeeded
found ld-linux-x86-64.so.2 at /usr/lib/ld-linux-x86-64.so.2
```

关键结论：

- 编译链接全过程 **0 处**引用 `/tools` —— 交叉工具链已完成使命，`/tools` 可以删除。
- 28 个关键命令（`gcc`/`ld`/`make`/`perl`/`python3`/`mount` …）全部解析到 `/usr/bin`
  或 `/usr/sbin`，没有一个落在 `/tools/bin`（手册 §7.4：`/tools/bin` 不在 `PATH` 中）。
- 删除 `/tools` **之后**重跑：`cc` / `g++` 仍能编译、链接并运行产物，
  gawk / perl / python3 / bison / makeinfo / tar+xz / uuidgen 联合冒烟全部通过。

## 4. §7.13.1 Cleaning 执行结果

手册三条命令，原样执行：

| 手册命令 | 结果 |
| --- | --- |
| `rm -rf /usr/share/{info,man,doc}/*` | 三个目录均清空 |
| `find /usr/{lib,libexec} -name \*.la -delete` | 22 个 `.la` → 0 个 |
| `rm -rf /tools` | 删除 1.7 GB，`/tools` 不再存在 |

回收 **1696 MB**（手册预估「文档约 35 MB + /tools 约 1 GB」）。
清理后镜像根分区占用 **2.3 GB**（手册称此时约 3 GB）。

注意：`rm -rf /usr/share/man/*` 会连同 §7.5 建立的 `man1`…`man8` 子目录一起删除，
这是手册预期的结果，第 8 章各包 `make install` 时会自行重建所需子目录。

清理后复核（全部 OK，0 个 FAIL）：56 个关键程序仍可用；`libc` / `libstdc++` /
`libncursesw` / `libblkid` / `libmount` / `libuuid` / `libmagic` 仍在；
§7.6 的 `/etc/passwd`、`/etc/group`、`/etc/hosts`、`/etc/mtab`、`/home/tester`、
`/var/log/lastlog`、`/var/lib/hwclock` 仍在；§7.5 目录骨架仍在；
`/usr/lib64` 依旧不存在（手册 §7.5.1 Warning）。

## 5. §7.13.2 Backup —— 本阶段检查点

手册 §7.13.2 Backup 全部在 chroot 之外执行，本项目由 `scripts/pkg/run-7.13.sh`
在宿主机上接手。步骤与手册一致：卸载虚拟内核文件系统 → `cd $LFS` → `tar -cJpf`。

| 项 | 值 |
| --- | --- |
| 归档 | `/root/lfs/backups/lfs-temp-tools-13.0-systemd.tar.xz` |
| 大小 | 503 MB（打包前 `$LFS` 实占 2.3 GB） |
| 条目数 | 20 314 |
| 打包耗时 | 220 秒（`XZ_OPT=-T0`，8 线程） |
| `xz -t` | 通过 |
| SHA-256 | `ff9ea11a4d33d95ac55ec34fd889dba589da6c2ca81c1cdb2c50e5b25e77198c` |
| 校验和文件 | `…tar.xz.sha256` |

归档内已确认存在 `./usr/bin/gcc`、`./usr/bin/bash`、`./usr/lib/libc.so.6`、
`./etc/passwd`、`./usr/bin/perl`、`./usr/bin/python3`、`./usr/bin/mount`；
确认**不含** `./tools`（§7.13.1 已删除）。

### 与手册的三处适配（均已在日志中逐条说明）

1. **归档位置**：手册用 `$HOME/lfs-temp-tools-13.0-systemd.tar.xz`，本项目用
   `/root/lfs/backups/`。手册明确允许：*Replace `$HOME` by a directory of your choice*，
   要求只是「不得放在 `$LFS` 层级内」，`backups/` 满足。
2. **不打包 `./sources`**：手册里 `$LFS/sources` 是根分区上的普通目录，所以备份天然
   包含源码包。本项目按 `docs/conventions.md` 把宿主机的 `/root/lfs/sources` 以
   bind mount 挂到 `$LFS/sources`，源码根本不在镜像里。打包前先 `umount $LFS/sources`，
   归档中只保留空的 `./sources` 目录（还原后仍是可用挂载点）。手册「不必重新下载」的
   效果由宿主机上常驻的 `/root/lfs/sources` 直接提供。
3. **`XZ_OPT=-T0`**：只影响压缩耗时（8 线程），不改变归档格式，`xz -t` 与
   `tar -tJf` 均正常。

## 6. §7.13.3 Restore —— 适配本项目布局的还原步骤

> **警告**（手册原文）：*The following commands are extremely dangerous. If you run
> `rm -rf ./*` as the root user and you do not change to the `$LFS` directory or the
> LFS environment variable is not set for the root user, it will destroy your entire
> host system. YOU ARE WARNED.*

本项目**不能**直接照抄手册的 `cd $LFS && rm -rf ./*`：`$LFS/sources` 是指向宿主机
`/root/lfs/sources` 的 bind mount，`rm -rf ./*` 会穿过它删掉宿主机上 604 MB 的源码
缓存。必须先卸载再清空：

```sh
cd /root/lfs
make status                      # 先确认 loop 设备与挂载目标，再动手

# 1) 停容器，卸掉 $LFS 下的一切子挂载（虚拟内核文件系统 + sources bind mount）
docker rm -f lfs-build
LFS=/root/lfs/mnt/lfs
mountpoint -q $LFS/dev/shm && umount $LFS/dev/shm
umount $LFS/dev/pts 2>/dev/null || true
umount $LFS/{sys,proc,run,dev} 2>/dev/null || true
umount $LFS/sources 2>/dev/null || true
findmnt -R $LFS                  # 必须只剩 ext4 根分区本身，否则停

# 2) 清空并还原（此时 $LFS 下已无任何 bind mount，rm 不会伤到宿主机）
cd $LFS && rm -rf ./*
tar -xpf /root/lfs/backups/lfs-temp-tools-13.0-systemd.tar.xz

# 3) 重建构建环境（容器的 -v 会重新挂上 sources，prep 幂等补齐 §7.3）
make container-up
docker exec lfs-build bash /workspace/scripts/chroot.sh prep
```

还原前建议先核对校验和：

```sh
sha256sum -c /root/lfs/backups/lfs-temp-tools-13.0-systemd.tar.xz.sha256
```

## 7. 本次收尾时修正的一处环境问题

`scripts/chroot.sh` 的 §7.2 原样照抄了手册的
`chown --from lfs -R root:root $LFS/{usr,var,etc,tools}`。该函数是幂等的，第 8 章
每次进入 chroot 前都会再跑一遍，而 §7.13.1 的 `rm -rf /tools` 之后 `$LFS/tools`
已不存在，`chown` 会报 `cannot access '/mnt/lfs/tools'` 并使整个 prep 以退出码 1 中止
（虚拟内核文件系统随之无法挂载，第 8 章根本进不去 chroot）。

已改为只对当前实际存在的目标执行手册的 `chown`，并把跳过的目标明确打印出来：

```
跳过不存在的目标：$LFS/tools
  （$LFS/tools 在手册 §7.13.1 "rm -rf /tools" 之后就不存在了，属预期）
实际执行：chown --from lfs -R root:root /mnt/lfs/usr /mnt/lfs/var /mnt/lfs/etc /mnt/lfs/lib64
```

修正后 `chroot.sh prep` 退出码 0，`$LFS/{dev,dev/pts,dev/shm,proc,sys,run,sources}`
全部恢复挂载。

## 8. 检查点状态：可以进入第 8 章

chroot 内实测（`scripts/chroot.sh run`）：

```
PATH    : /usr/bin:/usr/sbin          （/tools/bin 不在 PATH，符合手册 §7.4）
MAKEFLAGS=-j8 TESTSUITEFLAGS=-j8
OK   /tools 不存在
OK   cc 编译+运行正常
OK   g++ 正常
OK   /proc 可读
OK   /sources 源码包：94 个
OK   tester 用户：tester:x:101:101::/home/tester:/bin/bash
```

| 检查点要素 | 状态 |
| --- | --- |
| 28 个 package-build 子任务 | 全部 DONE |
| 临时系统目录（§7.5 / §7.6） | 齐全，`/usr/lib64` 不存在 |
| 工具链自洽（删 `/tools` 后仍可自举） | 通过 |
| §7.13.1 Cleaning | 完成，回收 1696 MB |
| §7.13.2 Backup | 完成，503 MB，SHA-256 已记录 |
| 虚拟内核文件系统 | 已重新挂载 |
| 第 8 章入口 | 就绪 |

## 9. 相关文件

- 本节完整日志：`logs/packages/7.13-cleanup-and-backup.log`
- chroot 准备日志：`logs/host/chroot-prep.log`
- 执行脚本：`scripts/pkg/7.13-cleanup.sh`（chroot 内）、`scripts/pkg/run-7.13.sh`（宿主机侧）
- 手册原文快照：`docs/book/chapter07-cleanup.html`
