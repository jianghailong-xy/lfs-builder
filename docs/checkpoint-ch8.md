# 第 8 章最终 LFS 用户空间检查点

- 手册：LFS 13.0-systemd
- 完成时间：2026-08-25（Asia/Shanghai）
- Orbit 汇总任务：`34AD3dz8MwbdT6uSnWGG4`
- package 状态：同时带 `package-build` 与 `chapter-08` 标签的 81 个任务全部 `DONE`

## 收尾结果

- §8.84 已记录调试符号说明。
- §8.85 已执行 strip；7 个关键库的调试信息以 Zstd 压缩的 `.dbg` 文件保留。
- `/usr` 从 4,345,708 KiB 减少到 1,455,088 KiB，共回收 2,890,620 KiB。
- §8.86 已清空测试临时文件、删除 `.la` 文件和临时交叉工具链，并删除 `tester` 用户。
- 原生 C 编译、链接、动态加载与执行检查通过；bash、GCC、binutils、systemd、D-Bus 和 e2fsprogs 的关键命令均可执行。

## 证据与恢复点

- 独立复核日志：`logs/packages/8.84-8.86-final-userspace.log`
  - SHA-256: `e4a639ff42058b32284da1ea57db8214c402b147cdd9be85cb915348ac152e81`
- strip 前恢复归档：`backups/lfs-ch8-pre-strip.tar.zst`（约 1.2 GiB，已通过 `zstd -t`）
  - SHA-256: `8e20c39520987d94612e5cd03d3475d19269fa1503f61f51f273ee625ff93423`
  - 校验文件：`backups/lfs-ch8-pre-strip.tar.zst.sha256`
- 幂等完成标记：目标系统内 `/var/lib/lfs/chapter-08-finalized`

复核日志最终结论为 `RESULT: PASS`，本检查点可作为第 9 章系统配置工作的起点。
