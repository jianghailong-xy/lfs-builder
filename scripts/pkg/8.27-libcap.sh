#!/usr/bin/env bash
# LFS 13.0-systemd §8.27 Libcap-2.77
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §8.27.1 Installation of Libcap 的命令序列（全部 4 条，一条不多一条不少）：
#   sed -i '/install -m.*STA/d' libcap/Makefile
#   make prefix=/usr lib=lib
#   make test
#   make prefix=/usr lib=lib install
#
# 本节的形态与前面几节都不同，照抄 §8.25/§8.26 的写法会全线扑空：
#   - **没有 configure**（libcap 是纯手写 Makefile + Make.Rules，不用 autotools），
#     故没有 --prefix/--disable-static/--docdir，也没有 config.log / libtool 可查；
#     "禁止安装静态库" 这件事在本节是靠那条 sed 删掉两行 install 命令做到的，
#     不是靠 --disable-static。
#   - **没有 docdir**，本节不装 /usr/share/doc/libcap-2.77（对照 §8.25/§8.26 都装了）。
#   - make 与 make install 都要带 prefix=/usr lib=lib，而 make test **不带**
#     （手册原文就是光秃秃一条 make test）。
#   - 本节手册**没有任何关于测试的提示框**，也没有 "known to fail" 的说法，
#     故与 §8.26 相反：make test 的退出码就是判据，必须为 0。
#
# 手册在 §8.27.1 开头有**一个 Note 提示框**（是本节唯一的提示框）：
#   「If updating this package on an existing system and the go compiler is
#     installed, prevent a build error by using `export GOLANG=no` before running
#     the commands below. Be sure to unset GOLANG after installation is complete.」
#   两个前提在本环境都不成立：(a) 这是**首次**安装而非在既有系统上更新；
#   (b) 系统里没有 go 编译器。下面的前置检查会把这两点分别实测确认，并顺带把
#   Make.Rules 自己算出来的 GOLANG 值打出来（应为 no），证明不需要 export GOLANG=no。
#
# 手册对 lib=lib 的说明（The meaning of the make option）：
#   「lib=lib —— This parameter sets the library directory to /usr/lib rather than
#     /usr/lib64 on x86_64. It has no effect on x86.」
#   这条在本环境是**实打实起作用**的：Make.Rules:21 把 lib 的默认值定义为
#     lib=$(shell ldd /usr/bin/ld|grep -E "ld-linux|ld.so"|cut -d/ -f2)
#   本机 ldd /usr/bin/ld 里解释器是 /lib64/ld-linux-x86-64.so.2，故默认值真的是
#   lib64。不给 lib=lib 就会装到 /lib64，直接违反手册 §7.5.1 的
#   「/usr/lib64 ... it is imperative that this directory be non-existent」。
#   下面会把两种取值下的 LIBDIR/SBINDIR 都算出来对照。
set -euo pipefail

PKG=libcap
VER=2.77
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER
SEDLOG=/sources/.libcap-sed.log
MAKELOG=/sources/.libcap-make.log
TESTLOG=/sources/.libcap-make-test.log
INSTLOG=/sources/.libcap-make-install.log
SUMLOG=/sources/.libcap-test-summary.log

echo "===== LFS 13.0-systemd §8.27 Libcap-$VER ====="
echo "开始时间：$(date -Is)"
echo "手册简介：The Libcap package implements the userspace interface to the POSIX"
echo "  1003.1e capabilities available in Linux kernels. These capabilities partition"
echo "  the all-powerful root privilege into a set of distinct privileges."
echo "手册数据：Approximate build time less than 0.1 SBU，Required disk space 3.1 MB"
echo
echo "----- chroot 环境自述（手册 §7.4） -----"
echo "date      : $(date -Is)"
echo "hostname  : $(hostname 2>/dev/null || echo '(无)')"
echo "kernel    : $(uname -srm)"
echo "PATH      : $PATH"
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

echo "1) 上一任务 §8.26 Acl-2.3.2 的产物是否可用："
echo "   说明：Libcap 在**构建层面并不依赖** Acl/Attr（它只用内核头文件 + libc +"
echo "   pthread，见下面 make 阶段实测的 NEEDED 只有 libc.so.6）。这里检查上一任务"
echo "   产物，是任务书「开始前确认上一任务产物可用」的要求，不是本包的编译依赖。"
for f in /usr/bin/chacl /usr/bin/getfacl /usr/bin/setfacl \
         /usr/lib/libacl.so /usr/lib/libacl.so.1 /usr/lib/pkgconfig/libacl.pc \
         /usr/include/sys/acl.h /usr/include/acl/libacl.h; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"
  else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "   不只看文件在不在 —— 实际跑一次上一节装出的程序与库："
{ getfacl --version 2>&1 | sed -n 1p || true; } | sed 's/^/     /'
if pkg-config --modversion libacl >/dev/null 2>&1; then
  echo "     OK   pkg-config --modversion libacl = $(pkg-config --modversion libacl)"
else
  echo "     FAIL pkg-config 找不到 libacl"; rc=1
fi
echo

echo "2) 手册 §8.27.1 那个 Note 的两个前提，逐条实测："
echo "   Note 原文：「If updating this package on an existing system and the go compiler"
echo "     is installed, prevent a build error by using export GOLANG=no before running"
echo "     the commands below. Be sure to unset GOLANG after installation is complete.」"
echo "   前提 (a)「updating ... on an existing system」——本节应当是首次安装："
first_install=yes
for f in /usr/sbin/capsh /usr/sbin/getcap /usr/sbin/getpcaps /usr/sbin/setcap \
         /usr/lib/libcap.so /usr/lib/libpsx.so /usr/include/sys/capability.h \
         /usr/include/sys/psx_syscall.h /usr/lib/pkgconfig/libcap.pc; do
  if [ -e "$f" ]; then printf '     INFO %s 已存在（将被覆盖）\n' "$f"; first_install=no
  else printf '     OK   %s 尚不存在\n' "$f"; fi
done
echo "     判定：$([ "$first_install" = yes ] && echo '首次安装，前提 (a) 不成立' || echo '存在旧文件，属于更新')"
echo "   前提 (b)「the go compiler is installed」——查 go / gccgo："
go_found=no
for t in go gccgo; do
  p=$({ command -v "$t" 2>/dev/null || true; })
  if [ -n "$p" ]; then printf '     INFO %-6s %s（已安装）\n' "$t" "$p"; go_found=yes
  else printf '     OK   %-6s 未安装\n' "$t"; fi
done
echo "     判定：$([ "$go_found" = no ] && echo 'go 编译器不存在，前提 (b) 不成立' || echo 'go 存在')"
if [ "$first_install" = yes ] && [ "$go_found" = no ]; then
  echo "   结论：Note 的两个前提都不成立，**不需要** export GOLANG=no，"
  echo "         也就不存在「安装后要 unset GOLANG」的收尾动作。本脚本不设置该变量。"
  echo "   当前环境中 GOLANG 是否确实为空：GOLANG=[${GOLANG:-}]"
else
  echo "   结论：Note 的前提成立，需要 export GOLANG=no。"
  export GOLANG=no
  echo "   已执行 export GOLANG=no（安装后会 unset）"
fi
echo

