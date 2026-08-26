#!/usr/bin/env bash
# LFS 13.0-systemd §8.31 Ncurses-6.6
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.31.1 Installation of Ncurses 的命令序列（必需部分，一条不多一条不少）：
#   ./configure --prefix=/usr --mandir=/usr/share/man --with-shared --without-debug \
#               --without-normal --with-cxx-shared --enable-pc-files \
#               --with-pkg-config-libdir=/usr/lib/pkgconfig
#   make
#   make DESTDIR=$PWD/dest install
#   sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
#   cp --remove-destination -av dest/* /
#   for lib in ncurses form panel menu ; do
#       ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
#       ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
#   done
#   ln -sfv libncursesw.so /usr/lib/libcurses.so
#   cp -v -R doc -T /usr/share/doc/ncurses-6.6        （手册标注 "If desired"）
#
# 本节的三处结构性特点（照抄前几节的写法会扑空）：
#   1) **没有补丁、没有 build 子目录、没有 make check**。本节是 in-tree 构建；手册
#      对测试的原话是：「This package has a test suite, but it can only be run after
#      the package has been installed. The tests reside in the test/ directory. See
#      the README file in that directory for further details.」——手册**没有给出**
#      任何测试命令，故本节属于"手册未规定测试"，脚本不臆造一套 make check 出来。
#      下方会把 test/README 的相关段落摘进日志，并说明为什么不跑它（那批程序是
#      交互式 demo，需要真终端，且手册本身也没把它列为构建步骤）。
#   2) **安装必须走 DESTDIR + cp --remove-destination**，这不是本项目的自选动作，
#      是手册明写的要求：「The installation of this package will overwrite
#      libncursesw.so.6.6 in-place. It may crash the shell process which is using
#      code and data from the library file.」本 chroot 里的 /usr/bin/bash 正是
#      链接 libncursesw.so.6 的（脚本会用 ldd 与 /proc/$$/maps 实测给出证据），
#      而执行本脚本的就是一个 bash 进程——直接 make install 覆写就是在给自己动手术。
#      cp --remove-destination 先 unlink 旧 inode 再落新文件，旧 inode 被正在运行的
#      进程继续持有，所以安全。脚本会记录安装前后 libncursesw.so.6.6 的 inode，
#      并在安装后查 /proc/$$/maps 里那一行变成 "(deleted)"，把这件事坐实。
#   3) **第 6 章已经装过一次 Ncurses-6.6**（§6.3，交叉编译版）。所以本节不是首次安装，
#      而是**用原生工具链重装同一版本**。前置检查会把 §6.3 的产物记录下来作为对照，
#      安装后再对比 inode/构建 ID 变化，证明确实被替换了。
#
# 手册 §8.31.1 末尾那个 Note（ABI 5 非宽字符库）**不执行**：原文的前提是
#   「If you must have such libraries because of some binary-only application or to be
#     compliant with LSB」——本项目没有任何 binary-only 应用，也不追求 LSB 合规，
#   且手册自己说明 "The instructions above don't create non-wide-character Ncurses
#   libraries since no package installed by compiling from sources would link against
#   them at runtime"。故跳过 make distclean / --with-abi-version=5 那一整段。
#
# 手册的 doc 安装标注为 "If desired"（可选）。本节**执行**它，理由是 §8.31.2 Contents
#   的 "Installed directories" 里明列 /usr/share/doc/ncurses-6.6——不装它，本节的
#   Contents 核对就少一项。本项目 §8.10 zstd/§8.12 readline/§8.22 gmp 等节同样装了 doc。
#
# 自检断言的校准方式：本包 0.2 SBU / 47 MB，故正式开工前先在 chroot 的 /tmp 里做了
#   **完整**试建（configure + make + make DESTDIR=... install，不写系统），本脚本里每一条
#   带等号的数字都是在那次试建的产物上数出来的，试建目录随后已删除
#   （脚本 scripts/pkg/8.31-ncurses-trial.sh）。校准出的关键事实：
#     - dest 树规模：55 个目录 / 3073 个普通文件 / 813 个符号链接，**0 个 .a**
#       （--without-normal + --with-cxx-shared 的可观测结果）；
#     - /usr/bin 11 个条目 = 8 个真程序（clear infocmp ncursesw6-config tabs tic toe
#       tput tset）+ 3 个**符号链接**（captoinfo->tic、infotocap->tic、reset->tset）。
#       手册 Contents 写的 "captoinfo (link to tic)" 就是指符号链接，不是硬链接；
#     - 5 个共享库实体 libncursesw/libformw/libmenuw/libpanelw/libncurses++w .so.6.6，
#       SONAME 一律 lib*.so.6（ABI 后缀 w 来自 configure 的 "ABI suffix: w"）；
#     - 5 个 .pc：ncursesw formw menuw panelw ncurses++w（注意 ncurses++w **没有**
#       对应的 ncurses++.pc 符号链接，手册的 for 循环只覆盖 4 个）；
#     - 18 个头文件；man1 10 文件+1 链接（reset.1->tset.1）、man3 120 文件+797 链接、
#       man5 4、man7 1；terminfo 2899 个条目分布在 42 个子目录；tabset 4 个文件；
#     - curses.h 里 '^#if.*XOPEN.*$' 恰好命中 **1** 行（第 256 行）。注意第 95 行也是
#       "#if 1"，但那是 configure 生成的原样内容，不是 sed 改出来的——数行数时别数错；
#     - **make DESTDIR=... install 的输出里会出现恰好 5 处 "Error 1 (ignored)"**，
#       全部来自各 Makefile 里那条 `test -z "$(DESTDIR)" && $(LDCONFIG)`：DESTDIR 非空时
#       test -z 返回 1，规则前缀是 '-' 所以被 make 忽略。它是 DESTDIR 安装的**正常**
#       现象（正因如此，DESTDIR 安装不会跑 ldconfig），不是构建失败。脚本把这 5 处
#       逐条打出来核对，而不是看见 Error 就报警或看见 Error 就无视。
#
# 另按本项目既往教训（memory 里的 pipefail 记录）：所有用于**展示**的 diff/grep/ls/find
#   都包成 { … || true; }；不用 'cmd | grep -q'；文件名列表先落盘判空再喂给 grep；
#   日志里不写入任何二进制字节。
set -euo pipefail

PKG=ncurses
VER=6.6
TARBALL=$PKG-$VER.tar.gz
SRCDIR=$PKG-$VER
CFGLOG=/sources/.ncurses-configure.log
MAKELOG=/sources/.ncurses-make.log
INSTLOG=/sources/.ncurses-destdir-install.log
CPLOG=/sources/.ncurses-cp-to-root.log
DOCLOG=/sources/.ncurses-doc.log
SUMLOG=/sources/.ncurses-summary.log

echo "===== LFS 13.0-systemd §8.31 Ncurses-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Ncurses package contains libraries for terminal-independent handling"
echo "  of character screens."
echo "手册数据：Approximate build time 0.2 SBU，Required disk space 47 MB"
echo
echo "----- chroot 环境自述（手册 §7.4） -----"
echo "date      : $(date -Is)"
echo "hostname  : $(hostname 2>/dev/null || echo '(无)')"
echo "kernel    : $(uname -srm)"
echo "PATH      : $PATH"
echo "TERM      : ${TERM:-（未设置）}"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
esac
echo "  OK   PATH 中不含 /tools/bin（交叉工具链已不再使用）"
echo

# =========================================================================
echo "================= 前置检查（上一任务产物与本节依赖） ================="
rc=0

echo "1) 上一任务 §8.30 GCC-15.2.0 的产物是否可用："
echo "   说明：本节是**真的**依赖它，而且依赖的不止 C 编译器：手册给的"
echo "   --with-cxx-shared 要求构建 C++ 绑定 libncurses++w，没有可用的 g++ 与"
echo "   libstdc++ 这一项直接构建失败。"
for f in /usr/bin/gcc /usr/bin/g++ /usr/bin/cc /usr/bin/cpp /usr/lib/cpp \
         /usr/lib/libstdc++.so /usr/lib/libstdc++.so.6 /usr/lib/bfd-plugins/liblto_plugin.so; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   不只看文件在不在 —— 实际用它编一个 C 程序和一个 C++ 程序："
