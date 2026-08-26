# 源码包与补丁（LFS 13.0-systemd）

本文件记录 `sources/` 的来源、校验方式与缓存复用策略。
操作入口：`make sources` / `make sources-verify` / `make sources-status`，
实现见 [`scripts/fetch-sources.sh`](../scripts/fetch-sources.sh)。

## 1. 权威清单

固定取自 **13.0-systemd** 已发布书（不用 stable / development）：

| 用途 | URL |
| --- | --- |
| 下载清单 | `https://www.linuxfromscratch.org/lfs/view/13.0-systemd/wget-list-systemd` |
| 校验和 | `https://www.linuxfromscratch.org/lfs/view/13.0-systemd/md5sums` |

两份清单都会落盘到 `sources/`，与手册 §3.1 的用法一致，之后可原样执行：

```sh
cd $LFS/sources && md5sum -c md5sums
```

> **注意 systemd 版与 SysV 版的清单不同。**
> `downloads/13.0-systemd/wget-list` 返回的是 **97 条**的 SysV 清单，
> 多出 `lfs-bootscripts`、`sysvinit`、`sysklogd`、`udev-lfs` 与
> `sysvinit-3.14-consolidated-1.patch`，而同目录的 `md5sums` 只有 92 条，
> 两者对不上。systemd 构建必须用 `wget-list-systemd`（92 条），
> 它与 `md5sums` 严格一一对应——脚本每次拉取后都会 `diff` 校验这一点，
> 不一致直接报错退出，避免"少下了 5 个包却显示全部通过"。

## 2. 存放位置与缓存复用

| 宿主机 | 容器内 | 说明 |
| --- | --- | --- |
| `/root/lfs/sources` | `/mnt/lfs/sources`（= `$LFS/sources`） | bind mount |

源码**不在镜像里**：`sources/` 是宿主机目录，通过 bind mount 出现在容器的
`$LFS/sources`。因此

- `make image FORCE=1` 重建磁盘镜像、或删除并重建容器，都不会丢源码；
- 镜像的 30G 空间不被 ~1.1G 源码占用。

`fetch-sources.sh` 是**幂等**的：每次先逐个文件算 MD5，只有缺失或损坏的才下载，
已命中的直接跳过。重跑 `make sources` 在全部就绪时只做一次校验，不产生网络下载。

目录权限按手册 §4.2 固定为 `1777`（`drwxrwxrwt`），脚本每次运行都会确保。

## 3. 校验方式

脚本不解析 `md5sum -c` 的文案，而是逐个文件自己算 MD5 与清单比对，
输出 `OK / BAD / MISSING` 三态。原因：宿主机 locale 是 `zh_CN.UTF-8`，
`md5sum -c` 会把 `FAILED` / `OK` 翻译成中文，按英文关键字 grep 会全线误判
（把损坏当成通过）。脚本内统一 `export LC_ALL=C`，并在逐文件校验全通过后，
再用手册原样的 `md5sum -c md5sums` 复核一遍，两者结论必须一致。

## 4. 下载源与兜底顺序

每个文件按下列顺序逐个源尝试，第一个成功即止（`--continue`，超时 20s，重试 2 次）：

1. `wget-list-systemd` 里的官方上游 URL；
2. `https://mirror.nju.edu.cn/lfs/lfs-packages/13.0/<文件名>`
3. `https://ftp.osuosl.org/pub/lfs/lfs-packages/13.0/<文件名>`
4. `https://mirrors.aliyun.com/lfs/lfs-packages/13.0/<文件名>`
5. `https://anduin.linuxfromscratch.org/LFS/<文件名>`

2–4 是 LFS 官方 package 镜像，13.0 的 92 个文件已逐一 HEAD 探测确认齐全；
**anduin 只放 LFS 自产文件**（`lfs-bootscripts`、`udev-lfs` 等），
`attr` 这类第三方包在它上面是 404，所以排最后而不能当主兜底。
实测部分上游不可达（如 `download.savannah.gnu.org` 连接超时），镜像链是必需的。

换源前会 `rm -f` 掉半截文件——否则下一个源的 `--continue` 会从错误的偏移续传，
拼出一个长度对、内容错的文件。

整体最多 3 轮。第 1 轮对已存在的文件保留 `--continue`，让上次中断的大包
（gcc / glibc / linux）能续传而不是从头再来；第 2 轮起改为**先删后下**。
代价是：内容已损坏（而非只下了一半）的文件，第 1 轮的续传注定无效，
要到第 2 轮才真正修好——实测破坏 `glibc-fhs-1.patch` 后，第 1 轮空转、
第 2 轮重下、第 3 轮确认全绿，最终 92/92 通过。用一次空转换大包可续传，
这个取舍是刻意的。

`MIRROR_FIRST=1 make sources` 可跳过上游直接走镜像（上游整体不可达时用）。

## 5. 日志

全部操作追加到 `logs/host/sources.log`（wget 输出、每轮下载清单、逐文件校验结果）。