echo "3) 本节构建链所需的工具（本节没有 configure，全靠 make + gcc + sed）："
for t in gcc make sed ld ar grep awk install xz tar find diff pkg-config perl; do
  p=$({ command -v "$t" 2>/dev/null || true; })
  if [ -n "$p" ]; then printf '   OK   %-11s %s\n' "$t" "$p"
  else printf '   FAIL %-11s 未找到\n' "$t"; rc=1; fi
done
echo "   版本："
{ gcc --version | sed -n 1p || true; } | sed 's/^/     /'
{ make --version | sed -n 1p || true; } | sed 's/^/     /'
{ sed --version | sed -n 1p || true; } | sed 's/^/     /'
echo "   注：本节**没有 configure**，libcap 用的是手写 Makefile + Make.Rules，"
echo "     所以后面核对 prefix/lib 是否生效时，查的不是 config.log/libtool，"
echo "     而是直接用 make 把 Make.Rules 里的变量求值打印出来。"
echo "   注：本包 tarball 是 .tar.xz，故 xz 必须可用。"
echo "   注：本节**不**需要 perl/gperf 来生成任何东西（cap_names.list.h 由源码自带的"
echo "     _makenames 在 make 阶段现编现跑生成）；perl 只是顺带记录。"
echo

echo "4) 本节测试与安装依赖的内核/文件系统能力："
echo "   a) 内核 capabilities 支持（libcap 的全部意义所在）——当前进程的 capability 集："
{ grep -E '^Cap(Inh|Prm|Eff|Bnd|Amb):' /proc/self/status || true; } | sed 's/^/     /'
capeff=$({ grep -m1 '^CapEff:' /proc/self/status || true; } | awk '{print $2}')
if [ -n "$capeff" ]; then
  echo "     OK   /proc/self/status 提供 capability 集（CapEff=$capeff）"
else
  echo "     FAIL 内核未提供 capability 信息"; rc=1
fi
echo "     CAP_SETFCAP（第 31 位，setcap 往文件写 capability 所必需）："
# CAP_SETFCAP = 31；用位运算判断 CapEff 是否含该位（不依赖尚未安装的 capsh）
if [ -n "$capeff" ] && [ $(( 0x$capeff >> 31 & 1 )) -eq 1 ]; then
  echo "     OK   本进程持有 CAP_SETFCAP，下面的 setcap 功能验证可以真正落地"
else
  echo "     FAIL 本进程没有 CAP_SETFCAP"; rc=1
fi
echo "   b) 文件 capability 存放在 security.capability 扩展属性里，"
echo "      故安装目标所在文件系统必须支持 xattr —— 直接写一个探针试试："
probe=/usr/.libcap-xattr-probe.$$
: > "$probe"
if setfattr -n security.capability \
   -v 0s$(printf '\x01\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' | base64 -w0) \
   "$probe" 2>/tmp/.libcap-xattr.err; then
  echo "     OK   /usr 所在文件系统可写 security.capability"
  { getfattr -n security.capability -e hex "$probe" 2>/dev/null || true; } \
    | { grep -m1 '^security.capability=' || true; } | sed 's/^/       读回：/'
else
  echo "     FAIL 无法写 security.capability："; sed 's/^/       /' /tmp/.libcap-xattr.err; rc=1
fi
rm -f "$probe" /tmp/.libcap-xattr.err
{ stat -f -c '     /usr 文件系统类型：%T' /usr || true; }
{ grep -E ' / ' /proc/mounts || true; } | sed 's/^/     /'
echo

echo "5) 手册 §7.5.1 的硬性约束（本节的 lib=lib 就是为它服务的）："
echo "   「The FHS does not mandate the existence of the directory /usr/lib64, and the"
echo "     LFS editors have decided not to use it. ... it is imperative that this"
echo "     directory be non-existent.」"
if [ -e /usr/lib64 ]; then echo "   FAIL /usr/lib64 已存在"; rc=1
else echo "   OK   /usr/lib64 不存在（安装后会再查一次）"; fi
echo "   /lib64 当前内容（LFS 里它只该有动态装载器，不该出现 libcap）："
{ ls -A /lib64 2>/dev/null || true; } | sed 's/^/     /'
echo

if [ $rc -ne 0 ]; then
  echo "前置检查未通过，按任务要求不继续 §8.27。" >&2
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

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
[ -d "$SRCDIR" ] && { echo "发现上次遗留的 $SRCDIR，先删除以保证从干净源码开始"; rm -rf "$SRCDIR"; }
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "构建目录：$(pwd)（in-tree build，本节手册没有 mkdir build）"
echo "源码树顶层：$(ls | tr '\n' ' ')"
echo "版本号（Make.Rules 的 VERSION.MINOR，应为 $VER）："
{ grep -E '^(VERSION|MINOR)=' Make.Rules || true; } | sed 's/^/  /'
mk_ver="$({ grep -m1 '^VERSION=' Make.Rules || true; } | cut -d= -f2).$({ grep -m1 '^MINOR=' Make.Rules || true; } | cut -d= -f2)"
if [ "$mk_ver" = "$VER" ]; then echo "  OK   Make.Rules 自述版本 $mk_ver 与包名一致"
else echo "  FAIL Make.Rules 自述版本 $mk_ver ≠ $VER"; exit 1; fi
echo

