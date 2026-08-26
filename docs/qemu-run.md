# QEMU 启动与验收

> 本文中的 `/root/lfs` 是示例路径；实际以当前 clone 的仓库根目录为准。

先确保镜像没有挂载，再从项目根目录启动：

```sh
cd /root/lfs
make umount
make qemu
```

同一 raw 镜像同一时间只能有一个可写 QEMU 实例。若提示镜像被占用，先关闭已有
虚拟机（在来宾中执行 `poweroff`）或等待已有的限时测试结束，再重新运行；启动脚本
会列出持有镜像的进程 PID 和命令行。

启动脚本使用 BIOS、raw 格式成品镜像、`virtio-blk-pci` 磁盘和 `ttyS0`
串口控制台。串口全文写入 `logs/host/qemu-serial.log`。GRUB 倒计时结束后，
以用户 `root`、口令 `lfs` 登录。退出 QEMU 时按 `Ctrl-a`，再按 `x`。
镜像不使用 initramfs，因此 GRUB 以稳定的 VirtIO 设备名 `/dev/vda1` 指定根分区；
若改变磁盘总线或设备顺序，必须同步调整该内核参数。

默认优先使用 KVM，不可用时回退到 TCG。可用环境变量：

```sh
QEMU_MEMORY=4096 QEMU_CPUS=4 make qemu
QEMU_SNAPSHOT=1 make qemu   # 临时验收，不把来宾写入落到 raw 镜像
QEMU_LOG=/tmp/lfs-serial.log make qemu
```

验收登录后可执行：

```sh
uname -a
findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS /
systemctl is-system-running
systemctl --failed --no-legend
cat /proc/cmdline
```

已知限制：镜像采用传统 BIOS/MBR 引导，不提供 UEFI 启动；未配置图形桌面，
正式操作界面是串口控制台；网络是否可用取决于来宾内核和后续网络配置，启动脚本
不把网络可用性作为基础启动验收条件；强制退出 QEMU 等同于断电，正常使用时应先在
来宾内执行 `poweroff`。