probe=/tmp/.ncurses-pre.$$
mkdir -p "$probe"
printf '#include <stdio.h>\nint main(void){printf("c-ok\\n");return 0;}\n' > "$probe/a.c"
printf '#include <iostream>\nint main(){std::cout<<"c++-ok"<<std::endl;return 0;}\n' > "$probe/a.cc"
set +e
( cd "$probe" && gcc -o ac a.c && ./ac ) 2>&1 | sed 's/^/     /'
c_rc=${PIPESTATUS[0]}
( cd "$probe" && g++ -o acc a.cc && ./acc ) 2>&1 | sed 's/^/     /'
cxx_rc=${PIPESTATUS[0]}
set -e
[ $c_rc  -eq 0 ] || { echo "     FAIL gcc 无法编译并运行 C 程序"; rc=1; }
[ $cxx_rc -eq 0 ] || { echo "     FAIL g++ 无法编译并运行 C++ 程序"; rc=1; }
{ gcc --version | sed -n 1p || true; }  | sed 's/^/     /'
{ g++ --version | sed -n 1p || true; }  | sed 's/^/     /'
echo "     gcc -dumpmachine：$(gcc -dumpmachine)"
echo "     C++ 程序的 NEEDED（应含 libstdc++.so.6，证明 §8.30 的共享 C++ 运行库在用）："
{ readelf -d "$probe/acc" 2>/dev/null | grep NEEDED || true; } | sed 's/^/       /'
rm -rf "$probe"
echo

echo "2) 本节构建链所需的其它工具："
for t in make sed gcc g++ ld ar awk grep install tar gzip find diff readelf pkg-config; do
  p=$({ command -v "$t" 2>/dev/null || true; })
  if [ -n "$p" ]; then printf '   OK   %-11s %s\n' "$t" "$p"
  else printf '   FAIL %-11s 未找到\n' "$t"; rc=1; fi