echo "----- 本包的结构性事实（开工前已在 chroot /tmp 的完整试建中逐条确认） -----"
echo "本包 <0.1 SBU / 3.1 MB，故正式开工前先在 /tmp 里做过完整试建（sed + make +"
echo "make test + make prefix=/usr lib=lib DESTDIR=... install，不写系统），本脚本下面"
echo "每一条数字/名称断言都是在那次试建的产物上验过的，试建目录已删除。"
echo "与 §8.25/§8.26 差别最大、照抄必然扑空的点："
echo "  a) **本节没有 configure**。libcap 是手写 Makefile + Make.Rules，安装路径由"
echo "     make 命令行上的 prefix=/usr lib=lib 决定。没有 config.log、没有生成的"
echo "     libtool 脚本可查，故「选项是否生效」要用 make 求值 Make.Rules 变量来验。"
echo "  b) **禁止静态库的手段不是 --disable-static，而是那条 sed**。sed 删掉的是"
echo "     libcap/Makefile 里 install-static-cap / install-static-psx 两个目标下的"
echo "     两条 install 命令，命中行原文（试建实测在第 194、205 行）："
echo "       194: \tinstall -m 0644 \$(STACAPLIBNAME) \$(FAKEROOT)\$(LIBDIR)/\$(STACAPLIBNAME)"
echo "       205: \tinstall -m 0644 \$(STAPSXLIBNAME) \$(FAKEROOT)\$(LIBDIR)/\$(STAPSXLIBNAME)"
echo "     注意：静态库 libcap.a / libpsx.a **仍然会被编译出来**（留在构建目录里），"
echo "     sed 只是让 install 不再把它们拷进系统。试建对照实测：不做 sed 时会多装出"
echo "     /usr/lib/libcap.a 与 /usr/lib/libpsx.a 两个文件，做了 sed 后是 0 个。"
echo "  c) **lib=lib 在本机是真的必要**。Make.Rules:21 把 lib 的默认值定义为"
echo "       lib=\$(shell ldd /usr/bin/ld|grep -E \"ld-linux|ld.so\"|cut -d/ -f2)"
echo "     本机 ldd /usr/bin/ld 的解释器行是 /lib64/ld-linux-x86-64.so.2，故默认值"
echo "     真的算成 lib64；不给 lib=lib 就会往 /lib64 装库、往 /sbin 装程序。"
echo "  d) **make test 手册故意不带 prefix/lib**，于是它以默认 lib=lib64 运行。"
echo "     这不会污染安装结果：libcap.pc / libpsx.pc 是在前一步 make（带 lib=lib）时"
echo "     由 .pc.in 生成的，make test 不重新生成它们（.pc 比 .pc.in 新）。试建里"
echo "     逐步 cat 过这两个文件，make 后、make test 后、装出后三处 libdir 都是"
echo "     /usr/lib。下面正式执行时同样会在 make test 前后各查一次。"
echo "  e) 共享库实体是 libcap.so.2.77 / libpsx.so.2.77，SONAME 分别是 libcap.so.2 /"
echo "     libpsx.so.2。这里的 2 与 77 就是包版本 2.77（与 §8.26 的 libacl.so.1.1.2302"
echo "     那种与版本无关的 libtool 编号完全不同）。"
echo "  f) 程序装到 **/usr/sbin**（不是 /usr/bin）：SBINDIR=\$(exec_prefix)/sbin。"
echo "     手册 Contents 只写了程序名没写路径，照 §8.26 去 /usr/bin 找必然扑空。"
echo "  g) **本节不装 /usr/share/doc/libcap-2.77**（手册没给 docdir，libcap 也没有该"
echo "     概念），但会装 man1/man3/man5/man7/man8 五类 man 页。"
echo "  h) pam_cap.so **不会**被构建：Make.Rules:123 让 PAM_CAP 取决于"
echo "     /usr/include/security/pam_modules.h 是否存在，本系统还没有 Linux-PAM，"
echo "     故 PAM_CAP=no。但 doc 目录仍会无条件装上 pam_cap.8 这一页 man——"
echo "     man 页在，模块不在，属正常，手册 Contents 也没列 pam_cap.so。"
echo "  i) RAISE_SETFCAP 默认为 no（Make.Rules:185），故 progs/Makefile:48-49 那条"
echo "     「给装好的 setcap 自己打上 cap_setfcap=i」的命令**不会执行**。安装后"
echo "     getcap /usr/sbin/setcap 应当是空输出，这是符合手册的默认行为。"
echo

echo "----- 测试结构预读（决定 make test 的判定标准） -----"
echo "顶层 Makefile 把 all/test/install 等目标转发给各子目录："
{ sed -n '/^all test sudotest install clean/,/doc \$@/p' Makefile || true; } | sed 's/^/  /'
echo "各子目录的 test 目标实际做什么："
echo "  libcap/ : 编译并运行 cap_test，再跑 libcapsotest / libpsxsotest"
echo "  tests/  : psx_test、libcap_psx_test、weaver.so、b219174"
echo "  progs/  : 只有一句无条件的 echo（progs/Makefile 第 52-53 行）——"
{ sed -n '52,53p' progs/Makefile || true; } | sed 's/^/            /'
echo "            注意：这句**不是**在检测权限，它是写死的 echo，任何情况下都会打印。"
echo "            真正需要特权的程序测试在 make sudotest 里，而手册没有要求执行它。"
echo "  doc/    : 无测试，打印 no doc tests available"
echo "本节手册**没有任何关于测试的提示框**，也没有 known-to-fail 的说法，"
echo "故与 §8.26 相反：make test 的退出码就是判据，必须为 0。"
echo

# =========================================================================
echo "================= 8.27.1. Installation of Libcap ================="
echo
echo "----- 手册命令 1/4：sed（禁止安装静态库） -----"
echo "手册原文：Prevent static libraries from being installed:"
echo "手册命令：sed -i '/install -m.*STA/d' libcap/Makefile"
echo "（完整记录另存到 $SEDLOG）"
{
  echo "===== §8.27 手册命令 1/4 的完整记录 ====="
  echo "命令：sed -i '/install -m.*STA/d' libcap/Makefile"
  echo
  echo "--- 执行前，libcap/Makefile 中匹配 /install -m.*STA/ 的行（带行号） ---"
  { grep -n 'install -m.*STA' libcap/Makefile || true; }
  echo
  echo "--- 这些行的上下文（各前后 2 行） ---"
  { grep -n -B2 -A2 'install -m.*STA' libcap/Makefile || true; }
} > "$SEDLOG"
before_n=$({ grep -c 'install -m.*STA' libcap/Makefile || true; })
echo "执行前匹配行数：$before_n"
{ grep -n 'install -m.*STA' libcap/Makefile || true; } | sed 's/^/  /'
cp libcap/Makefile /tmp/.libcap-Makefile.before
sed -i '/install -m.*STA/d' libcap/Makefile
after_n=$({ grep -c 'install -m.*STA' libcap/Makefile || true; })
echo "执行后匹配行数：$after_n"
echo "diff（应恰好是删掉那两行）："
{ diff /tmp/.libcap-Makefile.before libcap/Makefile || true; } | sed 's/^/  /'
{
  echo
  echo "--- 执行后匹配行数：$after_n（执行前 $before_n） ---"
  echo "--- diff（before -> after） ---"
  { diff /tmp/.libcap-Makefile.before libcap/Makefile || true; }
  echo
  echo "--- 执行后 libcap/Makefile 的两个 install-static-* 目标（应只剩依赖行、无命令） ---"
  { sed -n '/^install-static-cap:/,/^$/p;/^install-static-psx:/,/^$/p' libcap/Makefile || true; }
} >> "$SEDLOG"
sed_rc=0
if [ "$before_n" -eq 2 ]; then echo "  OK   sed 执行前恰好命中 2 行（静态 cap 库 + 静态 psx 库各一条 install）"
else echo "  FAIL sed 执行前命中 $before_n 行，试建实测应为 2 行"; sed_rc=1; fi
if [ "$after_n" -eq 0 ]; then echo "  OK   sed 执行后 0 行残留，两条 install 命令已删除"
else echo "  FAIL sed 执行后仍有 $after_n 行残留"; sed_rc=1; fi
echo "  被 sed 掏空的两个目标现在长这样（只剩依赖，没有命令行）："
{ sed -n '/^install-static-cap:/,/^$/p;/^install-static-psx:/,/^$/p' libcap/Makefile || true; } | sed 's/^/    /'
rm -f /tmp/.libcap-Makefile.before
[ $sed_rc -eq 0 ] || { echo "sed 结果与预期不符" >&2; exit 1; }
echo

echo "----- make 变量求值：核对手册给的 prefix=/usr lib=lib 确实生效 -----"
echo "本节没有 configure，故直接用一个临时 makefile include Make.Rules 求值。"
cat > /tmp/.libcap-probe.mk <<'MK'
topdir=$(shell pwd)
include Make.Rules
probe:
	@echo "prefix=$(prefix)"
	@echo "exec_prefix=$(exec_prefix)"
	@echo "lib=$(lib)"
	@echo "LIBDIR=$(LIBDIR)"
	@echo "SBINDIR=$(SBINDIR)"
	@echo "INCDIR=$(INCDIR)"
	@echo "PKGCONFIGDIR=$(PKGCONFIGDIR)"
	@echo "MANDIR=$(MANDIR)"
	@echo "GOLANG=$(GOLANG)"
	@echo "PAM_CAP=$(PAM_CAP)"
	@echo "SHARED=$(SHARED)"
	@echo "PTHREADS=$(PTHREADS)"
	@echo "RAISE_SETFCAP=$(RAISE_SETFCAP)"
