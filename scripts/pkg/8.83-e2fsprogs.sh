#!/usr/bin/env bash
set -euo pipefail

cd /sources
echo "===== 前置产物与源码检查 ====="
test -x /usr/bin/mount
test -x /usr/bin/lsblk
test -e /usr/lib/libmount.so
mount --version | head -n1
lsblk --version
test -f e2fsprogs-1.47.3.tar.gz
rm -rf e2fsprogs-1.47.3

echo "===== 解包源码 ====="
tar -xvf e2fsprogs-1.47.3.tar.gz
cd e2fsprogs-1.47.3

echo "===== 配置 ====="
mkdir -v build
cd build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-elf-shlibs \
             --disable-libblkid  \
             --disable-libuuid   \
             --disable-uuidd     \
             --disable-fsck

echo "===== 编译 ====="
make

echo "===== 测试 ====="
set +e
make check
test_rc=$?
set -e
echo "make check exit code: $test_rc"
if [ "$test_rc" -ne 0 ]; then
  echo "测试返回非零；汇总失败测试（手册仅允许 m_assume_storage_prezeroed，非 ext4 时另允许 m_rootdir_acl）："
  failed=$(find tests -type f \( -name '*.failed' -o -name '*.log' \) -exec grep -H -E '^FAIL|FAILED|Failure' {} + 2>/dev/null || true)
  printf '%s\n' "$failed"
  unexpected=$(printf '%s\n' "$failed" | grep -v -E 'm_assume_storage_prezeroed|m_rootdir_acl|^$' || true)
  if [ -n "$unexpected" ]; then
    echo "ERROR: 存在手册未允许的测试失败"
    exit "$test_rc"
  fi
fi

echo "===== 安装 ====="
make install
rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
gunzip -v /usr/share/info/libext2fs.info.gz
install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info

echo "===== 安装结果验证 ====="
for p in /usr/sbin/e2fsck /usr/sbin/mke2fs /usr/sbin/tune2fs /usr/bin/chattr /usr/bin/lsattr; do
  test -x "$p"
  echo "OK: $p"
done
for l in libcom_err libe2p libext2fs libss; do
  test -e "/usr/lib/$l.so"
  test ! -e "/usr/lib/$l.a"
  echo "OK: /usr/lib/$l.so；静态库不存在"
done
test -s /usr/share/info/libext2fs.info
/usr/sbin/mke2fs -V 2>&1 | head -n2
echo "OK: E2fsprogs-1.47.3 关键程序、共享库和 info 文档均已验证。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf e2fsprogs-1.47.3
test ! -e /sources/e2fsprogs-1.47.3
echo "OK: /sources/e2fsprogs-1.47.3 已删除，源码包保留。"
echo "finish: $(date -Is)"
echo "FINAL_RESULT: SUCCESS"