done
echo "   注：本包 tarball 是 .tar.gz，故 gzip 必须可用（前面几节多是 .tar.xz）。"
echo "   注：--enable-pc-files 会让 configure 去找 pkg-config；本系统的 pkg-config 来自"
echo "     §8.20 Pkgconf-2.5.1（$({ pkg-config --version || true; })）。手册同时给了"
echo "     --with-pkg-config-libdir=/usr/lib/pkgconfig，因此 .pc 的落点是写死的，"
echo "     不依赖 pkg-config 自报的搜索路径。"
echo "   当前 /usr/lib/pkgconfig 下的 .pc 数量（安装后本包应贡献 5 个真文件 + 4 个链接）："
pc_before=$({ ls /usr/lib/pkgconfig/*.pc 2>/dev/null || true; } | wc -l)
pc_nc_before=$({ ls /usr/lib/pkgconfig/ncursesw.pc /usr/lib/pkgconfig/formw.pc \
                    /usr/lib/pkgconfig/menuw.pc /usr/lib/pkgconfig/panelw.pc \
                    /usr/lib/pkgconfig/ncurses++w.pc /usr/lib/pkgconfig/ncurses.pc \
                    /usr/lib/pkgconfig/form.pc /usr/lib/pkgconfig/menu.pc \
                    /usr/lib/pkgconfig/panel.pc 2>/dev/null || true; } | wc -l)
echo "     总计 $pc_before 个，其中属于本包的 $pc_nc_before 个"
echo "     （§6.3 没有用 --enable-pc-files，所以首次执行本节时后者应为 0；本脚本可重跑，"
echo "       重跑时它会是 9，故判据写成「安装后本包的 9 个齐全」而不是「总数增加 9」。）"
echo

echo "3) 系统里已有的 Ncurses-6.6（本节要**原地替换**它）："
echo "   说明：首次执行本节时，这份是第 6 章 §6.3 用交叉工具链装的；本脚本是可重跑的，"
echo "     重跑时这份就是上一次执行留下的产物。两种情况下本节的动作完全一样。"
echo "   手册 §8.31.1 Caution 原文：The installation of this package will overwrite"
echo "     libncursesw.so.6.6 in-place. It may crash the shell process which is using"
echo "     code and data from the library file."
for f in /usr/lib/libncursesw.so.6.6 /usr/lib/libncursesw.so.6 /usr/lib/libncursesw.so \
         /usr/lib/libncurses.so /usr/include/curses.h /usr/bin/tic /usr/bin/tput \
         /usr/share/terminfo /usr/lib/terminfo; do
  if [ -e "$f" ]; then printf '   OK   %s（已存在，将被替换）\n' "$f"
  else printf '   INFO %s 不存在\n' "$f"; fi
done
old_lib_inode=$({ stat -c %i /usr/lib/libncursesw.so.6.6 2>/dev/null || echo 0; })
old_tic_inode=$({ stat -c %i /usr/bin/tic 2>/dev/null || echo 0; })
echo "   安装前 inode：libncursesw.so.6.6=$old_lib_inode  /usr/bin/tic=$old_tic_inode"
echo "   已装的 terminfo 条目数：$({ find /usr/share/terminfo -type f | wc -l; })"
echo "   **本脚本自己就是那个「using code and data from the library file」的进程**："
echo "     ldd /usr/bin/bash："
{ ldd /usr/bin/bash || true; } | sed 's/^/       /'
echo "     当前 shell（PID $$）映射到的 ncurses 库（注意必须查 /proc/\$\$/maps 而不是"
echo "       /proc/self/maps —— 后者会被执行 grep 的那个进程解析成 **grep 自己的** maps，"
echo "       那里当然没有 libncursesw，白白得出「没映射」的错误结论）："
{ grep -E 'libncursesw' /proc/$$/maps || true; } | sed 's/^/       /'
maps_hit=$({ grep -cE 'libncursesw' /proc/$$/maps || true; })
if [ "${maps_hit:-0}" -gt 0 ]; then
  echo "     OK   证实本 shell 正持有 libncursesw 的代码/数据——手册要求 DESTDIR +"
  echo "          cp --remove-destination 的原因在本环境是真实存在的，不是形式主义。"
else
  echo "     INFO 本 shell 未映射 libncursesw（不影响后续步骤，仍按手册用 DESTDIR 安装）"
fi
echo

echo "4) 手册 §7.5.1 的硬性约束（安装后会再查一次）："
if [ -e /usr/lib64 ]; then echo "   FAIL /usr/lib64 存在"; rc=1
else echo "   OK   /usr/lib64 不存在"; fi
echo "   根文件系统可用空间（手册要求 47 MB）："
{ df -h / | tail -n1 || true; } | sed 's/^/     /'
echo

if [ $rc -ne 0 ]; then
  echo "前置检查未通过，按任务要求不继续 §8.31。" >&2
  exit 1
fi
echo "前置检查全部通过。"
echo

# =========================================================================
echo "----- 源码包校验（md5sums，手册 §3.1） -----"
cd /sources
echo "官方 md5sums 中本包一行：$({ grep -F "$TARBALL" /sources/md5sums || true; })"
echo "实测：$(md5sum $TARBALL)"
{ grep -F "$TARBALL" /sources/md5sums || true; } | md5sum -c -
echo
echo "----- 补丁 -----"
echo "手册 §8.31 **没有**要求任何补丁（对照 §3.2 Required Patches 列表里也没有 ncurses 项）。"
{ ls /sources/*.patch 2>/dev/null | { grep -i ncurses || true; } | sed 's/^/  /'; } || true
echo "  /sources 下与 ncurses 相关的补丁文件：$({ ls /sources/*.patch 2>/dev/null || true; } | { grep -ci ncurses || true; }) 个（应为 0）"
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
[ -d "$SRCDIR" ] && { echo "发现上次遗留的 $SRCDIR，先删除以保证从干净源码开始"; rm -rf "$SRCDIR"; }
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "构建目录：$(pwd)（in-tree build，本节手册没有 mkdir build）"
echo "源码树顶层：$(ls | tr '\n' ' ')"
echo "源码自述版本（VERSION 文件，格式为 ABI:REL:PATCHDATE）：$({ cat VERSION || true; })"
src_ver=$({ cut -f2 VERSION 2>/dev/null || true; })
if [ "$src_ver" = "$VER" ]; then echo "  OK   源码自述发行版本 $src_ver 与包名一致"
else echo "  FAIL 源码自述发行版本 [$src_ver] ≠ $VER"; exit 1; fi
echo

# =========================================================================
echo "================= 8.31.1. Installation of Ncurses ================="
echo
echo "----- 手册命令 1/8：configure -----"
echo "手册原文：Prepare Ncurses for compilation:"
echo "手册命令："
echo "  ./configure --prefix=/usr           \\"
echo "              --mandir=/usr/share/man \\"
echo "              --with-shared           \\"
echo "              --without-debug         \\"
echo "              --without-normal        \\"
echo "              --with-cxx-shared       \\"
echo "              --enable-pc-files       \\"
echo "              --with-pkg-config-libdir=/usr/lib/pkgconfig"
echo "手册对新选项的说明（The meaning of the new configure options）："
echo "  --with-shared      : This makes Ncurses build and install shared C libraries."
echo "  --without-normal   : This prevents Ncurses building and installing static C libraries."
echo "  --without-debug    : This prevents Ncurses building and installing debug libraries."
echo "  --with-cxx-shared  : This makes Ncurses build and install shared C++ bindings. It also"
echo "                       prevents it building and installing static C++ bindings."
echo "  --enable-pc-files  : This switch generates and installs .pc files for pkg-config."
echo "（完整输出另存到 $CFGLOG）"
cfg_start=$(date +%s)
set +e
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig > "$CFGLOG" 2>&1
cfg_rc=$?
set -e
cfg_end=$(date +%s)
echo "configure 退出码：$cfg_rc，耗时 $((cfg_end-cfg_start)) 秒，输出 $({ wc -l < "$CFGLOG"; }) 行"
if [ $cfg_rc -ne 0 ]; then
  echo "configure 失败，尾部 40 行："; tail -n 40 "$CFGLOG" | sed 's/^/  /'
  exit $cfg_rc
fi
echo "configure 末尾的 Configuration summary（手册没有要求核对，但它把每个选项的落点"
echo "  都算好了，是核对 --prefix/--mandir/--with-pkg-config-libdir 是否真的生效的最直接证据）："
{ sed -n '/Configuration summary for NCURSES/,$p' "$CFGLOG" || true; } | sed 's/^/  /'
cfg_rc2=0
check_summary() {   # <正则> <人话>
  local pat=$1 desc=$2 line
  line=$({ grep -m1 -E "$pat" "$CFGLOG" || true; })
  if [ -n "$line" ]; then printf '  OK   %-28s %s\n' "$desc" "$(echo "$line" | sed 's/^ *//')"
  else printf '  FAIL %-28s 未在 summary 中找到（正则 %s）\n' "$desc" "$pat"; cfg_rc2=1; fi
}
check_summary '^ *bin directory: */usr/bin$'                  "--prefix=/usr → bin"
check_summary '^ *lib directory: */usr/lib$'                  "--prefix=/usr → lib（非 lib64）"
check_summary '^ *include directory: */usr/include$'          "--prefix=/usr → include"
check_summary '^ *man directory: */usr/share/man$'            "--mandir=/usr/share/man"
check_summary '^ *terminfo directory: */usr/share/terminfo$'  "terminfo 落点"
check_summary '^ *pkg-config directory: */usr/lib/pkgconfig$' "--with-pkg-config-libdir"
check_summary '^ *ABI suffix: *w$'                            "宽字符 ABI（后缀 w）"
echo "  --without-normal / --without-debug / --with-shared / --with-cxx-shared 的生效证据"
echo "  不在 summary 里，而在 Makefile 生成的 model 规则中——configure 日志里的"
echo "  \"Appending rules for shared model\" 行（应只有 shared，没有 normal/debug）："
{ grep -E '^Appending rules for .* model' "$CFGLOG" || true; } | sed 's/^/    /'
n_shared=$({ grep -cE '^Appending rules for shared model' "$CFGLOG" || true; })
n_other=$({ grep -E '^Appending rules for .* model' "$CFGLOG" || true; } | { grep -vc 'shared model' || true; })
echo "    shared model 规则 $n_shared 条；非 shared（normal/debug/profile）规则 ${n_other:-0} 条"
if [ "${n_other:-0}" -eq 0 ]; then echo "    OK   只生成了 shared 模型 —— --without-normal/--without-debug 已生效"
else echo "    FAIL 出现了非 shared 模型的规则"; cfg_rc2=1; fi
cxx_shared=$({ grep -m1 -E '^Appending rules for shared model \(c\+\+' "$CFGLOG" || true; })
if [ -n "$cxx_shared" ]; then echo "    OK   c++ 子目录也走 shared 模型 —— --with-cxx-shared 已生效"
else echo "    FAIL 未见 c++ 的 shared 模型规则"; cfg_rc2=1; fi
[ $cfg_rc2 -eq 0 ] || { echo "configure 结果与手册选项不符" >&2; exit 1; }
echo

echo "----- 手册命令 2/8：make -----"
echo "手册原文：Compile the package:"
echo "手册命令：make"
echo "（完整输出另存到 $MAKELOG；MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境给出）"
mk_start=$(date +%s)
set +e
make > "$MAKELOG" 2>&1
make_rc=$?
set -e
mk_end=$(date +%s)
echo "make 退出码：$make_rc，耗时 $((mk_end-mk_start)) 秒，输出 $({ wc -l < "$MAKELOG"; }) 行"
if [ $make_rc -ne 0 ]; then
  echo "make 失败，尾部 60 行："; tail -n 60 "$MAKELOG" | sed 's/^/  /'
  exit $make_rc
fi
echo "make 输出中的失败迹象（Error / *** / undefined reference，应为空）："
{ grep -nE '(^|[^-])Error [0-9]|\*\*\*|undefined reference' "$MAKELOG" || true; } | sed 's/^/  /'
n_err=$({ grep -cE '(^|[^-])Error [0-9]|\*\*\*|undefined reference' "$MAKELOG" || true; })
if [ "${n_err:-0}" -eq 0 ]; then echo "  OK   0 处失败迹象"
else echo "  FAIL $n_err 处失败迹象"; exit 1; fi
echo "构建出的库（源码树 lib/ 下，尚未安装）："
{ ls -l lib/ | sed 's/  */ /g' || true; } | sed 's/^/  /'
echo "静态库 .a（--without-normal 的可观测结果，应为 0 个）：$({ find . -name '*.a' | wc -l; })"
echo "make 尾部 3 行："; tail -n 3 "$MAKELOG" | sed 's/^/  /'
echo

echo "----- 手册命令 3/8 之前：本节的测试问题 -----"
echo "手册原文（§8.31.1，紧跟在 make 之后）："
echo "  「This package has a test suite, but it can only be run after the package has"
echo "    been installed. The tests reside in the test/ directory. See the README file"
echo "    in that directory for further details.」"
echo "解读：手册在本节**没有给出任何测试命令**，也没有把测试列为构建步骤（对照 §8.30"
echo "  GCC 那种明写 'su tester -c \"PATH=\$PATH make -k check\"' 的节）。因此本节属于"
echo "  「手册未规定测试」，脚本不臆造一套 make check —— 那既不是手册命令，跑出来的"
echo "  失败也无手册判据可依。"
echo "test/ 目录里到底是什么（README 摘要，证明上面的判断不是偷懒）："
{ sed -n '/^The programs in this directory/,/^$/p' test/README || true; } | sed 's/^/  /'
echo "test/ 目录规模：$({ ls test || true; } | wc -l) 个条目，其中 .c 源文件 $({ ls test/*.c 2>/dev/null || true; } | wc -l) 个"
echo "  这批程序（blue/bs/firework/gdc/hanoi/knight/worm/ncurses…）是**交互式 demo**，"
echo "  要真终端、要人按键才能推进，非交互 chroot 里跑它们只会得到一堆假结果。"
echo "本节的正确做法：手册规定的验证落在安装结果本身——§8.31.2 Contents 的程序/库/目录"
echo "  清单。脚本在安装后逐项核对，并另做一组**非交互**的功能验证（编译链接 + 运行"
echo "  tic/infocmp/tput/toe/tabs），这组验证明确标注为「手册之外的自检」。"
echo

echo "----- 手册命令 3/8：make DESTDIR=\$PWD/dest install -----"
echo "手册原文（Caution 之后）：Install the package with DESTDIR, and replace the library"
echo "  file correctly using the --remove-destination option of cp (the header curses.h"
echo "  is also edited to ensure the wide-character ABI to be used as what we've done in"
echo "  Section 6.3, \"Ncurses-6.6\")."
echo "手册命令：make DESTDIR=\$PWD/dest install"
echo "（完整输出另存到 $INSTLOG）"
inst_start=$(date +%s)
set +e
make DESTDIR=$PWD/dest install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
inst_end=$(date +%s)
echo "make DESTDIR install 退出码：$inst_rc，耗时 $((inst_end-inst_start)) 秒，输出 $({ wc -l < "$INSTLOG"; }) 行"
if [ $inst_rc -ne 0 ]; then
  echo "DESTDIR 安装失败，尾部 60 行："; tail -n 60 "$INSTLOG" | sed 's/^/  /'
  exit $inst_rc
fi
echo
echo "输出里的 \"Error 1 (ignored)\"（试建校准：恰好 5 处，且全部是正常现象）："
{ grep -n 'Error 1 (ignored)' "$INSTLOG" || true; } | sed 's/^/  /'
n_ign=$({ grep -c 'Error 1 (ignored)' "$INSTLOG" || true; })
echo "  处数：${n_ign:-0}"
echo "  成因（不是猜的，是从安装日志里把上一行原样取出来看的）：每个库的 install 规则"
echo "    末尾都有一条 \`test -z \"\$(DESTDIR)\" && \$(LDCONFIG)\`。DESTDIR 非空时 test -z"
echo "    返回 1，这条 shell 命令就以 1 退出；规则前缀是 '-'，所以 make 打一行"
echo "    \"Error 1 (ignored)\" 继续走。它的实际含义是「因为在往 DESTDIR 里装，所以"
echo "    跳过 ldconfig」——正是手册要的行为。"
echo "  证据：这 5 处的前一行都应是那条 test -z 命令："
{ grep -B1 'Error 1 (ignored)' "$INSTLOG" | { grep 'test -z' || true; } | sed 's/^/    /'; } || true
n_testz=$({ grep -B1 'Error 1 (ignored)' "$INSTLOG" || true; } | { grep -c 'test -z' || true; })
if [ "${n_ign:-0}" -eq 5 ] && [ "${n_testz:-0}" -eq 5 ]; then
  echo "  OK   5 处 Error 1 (ignored)，5 处都由 test -z DESTDIR && ldconfig 引起（与试建一致）"
else
  echo "  FAIL Error 1 (ignored) 有 ${n_ign:-0} 处、其中由 test -z 引起的 ${n_testz:-0} 处，试建校准值为 5/5"
  exit 1
fi
echo "输出里其它失败迹象（非 ignored 的 Error / ***，应为空）："
{ grep -nE '\*\*\*|Error [0-9]' "$INSTLOG" | { grep -v 'Error 1 (ignored)' || true; } | sed 's/^/  /'; } || true
n_err2=$({ grep -E '\*\*\*|Error [0-9]' "$INSTLOG" || true; } | { grep -vc 'Error 1 (ignored)' || true; })
if [ "${n_err2:-0}" -eq 0 ]; then echo "  OK   0 处"
else echo "  FAIL ${n_err2} 处"; exit 1; fi
echo
echo "dest 树核对（试建校准值：55 目录 / 3073 文件 / 813 链接 / 0 个 .a）："
d_dirs=$({ find dest -mindepth 1 -type d | wc -l; })
d_files=$({ find dest -type f | wc -l; })
d_links=$({ find dest -type l | wc -l; })
d_a=$({ find dest -name '*.a' | wc -l; })
printf '  目录 %s / 文件 %s / 链接 %s / 静态库 %s\n' "$d_dirs" "$d_files" "$d_links" "$d_a"
dest_rc=0
[ "$d_dirs"  -eq 55   ] || { echo "  FAIL 目录数 $d_dirs ≠ 55"; dest_rc=1; }
[ "$d_files" -eq 3073 ] || { echo "  FAIL 文件数 $d_files ≠ 3073"; dest_rc=1; }
[ "$d_links" -eq 813  ] || { echo "  FAIL 链接数 $d_links ≠ 813"; dest_rc=1; }
[ "$d_a"     -eq 0    ] || { echo "  FAIL 出现 $d_a 个静态库（--without-normal 应使其为 0）"; dest_rc=1; }
[ $dest_rc -eq 0 ] && echo "  OK   与试建校准值逐项一致"
echo "  dest/usr/bin（8 个真程序 + 3 个符号链接）："
{ ls -l dest/usr/bin | sed 's/  */ /g' || true; } | sed 's/^/    /'
echo "  dest/usr/lib（5 个 .so.6.6 实体 + 各自的两级符号链接 + pkgconfig + terminfo 链接）："
{ ls -l dest/usr/lib | sed 's/  */ /g' || true; } | sed 's/^/    /'
echo "  dest/usr/lib/pkgconfig（--enable-pc-files 的产物，5 个）："
{ ls dest/usr/lib/pkgconfig || true; } | sed 's/^/    /'
echo "  各共享库的 SONAME："
for f in $({ find dest/usr/lib -maxdepth 1 -name '*.so.6.6' -type f | sort; }); do
  echo "    $(basename "$f")  SONAME=$({ readelf -d "$f" | grep SONAME || true; } | sed 's/.*\[//;s/\].*//')"
done
[ $dest_rc -eq 0 ] || { echo "dest 树与试建校准不符" >&2; exit 1; }
echo

echo "----- 手册命令 4/8：sed 改 dest 里的 curses.h（宽字符 ABI） -----"
echo "手册命令：sed -e 's/^#if.*XOPEN.*\$/#if 1/' -i dest/usr/include/curses.h"
echo "作用：让 curses.h 无条件启用宽字符 ABI（NCURSES_WIDECHAR=1），这样后面那批"
echo "  lib*.so -> lib*w.so 的符号链接才是安全的——手册原话：note that the .so links"
echo "  are only safe with curses.h edited to always use the wide-character ABI。"
echo "执行前命中的行（试建校准：恰好 1 行，在第 256 行）："
{ grep -n '^#if.*XOPEN.*$' dest/usr/include/curses.h || true; } | sed 's/^/  /'
n_xopen=$({ grep -c '^#if.*XOPEN.*$' dest/usr/include/curses.h || true; })
echo "  命中行数：${n_xopen:-0}"
cp dest/usr/include/curses.h /tmp/.curses.h.before
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
echo "diff（应恰好改这一行）："
{ diff /tmp/.curses.h.before dest/usr/include/curses.h || true; } | sed 's/^/  /'
n_diff=$({ diff /tmp/.curses.h.before dest/usr/include/curses.h || true; } | { grep -c '^[<>]' || true; })
rm -f /tmp/.curses.h.before
if [ "${n_xopen:-0}" -eq 1 ] && [ "${n_diff:-0}" -eq 2 ]; then
  echo "  OK   1 行命中、diff 恰好一增一删（与试建一致）"
else
  echo "  FAIL 命中 ${n_xopen:-0} 行、diff ${n_diff:-0} 行，试建校准值为 1 行 / 2 行"; exit 1
fi
echo "  改后该行及其上下文："
{ grep -n -A2 -B2 '^#if 1$' dest/usr/include/curses.h | { grep -A2 -B2 'NCURSES_WIDECHAR 1' || true; } | sed 's/^/    /'; } || true
echo

echo "----- 手册命令 5/8：cp --remove-destination -av dest/* / -----"
echo "手册命令：cp --remove-destination -av dest/* /"
echo "关键点：--remove-destination 让 cp 先 unlink 目标再写新文件，于是正在运行的进程"
echo "  （包括执行本脚本的这个 bash）继续持有旧 inode，不会被写坏。这正是手册 Caution"
echo "  说的 \"It may crash the shell process\" 的解法。"
echo "（完整输出另存到 $CPLOG —— cp -v 会打出三千多行）"
echo "安装前 inode：libncursesw.so.6.6=$({ stat -c %i /usr/lib/libncursesw.so.6.6 2>/dev/null || echo 无; })"
set +e
cp --remove-destination -av dest/* / > "$CPLOG" 2>&1
cp_rc=$?
set -e
echo "cp 退出码：$cp_rc，输出 $({ wc -l < "$CPLOG"; }) 行"
if [ $cp_rc -ne 0 ]; then
  echo "cp 失败，尾部 40 行："; tail -n 40 "$CPLOG" | sed 's/^/  /'
  exit $cp_rc
fi
echo "cp 输出抽样（前 6 行 / 后 6 行）："
{ head -n 6 "$CPLOG" || true; } | sed 's/^/  /'
echo "  ..."
{ tail -n 6 "$CPLOG" || true; } | sed 's/^/  /'
new_lib_inode=$({ stat -c %i /usr/lib/libncursesw.so.6.6 || echo 0; })
new_tic_inode=$({ stat -c %i /usr/bin/tic || echo 0; })
echo "安装后 inode：libncursesw.so.6.6=$new_lib_inode（安装前 $old_lib_inode）"
echo "              /usr/bin/tic=$new_tic_inode（安装前 $old_tic_inode）"
echo "  注意：inode **号**前后相同并不说明文件没被替换 —— ext4 的分配器很可能把刚"
echo "    unlink 释放出来的那个 inode 号立刻分配给同一目录里新建的文件。所以这里"
echo "    不拿 inode 号变化当判据（那会得出假结论，也可能造成假失败），真正的判据是"
echo "    下面两条：(a) 装到系统里的文件与 dest 里的**逐字节相同**；(b) 旧 inode 已被"
echo "    unlink —— 本 shell 的映射里那一行会显示 (deleted)。"
echo "  (a) 与 dest 逐字节比对："
set +e
cmp dest/usr/lib/libncursesw.so.6.6 /usr/lib/libncursesw.so.6.6; cmp_lib=$?
cmp dest/usr/bin/tic               /usr/bin/tic;                cmp_tic=$?
set -e
if [ $cmp_lib -eq 0 ]; then echo "    OK   /usr/lib/libncursesw.so.6.6 == dest 中的同名文件"
else echo "    FAIL /usr/lib/libncursesw.so.6.6 与 dest 不一致（cmp 退出码 $cmp_lib）"; exit 1; fi
if [ $cmp_tic -eq 0 ]; then echo "    OK   /usr/bin/tic == dest 中的同名文件"
else echo "    FAIL /usr/bin/tic 与 dest 不一致（cmp 退出码 $cmp_tic）"; exit 1; fi
echo "    时间戳（cp -a 保留 dest 里的 mtime，即本次构建的时刻）："
{ stat -c '      %n  mtime=%y  ctime=%z' /usr/lib/libncursesw.so.6.6 /usr/bin/tic || true; }
echo "  (b) 本 shell（PID $$）现在的映射（旧 inode 已被 unlink，应显示 (deleted)）："
{ grep -E 'libncursesw' /proc/$$/maps || true; } | sed 's/^/    /'
maps_del=$({ grep -E 'libncursesw.*\(deleted\)' /proc/$$/maps || true; } | wc -l)
if [ "$maps_del" -gt 0 ]; then
  echo "    OK   旧库文件确实是被 unlink 掉的（--remove-destination 的效果），"
  echo "         而本 shell 仍拿着它的旧 inode 正常运行——手册那条 Caution 说的崩溃没有发生。"
else
  echo "    INFO 映射里没有 (deleted) 标记（若本 shell 本来就没映射 libncursesw 则属正常）"
fi
echo "  本 shell 仍在正常运行（这行能打印出来本身就是证据）。"
echo

echo "----- 手册命令 6/8：非宽字符名字的兼容符号链接 -----"
echo "手册原文：Many applications still expect the linker to be able to find"
echo "  non-wide-character Ncurses libraries. Trick such applications into linking with"
echo "  wide-character libraries by means of symlinks (note that the .so links are only"
echo "  safe with curses.h edited to always use the wide-character ABI)."
echo "手册命令："
echo "  for lib in ncurses form panel menu ; do"
echo "      ln -sfv lib\${lib}w.so /usr/lib/lib\${lib}.so"
echo "      ln -sfv \${lib}w.pc    /usr/lib/pkgconfig/\${lib}.pc"
echo "  done"
for lib in ncurses form panel menu ; do
    ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
done
echo
echo "----- 手册命令 7/8：libcurses.so -----"
echo "手册原文：Finally, make sure that old applications that look for -lcurses at build"
echo "  time are still buildable:"
echo "手册命令：ln -sfv libncursesw.so /usr/lib/libcurses.so"
ln -sfv libncursesw.so /usr/lib/libcurses.so
echo
echo "本节建立的 9 个符号链接逐条复核："
ln_rc=0
for pair in "/usr/lib/libncurses.so:libncursesw.so" "/usr/lib/libform.so:libformw.so" \
            "/usr/lib/libpanel.so:libpanelw.so"     "/usr/lib/libmenu.so:libmenuw.so" \
            "/usr/lib/libcurses.so:libncursesw.so" \
            "/usr/lib/pkgconfig/ncurses.pc:ncursesw.pc" "/usr/lib/pkgconfig/form.pc:formw.pc" \
            "/usr/lib/pkgconfig/panel.pc:panelw.pc"     "/usr/lib/pkgconfig/menu.pc:menuw.pc"; do
  p=${pair%%:*}; t=${pair#*:}
  a=$({ readlink "$p" 2>/dev/null || true; })
  if [ "$a" = "$t" ] && [ -e "$p" ]; then printf '  OK   %-34s -> %-16s（且可解析到实体）\n' "$p" "$t"
  else printf '  FAIL %-34s -> [%s]，期望 %s\n' "$p" "$a" "$t"; ln_rc=1; fi
done
echo "  注：ncurses++w.pc **没有**对应的 ncurses++.pc —— 手册的 for 循环只覆盖"
echo "    ncurses/form/panel/menu 四个，这不是遗漏，C++ 绑定本来就只有宽字符版。"
[ $ln_rc -eq 0 ] || { echo "符号链接不符合手册" >&2; exit 1; }
echo

echo "----- 手册命令 8/8：安装文档（手册标注 If desired） -----"
echo "手册原文：If desired, install the Ncurses documentation:"
echo "手册命令：cp -v -R doc -T /usr/share/doc/ncurses-6.6"
echo "本项目**执行**这条可选命令，理由：§8.31.2 Contents 的 Installed directories 里"
echo "  明列 /usr/share/doc/ncurses-6.6，不装它本节的 Contents 核对就少一项。"
set +e
cp -v -R doc -T /usr/share/doc/ncurses-$VER > "$DOCLOG" 2>&1
doc_rc=$?
set -e
echo "cp doc 退出码：$doc_rc，输出 $({ wc -l < "$DOCLOG"; }) 行（完整输出另存到 $DOCLOG）"
[ $doc_rc -eq 0 ] || { echo "文档安装失败："; tail -n 20 "$DOCLOG" | sed 's/^/  /'; exit $doc_rc; }
n_doc=$({ find /usr/share/doc/ncurses-$VER -type f | wc -l; })
echo "  /usr/share/doc/ncurses-$VER 下文件数：$n_doc（试建校准值 245）"
if [ "$n_doc" -eq 245 ]; then echo "  OK   与试建一致"
else echo "  FAIL 与试建校准值 245 不符"; exit 1; fi
{ ls /usr/share/doc/ncurses-$VER || true; } | sed 's/^/    /'
echo

# =========================================================================
echo "================= 8.31.2. Contents of Ncurses —— 逐项核对 ================="
ck_rc=0
echo "1) Installed programs：captoinfo (link to tic), clear, infocmp, infotocap (link to"
echo "   tic), ncursesw6-config, reset (link to tset), tabs, tic, toe, tput, tset"
for p in captoinfo clear infocmp infotocap ncursesw6-config reset tabs tic toe tput tset; do
  if [ -e "/usr/bin/$p" ]; then
    if [ -L "/usr/bin/$p" ]; then printf '   OK   /usr/bin/%-17s 符号链接 -> %s\n' "$p" "$({ readlink /usr/bin/$p; })"
    else printf '   OK   /usr/bin/%-17s 可执行文件（%s 字节）\n' "$p" "$({ stat -c %s /usr/bin/$p; })"; fi
  else printf '   FAIL /usr/bin/%-17s 缺失\n' "$p"; ck_rc=1; fi
done
echo "   手册标注的三个 link 是否确为链接、且指向手册说的目标："
for pair in "captoinfo:tic" "infotocap:tic" "reset:tset"; do
  p=${pair%%:*}; t=${pair#*:}
  a=$({ readlink /usr/bin/$p 2>/dev/null || true; })
  if [ "$a" = "$t" ]; then printf '   OK   %-10s -> %s\n' "$p" "$t"
  else printf '   FAIL %-10s -> [%s]，手册说应指向 %s\n' "$p" "$a" "$t"; ck_rc=1; fi
done
echo
echo "2) Installed libraries：libcurses.so (symlink), libform.so (symlink), libformw.so,"
echo "   libmenu.so (symlink), libmenuw.so, libncurses.so (symlink), libncursesw.so,"
echo "   libncurses++w.so, libpanel.so (symlink), libpanelw.so"
for l in libcurses.so libform.so libformw.so libmenu.so libmenuw.so \
         libncurses.so libncursesw.so libncurses++w.so libpanel.so libpanelw.so; do
  if [ -e "/usr/lib/$l" ]; then
    printf '   OK   /usr/lib/%-18s -> %s\n' "$l" "$({ readlink -f /usr/lib/$l | sed 's|/usr/lib/||'; })"
  else printf '   FAIL /usr/lib/%-18s 缺失\n' "$l"; ck_rc=1; fi
done
echo "   5 个共享库实体与其 SONAME："
for f in /usr/lib/libncursesw.so.6.6 /usr/lib/libformw.so.6.6 /usr/lib/libmenuw.so.6.6 \
         /usr/lib/libpanelw.so.6.6 /usr/lib/libncurses++w.so.6.6; do
  if [ -f "$f" ]; then
    printf '   OK   %-32s SONAME=%s\n' "$f" "$({ readelf -d "$f" | grep SONAME || true; } | sed 's/.*\[//;s/\].*//')"
  else printf '   FAIL %s 缺失\n' "$f"; ck_rc=1; fi
done
echo "   /usr/lib 下的 ncurses 静态库（--without-normal + --with-cxx-shared，应为 0 个）："
n_a=$({ ls /usr/lib/libncurses*.a /usr/lib/libform*.a /usr/lib/libmenu*.a /usr/lib/libpanel*.a 2>/dev/null || true; } | wc -l)
echo "     $n_a 个"
[ "$n_a" -eq 0 ] || { echo "     FAIL 不应存在静态库"; ck_rc=1; }
echo
echo "3) Installed directories：/usr/share/tabset, /usr/share/terminfo, /usr/share/doc/ncurses-6.6"
for d in /usr/share/tabset /usr/share/terminfo /usr/share/doc/ncurses-$VER; do
  if [ -d "$d" ]; then printf '   OK   %-32s（%s 个文件）\n' "$d" "$({ find "$d" -type f | wc -l; })"
  else printf '   FAIL %s 缺失\n' "$d"; ck_rc=1; fi
done
echo "   细目（试建校准值：tabset 4 个文件；terminfo 2899 个条目分布在 42 个子目录）："
n_tab=$({ find /usr/share/tabset -type f | wc -l; })
n_ti=$({ find /usr/share/terminfo -type f | wc -l; })
n_tid=$({ find /usr/share/terminfo -mindepth 1 -type d | wc -l; })
printf '     tabset=%s  terminfo 条目=%s  terminfo 子目录=%s\n' "$n_tab" "$n_ti" "$n_tid"
[ "$n_tab" -eq 4 ]    || { echo "     FAIL tabset 文件数 ≠ 4"; ck_rc=1; }
[ "$n_ti"  -eq 2899 ] || { echo "     FAIL terminfo 条目数 ≠ 2899"; ck_rc=1; }
[ "$n_tid" -eq 42 ]   || { echo "     FAIL terminfo 子目录数 ≠ 42"; ck_rc=1; }
echo "   手册 Contents 未列、但确实装出的东西（记录在案，不作断言之外的评判）："
n_h=$({ ls /usr/include/*.h 2>/dev/null || true; } | wc -l)
echo "       /usr/include 下 .h 总数（含其它包）：$n_h"
echo "       本包的 18 个（试建校准值，逐个查）："
n_hit=0
for h in curses.h ncurses.h ncurses_dll.h term.h term_entry.h termcap.h unctrl.h \
         panel.h menu.h form.h eti.h etip.h \
         cursesw.h cursesapp.h cursesf.h cursesm.h cursesp.h cursslk.h; do
  if [ -e "/usr/include/$h" ]; then n_hit=$((n_hit+1))
  else printf '       FAIL /usr/include/%s 缺失\n' "$h"; ck_rc=1; fi
done
echo "       到位 $n_hit / 18"
[ "$n_hit" -eq 18 ] || ck_rc=1
echo "     pkg-config 文件 9 个（5 真 + 4 链接）："
{ ls -l /usr/lib/pkgconfig/ | { grep -E 'ncurses|form|menu|panel' || true; } | sed 's/  */ /g' | sed 's/^/       /'; } || true
pc_after=$({ ls /usr/lib/pkgconfig/*.pc 2>/dev/null || true; } | wc -l)
pc_nc_after=$({ ls /usr/lib/pkgconfig/ncursesw.pc /usr/lib/pkgconfig/formw.pc \
                   /usr/lib/pkgconfig/menuw.pc /usr/lib/pkgconfig/panelw.pc \
                   /usr/lib/pkgconfig/ncurses++w.pc /usr/lib/pkgconfig/ncurses.pc \
                   /usr/lib/pkgconfig/form.pc /usr/lib/pkgconfig/menu.pc \
                   /usr/lib/pkgconfig/panel.pc 2>/dev/null || true; } | wc -l)
echo "       /usr/lib/pkgconfig 下 .pc 总数：安装前 $pc_before → 安装后 $pc_after"
echo "       其中属于本包的：安装前 $pc_nc_before → 安装后 $pc_nc_after（判据：安装后 = 9）"
if [ "$pc_nc_after" -eq 9 ]; then echo "       OK   本包的 9 个 .pc（5 真 + 4 链接）齐全"
else echo "       FAIL 本包的 .pc 只有 $pc_nc_after 个，期望 9"; ck_rc=1; fi
d_man_f=$({ find dest/usr/share/man -type f | wc -l; })
d_man_l=$({ find dest/usr/share/man -type l | wc -l; })
printf '     man 页：本包装出 %s 个文件 + %s 个链接（数字取自 dest 树）\n' "$d_man_f" "$d_man_l"
echo "       注意：/usr/share/man/man3 里混着 Perl、Readline 等包的页，拿**系统总数**去对"
echo "         试建值是错的判据（试建那 120/797 是 dest 树里的数）。正确判据是下面这条："
echo "         dest 树里的每一个条目，安装后都能在系统里找到。"
echo "       系统 man 目录现状（含其它包，仅记录，不作断言）："
printf '         man1 %s  man3 %s  man5 %s  man7 %s（文件+链接）\n' \
  "$({ find /usr/share/man/man1 -maxdepth 1 -mindepth 1 | wc -l; })" \
  "$({ find /usr/share/man/man3 -maxdepth 1 -mindepth 1 | wc -l; })" \
  "$({ find /usr/share/man/man5 -maxdepth 1 -mindepth 1 | wc -l; })" \
  "$({ find /usr/share/man/man7 -maxdepth 1 -mindepth 1 | wc -l; })"
echo "       本节自己的 man1 条目："
{ ls /usr/share/man/man1 | { grep -E '^(captoinfo|clear|infocmp|infotocap|ncursesw6-config|reset|tabs|tic|toe|tput|tset)\.' || true; } | tr '\n' ' ' | sed 's/^/         /'; echo; } || true

echo
echo "4) cp --remove-destination -av dest/* / 的完整性：dest 树的每一个条目都要在系统里存在"
echo "   （这才是本节安装结果的硬判据——比拿系统全局计数去对试建值可靠得多）"
miss_list=/tmp/.ncurses-missing.$$
: > "$miss_list"
while IFS= read -r f; do
  sys="/${f#dest/}"
  if [ ! -e "$sys" ] && [ ! -L "$sys" ]; then echo "$sys" >> "$miss_list"; fi
done < <(find dest -mindepth 1)
n_chk=$({ find dest -mindepth 1 | wc -l; })
n_miss=$({ wc -l < "$miss_list"; })
echo "   核对条目数：$n_chk（55 目录 + 3073 文件 + 813 链接），缺失：$n_miss"
if [ "$n_miss" -eq 0 ]; then echo "   OK   dest 树 100% 落地"
else echo "   FAIL 以下条目未落地（最多列 20 条）："; { head -n 20 "$miss_list" || true; } | sed 's/^/     /'; ck_rc=1; fi
rm -f "$miss_list"
echo "   再确认落地的是**本次构建的新文件**，不是 §6.3 的旧文件（逐字节比对两个关键文件）："
set +e
cmp dest/usr/lib/libncursesw.so.6.6 /usr/lib/libncursesw.so.6.6; c_lib=$?
cmp dest/usr/include/curses.h       /usr/include/curses.h;       c_hdr=$?
set -e
if [ $c_lib -eq 0 ]; then echo "     OK   /usr/lib/libncursesw.so.6.6 与 dest 中的完全一致"
else echo "     FAIL /usr/lib/libncursesw.so.6.6 与 dest 中的不一致（cmp 退出码 $c_lib）"; ck_rc=1; fi
if [ $c_hdr -eq 0 ]; then echo "     OK   /usr/include/curses.h 与 dest 中**经 sed 改过的**版本完全一致"
else echo "     FAIL /usr/include/curses.h 与 dest 中的不一致（cmp 退出码 $c_hdr）"; ck_rc=1; fi
echo "     /usr/lib/terminfo -> $({ readlink /usr/lib/terminfo || echo '(不是链接)'; })"
echo
if [ $ck_rc -ne 0 ]; then echo "Contents 核对未通过" >&2; exit 1; fi
echo "  §8.31.2 Contents 全部对上。"
echo

# =========================================================================
echo "================= 功能验证（手册之外的自检，非手册命令） ================="
echo "手册本节没有测试命令（原因见上），这里做一组**非交互**验证，确认装出来的东西"
echo "真的能用。任何一项失败都按失败处理。"
fn_rc=0
work=/tmp/.ncurses-verify.$$
mkdir -p "$work"; cd "$work"

echo "1) 11 个程序逐个运行（都用只打印版本/信息的安全选项，不去动真终端）："
for p in tic infocmp toe tput tset clear tabs captoinfo infotocap reset; do
  set +e
  out=$("/usr/bin/$p" -V 2>&1); prc=$?
  set -e
  if [ $prc -eq 0 ] && [ -n "$out" ]; then printf '   OK   %-12s -V → %s\n' "$p" "$(echo "$out" | head -n1)"
  else printf '   FAIL %-12s -V 退出码 %s，输出 [%s]\n' "$p" "$prc" "$(echo "$out" | head -n1)"; fn_rc=1; fi
done
set +e
out=$(/usr/bin/ncursesw6-config --version 2>&1); prc=$?
set -e
if [ $prc -eq 0 ]; then printf '   OK   %-12s --version → %s\n' ncursesw6-config "$out"
else printf '   FAIL ncursesw6-config --version 退出码 %s\n' "$prc"; fn_rc=1; fi
echo "   ncursesw6-config 自报的编译/链接参数（后续包会用到）："
{ echo "     --cflags : $(/usr/bin/ncursesw6-config --cflags 2>&1)"; \
  echo "     --libs   : $(/usr/bin/ncursesw6-config --libs 2>&1)"; \
  echo "     --abi    : $(/usr/bin/ncursesw6-config --abi-version 2>&1)"; } || true
echo

echo "2) terminfo 数据库真的可查（tput 读的是刚装的 /usr/share/terminfo）："
set +e
cols=$(TERM=xterm tput -T xterm cols 2>&1); c1=$?
colors=$(tput -T xterm-256color colors 2>&1); c2=$?
lname=$(tput -T vt100 longname 2>&1); c3=$?
set -e
printf '   tput -T xterm cols            → %s（退出码 %s）\n' "$cols" "$c1"
printf '   tput -T xterm-256color colors → %s（退出码 %s）\n' "$colors" "$c2"
printf '   tput -T vt100 longname        → %s（退出码 %s）\n' "$lname" "$c3"
if [ "$colors" = "256" ]; then echo "   OK   xterm-256color 报告 256 色，terminfo 条目解析正确"
else echo "   FAIL xterm-256color 的 colors 不是 256"; fn_rc=1; fi
echo "   infocmp 能反编译条目（取 xterm 的前 3 行）："
{ infocmp -T xterm 2>&1 | head -n3 || true; } | sed 's/^/     /'
echo "   toe 列出的终端类型数：$({ toe 2>/dev/null || true; } | wc -l)"
echo "   tic 往回编一条最小 terminfo（证明编译器可用，产物写到临时 TERMINFO 目录）："
mkdir -p "$work/ti"
cat > mini.src <<'TIEOF'
minitest|a minimal terminfo entry for verification,
	cols#80, lines#24,
	clear=\E[H\E[2J, cup=\E[%i%p1%d;%p2%dH,
TIEOF
set +e
tic -o "$work/ti" mini.src 2>tic.err; t_rc=$?
set -e
ti_out=$({ find "$work/ti" -type f || true; })
if [ $t_rc -eq 0 ] && [ -n "$ti_out" ]; then
  echo "     OK   tic 编译成功：$(echo "$ti_out" | sed "s|$work/ti/||" | tr '\n' ' ')"
  echo "     用 infocmp 读回（TERMINFO=$work/ti）："
  { TERMINFO=$work/ti infocmp -T minitest 2>&1 | head -n4 || true; } | sed 's/^/       /'
else
  echo "     FAIL tic 退出码 $t_rc"; { sed 's/^/       /' tic.err || true; }; fn_rc=1
fi
echo

echo "3) 编译链接一个真正调用 ncurses 的程序（用 newterm 打到 /dev/null，无需真终端）："
cat > t.c <<'CEOF'
#include <curses.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    FILE *out = fopen("/dev/null", "w");
    SCREEN *sp = newterm("xterm", out, stdin);
    if (!sp) { printf("newterm failed\n"); return 1; }
    printf("curses_version = %s\n", curses_version());
    printf("COLS=%d LINES=%d\n", COLS, LINES);
    printf("has_colors=%d start_color=%d\n", has_colors(), start_color() == OK);
    /* 宽字符 API：没有定义 _XOPEN_SOURCE_EXTENDED 也应可用，
       这正是手册那条 curses.h sed 的效果 */
    cchar_t cc;
    wchar_t w[2] = { L'A', L'\0' };
    printf("setcchar=%d\n", setcchar(&cc, w, A_NORMAL, 0, NULL) == OK);
    endwin();
    delscreen(sp);
    return 0;
}
CEOF
echo "   注意编译方式：这里**故意不用** pkg-config 的 cflags。pkg-config 给出的是"
echo "     -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=600，而 _XOPEN_SOURCE=600 本身就会让"
echo "     curses.h 里那个原始条件成立——带上它就验不出手册那条 sed 到底有没有生效。"
echo "     故先用光秃秃的 gcc -lncursesw 编一次（没有任何 XOPEN 宏），再单独用"
echo "     pkg-config 的参数编一次。"
set +e
gcc -o t t.c -lncursesw 2>t.err; g_rc=$?
set -e
if [ $g_rc -eq 0 ]; then
  echo "   OK   gcc -lncursesw（无任何 XOPEN 宏）编译成功"
  echo "        NEEDED："; { readelf -d t | grep NEEDED || true; } | sed 's/^/          /'
  set +e
  ./t > t.out 2>t.run.err; r_rc=$?
  set -e
  if [ $r_rc -eq 0 ]; then { sed 's/^/        /' t.out || true; }
    echo "   OK   程序运行成功（newterm/COLS/LINES/颜色/setcchar 均正常）"
  else echo "   FAIL 运行退出码 $r_rc"; { sed 's/^/        /' t.out t.run.err || true; }; fn_rc=1; fi
else
  echo "   FAIL 编译失败："; { sed 's/^/        /' t.err || true; }; fn_rc=1
fi
echo "   再用 pkg-config 给出的参数编一次（后续包正是这么用的）："
set +e
gcc -o t2 t.c $(pkg-config --cflags --libs ncursesw) 2>t2.err; g2_rc=$?
set -e
if [ $g2_rc -eq 0 ]; then
  echo "     OK   参数：$({ pkg-config --cflags --libs ncursesw; })"
  set +e
  ./t2 > t2.out 2>&1; r2_rc=$?
  set -e
  if [ $r2_rc -eq 0 ]; then { sed 's/^/       /' t2.out || true; }
  else echo "     FAIL 运行退出码 $r2_rc"; { sed 's/^/       /' t2.out || true; }; fn_rc=1; fi
else
  echo "     FAIL 编译失败："; { sed 's/^/       /' t2.err || true; }; fn_rc=1
fi
echo "   注：源码里**没有** #define _XOPEN_SOURCE_EXTENDED 却用了 cchar_t/setcchar，"
echo "     能编过就说明 curses.h 里那条 sed（#if 1）确实让宽字符 ABI 无条件生效了。"
echo "   当前已装 curses.h 的第 256 行（应为 '#if 1'）："
{ sed -n '256p' /usr/include/curses.h || true; } | sed 's/^/     /'
{ grep -c '^#if.*XOPEN.*$' /usr/include/curses.h || true; } | sed 's/^/     剩余未替换的 XOPEN 条件行数：/'
echo

echo "4) 非宽字符名字的兼容链接真的能用（手册命令 6/8、7/8 的意义所在）："
for l in curses ncurses form menu panel; do
  case $l in
    curses|ncurses) src='#include <curses.h>
int main(void){ return 0; }' ;;
    form)  src='#include <form.h>
int main(void){ return 0; }' ;;
    menu)  src='#include <menu.h>
int main(void){ return 0; }' ;;
    panel) src='#include <panel.h>
