#!/usr/bin/env bash
# 宿主机侧驱动：在构建容器内准备 chroot（手册 §7.2/§7.3/§7.5/§7.6，幂等）后，
# 在 chroot 内执行 §8.31 Ncurses-6.6，完整输出落到
# logs/packages/8.31-ncurses-6.6.log。
set -uo pipefail
LFS_ROOT=/root/lfs
LOG=$LFS_ROOT/logs/packages/8.31-ncurses-6.6.log
PREP_LOG=$LFS_ROOT/logs/host/chroot-prep.log
CONTAINER=${CONTAINER:-lfs-build}

mkdir -p "$LFS_ROOT/logs/host" "$LFS_ROOT/logs/packages"

echo "===== chroot 环境准备（手册 §7.2/§7.3/§7.5/§7.6，幂等）====="
{
  echo "##### chroot 准备（§8.31 前）—— 宿主机时间：$(date -Is)"
  echo
} >> "$PREP_LOG"
docker exec "$CONTAINER" bash /workspace/scripts/chroot.sh prep >> "$PREP_LOG" 2>&1
prep_rc=$?
echo "##### prep 退出码：$prep_rc" >> "$PREP_LOG"
echo "chroot 准备退出码：$prep_rc（日志：$PREP_LOG）"
if [ $prep_rc -ne 0 ]; then
  echo "chroot 环境准备失败，按任务要求不继续 §8.31；保留日志 $PREP_LOG" >&2
  exit $prep_rc
fi