MK
echo "【对照】不给 prefix/lib 时（即 make test 所处的默认状态）："
make -f /tmp/.libcap-probe.mk probe 2>/dev/null | sed 's/^/  /' > /tmp/.libcap-def.txt
sed 's/^/  /' /tmp/.libcap-def.txt
def_lib=$({ grep -m1 '^  lib=' /tmp/.libcap-def.txt || true; } | cut -d= -f2)
echo "  ——手册那句「sets the library directory to /usr/lib rather than /usr/lib64 on"
echo "    x86_64」在本机是实打实的：默认 lib=$def_lib（由 Make.Rules:21 从"
echo "    ldd /usr/bin/ld 的解释器路径 $({ ldd /usr/bin/ld | grep -E 'ld-linux|ld\.so' || true; } | awk '{print $1}') 里 cut 出来）。"
echo "【手册的 prefix=/usr lib=lib】："
make -f /tmp/.libcap-probe.mk prefix=/usr lib=lib probe 2>/dev/null > /tmp/.libcap-opt.txt
sed 's/^/  /' /tmp/.libcap-opt.txt
rm -f /tmp/.libcap-probe.mk
opt_rc=0
chk() { # <描述> <期望> <实测>
  if [ "$2" = "$3" ]; then printf '  OK   %-30s = %s\n' "$1" "$3"
  else printf '  FAIL %-30s 期望 %s，实测 %s\n' "$1" "$2" "$3"; opt_rc=1; fi
}
v() { { grep -m1 "^$1=" /tmp/.libcap-opt.txt || true; } | cut -d= -f2-; }
chk "prefix=/usr → prefix"        "/usr"                "$(v prefix)"
chk "  （随之）exec_prefix"       "/usr"                "$(v exec_prefix)"
chk "lib=lib → lib"               "lib"                 "$(v lib)"
chk "  （随之）LIBDIR"            "/usr/lib"            "$(v LIBDIR)"
chk "  （随之）SBINDIR"           "/usr/sbin"           "$(v SBINDIR)"
chk "  （随之）PKGCONFIGDIR"      "/usr/lib/pkgconfig"  "$(v PKGCONFIGDIR)"
chk "  （随之）INCDIR"            "/usr/include"        "$(v INCDIR)"
chk "  （随之）MANDIR"            "/usr/share/man"      "$(v MANDIR)"
chk "GOLANG（Note 的 go 检测）"   "no"                  "$(v GOLANG)"
chk "PAM_CAP（无 Linux-PAM）"     "no"                  "$(v PAM_CAP)"
chk "SHARED"                      "yes"                 "$(v SHARED)"
chk "PTHREADS（libpsx 所需）"     "yes"                 "$(v PTHREADS)"
chk "RAISE_SETFCAP（默认不提权）" "no"                  "$(v RAISE_SETFCAP)"
if [ "$def_lib" = lib64 ]; then
  echo "  OK   已确认 lib=lib 不是摆设：不给它就会装到 /$def_lib，违反 §7.5.1"
else
  echo "  INFO 本机默认 lib=$def_lib（非 lib64），lib=lib 在此为同值确认"
fi
rm -f /tmp/.libcap-def.txt /tmp/.libcap-opt.txt
[ $opt_rc -eq 0 ] || { echo "make 变量核对未通过" >&2; exit 1; }
echo

