# Linux From Scratch 13.0-systemd —— Docker 构建 / QEMU 启动

本仓库用 Docker 提供可复现的隔离构建环境，产出可由
`qemu-system-x86_64` 启动的独立 LFS raw 磁盘镜像。

> 文档中的 `~/lfs-builder` 只是示例路径；仓库可 clone 到任意目录，实际路径始终以
> 当前 clone 的仓库根目录为准。checkpoint、实测记录或日志摘录中的原始绝对路径
> 是原始构建机当时的实际路径，特意保留以免历史记录失真。

- 手册版本固定为 **LFS 13.0-systemd**（不使用 stable / development）
- 目标：x86_64 / BIOS + GRUB / ext4 根文件系统 / VirtIO 磁盘 + 串口控制台

## 操作文档

| 文档 | 内容 |
| --- | --- |
| [`docs/conventions.md`](docs/conventions.md) | **路径与容器挂载点约定**，全项目强制遵循 |
| [`docs/host-environment.md`](docs/host-environment.md) | 宿主机体检结论：工具、磁盘空间、KVM 能力 |
| [`docs/disk-image.md`](docs/disk-image.md) | raw 镜像布局、分区表、文件系统 UUID 与 loop/挂载操作 |
| [`docs/physical-disk.md`](docs/physical-disk.md) | **破坏性**物理整盘安装、安全闸、人工确认与只读检查 |
| [`docs/sources.md`](docs/sources.md) | 源码包清单来源、MD5 校验方式与缓存复用策略 |
| [`docs/build-environment.md`](docs/build-environment.md) | 构建容器、手册 §2.2/§4.2/§4.3/§4.4 准备与 SBU 基准 |
| [`docs/checkpoint-ch5-7.md`](docs/checkpoint-ch5-7.md) | **第 5–7 章阶段检查点**：28 个包的产物与版本、工具链一致性验证、§7.13 清理与临时系统备份/还原 |
| [`docs/qemu-run.md`](docs/qemu-run.md) | 成品镜像的 QEMU 串口启动、登录、验收命令与已知限制 |

## 快速开始

仓库可 clone 到任意目录；无论从哪里调用，`make` 都会以 Makefile 所在的仓库根目录
作为工作目录和 `LFS_ROOT`，脚本单独执行时也会从自身位置定位仓库根。下文的
`~/lfs-builder` 只是示例路径，可替换为任意 clone 目录。

下面是从空白环境到串口出现 `lfs login:` 的最短有序路径。除第一条外，
每一步都以前一步成功为前置条件；耗时是本机量级，网络和 CPU 会影响实际时间。

```sh
git clone git@github.com:jianghailong-xy/lfs-builder.git ~/lfs-builder
cd ~/lfs-builder
make doctor    # 前置：宿主机；约 1 分钟，检查 Docker/QEMU/loop/GRUB/磁盘/KVM
make image     # 前置：doctor 通过；约 1 分钟，创建 30G raw 镜像（已有镜像会拒绝覆盖）
make mount     # 前置：image；数秒，关联 loop 并挂载到 mnt/lfs
make sources   # 前置：网络可用；约 5–20 分钟，下载并校验源码（缓存命中更快）
make env       # 前置：mount；约 5–15 分钟，构建/启动容器并准备第 4 章环境
make build-all # 前置：mount、sources、env；本机 -j8 实测约 19 小时，构建第 5–8 章 110 个小节
make grub      # 前置：build-all 且镜像仍挂载、容器运行；先完成 §§8.84–10.3，再仅向项目镜像安装 GRUB
make umount    # 前置：grub；数秒，先卸载虚拟文件系统/根分区，再解除 loop
make qemu      # 前置：umount；约 1 分钟启动，串口应出现 lfs login:
```

验证完全无缓存的复现时，将上面的 `make env` 改为
`make env DOCKER_NO_CACHE=1`；这会向 Docker build 传入 `--no-cache`。源码目录也必须
从空目录开始，不能复用其他 clone 的 `sources/` 或快照。

`make grub` 先运行仓库中原先未接入最短路径的 §§8.84–8.86 收尾、Chapter 9/§10.2
系统配置和 §10.3 内核构建，然后在 LFS chroot 内安装 BIOS GRUB，并由 `blkid` 读取根分区的实际
PARTUUID，生成 `root=PARTUUID=... ro console=ttyS0,115200n8`。它不生成
initramfs，也不写 `initrd` 行，因此根盘不依赖 VirtIO 或“第一块盘”的设备名。

`make sources` 幂等：已存在且 MD5 正确的文件直接跳过，只补缺失/损坏的。
`sources/` 在宿主机上，通过 bind mount 出现在容器的 `$LFS/sources`，
重建镜像或容器都不必重新下载。只想校验用 `make sources-verify`（只读）。

`make doctor` 的强制项失败时返回非零退出码并给出 `apt-get install` 建议；
KVM 属可选项，缺失只告警。

## 构建到物理硬盘

> **危险：`make disk-install` 会不可恢复地清空目标整盘。** 它不是复制文件命令，
> 而是重建 GPT 分区表、格式化 ext4 并把新根分区挂到 `mnt/lfs`。

必须用规范整盘路径显式指定目标，且先做只读检查：

```sh
make disk-install-check DISK=/dev/sdX   # 只读；安全闸命中时非零退出
make disk-install DISK=/dev/sdX         # 通过安全闸后仍要求在终端输入“清空 /dev/sdX”
```

