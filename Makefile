# Linux From Scratch 13.0-systemd —— Docker 构建 / QEMU 启动
# 工作目录由本 Makefile 的位置自动推导。约定详见 docs/conventions.md。
#
# 当前可用目标：dirs、doctor、status、image、mount、umount、sources、env、
#               build-chapter*、build-all、grub、qemu、container-*、lfs-shell、help

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---- 宿主机路径（唯一事实来源，所有脚本从这里取值） -----------------------
LFS_ROOT      := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CLONE_NAME    := $(notdir $(LFS_ROOT))
SOURCES_DIR   := $(LFS_ROOT)/sources
SCRIPTS_DIR   := $(LFS_ROOT)/scripts
DOCS_DIR      := $(LFS_ROOT)/docs
DOCKER_DIR    := $(LFS_ROOT)/docker
IMAGES_DIR    := $(LFS_ROOT)/images
LOGS_DIR      := $(LFS_ROOT)/logs
PKG_LOGS_DIR  := $(LOGS_DIR)/packages
HOST_LOGS_DIR := $(LOGS_DIR)/host
LFS_MNT       := $(LFS_ROOT)/mnt/lfs

# ---- 镜像参数（image/mount 任务使用） ------------------------------------
IMAGE         := $(IMAGES_DIR)/lfs.img
IMAGE_SIZE_GB ?= 30
MIN_FREE_GB   ?= 60
IMAGE_LABEL   ?= LFS
# 留空时由 mkfs.ext4 为每次创建随机生成；也可从 make 命令行显式覆盖。
IMAGE_UUID    ?=
# image: FORCE=1 允许删除并重建已存在的镜像
FORCE         ?= 0
IMAGE_INFO    := $(IMAGE).info
DISK_SCRIPT   := $(SCRIPTS_DIR)/disk-image.sh
DISK_TARGET_SCRIPT := $(SCRIPTS_DIR)/disk-target.sh
DISK_MNT      ?= $(LFS_MNT)

# ---- 源码包（sources 任务使用） ------------------------------------------
SOURCES_SCRIPT := $(SCRIPTS_DIR)/fetch-sources.sh

# ---- 构建容器（第 5 章起的所有 package 都在容器内构建） ------------------
CONTAINER_SCRIPT := $(SCRIPTS_DIR)/lfs-container.sh
BUILD_SCRIPT     := $(SCRIPTS_DIR)/build-packages.sh
GRUB_SCRIPT      := $(SCRIPTS_DIR)/install-grub.sh

# ---- 容器内路径（与 docs/conventions.md 中的挂载点约定一一对应） ----------
C_PROJECT     := /workspace
C_LFS         := /mnt/lfs
C_SOURCES     := /mnt/lfs/sources
DOCKER_IMAGE  ?= lfs-build-$(CLONE_NAME):13.0-systemd
CONTAINER     ?= lfs-build-$(CLONE_NAME)
DOCKER_NO_CACHE ?= 0

SKEL_DIRS := $(SOURCES_DIR) $(SCRIPTS_DIR) $(DOCS_DIR) $(DOCKER_DIR) \
             $(IMAGES_DIR) $(LOGS_DIR) $(PKG_LOGS_DIR) $(HOST_LOGS_DIR) $(LFS_MNT)

export LFS_ROOT SOURCES_DIR SCRIPTS_DIR LOGS_DIR PKG_LOGS_DIR HOST_LOGS_DIR
export LFS_MNT IMAGES_DIR IMAGE IMAGE_SIZE_GB MIN_FREE_GB IMAGE_LABEL IMAGE_UUID FORCE
export DISK DISK_MNT ALLOW_LOOP_TEST
export C_PROJECT C_LFS C_SOURCES DOCKER_IMAGE CONTAINER DOCKER_NO_CACHE

.PHONY: help dirs doctor status image mount umount disk-install disk-install-check grub qemu sources sources-verify \
        sources-status env container-build container-up container-prepare \
        container-check container-shell lfs-shell container-down container-status \
        build-chapter5 build-chapter6 build-chapter7 build-chapter8 build-all finish-system

help: ## 显示可用目标
	@echo "LFS 13.0-systemd 构建 (LFS_ROOT=$(LFS_ROOT))"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "挂载点约定见 $(DOCS_DIR)/conventions.md"

dirs: ## 创建项目目录骨架
	@mkdir -p $(SKEL_DIRS)
	@echo "目录骨架就绪：$(LFS_ROOT)"

doctor: dirs ## 体检宿主机构建环境（Docker/QEMU/loop/分区/GRUB/磁盘/KVM）
	@$(SCRIPTS_DIR)/host-doctor.sh

image: dirs ## 创建 raw 镜像、写入 msdos 分区表并格式化 ext4（已存在需 FORCE=1）
	@$(DISK_SCRIPT) create

mount: dirs ## 关联 loop 并把根分区挂载到 mnt/lfs（幂等）
	@$(DISK_SCRIPT) mount

umount: ## 卸载 mnt/lfs 并解除 loop 关联（先卸载后解关联）
	@$(DISK_SCRIPT) umount

