# LFS 13.0-systemd 构建约定

> 本文中的 `~/lfs-builder` 是示例路径；实际 `LFS_ROOT` 由当前 clone 的
> Makefile 位置推导，仓库可位于任意目录。

本文件是全项目的路径与挂载点唯一约定，**所有 package 任务必须遵循**。
与 `Makefile` 顶部的变量一一对应，改动必须同步两处。

- 手册版本：Linux From Scratch **13.0-systemd**（不使用 stable / development）
- 目标架构：x86_64；引导：BIOS + GRUB；根文件系统：ext4
- QEMU：VirtIO 磁盘 + 串口控制台
- 产物：raw 磁盘镜像

---

## 1. 宿主机目录骨架

| 宿主机路径 | 用途 |
| --- | --- |
| `~/lfs-builder` | 项目根（`LFS_ROOT`；此处为示例，实际随 clone 目录变化） |
| `~/lfs-builder/Makefile` | 全部操作入口（`make doctor` / `dirs` / `status` …） |
| `~/lfs-builder/scripts/` | 可复现脚本（`host-doctor.sh` 等） |
| `~/lfs-builder/docs/` | 操作文档与约定（本文件） |
| `~/lfs-builder/docker/` | Dockerfile 与容器启动脚本 |
| `~/lfs-builder/sources/` | LFS 源码包与补丁（**宿主机持有**，不随镜像重建而丢失） |
| `~/lfs-builder/images/` | raw 磁盘镜像，默认 `images/lfs.img` |
| `~/lfs-builder/mnt/lfs/` | 镜像根分区在**宿主机**上的挂载点 |
| `~/lfs-builder/logs/packages/` | 每个 package 任务的完整构建日志 |
| `~/lfs-builder/logs/host/` | 宿主机侧操作日志（doctor、镜像、挂载等） |

### 日志命名

package 任务日志固定为：

```
~/lfs-builder/logs/packages/<节号>-<包名小写>-<版本>.log
```

例如 `logs/packages/8.83-e2fsprogs-1.47.3.log`、`logs/packages/10.3-linux-6.18.10.log`。
日志须包含该节的全部命令输出，并在末尾记录测试结论与手册允许的失败项。

---

## 2. 容器内挂载点约定（核心）

Docker 仅作为**构建环境**，不持有构建产物：产物一律落在通过 bind mount
传入的宿主机路径上，因此容器随时可以销毁重建而不丢失进度。

| 宿主机路径 | 容器内路径 | Makefile 变量 | 说明 |
| --- | --- | --- | --- |
| `~/lfs-builder` | `/workspace` | `C_PROJECT` | 项目根：脚本、文档、日志。日志因此自动落到 `/workspace/logs/packages/` = 宿主 `~/lfs-builder/logs/packages/` |
| `~/lfs-builder/mnt/lfs` | `/mnt/lfs` | `C_LFS` | **`$LFS` 目标根**，即镜像根分区。与手册的 `LFS=/mnt/lfs` 完全一致，手册命令可原样照抄 |
| `~/lfs-builder/sources` | `/mnt/lfs/sources` | `C_SOURCES` | 源码与补丁。手册的 `$LFS/sources` 在此指向宿主机目录，源码不占用镜像空间，也不必随镜像重建重新下载 |

由此得到全项目统一的环境变量：

```sh
export LFS=/mnt/lfs          # 容器内恒定
# 源码：$LFS/sources         -> 宿主 ~/lfs-builder/sources
# 日志：/workspace/logs/packages/<节号>-<包>-<版本>.log
```

### 硬性规则

1. **`$LFS` 在容器内恒为 `/mnt/lfs`**，任何任务不得改写。
2. **挂载顺序**：先在宿主机上把镜像分区挂到 `~/lfs-builder/mnt/lfs`，**再**启动容器。
   容器启动后宿主机新增的挂载不会自动出现在容器里，需依赖 `rshared` 传播。
3. **写入位置**：所有最终系统文件写入 `$LFS`（= 镜像内）；所有日志写入
   `/workspace/logs`（= 宿主机内）。构建中间目录用完即清理（见手册各节末尾）。
4. **禁止**在容器内直接操作 loop 设备或宿主机其他磁盘；loop、分区、格式化、
   挂载/卸载一律由宿主机侧 `make` 目标完成。
5. chroot 阶段（手册第 7 章起）在容器内进行，容器需具备 `CAP_SYS_ADMIN`
   才能在 chroot 内挂载 `/dev`、`/proc`、`/sys`、`/run`。

### 容器启动形态（供后续 docker 任务实现）

```sh
docker run --rm -it \
  --name  lfs-build \
  --privileged \
  -v ~/lfs-builder:/workspace \
  --mount type=bind,source=~/lfs-builder/mnt/lfs,target=/mnt/lfs,bind-propagation=rshared \
  -v ~/lfs-builder/sources:/mnt/lfs/sources \
  -w /workspace \
  -e LFS=/mnt/lfs \
  lfs-build:13.0-systemd /bin/bash
```

> `--privileged` 是为了 chroot 内的 mount；宿主机上执行前须确认
> `~/lfs-builder/mnt/lfs` 已挂载正确的镜像分区（`make status`）。

---

## 2.5 目标系统凭据（§8.29 Shadow 之后有效）

| 项 | 值 | 来源 |
| --- | --- | --- |
| 镜像内 root 口令 | `lfs` | LFS 13.0-systemd §8.29.3 `passwd root` |

手册 §8.29.3 的 `passwd root` 是交互式命令，本项目 chroot 执行无 tty，实际执行的是
shadow-4.19.3 自带的等价入口 `printf '%s\n' lfs | passwd --stdin root`。散列算法是
yescrypt（`$y$` 前缀），由 §8.29.1 写进 `/etc/login.defs` 的 `ENCRYPT_METHOD YESCRYPT`
与 §8.28 Libxcrypt 共同决定。

后续 §10/§11 的 GRUB 引导与 QEMU 验收任务用这个口令登录。这是**构建产物磁盘镜像内**
的口令，与宿主机无关；完整执行记录见 `logs/packages/8.29-shadow-4.19.3.log`。

---

## 3. 安全边界

- 只允许操作 `~/lfs-builder/images/` 下的镜像文件与其关联的 loop 设备。
- 任何 `losetup` / `mount` / `umount` / `mkfs` / `grub-install` 前，先用
  `make status` 或 `losetup -a` 确认精确目标设备，**禁止**触碰宿主机
  `/dev/nvme*`、`/dev/sd*` 等真实磁盘及其挂载点。
- 清理操作先卸载再解除 loop 关联，顺序不可颠倒。

---

## 4. 环境体检

```sh
make doctor
```

强制项失败会返回非零退出码并给出 `apt-get install` 建议；KVM 属可选项，
缺失仅告警（QEMU 回退 `-accel tcg`，慢但不影响正确性）。
体检结论存档见 `docs/host-environment.md`。
