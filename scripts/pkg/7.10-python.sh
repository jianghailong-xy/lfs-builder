#!/usr/bin/env bash
# LFS 13.0-systemd §7.10 Python-3.14.3（临时工具）
# 在 chroot 环境内以 root 执行（由 scripts/chroot.sh run 送入，环境即手册 §7.4 的
# env -i HOME=/root TERM=$TERM PS1=... PATH=/usr/bin:/usr/sbin MAKEFLAGS=-j$(nproc)
# TESTSUITEFLAGS=-j$(nproc) /bin/bash --login）。
#
# 手册 §7.10.1 的命令序列（全部；本节无补丁、无测试套件）：
#   ./configure --prefix=/usr        \
#               --enable-shared      \
#               --without-ensurepip  \
#               --without-static-libpython
#   make
#   make install
#
# 手册 §7.10.1 Note：There are two package files whose name starts with the "python"
#   prefix. The one to extract from is Python-3.14.3.tar.xz (notice the uppercase
#   first letter).
set -euo pipefail

PKG=Python
VER=3.14.3
TARBALL=$PKG-$VER.tar.xz
SRCDIR=$PKG-$VER

echo "===== LFS 13.0-systemd §7.10 Python-$VER（临时工具） ====="
echo "开始时间：$(date -Is)"
echo "手册数据：Approximate build time 0.5 SBU，Required disk space 592 MB"
echo "手册简介：The Python 3 package contains the Python development environment."
echo "  It is useful for object-oriented programming, writing scripts, prototyping"
echo "  large programs, and developing entire applications. Python is an interpreted"
echo "  computer language."
echo

echo "----- 环境（手册 §7.4 进入 chroot 后的环境） -----"
echo "id        : $(id)"
echo "whoami    : $(whoami)"
echo "PATH      : $PATH"
echo "HOME      : $HOME"
echo "MAKEFLAGS : ${MAKEFLAGS:-（未设置）}"
echo "TESTSUITEFLAGS: ${TESTSUITEFLAGS:-（未设置）}"
echo "umask     : $(umask)"
echo "uname -m  : $(uname -m)"
echo "nproc     : $(nproc)"
echo "根目录内容：$(ls / | tr '\n' ' ')"
[ "$(id -u)" -eq 0 ] || { echo "错误：chroot 内必须是 root" >&2; exit 1; }
case ":$PATH:" in
  *:/tools/bin:*) echo "错误：PATH 中仍含 /tools/bin，不符合手册 §7.4" >&2; exit 1 ;;
  *) echo "OK        : /tools/bin 不在 PATH（交叉工具链已停用）" ;;
esac
echo "可用空间（手册本节要求 592 MB）："
df -h / | tail -n1
avail_mb=$(df -Pm / | tail -n1 | awk '{print $4}')
[ "$avail_mb" -ge 592 ] || { echo "错误：可用空间 ${avail_mb}MB 少于手册要求的 592MB" >&2; exit 1; }
echo

echo "----- 前置检查：上一任务（§7.9 Perl-5.42.0）产物及 chroot 基础必须可用 -----"
rc=0
echo "1) §7.9 装入 /usr 的 Perl 产物（Python 构建期不直接依赖，确认上一任务产物完好）："
if command -v perl >/dev/null 2>&1; then
  printf '   OK   %-9s %-16s %s\n' perl "$(command -v perl)" "$(perl -e 'print "v$]"')"
  perl -V:version 2>/dev/null | sed 's/^/        /'
else
  echo "   FAIL perl 不可用（§7.9 未完成？）"; rc=1
fi
for f in /usr/bin/perl /usr/bin/cpan /usr/bin/prove; do
  if [ -x "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "2) §7.7/§7.8 产物（构建链路完好性确认）："
for t in msgfmt xgettext bison yacc; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-9s %s\n' "$t" "$(command -v $t)"
  else printf '   FAIL %s 不可用\n' "$t"; rc=1; fi
done
echo "3) 编译器与第 6 章工具（Python 的 configure 是 autoconf 脚本，需 sh/sed/grep/awk/cc/ld/ar/make 等）："
for t in gcc cc g++ ld as ar ranlib make sed grep gawk m4 tar xz patch find diff file bash pkg-config; do
  if command -v $t >/dev/null 2>&1; then printf '   OK   %-11s %s\n' "$t" "$(command -v $t)"
  else printf '   INFO %-11s 不可用\n' "$t"; fi