disk-install: ## 清空整块物理盘并建立 LFS 分区（必须显式 DISK=/dev/...；破坏性）
	@test -n "$(DISK)" || { echo "[FAIL] 必须显式传入 DISK=/dev/sdX 或 /dev/nvmeXnY" >&2; exit 2; }
	@$(DISK_TARGET_SCRIPT) install "$(DISK)"

disk-install-check: ## 只读检查物理盘安全闸，不确认、不写盘（必须显式 DISK=...）
	@test -n "$(DISK)" || { echo "[FAIL] 必须显式传入 DISK=/dev/sdX 或 /dev/nvmeXnY" >&2; exit 2; }
	@$(DISK_TARGET_SCRIPT) check "$(DISK)"

grub: finish-system ## 安全地把 BIOS GRUB 安装到项目镜像（自动完成 §§8.84–10.3）
	@$(GRUB_SCRIPT)

finish-system: ## 完成 §§8.84–8.86、Chapter 9/§10.2 和 §10.3 内核
	@$(SCRIPTS_DIR)/finish-system.sh

qemu: dirs ## 以 VirtIO 磁盘和串口控制台启动成品镜像
	@$(SCRIPTS_DIR)/qemu-run.sh

sources: dirs ## 按官方 wget-list-systemd 下载源码与补丁到 sources 并校验 MD5（幂等）
	@$(SOURCES_SCRIPT) all

sources-verify: ## 只对照 md5sums 校验 sources（只读）
	@$(SOURCES_SCRIPT) verify

sources-status: ## 显示 sources 清单、文件数与 MD5 通过情况（只读）
	@$(SOURCES_SCRIPT) status

# ---- 第 5–8 章批量构建（成功日志自动跳过，失败立即停止） ----------------
build-chapter5: ## 按顺序构建第 5 章；可断点续跑
	@$(BUILD_SCRIPT) 5

build-chapter6: ## 按顺序构建第 6 章；可断点续跑
	@$(BUILD_SCRIPT) 6

build-chapter7: ## 按顺序构建第 7 章；可断点续跑
	@$(BUILD_SCRIPT) 7

build-chapter8: ## 按顺序构建第 8 章；可断点续跑
	@$(BUILD_SCRIPT) 8

build-all: ## 按顺序构建第 5–8 章全部 110 个小节；可断点续跑
	@$(BUILD_SCRIPT) 5 6 7 8

# ---- 构建容器 ------------------------------------------------------------
env: container-build container-up container-prepare container-check ## 一键就绪：构建镜像+启动容器+§4.2/4.3/4.4 准备+§2.2 体检
	@echo "构建环境就绪：容器 $(CONTAINER)，\$$LFS=$(C_LFS)"

container-build: ## 构建构建环境镜像 $(DOCKER_IMAGE)
	@$(CONTAINER_SCRIPT) build

container-up: ## 启动（或复用）常驻构建容器 $(CONTAINER)（需先 make mount）
	@$(CONTAINER_SCRIPT) up

container-prepare: ## 容器内执行手册 §4.2/§4.3/§4.4 准备（幂等）
	@$(CONTAINER_SCRIPT) prepare

container-check: ## 容器内运行手册 §2.2 version-check.sh
	@$(CONTAINER_SCRIPT) check

container-shell: ## 进入容器 root shell
	@$(CONTAINER_SCRIPT) shell

lfs-shell: ## 以 lfs 用户、手册 §4.4 干净环境进入容器 shell
	@$(CONTAINER_SCRIPT) lfs-sh

container-down: ## 停止并删除构建容器（镜像与 $LFS 产物不受影响）
	@$(CONTAINER_SCRIPT) down

container-status: ## 只读显示构建镜像/容器与容器内 $LFS
	@$(CONTAINER_SCRIPT) status

status: ## 显示镜像、loop 关联与挂载状态（只读，不做任何变更）
	@echo "== 镜像 =="
	@if [ -f "$(IMAGE)" ]; then ls -lh "$(IMAGE)"; else echo "  (未创建) $(IMAGE)"; fi
	@echo "== 本项目占用的 loop 设备 =="
	@losetup -a 2>/dev/null | grep -F "$(IMAGES_DIR)/" || echo "  (无)"
	@echo "== $(LFS_MNT) 挂载状态 =="
	@findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS "$(LFS_MNT)" 2>/dev/null || echo "  (未挂载)"
	@echo "== 分区与文件系统信息 =="
	@if [ -f "$(IMAGE_INFO)" ]; then grep -v '^#' "$(IMAGE_INFO)" | sed 's/^/  /'; else echo "  (无) $(IMAGE_INFO)"; fi
	@echo "== 源码包 =="
	@if [ -f "$(SOURCES_DIR)/md5sums" ]; then \
	  printf "  %s 个包/补丁，%s，清单 %s 条\n" \
	    "$$(find $(SOURCES_DIR) -maxdepth 1 -type f ! -name wget-list-systemd ! -name md5sums | wc -l)" \
	    "$$(du -sh $(SOURCES_DIR) | cut -f1)" \
	    "$$(grep -c . $(SOURCES_DIR)/md5sums)"; \
	else echo "  (未下载) 执行 make sources"; fi
	@echo "== 磁盘空间 =="
	@df -hT "$(LFS_ROOT)" | tail -1
