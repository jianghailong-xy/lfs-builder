# 构建环境：Docker 容器 + 手册第 2/4 章准备

> 本文中的 `/root/lfs` 是原始构建机的示例路径；实际以当前 clone 的仓库根目录为准。

第 5 章起的所有 package 都在容器 `lfs-build` 内构建，产物落在 bind mount 出去的
镜像分区（`$LFS`）与宿主机日志目录上，容器本身可随时销毁重建。
路径与挂载点约定见 [`conventions.md`](conventions.md)。

## 1. 一键就绪

```sh
make mount     # 先在宿主机挂好镜像分区（必须，容器只认已挂载的 /root/lfs/mnt/lfs）
make env       # = container-build + container-up + container-prepare + container-check
```

| 目标 | 作用 |
| --- | --- |
| `make container-build` | 用 `docker/Dockerfile` 构建 `lfs-build:13.0-systemd` |
| `make container-up` | 启动常驻容器 `lfs-build`（幂等，已运行则复用） |
| `make container-prepare` | 容器内执行手册 §4.2 / §4.3 / §4.4（幂等） |
| `make container-check` | 容器内跑手册 §2.2 的 `version-check.sh` |
| `make lfs-shell` | 以 `lfs` 用户、手册 §4.4 的干净环境进容器 |
| `make container-down` | 删除容器（镜像与 `$LFS` 产物不受影响） |

## 2. 镜像内容（满足手册 §2.2）

基础镜像 `debian:trixie`，安装手册 §2.2 列出的全部工具，并建立手册要求的符号链接：
`sh -> bash`、`/usr/bin/awk -> gawk`、`/usr/bin/yacc -> bison`；
按 §4.4 的 Important 把 `/etc/bash.bashrc` 挪成 `.NOUSE`；按 §4.3 建立 `lfs` 用户与组。

`make container-check` 的实测结论（2026-08-24）：§2.2 全部条目 OK，无 ERROR。
关键版本：GCC 14.2.0、Binutils 2.44、Glibc 侧工具链齐全、Python 3.13.5、内核 6.1.0、8 逻辑核。
两个上限约束都满足：宿主 Binutils ≤ 2.46.0、GCC ≤ 15.2.0。

## 3. 容器启动形态

```sh
docker run -d --name lfs-build --privileged \
  -v /root/lfs:/workspace \
  --mount type=bind,source=/root/lfs/mnt/lfs,target=/mnt/lfs,bind-propagation=rshared \
  -v /root/lfs/sources:/mnt/lfs/sources \
  -w /workspace -e LFS=/mnt/lfs \
  lfs-build:13.0-systemd sleep infinity
```

`scripts/lfs-container.sh up` 在启动前强制校验：`/root/lfs/mnt/lfs` 已挂载、来源是
`/dev/loop*`、且该 loop 指向 `/root/lfs/images/` 下的镜像；任一不满足直接拒绝启动，
避免误把宿主机真实磁盘挂进容器。`--privileged` 是为第 7 章起 chroot 内的 mount 准备的。

## 4. 手册 §4.2 / §4.3 / §4.4 的落地

`scripts/prepare-chapter4.sh`（容器内 root 执行，幂等）：

- §4.2：`$LFS/{etc,var}`、`$LFS/usr/{bin,lib,sbin}`、`bin|lib|sbin` 符号链接、
  `$LFS/lib64`、`$LFS/tools`；
- §4.3：`chown -v lfs $LFS/{usr{,/*},var,etc,tools}` 与 `$LFS/lib64`
  （`lfs` 用户/组已在镜像里建好）；
- §4.4：写 `/home/lfs/.bash_profile`（`exec env -i …`）与 `/home/lfs/.bashrc`
  （`set +h`、`umask 022`、`LFS`、`LC_ALL=POSIX`、`LFS_TGT`、`PATH`、`CONFIG_SITE`、
  `MAKEFLAGS=-j$(nproc)`），内容与手册逐字一致。

> `$LFS/sources` 是宿主机目录的 bind mount，权限 `1777`，`lfs` 用户可直接在其中解包，
> 因此不需要（也不应该）对它 `chown`。

## 5. package 构建的调用方式

每个 package 任务写一个脚本 `scripts/pkg/<节号>-<包名>.sh`，在容器内以 `lfs` 用户、
手册 §4.4 的干净环境执行（`env -i` + `source ~/.bashrc`，等价于手册的 `su - lfs`）：

```sh
./scripts/lfs-container.sh exec-lfs 'bash /workspace/scripts/pkg/5.2-binutils-pass1.sh' \
  > logs/packages/5.2-binutils-2.46.0-pass-1.log 2>&1
```

## 6. SBU 基准

手册 §4.5 的 1 SBU = §5.2 Binutils Pass 1 从 configure 到 make install 的时间。
本环境实测（`MAKEFLAGS=-j8`）：

```
real 1m24.080s   user 5m19.772s   sys 0m37.605s
```

即 **1 SBU ≈ 1.4 分钟**（wall clock，8 逻辑核）。手册中标注 N SBU 的包，
在本环境的预计耗时约为 N × 1.4 分钟。

## 7. 手册存档

构建过程中依据的手册页面已存档到 `docs/book/`（从
`https://www.linuxfromscratch.org/lfs/view/13.0-systemd/` 抓取的原始 HTML），
避免上游改版导致命令漂移：

| 文件 | 手册位置 |
| --- | --- |
| `chapter02-hostreqs.html` | §2.2 Host System Requirements（含 version-check.sh 原文） |
| `partintro-toolchaintechnotes.html` | ii. Toolchain Technical Notes |
| `partintro-generalinstructions.html` | iii. General Compilation Instructions |
| `chapter04-creatingminlayout.html` | §4.2 目录骨架 |
| `chapter04-addinguser.html` | §4.3 lfs 用户 |
| `chapter04-settingenvironment.html` | §4.4 环境变量 |
| `chapter04-aboutsbus.html` | §4.5 About SBUs |
| `chapter05-introduction.html` | §5.1 Introduction |
| `chapter05-binutils-pass1.html` | §5.2 Binutils-2.46.0 - Pass 1 |