done
for t in gcc cc ld ar make sed grep gawk tar xz find bash; do
  command -v $t >/dev/null 2>&1 || { printf '   FAIL 必需工具 %s 不可用\n' "$t"; rc=1; }
done
gcc --version | sed -n '1s/^/   gcc: /p'
echo "4) Python 需要的 C 库头文件与库（configure 会探测大量 libc 特性）："
for h in /usr/include/stdio.h /usr/include/pthread.h /usr/include/dlfcn.h \
         /usr/include/sys/mman.h /usr/include/langinfo.h; do
  if [ -f "$h" ]; then printf '   OK   %s\n' "$h"; else printf '   FAIL %s 缺失\n' "$h"; rc=1; fi
done
for l in /usr/lib/libc.so /usr/lib/libm.so; do
  if [ -e "$l" ]; then printf '   OK   %s\n' "$l"; else printf '   FAIL %s 缺失\n' "$l"; rc=1; fi
done
echo "   动态链接器（--enable-shared 生成的 libpython 需要它）：$(ls /lib64/ld-linux-x86-64.so.2 2>/dev/null || echo 缺失)"
echo "5) §7.6 建立的基础文件："
for f in /etc/passwd /etc/group /etc/hosts /etc/mtab; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "6) §7.3 虚拟内核文件系统："
for f in /dev/null /dev/zero /dev/urandom /dev/pts /proc/self /sys; do
  if [ -e "$f" ]; then printf '   OK   %s\n' "$f"; else printf '   FAIL %s 缺失\n' "$f"; rc=1; fi
done
echo "7) 本节安装前 python3 相关文件的状态："
for f in /usr/bin/python3 /usr/bin/pydoc3 /usr/lib/libpython3.so; do
  if [ -e "$f" ]; then printf '   INFO %s 已存在（将被 make install 覆盖）\n' "$f"
  else printf '   OK   %s 尚未安装\n' "$f"; fi
done
[ $rc -eq 0 ] || { echo "错误：前置条件不满足" >&2; exit 1; }
echo

cd /sources
echo "----- 源码包选择（手册 §7.10.1 Note） -----"
echo "手册原文：There are two package files whose name starts with the \"python\""
echo "  prefix. The one to extract from is Python-3.14.3.tar.xz (notice the uppercase"
echo "  first letter)."
echo "/sources 下以 python 开头（不区分大小写）的文件："
ls -1 /sources | grep -i '^python' | sed 's/^/  /' || true
echo "本节采用：$TARBALL（首字母大写），另一份 python-$VER-docs-html.tar.bz2 是文档包，"
echo "  第 7 章不使用（第 8 章 §8.53 才可选安装文档）。"
echo

echo "----- 源码包校验（md5sums，手册 §3.1） -----"
grep -E " $TARBALL\$" md5sums
grep -E " $TARBALL\$" md5sums | md5sum -c -
echo

echo "----- 解包（手册 iii. General Compilation Instructions） -----"
rm -rf "$SRCDIR"
tar -xf "$TARBALL"
cd "$SRCDIR"
echo "源码目录：$PWD"
echo "包自报版本：$(grep -m1 -E '^PACKAGE_STRING=' configure | sed "s/^PACKAGE_STRING=//; s/'//g")"
echo "Include/patchlevel.h 版本：$(grep -m1 'PY_VERSION ' Include/patchlevel.h | sed 's/.*"\(.*\)".*/\1/')"
echo "本节无补丁：手册 §7.10 只有 ./configure、make、make install 三条命令，"
echo "  没有任何 patch/sed 前置改动（sources 目录下也没有 python 相关补丁文件：$(ls /sources | grep -ci 'python.*patch') 个）。"
echo