echo "----- 手册命令 2/4：make prefix=/usr lib=lib -----"
echo "手册原文：Compile the package:"
echo "手册命令：make prefix=/usr lib=lib"
echo "手册对该选项的说明（The meaning of the make option）："
echo "  lib=lib —— This parameter sets the library directory to /usr/lib rather than"
echo "             /usr/lib64 on x86_64. It has no effect on x86."
echo "（并行度来自手册 §7.4 设定的 MAKEFLAGS=${MAKEFLAGS:-}；完整输出另存到 $MAKELOG）"
set +e
make prefix=/usr lib=lib > "$MAKELOG" 2>&1
make_rc=$?
set -e
echo "make 退出码：$make_rc（输出 $(wc -l < "$MAKELOG") 行）"
[ $make_rc -eq 0 ] || { echo "make 失败，末尾 40 行："; tail -n 40 "$MAKELOG"; exit $make_rc; }
echo "make 末尾 5 行："
tail -n 5 "$MAKELOG" | sed 's/^/  /'
echo
echo "----- 编译结果确认 -----"
echo "编译告警统计（仅统计，不作判据）：$({ grep -cE 'warning:' "$MAKELOG" || true; }) 条 warning，$({ grep -cE ' error:' "$MAKELOG" || true; }) 条 error"
echo "构建出的库（注意：静态库 .a 仍会被编译出来，sed 只管不让它们被 install）："
{ ls -l libcap/libcap.so* libcap/libpsx.so* libcap/libcap.a libcap/libpsx.a 2>/dev/null || true; } | sed 's/^/  /'
echo "SONAME 与依赖："
for f in libcap/libcap.so.2.77 libcap/libpsx.so.2.77; do
  echo "  [$f]"
  { readelf -d "$f" 2>/dev/null | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/    /'
done
echo "  注：libpsx 的 NEEDED 里没有 libpthread.so.0 —— glibc 2.34 起 pthread 已并入"
echo "    libc.so.6，这是预期的，不是 PTHREADS 没生效（上面 PTHREADS=yes 已确认）。"
echo "构建出的程序（尚未安装）："
{ ls -l progs/capsh progs/getcap progs/getpcaps progs/setcap 2>/dev/null || true; } | sed 's/^/  /'
mk_rc=0
for f in libcap/libcap.so.2.77 libcap/libpsx.so.2.77 \
         progs/capsh progs/getcap progs/getpcaps progs/setcap; do
  if [ -e "$f" ]; then printf '  OK   已构建 %s\n' "$f"
  else printf '  FAIL 未构建出 %s\n' "$f"; mk_rc=1; fi
done
son_cap=$({ readelf -d libcap/libcap.so.2.77 2>/dev/null | grep SONAME || true; } | sed 's/.*\[\(.*\)\].*/\1/')
son_psx=$({ readelf -d libcap/libpsx.so.2.77 2>/dev/null | grep SONAME || true; } | sed 's/.*\[\(.*\)\].*/\1/')
if [ "$son_cap" = "libcap.so.2" ]; then echo "  OK   libcap SONAME = $son_cap"
else echo "  FAIL libcap SONAME 期望 libcap.so.2，实测 $son_cap"; mk_rc=1; fi
if [ "$son_psx" = "libpsx.so.2" ]; then echo "  OK   libpsx SONAME = $son_psx"
else echo "  FAIL libpsx SONAME 期望 libpsx.so.2，实测 $son_psx"; mk_rc=1; fi
echo "本次 make 生成的 pkg-config 文件（带 lib=lib，libdir 应为 /usr/lib）："
{ cat libcap/libcap.pc || true; } | sed 's/^/    /'
pc_before=$({ grep -m1 '^libdir=' libcap/libcap.pc || true; })
if [ "$pc_before" = "libdir=/usr/lib" ]; then echo "  OK   libcap.pc 的 $pc_before"
else echo "  FAIL libcap.pc 的 libdir 不是 /usr/lib：$pc_before"; mk_rc=1; fi
echo "pam_cap.so（PAM_CAP=no，应当没有构建出来）："
if [ -e pam_cap/pam_cap.so ]; then echo "  INFO pam_cap/pam_cap.so 存在（PAM_CAP 生效了？）"
else echo "  OK   pam_cap/pam_cap.so 不存在，与 PAM_CAP=no 一致"; fi
[ $mk_rc -eq 0 ] || { echo "编译结果确认未通过" >&2; exit 1; }
echo

# =========================================================================
echo "----- 手册命令 3/4：make test（本节的测试） -----"
echo "手册原文（本节关于测试的全部文字，只有一句，没有任何提示框）："
echo "  「To test the results, issue:」  make test"
echo "  注意手册这条**故意不带** prefix=/usr lib=lib（对照命令 2 和命令 4 都带）。"
echo "  于是 make test 以默认 lib=$def_lib 运行。这不影响安装结果，因为 .pc 文件"
echo "  已在上一步用 lib=lib 生成，make test 不会重新生成（.pc 比 .pc.in 新）；"
echo "  下面在 make test 之后会再 cat 一次 libcap.pc 作实证。"
echo "  本节手册没有任何 known-to-fail 说明（对照 §8.26 Acl 有一个 Note），"
echo "  故**退出码就是判据，必须为 0**。"
echo "（手册这条不带 tee，本节按原样直接执行；完整输出另存到 $TESTLOG 供留档。）"
set +e
make test > "$TESTLOG" 2>&1
test_rc=$?
set -e
echo "make test 退出码：$test_rc（输出 $(wc -l < "$TESTLOG") 行）"
echo
echo "----- make test 结论 -----"
echo "测试判定行（各子测试自报的 PASS/PASSED 与各子目录的说明）："
{ grep -nE '(^|[[:space:]/.])(PASS|PASSED|FAIL|FAILED|Error|error:)([[:space:]]|$)|no program tests|no doc tests' "$TESTLOG" || true; } | sed 's/^/  /'
echo
t_rc=0
echo "逐项核对（试建实测：这 7 个判定点全部出现，且 make test 退出码为 0）："
chkt() { # <描述> <匹配用的固定串>
  if { grep -qF "$2" "$TESTLOG"; }; then printf '  OK   %-42s（%s）\n' "$1" "$2"
  else printf '  FAIL %-42s 未出现：%s\n' "$1" "$2"; t_rc=1; fi
}
chkt "libcap/ cap_test"              "cap_test PASS"
chkt "libcap/ libcapsotest（跑 libcap.so 自身）" "is the shared library version: libcap-$VER."
chkt "libcap/ libpsxsotest（跑 libpsx.so 自身）" "is the shared library version: libpsx-$VER."
chkt "tests/ libcap_psx_test"        "hello libcap and libpsx .......... PASSED"
chkt "tests/ psx_test"               "./psx_test PASSED"
chkt "tests/ b219174 与 weaver.so"   "weaver.so launched threads"
chkt "progs/ 无特权测试说明"          "no program tests without privilege"
chkt "doc/ 无测试说明"                "no doc tests available"
echo
echo "失败迹象扫描（本节手册未允许任何失败，故这些都必须为空）："
bad=$({ grep -nE '^(FAIL|FAILED)|(\*\*\* )|Error [0-9]|make.*\*\*\*' "$TESTLOG" || true; })
if [ -n "$bad" ]; then echo "$bad" | sed 's/^/  /'; echo "  FAIL 测试输出中出现失败迹象"; t_rc=1
else echo "  OK   无 FAIL / make Error / *** 之类的失败迹象"; fi
echo
echo "退出码判定（本节的权威判据）："
if [ $test_rc -eq 0 ]; then echo "  OK   make test 退出码 0"
else echo "  FAIL make test 退出码 $test_rc，而本节手册未允许任何失败"; t_rc=1; fi
echo
echo "libcap.so 自报的运行时信息（libcapsotest 的 --summary 输出，含内核已知 cap 数）："
{ grep -A2 'Current mode:' "$TESTLOG" || true; } | sed 's/^/  /'
echo "make test 之后再查一次 pkg-config 文件（证明默认 lib=$def_lib 没有污染它）："
{ cat libcap/libcap.pc || true; } | sed 's/^/    /'
pc_after=$({ grep -m1 '^libdir=' libcap/libcap.pc || true; })
if [ "$pc_after" = "libdir=/usr/lib" ]; then
  echo "  OK   make test 前后 libcap.pc 的 libdir 都是 /usr/lib，未被默认 lib=$def_lib 改写"
else
  echo "  FAIL make test 之后 libcap.pc 的 libdir 变成了：$pc_after"; t_rc=1
fi
[ $t_rc -eq 0 ] || { echo "测试结果不符合手册要求" >&2; exit 1; }
echo
{
  echo "===== §8.27 Libcap-$VER 测试汇总 ====="
  echo "手册命令：make test"
  echo "手册判据（本节关于测试的全部文字，只有一句，没有任何提示框）："
  echo "  「To test the results, issue: make test」"
  echo "  本节手册**没有** known-to-fail 说明（对照 §8.26 Acl 的那个 Note），"
  echo "  故退出码即判据，必须为 0。"
  echo "  手册也没有给出期望的测试项数量，故下面逐项列出的 8 个判定点属本项目自加，"
  echo "  来源是源码各子目录 Makefile 的 test 目标，以及开工前同源码的 chroot /tmp 完整试建。"
  echo
  echo "make test 退出码：$test_rc（要求 0）"
  echo
  echo "逐项（按子目录）："
  echo "  libcap/  cap_test                 PASS   —— 库内部单元测试"
  echo "           libcapsotest             PASS   —— 直接执行 libcap.so 自身，自报 libcap-$VER"
  echo "           libpsxsotest             PASS   —— 直接执行 libpsx.so 自身，自报 libpsx-$VER"
  echo "  tests/   libcap_psx_test          PASSED"
  echo "           psx_test                 PASSED —— psx 的多线程 setuid 语义"
  echo "           weaver.so                PASSED"
  echo "           b219174                  PASSED —— 线程数一致性回归"
  echo "  progs/   （无测试）  打印 \"no program tests without privilege, try 'make sudotest'\""
  echo "           这是 progs/Makefile 第 53 行写死的 echo，**不是权限检测**，任何环境下"
  echo "           都会原样打印。需要特权的程序测试在 make sudotest 里，手册未要求执行。"
  echo "  doc/     （无测试）  打印 \"no doc tests available\""
  echo
  echo "失败迹象扫描：无 FAIL / FAILED / make Error / *** 之类输出。"
  echo "结论：make test 退出码 0，全部子测试自报通过，无未解释的意外失败。"
  echo
  echo "附：make test 手册故意不带 prefix/lib，于是它以默认 lib=$def_lib 运行。"
  echo "    已实证 libcap.pc 在 make test 前后的 libdir 均为 /usr/lib，未被污染。"
} > "$SUMLOG"
echo "测试汇总已写入 $SUMLOG"
echo

# =========================================================================
echo "----- 手册命令 4/4：make prefix=/usr lib=lib install -----"
echo "手册原文：Install the package:"
echo "手册命令：make prefix=/usr lib=lib install"
echo "（完整输出另存到 $INSTLOG）"
set +e
make prefix=/usr lib=lib install > "$INSTLOG" 2>&1
inst_rc=$?
set -e
echo "make install 退出码：$inst_rc（输出 $(wc -l < "$INSTLOG") 行）"
[ $inst_rc -eq 0 ] || { echo "make install 失败，末尾 40 行："; tail -n 40 "$INSTLOG"; exit $inst_rc; }
echo "install 各子目录的动作："
{ grep -E '^make -C |^mkdir -p|nothing to install' "$INSTLOG" || true; } | sed 's/^/  /'
echo

echo "----- 安装后检查（手册 §8.27.2 Contents of Libcap） -----"
ic_rc=0
echo "手册 Installed programs: capsh, getcap, getpcaps, and setcap"
echo "  （手册没写路径；本包 SBINDIR=/usr/sbin，故它们在 /usr/sbin 而不是 /usr/bin）"
for p in capsh getcap getpcaps setcap; do
  if [ -x "/usr/sbin/$p" ]; then
    printf '  OK   /usr/sbin/%-9s %s\n' "$p" "$({ file -b /usr/sbin/$p 2>/dev/null || true; } | cut -c1-58)"
  else printf '  FAIL /usr/sbin/%s 缺失\n' "$p"; ic_rc=1; fi
  if [ -e "/usr/bin/$p" ]; then printf '  INFO 另在 /usr/bin/%s 也发现同名文件\n' "$p"; fi
done
echo "手册 Installed library: libcap.so and libpsx.so"
for l in cap psx; do
  if [ -L "/usr/lib/lib$l.so" ]; then
    echo "  OK   /usr/lib/lib$l.so -> $(readlink /usr/lib/lib$l.so) -> $(readlink /usr/lib/lib$l.so.2 2>/dev/null)"
  else echo "  FAIL /usr/lib/lib$l.so 缺失或不是符号链接"; ic_rc=1; fi
  if [ -f "/usr/lib/lib$l.so.$VER" ]; then
    echo "  OK   实体 /usr/lib/lib$l.so.$VER"
  else echo "  FAIL 实体 /usr/lib/lib$l.so.$VER 缺失"; ic_rc=1; fi
done
{ ls -l /usr/lib/libcap.so* /usr/lib/libpsx.so* || true; } | sed 's/^/    /'
for f in /usr/lib/libcap.so.$VER /usr/lib/libpsx.so.$VER; do
  echo "    [$f]"
  { readelf -d "$f" 2>/dev/null | grep -E 'SONAME|NEEDED' || true; } | sed 's/^/      /'
done
echo "手册未列但确实装出的东西（如实记录，便于日后核对）："
for f in /usr/include/sys/capability.h /usr/include/sys/psx_syscall.h \
         /usr/lib/pkgconfig/libcap.pc /usr/lib/pkgconfig/libpsx.pc; do
  if [ -e "$f" ]; then printf '  OK   %s\n' "$f"
  else printf '  FAIL %s 缺失\n' "$f"; ic_rc=1; fi
done
n_man1=$({ ls /usr/share/man/man1/capsh.1 2>/dev/null | wc -l; })
n_man3=$({ ls /usr/share/man/man3/cap_*.3 /usr/share/man/man3/psx_*.3 \
              /usr/share/man/man3/__psx_syscall.3 /usr/share/man/man3/libcap.3 \
              /usr/share/man/man3/libpsx.3 /usr/share/man/man3/capsetp.3 \
              /usr/share/man/man3/capgetp.3 2>/dev/null | sort -u | wc -l; })
n_man5=$({ ls /usr/share/man/man5/capability.conf.5 2>/dev/null | wc -l; })
n_man7=$({ ls /usr/share/man/man7/cap_text_formats.7 2>/dev/null | wc -l; })
n_man8=$({ ls /usr/share/man/man8/{getcap,setcap,getpcaps,captree,pam_cap}.8 2>/dev/null | wc -l; })
echo "  INFO man 页：man1 $n_man1、man3 $n_man3、man5 $n_man5、man7 $n_man7、man8 $n_man8"
for m in /usr/share/man/man1/capsh.1 /usr/share/man/man3/libcap.3 /usr/share/man/man3/libpsx.3 \
         /usr/share/man/man5/capability.conf.5 /usr/share/man/man7/cap_text_formats.7 \
         /usr/share/man/man8/getcap.8 /usr/share/man/man8/setcap.8 /usr/share/man/man8/getpcaps.8; do
  if [ -e "$m" ]; then printf '  OK   %s\n' "$m"; else printf '  FAIL %s 缺失\n' "$m"; ic_rc=1; fi
done
echo "  INFO /usr/share/man/man8/pam_cap.8 装出了 man 页，但 PAM_CAP=no 故没有 pam_cap.so；"
echo "       手册 Contents 也没有列 pam_cap.so，属正常。"
if [ -e /usr/lib/security/pam_cap.so ] || [ -e /lib/security/pam_cap.so ]; then
  echo "  INFO 发现 pam_cap.so（与 PAM_CAP=no 不符，需留意）"
else
  echo "  OK   系统中没有 pam_cap.so，与 PAM_CAP=no 一致"
fi
echo "本节**不装** /usr/share/doc/libcap-$VER（手册没给 docdir）："
if [ -e "/usr/share/doc/libcap-$VER" ]; then
  echo "  INFO /usr/share/doc/libcap-$VER 竟然存在：$({ ls -A /usr/share/doc/libcap-$VER || true; } | tr '\n' ' ')"
else
  echo "  OK   /usr/share/doc/libcap-$VER 不存在，与手册一致"
fi
echo
echo "----- 那条 sed 的最终可观测结果（本节唯一的「补丁类」操作） -----"
echo "试建对照：不做 sed 时会多装出 /usr/lib/libcap.a 与 /usr/lib/libpsx.a。"
for a in /usr/lib/libcap.a /usr/lib/libpsx.a /lib64/libcap.a /lib64/libpsx.a; do
  if [ -e "$a" ]; then echo "  FAIL 静态库被装进系统：$a"; ic_rc=1
  else echo "  OK   $a 不存在"; fi
done
n_a=$({ find /usr/lib /lib64 -maxdepth 1 \( -name 'libcap.a' -o -name 'libpsx.a' \) 2>/dev/null | wc -l; })
echo "  OK   系统中 libcap/libpsx 静态库数量：$n_a（要求 0）"
echo "  对照：构建目录里它们**仍在**（sed 只管 install，不管编译）："
{ ls -l libcap/libcap.a libcap/libpsx.a 2>/dev/null || true; } | sed 's/^/    /'
echo
echo "----- lib=lib 的最终可观测结果 -----"
echo "手册 §7.5.1 Warning：/usr/lib64 必须不存在"
if [ -e /usr/lib64 ]; then echo "  FAIL /usr/lib64 存在：$({ ls -A /usr/lib64 || true; } | tr '\n' ' ')"; ic_rc=1
else echo "  OK   /usr/lib64 不存在"; fi
echo "/lib64 里不应出现 libcap/libpsx（不给 lib=lib 时它们就会装到这里）："
{ ls -A /lib64 2>/dev/null || true; } | sed 's/^/    /'
if { ls /lib64/libcap* /lib64/libpsx* >/dev/null 2>&1; }; then
  echo "  FAIL /lib64 下出现了 libcap/libpsx"; ic_rc=1
else echo "  OK   /lib64 下没有 libcap/libpsx"; fi
echo "pkg-config 文件里的 libdir 必须是 /usr/lib（后续包靠它找库）："
for pc in /usr/lib/pkgconfig/libcap.pc /usr/lib/pkgconfig/libpsx.pc; do
  d=$({ grep -m1 '^libdir=' "$pc" || true; })
  if [ "$d" = "libdir=/usr/lib" ]; then printf '  OK   %s：%s\n' "$pc" "$d"
  else printf '  FAIL %s：%s\n' "$pc" "$d"; ic_rc=1; fi
done
echo "  两个 .pc 全文："
{ cat /usr/lib/pkgconfig/libcap.pc /usr/lib/pkgconfig/libpsx.pc || true; } | sed 's/^/    /'
echo
echo "----- RAISE_SETFCAP 默认 no 的可观测结果 -----"
echo "progs/Makefile 第 48-49 行那条「给装好的 setcap 打上 cap_setfcap=i」只在"
echo "RAISE_SETFCAP=yes 时执行；本节手册没有要求它，故装出的 setcap 不应带文件 capability："
setcap_caps=$({ /usr/sbin/getcap /usr/sbin/setcap 2>/dev/null || true; })
if [ -z "$setcap_caps" ]; then echo "  OK   getcap /usr/sbin/setcap 无输出（未打 capability），与 RAISE_SETFCAP=no 一致"
else echo "  INFO getcap /usr/sbin/setcap = $setcap_caps"; fi
echo
[ $ic_rc -eq 0 ] || { echo "安装后检查未通过" >&2; exit 1; }

# =========================================================================
echo "----- 功能验证（对照手册 §8.27.2 的 Short Descriptions，用已安装的程序与库） -----"
fn_rc=0
work=$(mktemp -d /tmp/libcap-verify-XXXXXX)
cd "$work"
echo "手册：capsh —— A shell wrapper to explore and constrain capability support"
echo "  capsh --print 的前几行："
{ /usr/sbin/capsh --print 2>&1 || true; } | sed -n '1,8p' | sed 's/^/    /'
if { /usr/sbin/capsh --print >/dev/null 2>&1; }; then echo "  OK   capsh --print 正常返回"
else echo "  FAIL capsh --print 失败"; fn_rc=1; fi
echo "  capsh --decode（把 CapEff 位图译成名字，验证 cap 名字表 cap_names.list.h 可用）："
{ /usr/sbin/capsh --decode=0x0000000000003000 2>&1 || true; } | sed 's/^/    /'
if { /usr/sbin/capsh --decode=0x0000000000003000 2>/dev/null | grep -q 'cap_net_admin'; }; then
  echo "  OK   --decode 正确译出 cap_net_admin（第 12 位）"
else echo "  FAIL --decode 未译出预期的 cap_net_admin"; fn_rc=1; fi
echo
echo "手册：setcap —— Sets file capabilities / getcap —— Examines file capabilities"
cp /usr/bin/true ./tgt
echo "  设置前 getcap ./tgt：[$({ /usr/sbin/getcap ./tgt 2>&1 || true; })]"
if /usr/sbin/setcap 'cap_net_bind_service=+ep' ./tgt 2>/tmp/.setcap.err; then
  echo "  OK   setcap 'cap_net_bind_service=+ep' ./tgt"
else
  echo "  FAIL setcap 失败："; sed 's/^/    /' /tmp/.setcap.err; fn_rc=1
fi
got=$({ /usr/sbin/getcap ./tgt 2>&1 || true; })
echo "  设置后 getcap ./tgt：$got"
case "$got" in
  *cap_net_bind_service*) echo "  OK   getcap 读回了刚写入的 cap_net_bind_service" ;;
  *) echo "  FAIL getcap 没读回预期的 capability"; fn_rc=1 ;;