int main(void){ return 0; }' ;;
  esac
  printf '%s\n' "$src" > l.c
  set +e
  gcc -o l l.c -l$l -lncursesw 2>l.err; l_rc=$?
  set -e
  if [ $l_rc -eq 0 ]; then
    need=$({ readelf -d l | { grep NEEDED || true; } | sed 's/.*\[//;s/\].*//' | tr '\n' ' '; })
    printf '   OK   -l%-8s 链接成功，NEEDED = %s\n' "$l" "$need"
  else printf '   FAIL -l%-8s 链接失败：\n' "$l"; { sed 's/^/        /' l.err || true; }; fn_rc=1; fi
done
echo "   （NEEDED 里出现的都是 lib*w.so.6 —— 说明 -lcurses/-lncurses/-lform/-lmenu/-lpanel"
echo "     都被符号链接导向了宽字符库，正是手册那两步的目的。）"
echo

echo "5) C++ 绑定 libncurses++w（--with-cxx-shared 的产物）："
cat > c.cc <<'CXXEOF'
#include <cursesw.h>
int main() { return 0; }
CXXEOF
set +e
g++ -o c c.cc -lncurses++w -lncursesw 2>c.err; cx_rc=$?
set -e
if [ $cx_rc -eq 0 ]; then
  echo "   OK   g++ 用 -lncurses++w 链接成功"
  { readelf -d c | grep NEEDED || true; } | sed 's/^/        /'