echo "================= 7.10.1. Installation of Python ================="
echo "----- configure（手册原文：Prepare Python for compilation） -----"
echo "手册命令：./configure --prefix=/usr        \\"
echo "                      --enable-shared      \\"
echo "                      --without-ensurepip  \\"
echo "                      --without-static-libpython"
echo "手册对 configure 选项的说明："
echo "  --enable-shared              This switch prevents installation of static libraries."
echo "  --without-ensurepip          This switch disables the Python package installer,"
echo "                               which is not needed at this stage."
echo "  --without-static-libpython   This switch prevents building a large, but unneeded,"
echo "                               static library."
time ./configure --prefix=/usr        \
            --enable-shared      \
            --without-ensurepip  \
            --without-static-libpython
echo
echo "configure 结果确认："
grep -m1 '\$ \./configure' config.log | sed 's/^ *\$ */  实际参数：/' || true
if grep -qE '^\s*\$ \./configure --prefix=/usr --enable-shared --without-ensurepip --without-static-libpython\s*$' config.log; then
  echo "  OK   configure 参数与手册 §7.10 完全一致"
else
  echo "  注意：configure 参数与手册字面不一致，见上一行"
fi
echo "  生成的构建参数："
grep -m1 '^prefix=' Makefile        | sed 's/^/    Makefile: /' || true
grep -m1 '^VERSION=' Makefile       | sed 's/^/    Makefile: /' || true
grep -m1 '^LDLIBRARY=' Makefile     | sed 's/^/    Makefile: /' || true
grep -m1 '^ENABLE_SHARED=' Makefile | sed 's/^/    Makefile: /' || true
echo "  --enable-shared 生效检查（LDLIBRARY 应为 .so 而非 .a）："
if grep -qE '^LDLIBRARY=[[:space:]]*libpython.*\.so' Makefile; then
  echo "    OK   共享库构建已开启"
else
  echo "    FAIL LDLIBRARY 不是共享库"; exit 1
fi
echo "  --without-ensurepip 生效检查（ENSUREPIP 应为 no）："
grep -m1 '^ENSUREPIP=' Makefile | sed 's/^/    Makefile: /' || true
if grep -qE '^ENSUREPIP=[[:space:]]*no[[:space:]]*$' Makefile; then
  echo "    OK   ensurepip 已禁用（本阶段不安装 pip）"
else
  echo "    注意：ENSUREPIP 不是 no"
fi
echo

echo "----- 编译（手册原文：Compile the package） -----"
echo "手册命令：make"
echo "（MAKEFLAGS=${MAKEFLAGS:-} 由手册 §7.4 的 chroot 环境提供）"
echo "手册 Note：Some Python 3 modules can't be built now because the dependencies are"
echo "  not installed yet. For the ssl module, a message \"Python requires a OpenSSL"
echo "  1.1.1 or newer\" is outputted. The message should be ignored. Just make sure the"
echo "  toplevel make command has not failed. The optional modules are not needed now"
echo "  and they will be built in Chapter 8."
time make
echo
echo "顶层 make 退出码 0（手册要求：make sure the toplevel make command has not failed）"
echo "构建期缺失/跳过的可选模块（手册明确允许，第 8 章补齐）："
echo "  （下方 '缺失模块' 汇总由 make 输出给出，见上文；此处再复核一次）"
LD_LIBRARY_PATH=$PWD ./python -c 'import sys; print("  可用 builtin 模块数：", len(sys.builtin_module_names))' 2>/dev/null || true
for m in ssl _ssl _hashlib _curses readline _tkinter _lzma _bz2 _sqlite3 zlib; do
  if LD_LIBRARY_PATH=$PWD ./python -c "import $m" >/dev/null 2>&1; then printf '  可用   %s\n' "$m"
  else printf '  未构建 %s（手册允许，第 8 章补齐）\n' "$m"; fi
done
echo

echo "================= 本节测试 ================="
echo "手册 §7.10 未规定任何测试：本节命令只有 ./configure --prefix=/usr --enable-shared"
echo "  --without-ensurepip --without-static-libpython、make 和 make install，"
echo "  没有 make test / make check。"
echo "  第 7 章各小节（Gettext、Bison、Perl、Python、Texinfo、Util-linux）均不跑测试；"
echo "  手册 §7.1 说明第 7 章的临时工具不做测试，Python 的测试套件也不在第 8 章 §8.53 运行。"
echo "结论：本节无测试可执行，不存在测试失败；验证以下列安装结果检查为准。"
echo