{
  echo "##### LFS 13.0-systemd §8.31 Ncurses-6.6"
  echo "##### 宿主机时间：$(date -Is)"
  echo "##### 容器：$CONTAINER（镜像 lfs-build:13.0-systemd）"
  echo "##### 执行位置：chroot 环境内（手册 §7.4），chroot 根 = \$LFS = /mnt/lfs"
  echo "#####   = 宿主 /root/lfs/mnt/lfs = loop 挂载的镜像根分区"
  echo "##### 源码：chroot 内 /sources = 宿主 /root/lfs/sources"
  echo "##### 前置的 §7.2/§7.3/§7.5/§7.6 已在本次运行中确认就绪，其完整输出见"
  echo "#####   $PREP_LOG"
  echo "##### 上一任务 §8.30 GCC-15.2.0 已完成（日志 8.30-gcc-15.2.0.*）。本节**真的**"
  echo "#####   依赖它，而且不止 C 编译器：手册给的 --with-cxx-shared 要求构建 C++ 绑定"
  echo "#####   libncurses++w，没有可用的 g++ 与 libstdc++ 这一项直接构建失败。"
  echo "#####   下方「前置检查」第 1 项会实际用 gcc/g++ 各编一个程序跑一遍。"
  echo "##### 手册原文快照：docs/book/chapter08-ncurses.html（本次运行前从"
  echo "#####   https://www.linuxfromscratch.org/lfs/view/13.0-systemd/chapter08/ncurses.html 抓取）"
  echo "##### 本节命令序列（§8.31.1 的全部命令，按手册原文顺序）："
  echo "#####   ./configure --prefix=/usr --mandir=/usr/share/man --with-shared \\"
  echo "#####               --without-debug --without-normal --with-cxx-shared \\"
  echo "#####               --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig"
  echo "#####   make"
  echo "#####   make DESTDIR=\$PWD/dest install"
  echo "#####   sed -e 's/^#if.*XOPEN.*\$/#if 1/' -i dest/usr/include/curses.h"
  echo "#####   cp --remove-destination -av dest/* /"
  echo "#####   for lib in ncurses form panel menu ; do"
  echo "#####       ln -sfv lib\${lib}w.so /usr/lib/lib\${lib}.so"
  echo "#####       ln -sfv \${lib}w.pc    /usr/lib/pkgconfig/\${lib}.pc"
  echo "#####   done"
  echo "#####   ln -sfv libncursesw.so /usr/lib/libcurses.so"
  echo "#####   cp -v -R doc -T /usr/share/doc/ncurses-6.6      （手册标注 If desired）"
  echo "##### 与手册字面完全一致，没有增删任何一条命令。四处需要说明的执行细节："
  echo "#####   1) **本节手册没有规定任何测试**。手册原话是：This package has a test suite,"
  echo "#####      but it can only be run after the package has been installed. The tests"
  echo "#####      reside in the test/ directory. See the README file in that directory"
  echo "#####      for further details.——它没有给出任何测试命令，也没把测试列为构建步骤"
  echo "#####      （对照 §8.30 GCC 那种明写 su tester -c \"... make -k check\" 的节）。"
  echo "#####      test/ 里是 blue/bs/firework/gdc/worm 这类**交互式 demo**，要真终端与"
  echo "#####      人工按键，非交互 chroot 里跑只会得到无判据的假结果。故本节不跑它，"
  echo "#####      改为在安装后做一组非交互功能验证（编译链接 + tic/infocmp/tput/toe 往返），"
  echo "#####      并在日志里明确标注这组验证是「手册之外的自检」。"
  echo "#####   2) 手册末尾关于 ABI 5 非宽字符库的 Note **不执行**：其前提（binary-only"
  echo "#####      应用 / LSB 合规）在本项目都不成立，手册自己也写明源码编译的包运行时"
  echo "#####      不会链接它们。"
  echo "#####   3) 手册标注 If desired 的 doc 安装**执行**：§8.31.2 Contents 的"
  echo "#####      Installed directories 明列 /usr/share/doc/ncurses-6.6，不装则该项核对缺一。"
  echo "#####   4) make / DESTDIR install / cp -av 的完整输出分别有数百到数千行，全塞进"
  echo "#####      主日志会让它不可读，因此落到独立文件（见文末「留档」行），主日志记录"
  echo "#####      起止时间、退出码、耗时、关键抽样与全部核对结论。"
  echo "##### 本包 0.2 SBU / 47 MB，故正式开工前先在 chroot 的 /tmp 里做了**完整**试建"
  echo "#####   （configure + make + make DESTDIR=... install，不写系统），把脚本里每一条"
  echo "#####   带等号的断言在试建产物上逐条验过后才重新开工，试建目录随后已删除"
  echo "#####   （脚本 scripts/pkg/8.31-ncurses-trial.sh）。校准出的关键事实（都不是猜的）："
  echo "#####     - dest 树：55 目录 / 3073 文件 / 813 链接 / **0 个 .a**；"
  echo "#####     - /usr/bin 11 项 = 8 个真程序 + 3 个符号链接（captoinfo->tic、"
  echo "#####       infotocap->tic、reset->tset）——手册 Contents 写的 \"link to tic\" 指的是"
  echo "#####       符号链接，不是硬链接；"
  echo "#####     - 5 个共享库实体，SONAME 一律 lib*.so.6；5 个 .pc（ncurses++w **没有**"
  echo "#####       对应的 ncurses++.pc，手册的 for 循环只覆盖 4 个，这不是遗漏）；"
  echo "#####     - 18 个头文件；man3 120 文件 + 797 链接；terminfo 2899 条目 / 42 子目录；"
  echo "#####       tabset 4 个文件；doc 245 个文件；"
  echo "#####     - curses.h 里 '^#if.*XOPEN.*\$' 恰好命中 **1** 行（第 256 行）；第 95 行"
  echo "#####       虽然也是 \"#if 1\"，但那是 configure 生成的原样内容，数行数时别数错；"
  echo "#####     - **DESTDIR 安装的输出里会出现恰好 5 处 \"Error 1 (ignored)\"**，全部来自"
  echo "#####       各 Makefile 里的 \`test -z \"\$(DESTDIR)\" && \$(LDCONFIG)\`：DESTDIR 非空时"
  echo "#####       test -z 返回 1，规则前缀是 '-' 故被 make 忽略。它的含义是「因为在往"
  echo "#####       DESTDIR 里装所以跳过 ldconfig」，是正常现象。脚本逐条溯源核对，"
  echo "#####       既不当作失败报警，也不当作噪声无视。"
  echo "##### 另外，功能验证里用到的每一种手法（10 个程序的 -V、tput/infocmp/tic 往返、"
  echo "#####   newterm 打到 /dev/null 的 C 程序、-l* 兼容链接、C++ 绑定、pkg-config 查询）"
  echo "#####   都先用 scripts/pkg/8.31-probe.sh 在 §6.3 已装的同版本 ncurses 上预演过一遍，"
  echo "#####   确认手法本身可行后才写进正式脚本——避免重蹈「构建失败全部来自自加检查」的覆辙。"
  echo "##### 按同一条教训：所有用于展示的 diff/grep/ls/find 都包成 { … || true; }；"
  echo "#####   不用 'cmd | grep -q'；日志里不写二进制字节。"
  [ -n "${RUN_NOTE:-}" ] && { echo "#####"; echo "##### $RUN_NOTE"; }
  echo
} > "$LOG"

docker exec "$CONTAINER" \
  bash /workspace/scripts/chroot.sh run /workspace/scripts/pkg/8.31-ncurses.sh >> "$LOG" 2>&1
rc=$?

# chroot 内的脚本把各阶段完整输出留在 /sources（= 宿主 sources/），
# 这里把它们移进 logs/packages 作为留档，避免污染源码目录。
for pair in ".ncurses-configure.log:8.31-ncurses-6.6.configure.log" \
            ".ncurses-make.log:8.31-ncurses-6.6.make.log" \
            ".ncurses-destdir-install.log:8.31-ncurses-6.6.destdir-install.log" \
            ".ncurses-cp-to-root.log:8.31-ncurses-6.6.cp-to-root.log" \
            ".ncurses-doc.log:8.31-ncurses-6.6.doc.log" \
            ".ncurses-summary.log:8.31-ncurses-6.6.verify_summary.log"; do
  src=$LFS_ROOT/sources/${pair%%:*}
  dst=$LFS_ROOT/logs/packages/${pair#*:}
  if [ -f "$src" ]; then
    mv -f "$src" "$dst"
    echo "##### 留档：logs/packages/$(basename "$dst")（$(wc -l < "$dst") 行）" >> "$LOG"
  fi
done

echo "##### exec 退出码：$rc" >> "$LOG"
echo "退出码：$rc（日志：$LOG）"
exit $rc