else echo "   FAIL C++ 绑定链接失败："; { sed 's/^/        /' c.err || true; }; fn_rc=1; fi
echo

echo "6) pkg-config 各模块（后续包靠它找 ncurses）："
for m in ncursesw ncurses formw form menuw menu panelw panel ncurses++w; do
  set +e
  v=$(pkg-config --modversion "$m" 2>&1); p_rc=$?
  set -e
  if [ $p_rc -eq 0 ]; then printf '   OK   %-12s modversion=%-16s libs=%s\n' "$m" "$v" "$({ pkg-config --libs "$m"; })"
  else printf '   FAIL %-12s pkg-config 查询失败：%s\n' "$m" "$v"; fn_rc=1; fi
done
v_nc=$({ pkg-config --modversion ncursesw 2>/dev/null || true; })
case "$v_nc" in
  6.6*) echo "   OK   ncursesw 的版本串 $v_nc 以 6.6 开头（尾部 20251230 是 ncurses 的 patch date）" ;;
  *)    echo "   FAIL ncursesw 版本串 [$v_nc] 不以 6.6 开头"; fn_rc=1 ;;
esac
echo

echo "7) 动态链接器缓存与既有程序的健康状况："
echo "   注：DESTDIR 安装跳过了 ldconfig（见上文 5 处 Error 1 (ignored) 的解释），"
echo "     手册也没有要求补跑 ldconfig。因为库名/路径与既有安装完全一致，缓存里的条目"
echo "     依旧有效——下面把缓存内容打出来核对，而不是自作主张加一条手册没有的命令。"
{ ldconfig -p | { grep -E 'libncurses|libform|libmenu|libpanel' || true; } | sed 's/^/     /'; } || true
echo "   既有的、链接 ncurses 的程序仍能正常运行（bash 与 tput 各跑一次）："
set +e
bv=$(/usr/bin/bash -c 'echo bash-ok $BASH_VERSION' 2>&1); b_rc=$?
set -e
printf '     /usr/bin/bash → %s（退出码 %s）\n' "$bv" "$b_rc"
[ $b_rc -eq 0 ] || { echo "     FAIL 新装库之后 bash 起不来"; fn_rc=1; }
echo "     本脚本所在 shell 也一直活着（PID $$，从安装到现在没被换库搞死）"
echo

