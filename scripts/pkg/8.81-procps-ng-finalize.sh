#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

echo "===== §8.81 安装结果验证（修正库 SONAME 后续执行） ====="
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