不传 `DISK`、传分区路径、从非交互环境调用都会拒绝。已挂载、活动 swap、
ZFS/MD/LVM 成员、含 EFI 系统分区、承载当前 `/`、`/boot` 或 `/boot/efi` 的盘
会在确认提示出现前硬性拒绝。操作前应备份数据、核对型号/序列号/容量和完整设备画像，
并确保目标确实是可牺牲的空闲整盘。完整说明见
[`docs/physical-disk.md`](docs/physical-disk.md)。镜像入口 `make image/mount/umount/status`
仍使用原有独立安全逻辑。

## 从零复现

从零复现同样支持任意 clone 目录，`make` 始终以仓库根为工作目录；下文出现的
`~/lfs-builder` 只是示例路径，可替换为实际 clone 目录。

完整执行第 5–8 章在本机 `-j8` 实测约 **19 小时**（其中 §8.30 GCC 约
**4 小时**、§8.5 Glibc 约 **49 分钟**）；加上下载、环境准备、
GRUB 安装和首次启动，应按一天量级预留时间。空间至少包括：raw 镜像逻辑容量
**30G**、源码缓存约 **604M**、`backups/` 中两个快照合计约 **1.8G**；还应给编译临时文件和
宿主机留出余量（`make image` 默认要求所在文件系统至少有 60G 可用空间）。

`make build-all` 会按版本号顺序调用 `scripts/pkg/run-<节号>.sh`。若
`logs/packages/<节号>-*.log` 已存在且末尾记录成功退出码，该小节自动跳过；失败时
立即停止并打印小节、日志和续跑命令。修复问题后再次运行 `make build-all` 即从失败
点继续，也可用 `make build-chapter5`、`make build-chapter6`、
`make build-chapter7` 或 `make build-chapter8` 只续跑一章。

可以从以下两个已校验快照选择恢复点：

- `backups/lfs-temp-tools-13.0-systemd.tar.xz`（503M）：第 5–7 章完成态，
  恢复后从 `make build-chapter8` 继续。
- `backups/lfs-ch8-pre-strip.tar.zst`（1.26G）：第 8 章完成、strip 前的状态，
  恢复后只需完成收尾、内核和 GRUB；本机约 **2–3 小时**可从空镜像到可启动。

恢复前先校验相应的 `.sha256` 文件。例如使用第 5–7 章快照：

```sh
cd ~/lfs-builder
sha256sum -c backups/lfs-temp-tools-13.0-systemd.tar.xz.sha256
make mount
# 危险的清空/还原细节与安全核对必须逐项照此文档执行：
sed -n '129,160p' docs/checkpoint-ch5-7.md
make env
make build-chapter8
make grub
make umount
make qemu
```

使用第 8 章快照时，把校验文件换成
`backups/lfs-ch8-pre-strip.tar.zst.sha256`，并按快照配套恢复说明跳过第 5–8 章；
不要运行 `make build-all`。快照恢复会覆盖目标镜像内容，不能作为普通的断点续跑命令。

还原会清空镜像根文件系统，务必确认 `$LFS` 精确为 `~/lfs-builder/mnt/lfs`、其来源为
项目镜像的 loop 分区，并先卸载其下所有 bind/虚拟文件系统。完整、可复制的还原步骤
及检查项见 [`docs/checkpoint-ch5-7.md`](docs/checkpoint-ch5-7.md#6-7133-restore--适配本项目布局的还原步骤)。

## 目录结构

```
~/lfs-builder
├── Makefile                 全部操作入口
├── README.md                本文件
├── docs/                    约定与体检结论
├── scripts/                 可复现脚本（host-doctor.sh、disk-image.sh、lfs-container.sh …）
│   └── pkg/                 每个手册小节的 package 构建脚本
├── docker/                  Dockerfile 与 version-check.sh（手册 §2.2）
├── sources/                 LFS 源码包与补丁（宿主机持有）
├── images/                  raw 磁盘镜像（lfs.img 与 lfs.img.info 元信息）
├── backups/                 阶段检查点归档（手册 §7.13.2 的临时系统备份 + .sha256）
├── mnt/lfs/                 镜像根分区在宿主机上的挂载点
└── logs/
    ├── packages/            每个 package 任务的完整构建日志
    └── host/                宿主机侧操作日志（doctor.log、image.log、mount.log）
```

## 挂载点约定摘要

完整说明见 [`docs/conventions.md`](docs/conventions.md)。

| 宿主机 | 容器内 | 说明 |
| --- | --- | --- |
| `~/lfs-builder` | `/workspace` | 项目根：脚本、文档、日志 |
| `~/lfs-builder/mnt/lfs` | `/mnt/lfs` | **`$LFS`**，镜像根分区，与手册一致 |
| `~/lfs-builder/sources` | `/mnt/lfs/sources` | 源码与补丁，不占镜像空间 |

容器内恒有 `export LFS=/mnt/lfs`；package 日志固定写入
`/workspace/logs/packages/<节号>-<包名>-<版本>.log`。

## 安全边界

默认镜像流程只操作 `~/lfs-builder/images/` 下的镜像及其 loop 设备。物理盘只能经
`make disk-install DISK=...` 的独立安全闸和人工二次确认进入；任何绕过该入口的
`sfdisk` / `mkfs` / `wipefs` / `dd` / `grub-install` 都不属于受支持流程。