cd /sources/$SRCDIR
rm -rf "$work"
{
  echo "===== §8.31 Ncurses-$VER 验证汇总 ====="
  echo "手册规定测试：无（手册原文只说 test suite 在 test/ 目录、装完才能跑、详见 README，"
  echo "  未给出任何测试命令，故本节无「手册规定的测试」可执行）。"
  echo "替代验证（手册之外，本脚本自加，全部通过）："
  echo "  - 11 个程序 -V/--version 全部正常"
  echo "  - terminfo 数据库可查：xterm-256color = 256 色；tic 编译 + infocmp 读回往返成功"
  echo "  - 调用 newterm/setcchar 的 C 程序编译并运行成功（证明宽字符 ABI 生效）"
  echo "  - -lcurses/-lncurses/-lform/-lmenu/-lpanel 均能链接且都导向 lib*w.so.6"
  echo "  - C++ 绑定 -lncurses++w 链接成功"
  echo "  - pkg-config 9 个模块全部可查，ncursesw 版本 $v_nc"
  echo "  - 换库之后 bash 与本脚本进程均正常存活"
} > "$SUMLOG"
[ $fn_rc -eq 0 ] || { echo "功能验证未通过" >&2; exit 1; }
echo "功能验证全部通过。"
echo

# =========================================================================
echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.31.sh"
echo "  移入 /root/lfs/logs/packages/，不会在镜像内留下多余目录）"
echo "  configure       完整输出：$CFGLOG"
echo "  make            完整输出：$MAKELOG"
echo "  DESTDIR install 完整输出：$INSTLOG"
echo "  cp 到根          完整输出：$CPLOG"
echo "  doc 安装         完整输出：$DOCLOG"
echo "  验证汇总         ：$SUMLOG"
cd /sources
echo "清理前 /sources 下的 ncurses 相关条目："
{ ls -d /sources/ncurses* 2>/dev/null || true; } | sed 's/^/  /'
echo "  待删除：$({ du -sh /sources/$SRCDIR 2>/dev/null || true; } | awk '{print $1"\t"$2}')"
echo "  （其中 dest/ 子目录是手册命令 3/8 造出来的 DESTDIR 暂存树，随源码目录一并删除）"
rm -rf "/sources/$SRCDIR"
echo "已删除 /sources/$SRCDIR"
echo "清理后 /sources 下的 ncurses 相关条目（应只剩 tarball）："
{ ls -d /sources/ncurses* 2>/dev/null || true; } | sed 's/^/  /'
if [ -e "/sources/$SRCDIR" ]; then echo "  FAIL 源码构建目录仍存在"; exit 1
else echo "  OK   源码构建目录已删除"; fi
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -type d -name 'ncurses*' || true; } | sed 's/^/  /'
echo "/tmp 下本节留下的临时目录/文件（应为空）："
{ find /tmp -maxdepth 1 \( -name '*ncurses*' -o -name '.curses*' \) || true; } | sed 's/^/  /'
echo "根文件系统占用："
{ df -h / | tail -n1 || true; } | sed 's/^/  /'
echo

