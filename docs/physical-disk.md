# 构建到物理硬盘

> **这是破坏性操作：会清空目标整盘，原分区和数据将不可恢复。**

物理盘使用独立的 [`scripts/disk-target.sh`](../scripts/disk-target.sh)。原有 raw 镜像
仍由 `disk-image.sh` 管理，其“镜像必须位于 `images/`、loop 后备文件必须属于项目”
断言没有放宽，也不会因物理盘功能而接受 `/dev/sd*` 或 `/dev/nvme*`。

## 前置条件和流程

目标必须是已经备份、允许彻底擦除、没有被宿主机或存储栈使用的整盘。宿主机需有
root 权限以及 `lsblk`、`blkid`、`findmnt`、`sfdisk`、`partprobe`、`mkfs.ext4` 和
`mount`。只接受调用者显式给出的规范路径 `/dev/sdX` 或 `/dev/nvmeXnY`，不设默认值，
不接受 `/dev/sdX1`、`/dev/nvmeXnYp1` 等分区。

```sh
make disk-install-check DISK=/dev/sdX
make disk-install DISK=/dev/sdX
```

`disk-install-check` 只读取设备画像和安全状态，绝不进入确认或写盘。`disk-install`
先运行同一检查；通过后在真实终端中要求逐字输入 `清空 /dev/sdX`。stdin/stdout 不是
TTY 时默认拒绝，因此 CI、管道、重定向或无人值守调用不会自动继续。确认通过后建立：

- GPT 第 1 分区：1 MiB BIOS boot（供 BIOS GRUB 嵌入）；
- GPT 第 2 分区：占用余下空间的 Linux 根分区，格式化为 `ext4`、标签 `LFS`；
- 根分区挂载到仓库的 `mnt/lfs`（可用 `DISK_MNT` 显式覆盖）。

脚本结束时会保留根分区挂载，供后续 `make sources`、`make env`、`make build-all`
使用。卸载前仍需先停止容器并卸载根分区下的 bind/虚拟文件系统。不要把镜像专用的
`make umount` 用在物理盘上，因为它刻意只允许项目镜像 loop。

## 写盘前的完整画像

脚本会打印型号、序列号、容量、分区表类型，以及磁盘和每个分区的文件系统、标签、
挂载点和分区类型；还会报告活动 swap、ZFS 池引用、MD/LVM 标记和 EFI 分区判断。
人工确认不能替代这些机器检查：它用于让操作者再次把终端中的路径与实物盘标签核对，
防止“选中了另一块同容量磁盘”这类机器无法判断的错误。

## 硬性拒绝规则

以下任一条件命中都会返回非零，并且发生在确认提示之前：

1. 整盘或任一子分区已挂载，或是活动 swap；
2. `blkid` 标记为 `zfs_member`、`linux_raid_member`、`LVM2_member`；
3. `zpool status` 引用了设备，`pvs` 将其列为 PV，或内核 holder 表明它正被使用；
4. 存在 GPT/MBR EFI 系统分区；
5. 设备承载当前 `/`、`/boot` 或 `/boot/efi`，即当前运行系统的根盘/启动盘；
6. 挂载目标已被占用或非空。

这些是不可绕过的拒绝，不提供 `FORCE`。如检查认为一块盘仍在使用，应先在仓库之外
查清并安全停止对应存储栈，再重新运行检查，不能修改脚本来跳过保护。

## loop 验证入口

维护者可用 `ALLOW_LOOP_TEST=1` 对临时 loop 整盘测试相同的分区、格式化和挂载流程。
该模式只接受后备文件解析后位于当前仓库内的 loop；它不允许任意宿主 loop，也不改变
物理盘路径规则。生产使用不应设置此变量。
