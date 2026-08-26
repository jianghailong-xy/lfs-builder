#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

cd /sources

echo "===== LFS 13.0-systemd §8.81 Procps-ng-4.0.6 ====="
echo "start: $(date -Iseconds)"

echo "===== 上一任务产物与源码校验 ====="
test -x /usr/bin/man
test -x /usr/bin/mandb
/usr/bin/man --version | head -1
echo '20c23dc3dd1569a2bb1d1fa93de213ed  procps-ng-4.0.6.tar.xz' | md5sum -c -
test ! -e procps-ng-4.0.6 || {
  echo "错误：/sources/procps-ng-4.0.6 已存在；保留现场并停止。" >&2
  exit 1
}
echo "OK: §8.80 Man-DB 关键产物和 Procps-ng 源码包可用。"

echo "===== 解包 ====="
tar -xf procps-ng-4.0.6.tar.xz
cd procps-ng-4.0.6

echo "===== 补丁 ====="
echo "INFO: LFS 13.0-systemd §8.81 未规定补丁。"

echo "===== 配置 ====="
./configure --prefix=/usr                           \
            --docdir=/usr/share/doc/procps-ng-4.0.6 \
            --disable-static                        \
            --disable-kill                          \
            --enable-watch8bit                      \
            --with-systemd

echo "===== 编译 ====="
make

echo "===== 测试 ====="
chown -R tester .
set +e
su tester -c "PATH=$PATH make check"
test_rc=$?
set -e
echo "TEST_EXIT_CODE: $test_rc"
if [ "$test_rc" -ne 0 ]; then
  echo "===== 失败测试诊断 ====="
  find . -name testsuite.log -type f -exec sh -c 'echo "--- $1"; cat "$1"' sh {} \;
  fail_count=$(find . -name testsuite.log -type f -exec grep -hEc '^FAIL: ' {} \; | awk '{n+=$1} END {print n+0}')
  if [ "$fail_count" -eq 1 ] && find . -name testsuite.log -type f -exec grep -Eqi 'bsdtime.*cputime.*etime.*etimes|ps with output flag bsdtime,cputime,etime,etimes' {} +; then
    echo "TEST_RESULT: PASS_WITH_KNOWN_FAILURE"
    echo "INFO: 唯一失败为手册允许的 ps bsdtime,cputime,etime,etimes（内核未启用 CONFIG_BSD_PROCESS_ACCT 时已知失败）。"
  else
    echo "TEST_RESULT: FAIL_UNEXPECTED"
    exit "$test_rc"
  fi
else
  echo "TEST_RESULT: PASS"
fi

echo "===== 安装 ====="
make install

echo "===== 安装结果验证 ====="
for program in free pgrep pidof pkill pmap ps pwdx slabtop sysctl tload top uptime vmstat w watch; do
  command -v "$program"
  test -x "$(command -v "$program")"
  echo "OK: $program"
done
test -e /usr/lib/libproc2.so.1
test -e /usr/lib/libproc2.so
test -d /usr/include/libproc2
test -d /usr/share/doc/procps-ng-4.0.6
/usr/bin/ps --version
/usr/bin/free --version
echo "OK: Procps-ng-4.0.6 关键程序、库、头文件和文档目录均已验证。"

echo "===== 清理源码构建目录 ====="
cd /sources
rm -rf -- procps-ng-4.0.6
test ! -e procps-ng-4.0.6
echo "OK: /sources/procps-ng-4.0.6 已删除，源码包保留。"
echo "finish: $(date -Iseconds)"
echo "FINAL_RESULT: SUCCESS"
