# 宿主机构建环境体检结论

体检日期：2026-08-24
体检方式：`make doctor`（完整输出存档于 `logs/host/doctor.log`）
体检结果：**强制检查全部通过，0 项可选警告，退出码 0**

## 1. 宿主机概况

| 项 | 值 |
| --- | --- |
| 发行版 | Debian GNU/Linux 12 (bookworm) |
| 内核 | 6.1.0-41-amd64 |
| 架构 | x86_64（与目标架构一致，无需交叉工具链之外的额外处理） |
| 主机名 | workstation |
| 运行身份 | root（uid=0），loop / mount / chroot 操作所需 |
| 逻辑核心 | 8（构建时可用 `make -j8`） |
| 内存 | 62 GiB + 976 MiB swap |
| 虚拟化 | 裸机（`systemd-detect-virt` = none） |

## 2. 磁盘空间结论

| 项 | 值 |
| --- | --- |
| `/root/lfs` 所在文件系统 | `/dev/nvme0n1p2`，ext4，挂载于 `/` |
| 总容量 | 937 G |
| 已用 | 229 G（26%） |
| **可用** | **660 G** |
| doctor 下限 `MIN_FREE_GB` | 60 G |

**结论：磁盘空间充裕，满足要求。**
预算估算：raw 镜像 `IMAGE_SIZE_GB` = 30 G（LFS 13.0 最终系统约 5–6 G，
连同第 5–8 章构建中间产物与测试套件约需 20–25 G，30 G 留有余量）
＋ 源码包与补丁约 1.5 G（位于宿主机 `sources/`，不占镜像）
＋ Docker 构建镜像与层缓存约 5–10 G。
合计约 45 G，相对 660 G 可用空间余量超过 10 倍。

## 3. 关键工具（全部就位）

| 类别 | 工具 | 版本 / 位置 |
| --- | --- | --- |
| 容器 | docker | 服务端 29.7.2，存储驱动 overlay2，`docker run` 冒烟测试通过 |
| 虚拟机 | qemu-system-x86_64 | 7.2.22 (Debian 1:7.2+dfsg-7+deb12u18+b3)，`-accel help` 含 `kvm` |
| 虚拟机 | qemu-img | qemu-utils |
| loop | losetup、`/dev/loop-control` | util-linux；loop 模块已加载，当前占用 0 个 loop 设备 |
| 分区 | sfdisk、fdisk、partx、parted、kpartx | util-linux / fdisk / parted / kpartx |
| 文件系统 | mkfs.ext4、e2fsck、tune2fs、blkid、lsblk、mount、umount | e2fsprogs / util-linux；内核 `/proc/filesystems` 含 ext4 |
| 引导 | grub-install、grub-mkconfig、grub-mkimage | grub-pc-bin / grub-common 2.06-13+deb12u2 |
| 引导 | i386-pc 模块目录 | `/usr/lib/grub/i386-pc`，303 个文件（BIOS 引导必需） |
| 源码 | wget、curl、tar、xz、gzip、bzip2、patch、sha256sum、git、rsync | 均已安装 |

本次唯一补齐的工具：**kpartx**（0.9.4-3+deb12u2），作为 `partx` 的备选方案。
其余工具体检前即已就位，未做任何其他安装或升级。

## 4. KVM 能力（可选项）

| 项 | 结果 |
| --- | --- |
| `/dev/kvm` | 存在，`crw-rw---- root:kvm`，当前 root 可读写 |
| CPU 虚拟化标志 | `/proc/cpuinfo` 中 16 个核心线程带 vmx/svm |
| qemu 二进制 | `-accel help` 列出 `kvm` |
| 冒烟测试 | `qemu-system-x86_64 -accel kvm -display none -m 64 -monitor stdio` 正常启动并退出 |

**结论：KVM 硬件加速可用。** 最终启动镜像时使用 `-accel kvm`；
若日后环境变化导致 KVM 不可用，doctor 会降级为 WARN 而非 FAIL，
届时回退 `-accel tcg`（纯软件模拟，速度慢但不影响启动正确性）。

## 5. 本次未做的事

- **未创建、未分区、未格式化、未挂载任何磁盘镜像**（`make status` 确认：
  镜像不存在、无 loop 关联、`mnt/lfs` 未挂载）。这些属于后续
  「创建并挂载 LFS raw 磁盘镜像」任务。
- 未构建 Docker 镜像，未下载 LFS 源码包。

## 6. 已知的宿主机遗留问题（不影响本项目）

宿主机 dpkg 处于一个**先前遗留**的中断状态：`linux-image-6.1.0-52-amd64`
配置失败，另有 7 个包已解包未配置（docker-ce、bind9-dnsutils、
google-cloud-cli-anthoscli、libaprutil1、linux-headers-amd64、
linux-image-amd64、p7zip-full）。因此 `apt-get install` 会报
`E: dpkg 被中断`。

- 该问题**与本项目无关，且在本次任务开始前就已存在**。
- 修复它需要 `dpkg --configure -a`，会触发宿主机内核包配置、
  `update-initramfs` 与 `update-grub`，**改动宿主机自身的引导配置**。
  这超出本任务范围且有风险，故**未执行**，留待宿主机管理员决定。
- 规避方式：本次安装 kpartx 采用 `apt-get download` + `dpkg -i`
  （依赖 dmsetup / udev / libc6 / libdevmapper1.02.1 均已就位），
  只配置了 kpartx 一个包，未触碰任何内核或引导相关包。
- 若后续任务需要再装宿主机软件包，沿用同一规避方式，
  或先与宿主机管理员确认后再修复 dpkg 状态。
