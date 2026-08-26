# README 从零复现测试报告

日期：2026-08-26 至 2026-08-27。远端 `git@github.com:jianghailong-xy/lfs-builder.git`；clone 起点 `7498876857f71d8cd7aa79c1318c41296e5aac53`。

## 结论

从空 clone、空 sources 和新建 30 GiB 镜像出发，第 5–8 章全部从源码构建，随后完成 §§8.84–8.86、Chapter 9/§10.2、§10.3、BIOS GRUB，并用 QEMU/KVM 启动到 `lfs login:`。原 README 的最短路径在多处会停止；发现的问题已修复或接入自动路径。

## 实际步骤与耗时

- `make doctor` 0.541 秒；`make image` 0.557 秒；新镜像 PTUUID `40ae5d6f`、PARTUUID `40ae5d6f-01`。
- `make mount` 0.186 秒，`/dev/loop0p1` 精确挂到 clone 内。
- `make sources` 1234.051 秒；92 个文件从空目录下载，MD5 92/92，604 MiB。
- 删除任务专用容器/tag 后 `docker build --no-cache` 重建 35.515 秒，镜像 ID `395fc08ec088`。
- 首次 `make build-all` 3221.385 秒；第 5 章 5/5、第 6 章 17/17，随后在 §7.7 暴露脚本问题。
- 第 7 章 7/7；本次 §7.13 快照仅校验，未恢复或用于跳章。
- 第 8 章 81 个 runner 全部成功，另补跑 §§8.84–8.86；主轮约 6.3 小时，修复与严格重测另计。
- Chapter 9/§10.2、§10.3 完成；GRUB 安全闸确认精确 loop 目标后成功；QEMU 最终到登录提示。

## 发现与修复

1. `make env` 会命中 Docker layer cache；测试时显式 `docker build --no-cache`，现新增 `DOCKER_NO_CACHE=1` 并写入 README。
2. Shadow 前 `su tester` 不存在；改为 `chroot --userspec=101:101`。
3. §7.13 对重复 bind mount 卸载不完整，且 Cleaning 不可重入；已修复。
4. 断点检测把中途退出 0 误判为整节成功；限制为日志末尾最终标记。
5. 多个 §8 chroot 脚本意外展开未定义 `$LFS_ROOT`；已转义。
6. §8.53 Python 的日志位置、DNS 失败重试错误；已修复。
7. §8.73 Tar 的 testsuite 文件名、格式判断和重试路径错误；已修复。
8. §8.74 在宿主执行手册命令；已拆成宿主 runner 与 chroot package 脚本。
9. §8.75 Vim 缺 PTY；改为容器 PID namespace 中 `docker exec -t` 并取消 `/dev/null` stdin。7397 项最终仅允许的 `Test_client_server_stopinsert()` 失败。
10. Vim 判定器把跳过项误判为失败；现只核对 `Found errors in ...`。
11. §8.76 硬编码 Vim 编译时间，且 `pipefail` 下 `vim --version | head` 会 SIGPIPE；改为稳定版本/补丁检查。
12. §8.78 分段复测/安装未接入 runner；现仅在失败精确为 `test-namespace` 与 `test-format-table` 时自动用 C.UTF-8 复测并安装。
13. README 最短路径漏掉 §§8.84–8.86、Chapter 9/§10.2、§10.3；新增 `finish-system` 并作为 `grub` 前置。
14. 宿主 umount 后容器 namespace 仍可能持有根挂载，导致 loop 延迟释放；QEMU 正确拒绝，删除任务容器后释放。建议后续让 umount runner 先清理容器 namespace。

## 验收证据

- 防呆：`logs/host/repro-preflight-make-n-rerun.log`，真正 `/root/lfs(/|$)` 边界命中 0。
- 下载：`logs/host/repro-04-sources.log`，92/92 MD5，1234.051 秒。
- 包日志：`logs/packages/`；第 5–8 章 110 个 runner 均有成功标记，另有收尾、系统配置和内核日志。
- `/usr/bin`：普通文件 637，含符号链接共 708 个程序入口。
- GRUB：`root=PARTUUID=40ae5d6f-01 ro console=ttyS0,115200n8`。
- QEMU：`logs/host/qemu-serial-repro.log` 第 600 行为 `lfs login:`。
- 结束时任务容器已删除，clone 镜像无 loop 关联，clone 挂载点为空。

## 红线说明

“不得以任何方式读写 `/root/lfs`”与验收标准 1 要求读取该目录的 PTUUID、mtime、备份哈希和日志数量矛盾。本次服从绝对红线，没有读取生产资产，故不能提供这些任务后实测值。真实磁盘引导扇区仅读取裸设备前 512 字节，前后 MD5 一致，见任务评论。