esac
echo "  与底层扩展属性对照（文件 capability 就是 security.capability 这条 xattr）："
{ getfattr -n security.capability -e hex ./tgt 2>/dev/null || true; } | sed 's/^/    /'
echo "  再用 setcap -r 删除，确认可逆："
{ /usr/sbin/setcap -r ./tgt 2>&1 || true; } | sed 's/^/    /'
after=$({ /usr/sbin/getcap ./tgt 2>&1 || true; })
if [ -z "$after" ]; then echo "  OK   setcap -r 后 getcap 无输出，capability 已清除"
else echo "  FAIL setcap -r 后仍有：$after"; fn_rc=1; fi
rm -f /tmp/.setcap.err
echo
echo "手册：getpcaps —— Displays the capabilities of the queried process(es)"
{ /usr/sbin/getpcaps 1 $$ 2>&1 || true; } | sed 's/^/    /'
if { /usr/sbin/getpcaps $$ >/dev/null 2>&1; }; then echo "  OK   getpcaps 可查询进程 capability"
else echo "  FAIL getpcaps 失败"; fn_rc=1; fi
echo
echo "手册：libcap —— Contains the library functions for manipulating POSIX 1003.1e capabilities"
cat > t.c <<'CEOF'
#include <sys/capability.h>
#include <stdio.h>
int main(void) {
  cap_t c = cap_get_proc();
  if (!c) { perror("cap_get_proc"); return 1; }
  char *s = cap_to_text(c, NULL);
  printf("cap_get_proc 成功；cap_max_bits()=%u\n", cap_max_bits());
  printf("cap_to_text 前 70 字符：%.70s\n", s ? s : "(null)");
  cap_free(s); cap_free(c);
  return 0;
}
CEOF
if gcc -o t t.c -lcap 2>t.err; then
  echo "  OK   用 -lcap 链接成功（头文件 sys/capability.h 可用）"
  if ./t > t.out 2>t.run.err; then sed 's/^/    /' t.out
  else echo "  FAIL 运行失败："; sed 's/^/    /' t.run.err; fn_rc=1; fi
  { ldd t | grep -E 'libcap' || true; } | sed 's/^/    /'
