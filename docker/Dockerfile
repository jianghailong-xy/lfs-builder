# LFS 13.0-systemd 构建环境（Docker 仅作构建环境，产物全部落在 bind mount 上）
#
# 满足手册 §2.2 "Host System Requirements" 的全部软件与符号链接要求：
#   sh -> bash、/usr/bin/awk -> gawk、/usr/bin/yacc -> bison
# 版本上限：binutils <= 2.46.0、gcc <= 15.2.0（手册未测试更高版本）
FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash binutils bison coreutils diffutils findutils gawk \
        gcc g++ grep gzip m4 make patch perl python3 sed tar texinfo xz-utils \
        libc6-dev file bzip2 zstd ca-certificates procps less vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# 手册 §2.2 要求的符号链接（Debian 默认 sh->dash、awk->mawk 或 gawk 由 alternatives 决定）
RUN ln -sfv bash /usr/bin/sh \
    && ln -sfv gawk /usr/bin/awk \
    && ln -sfv bison /usr/bin/yacc

# 手册 §4.4 Important：/etc/bash.bashrc 会污染 lfs 用户环境，先挪走
RUN [ ! -e /etc/bash.bashrc ] || mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE

# 手册 §4.3：非特权构建用户 lfs
RUN groupadd lfs && useradd -s /bin/bash -g lfs -m -k /dev/null lfs

ENV LFS=/mnt/lfs LC_ALL=C LANG=C
WORKDIR /workspace
CMD ["/bin/bash"]
