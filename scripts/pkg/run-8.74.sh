#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

echo "===== LFS 13.0-systemd §8.74 Texinfo-7.2 ====="
echo "start: $(date -Iseconds)"
cd /sources

echo "===== 前置产物与源码校验 ====="
test "$(tar --version | head -n1)" = "tar (GNU tar) 1.35"
test -s /usr/share/doc/tar-1.35/tar.html/index.html
grep ' texinfo-7.2.tar.xz$' md5sums | md5sum -c -
test ! -e texinfo-7.2
echo "OK: 上一节 Tar-1.35 产物可用，Texinfo 源码校验通过。"

echo "===== 解包 ====="
tar -xf texinfo-7.2.tar.xz
cd texinfo-7.2

echo "===== 应用 §8.74 规定的 Perl-5.42 警告修复 ====="
sed 's/! $output_file eq/$output_file ne/' -i tp/Texinfo/Convert/*.pm
if grep -nF '! $output_file eq' tp/Texinfo/Convert/*.pm; then
  echo "ERROR: sed 修复后仍有旧模式残留" >&2
  exit 1
fi

echo "===== 配置 ====="
./configure --prefix=/usr

echo "===== 编译 ====="
make

echo "===== 测试 ====="
make check
echo "TEST_RESULT: PASS (make check exit 0)"

echo "===== 安装 ====="
make install

echo "===== 安装结果验证 ====="
makeinfo --version | head -n1
info --version | head -n1
test "$(makeinfo --version | head -n1)" = "texi2any (GNU texinfo) 7.2"
test -x /usr/bin/info
test -x /usr/bin/install-info
test -x /usr/bin/texi2any
test -s /usr/share/info/texinfo.info
echo "OK: Texinfo-7.2 关键程序与 Info 文档已安装。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf -- texinfo-7.2
test ! -e texinfo-7.2
echo "OK: /sources/texinfo-7.2 已删除，源码包保留。"
echo "finish: $(date -Iseconds)"
echo "FINAL_RESULT: SUCCESS"