else
  echo "  FAIL 用 -lcap 链接失败："; sed 's/^/    /' t.err; fn_rc=1
fi
echo
echo "手册：libpsx —— Contains functions to support POSIX semantics for syscalls"
echo "               associated with the pthread library"
cat > p.c <<'CEOF'
#include <sys/psx_syscall.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <stdio.h>
int main(void) {
  /* psx_syscall 把系统调用广播到进程的全部线程；这里用 getpid 这种无副作用的调用
     验证符号可解析且调用路径通畅。 */
  long r = psx_syscall3(SYS_getpid, 0, 0, 0);
  printf("psx_syscall3(SYS_getpid) = %ld，getpid() = %d\n", r, getpid());
  return (r == (long)getpid()) ? 0 : 1;
}
CEOF
if gcc -o p p.c $(pkg-config --libs libpsx) 2>p.err; then
  echo "  OK   用 pkg-config --libs libpsx 链接成功（头文件 sys/psx_syscall.h 可用）"
  echo "       实际链接参数：$(pkg-config --libs libpsx)"
  if ./p > p.out 2>p.run.err; then sed 's/^/    /' p.out; echo "  OK   psx_syscall3 返回值与 getpid() 一致"
  else echo "  FAIL 运行失败："; sed 's/^/    /' p.run.err; sed 's/^/    /' p.out 2>/dev/null || true; fn_rc=1; fi
