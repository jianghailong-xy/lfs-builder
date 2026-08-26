#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=POSIX

phase=${1:-all}
cd /sources

if [ "$phase" = retest-format-table ]; then
  cd /sources/systemd-259.1/build
  echo "===== 针对 test-format-table 的 locale 诊断复测 ====="
  echo "INFO: 全套测试继承 LC_ALL=POSIX，使期望的 Unicode 省略号降级为 ASCII 三点。"
  echo "INFO: 按测试自身要求改用 C.UTF-8，单独复测该用例。"
  LC_ALL=C.UTF-8 meson test test-format-table --print-errorlogs
  echo "RETEST_RESULT: PASS (test-format-table under LC_ALL=C.UTF-8)"
  exit 0
fi

if [ "$phase" = buildtest ] || [ "$phase" = all ]; then
  echo "===== LFS 13.0-systemd §8.78 Systemd-259.1 ====="
  echo "start: $(date -Iseconds)"
  echo "===== 前置产物与源码校验 ====="
  python3 - <<'PY'
import importlib.metadata
import jinja2
assert importlib.metadata.version("Jinja2") == "3.1.6"
assert jinja2.Template("{{ value }}").render(value="ok") == "ok"
print("OK: Jinja2-3.1.6 可导入并可渲染模板。")
PY
  echo '623f73826e7702ac08c57febb9d20431  systemd-259.1.tar.gz' | md5sum -c -
  echo 'de40a27b137ef707777811818995363c  systemd-man-pages-259.1.tar.xz' | md5sum -c -
  test ! -e systemd-259.1 || { echo "错误：/sources/systemd-259.1 已存在；保留现场并停止。" >&2; exit 1; }

  echo "===== 解包 ====="
  tar -xf systemd-259.1.tar.gz
  cd systemd-259.1

  echo "===== 补丁 ====="
  sed -e 's/GROUP="render"/GROUP="video"/' \
      -e 's/GROUP="sgx", //'               \
      -i rules.d/50-udev-default.rules.in

  echo "===== 配置 ====="
  mkdir -p build
  cd build
  meson setup ..                \
        --prefix=/usr           \
        --buildtype=release     \
        -D default-dnssec=no    \
        -D firstboot=false      \
        -D install-tests=false  \
        -D ldconfig=false       \
        -D sysusers=false       \
        -D rpmmacrosdir=no      \
        -D homed=disabled       \
        -D man=disabled         \
        -D mode=release         \
        -D pamconfdir=no        \
        -D dev-kvm-mode=0660    \
        -D nobody-group=nogroup \
        -D sysupdate=disabled   \
        -D ukify=disabled       \
        -D docdir=/usr/share/doc/systemd-259.1

  echo "===== 编译 ====="
  ninja

  echo "===== 测试 ====="
  echo 'NAME="Linux From Scratch"' > /etc/os-release
  set +e
  unshare -m ninja test
  test_rc=$?
  set -e
  echo "TEST_COMMAND_EXIT_CODE: $test_rc"
  echo "INFO: 手册允许 systemd:core / test-namespace 在 LFS chroot 中失败；其他依赖内核配置的测试也可能失败。"
  echo "BUILD_TEST_PHASE_COMPLETE"
  exit "$test_rc"
fi

if [ "$phase" = install ]; then
  test -d /sources/systemd-259.1/build
  cd /sources/systemd-259.1/build
  echo "===== 安装 ====="
  ninja install

  echo "===== 安装预生成手册页 ====="
  tar -xf ../../systemd-man-pages-259.1.tar.xz \
      --no-same-owner --strip-components=1     \
      -C /usr/share/man

  echo "===== 初始化 machine-id 与 preset ====="
  systemd-machine-id-setup
  systemctl preset-all

  echo "===== 安装结果验证 ====="
  test -x /usr/bin/systemctl
  test -x /usr/bin/systemd-machine-id-setup
  test -x /usr/bin/udevadm
  test -e /usr/lib/libsystemd.so
  test -e /usr/lib/libudev.so
  test -s /etc/machine-id
  test -f /usr/share/man/man1/systemctl.1
  systemctl --version
  udevadm --version
  echo "machine-id bytes: $(wc -c < /etc/machine-id)"
  echo "OK: Systemd-259.1 关键程序、库、手册页和 machine-id 均已验证。"

  echo "===== 清理源码构建目录 ====="
  cd /sources
  rm -rf -- systemd-259.1
  test ! -e systemd-259.1
  echo "OK: /sources/systemd-259.1 已删除，两个源码包保留。"
  echo "finish: $(date -Iseconds)"
  echo "FINAL_RESULT: SUCCESS"
  exit 0
fi

echo "用法：$0 buildtest|install" >&2
exit 2