echo "================= 本节结论 ================="
echo "手册 §8.31.1 的命令全部按原样执行完毕："
echo "  1. ./configure --prefix=/usr --mandir=/usr/share/man --with-shared --without-debug"
echo "     --without-normal --with-cxx-shared --enable-pc-files"
echo "     --with-pkg-config-libdir=/usr/lib/pkgconfig   —— 退出码 $cfg_rc"
echo "  2. make                                          —— 退出码 $make_rc"
echo "  3. make DESTDIR=\$PWD/dest install                 —— 退出码 $inst_rc"
echo "  4. sed -e 's/^#if.*XOPEN.*\$/#if 1/' -i dest/usr/include/curses.h —— 命中 1 行"
echo "  5. cp --remove-destination -av dest/* /           —— 退出码 $cp_rc"
echo "  6. for lib in ncurses form panel menu：8 个符号链接 —— 全部建立并复核"
echo "  7. ln -sfv libncursesw.so /usr/lib/libcurses.so   —— 已建立"
echo "  8. cp -v -R doc -T /usr/share/doc/ncurses-$VER      —— 退出码 $doc_rc（手册标注可选，本项目执行）"
echo "本节没有补丁、没有 build 子目录（in-tree 构建）。"
echo "手册 §8.31.1 末尾关于 ABI 5 非宽字符库的 Note **未执行**：其前提"
echo "  （binary-only 应用 / LSB 合规）在本项目都不成立，手册自己也说源码编译的包"
echo "  运行时不会链接它们。"
echo
echo "测试结论："
echo "  手册在本节**没有规定任何测试命令**。原文：This package has a test suite, but it"
echo "    can only be run after the package has been installed. The tests reside in the"
echo "    test/ directory. See the README file in that directory for further details."
echo "  test/ 里是需要真终端与人工按键的交互式 demo（blue/bs/firework/gdc/worm…），"
echo "    非交互 chroot 中运行只会产生无判据的假结果，故不运行；这不是跳过手册要求的"
echo "    测试，而是手册本节根本没有这项要求。"
echo "  作为替代，脚本做了一组非交互功能验证（详见「功能验证」一节与 $SUMLOG），"
echo "    全部通过，无未解释的意外失败。"
echo "  构建过程中出现的 5 处 \"Error 1 (ignored)\" 已逐条溯源：全部来自"
echo "    test -z \"\$(DESTDIR)\" && ldconfig，是 DESTDIR 安装的正常现象，非失败。"
echo
echo "手册 §8.31.2 Contents 逐项确认："
echo "  Installed programs   : captoinfo(->tic) clear infocmp infotocap(->tic)"
echo "                         ncursesw6-config reset(->tset) tabs tic toe tput tset"
echo "                         —— 11 项全在 /usr/bin，三个 link 确为符号链接"
echo "  Installed libraries  : libncursesw.so libformw.so libmenuw.so libpanelw.so"
echo "                         libncurses++w.so（5 个实体，SONAME 均为 lib*.so.6）"
echo "                         + libcurses.so libncurses.so libform.so libmenu.so"
echo "                         libpanel.so（5 个兼容符号链接）—— 全部到位，无静态库"
echo "  Installed directories: /usr/share/tabset（$n_tab 文件）、/usr/share/terminfo"
echo "                         （$n_ti 条目 / $n_tid 子目录）、/usr/share/doc/ncurses-$VER（$n_doc 文件）"
echo "  手册未列但确实装出：18 个头文件、9 个 pkg-config 文件（5 真 + 4 链接）、"
echo "                      man1/man3/man5/man7 共 $d_man_f 个 man 页 + $d_man_l 个 man 链接、"
echo "                      /usr/lib/terminfo -> ../share/terminfo"
echo
echo "与既有安装的关系：本节用原生工具链重装了同一个 Ncurses-6.6。替换确实发生了，"
echo "  证据是「与 dest 逐字节相同 + mtime 为本次构建时刻」，以及本 shell 映射里那行"
echo "  libncursesw 变成了 (deleted)（旧 inode 被 unlink、仍被在跑的进程持有）。"
echo "  inode 号仅供参考：libncursesw.so.6.6 $old_lib_inode → $new_lib_inode，"
echo "  /usr/bin/tic $old_tic_inode → $new_tic_inode —— 号相同也不代表没换文件，"
echo "  ext4 会把刚释放的 inode 号立刻复用给同目录新建的文件，故未用它作判据。"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.31 Ncurses-$VER 完成 ====="
