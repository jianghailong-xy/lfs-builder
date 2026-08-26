# LFS raw 磁盘镜像：布局、设备与操作

> 本文中的 `~/lfs-builder` 是示例路径，实际以当前 clone 的仓库根目录为准。
> 下方分区表、loop/挂载拓扑和执行后核对中的 `/root/lfs` 则是原始构建机当时的
> 实测路径，特意保留以免历史记录失真。

创建日期：2026-08-24　脚本：[`scripts/disk-image.sh`](../scripts/disk-image.sh)
入口：`make image` / `make mount` / `make umount` / `make status`

## 1. 镜像与分区布局

| 项 | 值 |
| --- | --- |
| 镜像文件 | `~/lfs-builder/images/lfs.img`（权限 `0600`） |
| 逻辑容量 | 30 GiB（`IMAGE_SIZE_GB`，= 32212254720 字节 / 62914560 扇区） |
| 实际占用 | 稀疏文件，格式化后约 133 MiB，按写入增长 |
| 创建方式 | `qemu-img create -f raw`（raw 格式，QEMU 可直接作为 VirtIO 磁盘使用） |
| 分区表 | **msdos (MBR)**，磁盘标识 `0x54c2aaeb` |
| 分区数 | 1（单一根分区，无独立 `/boot`、无 swap） |

分区表（`sfdisk -l images/lfs.img`）：

```
Device                    Boot Start      End  Sectors Size Id Type
/root/lfs/images/lfs.img1 *     2048 62914559 62912512  30G 83 Linux
```

- 起始扇区 **2048（1 MiB）**：既满足 1 MiB 对齐，也为 BIOS 版 GRUB 的
  `core.img` 留出 MBR gap（后续 `grub-install` 直接嵌入，无需 GPT 的 `bios_grub` 分区）。
- 分区类型 `83`（Linux），已置 **bootable** 标志。
- 选择 MBR 而非 GPT：与 `docs/conventions.md` 的 “BIOS + GRUB” 目标一致，
  QEMU 默认 SeaBIOS 直接可引导。

## 2. 文件系统

| 项 | 值 |
| --- | --- |
| 类型 | ext4（`mkfs.ext4 -F -L LFS -m 1`） |
| 卷标 | `LFS` |
| **UUID** | **`e0292aee-a40c-414b-a00b-d3d2685b6b0d`** |
| PTUUID | `54c2aaeb` |
| 保留块 | 1%（默认 5% 在 30 G 上会浪费约 1.5 G） |
| 可用空间 | 约 29 G |

> UUID 是后续章节写 `$LFS/etc/fstab` 与 `grub.cfg` 的依据。
> 机器可读副本见 `images/lfs.img.info`（由脚本生成，`make status` 会打印）。
> **重建镜像会改变 UUID**，届时须同步更新 fstab 与 GRUB 配置。

## 3. loop 设备与挂载

```
/dev/loop0        -> /root/lfs/images/lfs.img      （losetup -P，自动扫描分区）
/dev/loop0p1      -> /root/lfs/mnt/lfs   ext4 rw,relatime
```

loop 设备号 **不固定**：由 `losetup -f` 自动选取，重新关联后可能是 `loop1`、`loop2`…
因此任何后续脚本都必须用 `make status` 或 `losetup -j <镜像>` 现查，
**不得硬编码 `/dev/loop0`**。分区节点恒为 `<loop 设备>p1`。

## 4. 操作入口

| 命令 | 行为 |
| --- | --- |
| `make image` | 创建镜像 → 写 msdos 分区表 → 关联 loop → `mkfs.ext4` → 写 `.info` → **解除 loop**。镜像已存在时报错退出（保护数据） |
| `make image FORCE=1` | 先 `make umount`，再用此命令删除并重建镜像（UUID 会变） |
| `make mount` | 关联 loop（已关联则复用）→ 校验分区为 ext4 → 挂到 `mnt/lfs`。已挂载则幂等返回 |
| `make umount` | **先** `umount mnt/lfs`，**后** `losetup -d`，顺序不可颠倒 |
| `make status` | 只读：镜像、本项目 loop、挂载状态、分区信息、磁盘空间 |

日志：`logs/host/image.log`（创建）、`logs/host/mount.log`（挂载/卸载），追加写入。

## 5. 脚本内置的安全边界

对应 `docs/conventions.md` §3，`scripts/disk-image.sh` 在动手前逐条断言：

1. 镜像路径必须解析到 `~/lfs-builder/images/` 内，否则拒绝。
2. 挂载点必须恰为 `~/lfs-builder/mnt/lfs`，且目录须存在。
3. 任何将被 `losetup -d` / `umount` 的设备，先用 `losetup -O BACK-FILE` 反查，
   **backing file 不在 `images/` 内就立即中止** —— 这保证脚本无法误伤
   宿主机已有的 loop 设备，更不会碰到 `/dev/nvme*`、`/dev/sd*`。
4. 挂载前校验分区 `TYPE=ext4`，避免挂到非预期文件系统。
5. `umount` 严格先卸载再解关联。

本次执行后核对：宿主机全局仅 `/dev/loop0` 被占用（backing file 为本项目镜像），
`/dev/nvme0n1p2`（`/`）与 `/dev/sd*` 等真实磁盘的挂载状态未发生任何变化。

## 6. 与后续任务的衔接

- 容器启动前必须先 `make mount`（`docs/conventions.md` §2 硬性规则 2）：
  宿主 `mnt/lfs` 已是镜像根分区后，再 bind 到容器 `/mnt/lfs`（`$LFS`）。
- `sources/` 位于宿主机 `~/lfs-builder/sources`，不占镜像空间，
  重建镜像不会丢源码包。
- 目前根分区仅有 `lost+found`；LFS 手册 §4.2 起的目录骨架由后续任务创建。