else
  echo "  FAIL 链接 libpsx 失败："; sed 's/^/    /' p.err; fn_rc=1
fi
echo
echo "pkg-config 可用性（后续包靠它找 libcap，例如 §8.x systemd/shadow）："
{ pkg-config --modversion libcap && pkg-config --libs libcap && pkg-config --cflags libcap; } 2>&1 | sed 's/^/  /'
pcv=$({ pkg-config --modversion libcap 2>/dev/null || true; })
if [ "$pcv" = "$VER" ]; then echo "  OK   pkg-config --modversion libcap = $pcv"
else echo "  FAIL pkg-config --modversion libcap = $pcv，期望 $VER"; fn_rc=1; fi
pcvp=$({ pkg-config --modversion libpsx 2>/dev/null || true; })
if [ "$pcvp" = "$VER" ]; then echo "  OK   pkg-config --modversion libpsx = $pcvp"
else echo "  FAIL pkg-config --modversion libpsx = $pcvp，期望 $VER"; fn_rc=1; fi
echo "ldconfig 缓存是否已收录 libcap/libpsx（install 末尾会调 /sbin/ldconfig）："
{ ldconfig -p 2>/dev/null | grep -E 'libcap\.so|libpsx\.so' || true; } | sed 's/^/  /'
cd /sources/$SRCDIR
rm -rf "$work"
[ $fn_rc -eq 0 ] || { echo "功能验证未通过" >&2; exit 1; }
echo

# =========================================================================
echo "----- 保留日志摘要后清理构建目录（手册 iii：删除解包出来的源码目录） -----"
echo "（摘要先写到 /sources —— 它是宿主机 bind mount，随后由宿主机侧 run-8.27.sh"
echo "  移入 $LFS_ROOT/logs/packages/，不会在镜像内留下多余目录）"
echo "  sed 记录     ：$SEDLOG"
echo "  make         完整输出：$MAKELOG"
echo "  make test    完整输出：$TESTLOG"
echo "  make install 完整输出：$INSTLOG"
echo "  测试汇总     ：$SUMLOG"
cd /sources
echo "清理前 /sources 下的 libcap 相关条目："
{ ls -d /sources/libcap* 2>/dev/null || true; } | sed 's/^/  /'
echo "  待删除：$({ du -sh /sources/$SRCDIR 2>/dev/null || true; } | awk '{print $1"\t"$2}')"
rm -rf "/sources/$SRCDIR"
echo "已删除 /sources/$SRCDIR"
echo "清理后 /sources 下的 libcap 相关条目（应只剩 tarball）："
{ ls -d /sources/libcap* 2>/dev/null || true; } | sed 's/^/  /'
if [ -e "/sources/$SRCDIR" ]; then echo "  FAIL 源码构建目录仍存在"; exit 1
else echo "  OK   源码构建目录已删除"; fi
echo "/sources 下的解包残留（应为空）："
{ find /sources -maxdepth 1 -type d -name 'libcap*' || true; } | sed 's/^/  /'
echo "/sources 文件数：$({ ls -A /sources | wc -l; })"
echo "/tmp 下本节留下的临时目录/文件（应为空）："
{ find /tmp -maxdepth 1 \( -name 'libcap*' -o -name '.libcap*' \) || true; } | sed 's/^/  /'
echo "根文件系统占用："
{ df -h / | tail -n1 || true; } | sed 's/^/  /'
echo

echo "================= 本节结论 ================="
echo "手册 §8.27 的 4 条命令全部按原样执行完毕："
echo "  1. sed -i '/install -m.*STA/d' libcap/Makefile"
echo "                                     —— 完成，恰好删除 2 行（静态 cap/psx 库的 install）"
echo "  2. make prefix=/usr lib=lib        —— 完成，退出码 $make_rc"
echo "  3. make test                       —— 完成，退出码 $test_rc（本节要求 0）"
echo "  4. make prefix=/usr lib=lib install —— 完成，退出码 0"
echo "本节没有 configure、没有补丁文件、没有 build 目录（in-tree build），"
echo "  没有 docdir，也没有 make html/install-html。"
echo "本节唯一的提示框是 §8.27.1 开头那个关于 GOLANG 的 Note：其两个前提"
echo "  （在既有系统上更新、装有 go 编译器）在本环境都不成立（首次安装 + 无 go，"
echo "  Make.Rules 自算 GOLANG=no），故未设置也无需 unset GOLANG。"
echo
echo "测试结论："
echo "  make test 退出码：$test_rc（本节手册无 known-to-fail 说明，退出码即判据，要求 0）"
echo "  libcap/ ：cap_test PASS、libcapsotest PASS、libpsxsotest PASS"
echo "  tests/  ：libcap_psx_test PASSED、psx_test PASSED、weaver.so PASSED、b219174 PASSED"
echo "  progs/  ：无测试（\"no program tests without privilege\" 是写死的 echo，非权限检测；"
echo "            需特权的 make sudotest 手册未要求执行）"
echo "  doc/    ：无测试"
echo "  无 FAIL / make Error / *** 等失败迹象，无未解释的意外失败。"
echo
echo "手册 §8.27.2 Contents 逐项确认："
echo "  Installed programs : capsh, getcap, getpcaps, setcap —— 均已装入 /usr/sbin"
echo "                       （手册未写路径；本包 SBINDIR=/usr/sbin，不在 /usr/bin）"
echo "  Installed library  : libcap.so —— 已装（-> libcap.so.2 -> libcap.so.$VER，SONAME libcap.so.2）"
echo "                       libpsx.so —— 已装（-> libpsx.so.2 -> libpsx.so.$VER，SONAME libpsx.so.2）"
echo "  手册未列但确实装出：/usr/include/sys/capability.h、/usr/include/sys/psx_syscall.h、"
echo "                      /usr/lib/pkgconfig/{libcap.pc,libpsx.pc}、"
echo "                      man1 $n_man1 页 + man3 $n_man3 页 + man5 $n_man5 页 + man7 $n_man7 页 + man8 $n_man8 页"
echo "  两条手册命令选项的可观测结果："
echo "    sed     → /usr/lib 下没有 libcap.a / libpsx.a（不做 sed 会多装出这两个）"
echo "    lib=lib → 库进 /usr/lib、程序进 /usr/sbin，/usr/lib64 不存在、/lib64 无 libcap"
echo "              （本机默认 lib 会算成 $def_lib，故这个参数是实打实必要的）"
echo
echo "结束时间：$(date -Is)"
echo "===== §8.27 Libcap-$VER 完成 ====="