echo "----- 安装（手册原文：Install the package） -----"
echo "手册命令：make install"
time make install
echo

echo "----- 安装结果检查（对照手册 §8.53.2 Contents of Python 3） -----"
echo "手册 §8.53.2：Installed programs: idle3, pip3, pydoc3, python3, and python3-config；"
echo "  Installed library: libpython3.14.so and libpython3.so；"
echo "  Installed directories: /usr/include/python3.14, /usr/lib/python3,"
echo "  and /usr/share/doc/python-3.14.3"
echo "  说明：本节是第 7 章的临时安装，且使用了 --without-ensurepip，因此 pip3 不安装；"
echo "  idle3 需要先装 Tk 才有 Tkinter 模块，本阶段无 Tk；/usr/share/doc/python-3.14.3"
echo "  由第 8 章 §8.53 单独解包文档包生成。以上均非本节应产出的内容。"
rc=0
echo "1) 程序（本节应产出的）："
for p in /usr/bin/python3 /usr/bin/python3.14 /usr/bin/pydoc3 \
         /usr/bin/python3-config /usr/bin/python3.14-config; do
  if [ -e "$p" ]; then printf '   OK   %-30s %s\n' "$p" "$(file -b "$p" | cut -d, -f1-2)"
  else printf '   FAIL %s 缺失\n' "$p"; rc=1; fi
done
echo "   python3 -> $(readlink -f /usr/bin/python3)"
echo "2) 共享库（--enable-shared 的产物）："
for l in /usr/lib/libpython3.14.so /usr/lib/libpython3.so; do
  if [ -e "$l" ]; then printf '   OK   %-30s %s\n' "$l" "$(file -b "$l" | cut -d, -f1-3)"
  else printf '   FAIL %s 缺失\n' "$l"; rc=1; fi
done
echo "   --without-static-libpython 生效检查（不应有静态库 libpython3.14.a）："
if ls /usr/lib/libpython*.a >/dev/null 2>&1; then
  echo "     FAIL 存在静态库：$(ls /usr/lib/libpython*.a | tr '\n' ' ')"; rc=1
else
  echo "     OK   /usr/lib 下没有 libpython*.a"
fi
echo "   --without-ensurepip 生效检查（不应安装 pip3/pip3.14）："
if [ -e /usr/bin/pip3 ] || [ -e /usr/bin/pip3.14 ]; then
  echo "     FAIL 存在 pip3（ensurepip 未被禁用）"; rc=1
else
  echo "     OK   /usr/bin 下没有 pip3（符合 --without-ensurepip）"
fi
echo "3) 目录："
for d in /usr/include/python3.14 /usr/lib/python3.14; do
  if [ -d "$d" ]; then echo "   OK   $d（$(find "$d" -type f | wc -l) 个文件）"
  else echo "   FAIL $d 缺失"; rc=1; fi
done
echo "   /usr/lib/python3.14/lib-dynload（编译型扩展模块）：$(find /usr/lib/python3.14/lib-dynload -name '*.so' 2>/dev/null | wc -l) 个 .so"
echo "4) 运行冒烟测试："
py_ver=$(python3 --version 2>&1)
echo "   python3 --version：$py_ver"
case "$py_ver" in *"$VER"*) echo "   OK   版本号含 $VER" ;;
  *) echo "   FAIL python3 报告的版本不含 $VER"; rc=1 ;; esac
echo "   解释器可执行并动态链接到 libpython（--enable-shared）："
ldd /usr/bin/python3.14 | sed 's/^/     /'
if ldd /usr/bin/python3.14 | grep -q 'libpython3\.14\.so'; then
  echo "     OK   python3.14 链接到 libpython3.14.so"
else
  echo "     FAIL python3.14 未链接到 libpython3.14.so"; rc=1
fi
echo "   基本求值与标准库导入："
python3 -c 'print("     OK   算术：20+22 =", 20+22)' || { echo "     FAIL 解释器无法运行"; rc=1; }
python3 - <<'PYEOF' || rc=1
import sys, os, re, json, subprocess, sysconfig, importlib, encodings, unicodedata
print("     OK   sys.version   :", sys.version.split()[0])
print("     OK   sys.executable:", sys.executable)
print("     OK   sys.prefix    :", sys.prefix)
print("     OK   stdlib 路径   :", sysconfig.get_path("stdlib"))
for m in ("os", "re", "json", "subprocess", "sysconfig", "importlib",
          "encodings", "unicodedata", "argparse", "shutil", "hashlib",
          "logging", "tempfile", "textwrap", "collections", "datetime"):
    importlib.import_module(m)
print("     OK   标准库模块导入全部成功（os re json subprocess sysconfig importlib")
print("          encodings unicodedata argparse shutil hashlib logging tempfile")
print("          textwrap collections datetime）")
print("     OK   UTF-8 处理  :", "中文-ok".encode("utf-8").decode("utf-8"))
print("     OK   json 往返   :", __import__("json").loads('{"a": [1, 2, 3]}'))
PYEOF
echo "   编译型扩展（lib-dynload，依赖动态加载）逐个复核："
for m in math binascii select fcntl _struct _datetime array _csv unicodedata; do
  if python3 -c "import $m" >/dev/null 2>&1; then printf '     OK     %s\n' "$m"
  else printf '     FAIL   %s 无法导入（本节应可用）\n' "$m"; rc=1; fi
done
echo "   依赖第 8 章外部库、本节按手册允许缺失的可选模块："
for m in zlib _bz2 _lzma ssl _ssl _hashlib _sqlite3 readline _curses _tkinter; do
  if python3 -c "import $m" >/dev/null 2>&1; then printf '     可用   %s\n' "$m"
  else printf '     未构建 %s（手册 Note 明确允许，第 8 章补齐）\n' "$m"; fi
done
echo "   pydoc3（手册 §8.53.2：the Python documentation tool）："
# 注意：不要写成 pydoc3 os | head -n1 —— 本脚本开了 pipefail，head 提前退出会让
# pydoc3 收到 SIGPIPE（退出码 141），整条管道被判为失败，与 pydoc3 本身无关。
pydoc_out=/tmp/.py310-pydoc.out
if pydoc3 os >"$pydoc_out" 2>/dev/null && [ -s "$pydoc_out" ]; then
  echo "     OK   pydoc3 可输出模块文档（$(wc -l < "$pydoc_out") 行），首行："
  sed -n '1p' "$pydoc_out" | sed 's/^/       /'
else
  echo "     FAIL pydoc3 无法运行"; rc=1
fi
rm -f "$pydoc_out"
echo "   python3-config（后续包用它查询编译参数）："
echo "     --prefix : $(python3-config --prefix)"
echo "     --includes: $(python3-config --includes)"
echo "     --libs   : $(python3-config --libs)"
echo "   子进程调用（第 8 章多个包的构建脚本依赖）："
python3 -c 'import subprocess; print("     OK   subprocess:", subprocess.run(["echo","hello-from-subprocess"],capture_output=True,text=True).stdout.strip())' \
  || { echo "     FAIL subprocess 不可用"; rc=1; }
echo "   -m 模块运行（第 8 章 wheel/flit-core 等以 python3 -m 方式调用）："
python3 -m json.tool <<< '{"k":"v"}' | sed 's/^/     /' \
  || { echo "     FAIL python3 -m 不可用"; rc=1; }
echo "   site-packages 目录（第 8 章安装 Python 模块的目标）："
python3 -c 'import site; print("    ", site.getsitepackages())'
[ $rc -eq 0 ] || { echo "错误：Python 关键文件缺失或不符合手册要求" >&2; exit 1; }
echo

echo "----- 清理构建目录（手册 iii：删除解包出来的源码目录） -----"
cd /sources
rm -rf "$SRCDIR"
[ -d "/sources/$SRCDIR" ] && { echo "错误：源码目录未清理" >&2; exit 1; }
echo "已删除 /sources/$SRCDIR"
echo "/sources 下的解包残留（应为空）："
find /sources -maxdepth 1 -mindepth 1 -type d | sed 's/^/  /' || true
echo "/sources 文件数：$(find /sources -maxdepth 1 -type f | wc -l)"
echo "根文件系统占用："
df -h / | tail -n1
echo
echo "===== §7.10 完成，结束时间：$(date -Is) ====="
