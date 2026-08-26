#!/usr/bin/env bash
# LFS 13.0-systemd 源码包与补丁下载 / 校验
#
#   fetch-sources.sh lists     只刷新 wget-list-systemd 与 md5sums
#   fetch-sources.sh download  下载缺失/损坏的包（幂等，命中的文件直接跳过）
#   fetch-sources.sh verify    对照 md5sums 校验（只读）
#   fetch-sources.sh all       lists + download + verify（默认）
#   fetch-sources.sh status    只读汇总
#
# 源码固定落在宿主机 /root/lfs/sources（= 容器内 $LFS/sources），
# 与镜像解耦，镜像重建不必重新下载。约定见 docs/conventions.md。
set -euo pipefail
# md5sum/wget 的输出要被解析，必须锁定 C locale（宿主机是 zh_CN，
# 否则 "FAILED"/"OK" 会被翻译成中文，判定逻辑全部失效）
export LC_ALL=C LANG=C

LFS_ROOT="${LFS_ROOT:-/root/lfs}"
SOURCES_DIR="${SOURCES_DIR:-$LFS_ROOT/sources}"
HOST_LOGS_DIR="${HOST_LOGS_DIR:-$LFS_ROOT/logs/host}"
LOG="$HOST_LOGS_DIR/sources.log"

BOOK_BASE="https://www.linuxfromscratch.org/lfs/view/13.0-systemd"
WGET_LIST_URL="$BOOK_BASE/wget-list-systemd"
MD5SUMS_URL="$BOOK_BASE/md5sums"
# 上游站点抽风时的兜底镜像，按顺序尝试。前三个是 LFS 官方 package 镜像
# （目录布局 lfs-packages/<版本>/<文件名>，13.0 的 92 个文件已逐一探测齐全）；
# anduin 只放 LFS 自产文件（bootscripts/udev-lfs 等），故排最后。
MIRRORS=(
  "https://mirror.nju.edu.cn/lfs/lfs-packages/13.0"
  "https://ftp.osuosl.org/pub/lfs/lfs-packages/13.0"
  "https://mirrors.aliyun.com/lfs/lfs-packages/13.0"
  "https://anduin.linuxfromscratch.org/LFS"
)
# MIRROR_FIRST=1：跳过 wget-list 里的上游，直接走镜像（上游整体不可达时用）
MIRROR_FIRST="${MIRROR_FIRST:-0}"

WGET_LIST="$SOURCES_DIR/wget-list-systemd"
MD5SUMS="$SOURCES_DIR/md5sums"

MAX_ROUNDS="${MAX_ROUNDS:-3}"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }
die() { log "错误: $*"; exit 1; }

need_tools() {
  local t missing=()
  for t in wget curl md5sum awk; do command -v "$t" >/dev/null || missing+=("$t"); done
  [ ${#missing[@]} -eq 0 ] || die "缺少工具: ${missing[*]}（apt-get install wget curl coreutils gawk）"
}

prepare_dir() {
  mkdir -p "$SOURCES_DIR" "$HOST_LOGS_DIR"
  # 手册 §3.1 / §4.2：$LFS/sources 需 a+wt
  [ "$(stat -c %a "$SOURCES_DIR")" = "1777" ] || chmod a+wt "$SOURCES_DIR"
}

cmd_lists() {
  log "拉取官方清单 (13.0-systemd)"
  curl -fsSL --retry 3 --retry-delay 2 -o "$WGET_LIST.new" "$WGET_LIST_URL" \
    || die "下载 wget-list-systemd 失败"
  curl -fsSL --retry 3 --retry-delay 2 -o "$MD5SUMS.new" "$MD5SUMS_URL" \
    || die "下载 md5sums 失败"
  [ -s "$WGET_LIST.new" ] && [ -s "$MD5SUMS.new" ] || die "清单为空"
  mv -f "$WGET_LIST.new" "$WGET_LIST"
  mv -f "$MD5SUMS.new"  "$MD5SUMS"
  log "wget-list-systemd: $(grep -c . "$WGET_LIST") 条；md5sums: $(grep -c . "$MD5SUMS") 条"
  # 两份清单必须一一对应，否则后续"全部通过"的结论不可信
  diff <(awk -F/ 'NF{print $NF}' "$WGET_LIST" | sort) \
       <(awk 'NF{print $2}' "$MD5SUMS" | sort) >/dev/null \
    || die "wget-list 与 md5sums 文件名不一致"
  log "清单自洽：文件名一一对应"
}

# 逐条打印 "<文件名> OK|BAD|MISSING"。自己算 md5 而非解析 md5sum -c 的
# 文案，locale/措辞变化都影响不到判定。
check_all() {
  local want name got
  while read -r want name; do
    [ -n "${name:-}" ] || continue
    if [ ! -f "$SOURCES_DIR/$name" ]; then
      printf '%s MISSING\n' "$name"
    else
      got=$(md5sum "$SOURCES_DIR/$name" | awk '{print $1}')
      if [ "$got" = "$want" ]; then printf '%s OK\n' "$name"; else printf '%s BAD\n' "$name"; fi
    fi
  done < "$MD5SUMS"
}

bad_files() { check_all | awk '$2!="OK"{print $1}'; }

url_of() {
  awk -F/ -v n="$1" 'NF && $NF==n {print; exit}' "$WGET_LIST"
}

# 下一个候选 URL 逐个试，第一个下成功就返回 0
fetch_one() {
  local f="$1" urls=() u
  [ "$MIRROR_FIRST" = "1" ] || urls+=("$(url_of "$f")")
  for u in "${MIRRORS[@]}"; do urls+=("$u/$f"); done
  [ "$MIRROR_FIRST" = "1" ] && urls+=("$(url_of "$f")")
  for u in "${urls[@]}"; do
    [ -n "$u" ] || continue
    # -4：宿主机有 IPv6 地址但无 IPv6 出口，双栈站点会先卡满 20s 超时再回落，
    # 强制 IPv4 后 92 个上游有 86 个直接可达（实测）
    if wget -4 --continue --timeout=20 --tries=2 --no-verbose \
            --directory-prefix="$SOURCES_DIR" "$u" >>"$LOG" 2>&1; then
      return 0
    fi
    # 半截文件会让下一个候选的 --continue 从错误偏移续传，必须先清掉
    rm -f "$SOURCES_DIR/$f"
    log "    失败，换下一个源：$u"
  done
  return 1
}

cmd_download() {
  [ -f "$WGET_LIST" ] && [ -f "$MD5SUMS" ] || die "清单不存在，先执行 lists"
  local round f url todo=()
  for (( round=1; round<=MAX_ROUNDS; round++ )); do
    mapfile -t todo < <(bad_files)
    if [ ${#todo[@]} -eq 0 ]; then
      log "第 $round 轮：无待下载文件，$(grep -c . "$MD5SUMS") 个包全部命中本地缓存"
      return 0
    fi
    log "第 $round 轮：待下载/修复 ${#todo[@]} 个文件"
    for f in "${todo[@]}"; do
      url="$(url_of "$f")"
      [ -n "$url" ] || { log "  跳过 $f：wget-list 中无对应 URL"; continue; }
      # 第 2 轮起说明上一轮下到的内容 md5 不符，续传只会继续错，先删再下
      [ "$round" -gt 1 ] && rm -f "$SOURCES_DIR/$f"
      log "  下载 $f"
      fetch_one "$f" || log "  所有候选源均失败：$f"
    done
  done
  mapfile -t todo < <(bad_files)
  [ ${#todo[@]} -eq 0 ] || { log "经 $MAX_ROUNDS 轮仍未就绪(${#todo[@]}): ${todo[*]}"; return 1; }
}

cmd_verify() {
  [ -f "$MD5SUMS" ] || die "缺少 $MD5SUMS"
  local total ok bad missing res
  total=$(grep -c . "$MD5SUMS")
  res=$(check_all)
  printf '%s\n' "$res" >>"$LOG"
  ok=$(awk '$2=="OK"'      <<<"$res" | wc -l)
  bad=$(awk '$2=="BAD"'    <<<"$res" | wc -l)
  missing=$(awk '$2=="MISSING"' <<<"$res" | wc -l)
  log "MD5 校验：OK $ok / $total（损坏 $bad，缺失 $missing）"
  if [ "$bad" -ne 0 ] || [ "$missing" -ne 0 ]; then
    awk '$2!="OK"{print "  " $0}' <<<"$res" | tee -a "$LOG" >&2
    return 1
  fi
  # 再用手册原样的 md5sum -c 复核一遍，确保结论与手册口径一致
  ( cd "$SOURCES_DIR" && md5sum -c md5sums ) >>"$LOG" 2>&1 \
    || die "md5sum -c 复核失败（与逐文件结果矛盾，请检查）"
  log "md5sum -c md5sums 复核通过（手册 §3.1 口径）"
}

cmd_status() {
  echo "== sources 目录 =="
  ls -ld "$SOURCES_DIR"
  echo "== 清单 =="
  local f
  for f in "$WGET_LIST" "$MD5SUMS"; do
    if [ -f "$f" ]; then printf '  %s (%s 条)\n' "$f" "$(grep -c . "$f")"
    else printf '  (缺) %s\n' "$f"; fi
  done
  echo "== 包与补丁 =="
  printf '  文件数: %s\n' "$(find "$SOURCES_DIR" -maxdepth 1 -type f \
      ! -name 'wget-list-systemd' ! -name 'md5sums' | wc -l)"
  printf '  占用:   %s\n' "$(du -sh "$SOURCES_DIR" | cut -f1)"
  echo "== MD5 =="
  if [ -f "$MD5SUMS" ]; then
    local res
    res=$(check_all)
    printf '  OK %s / %s\n' "$(awk '$2=="OK"' <<<"$res" | wc -l)" "$(grep -c . "$MD5SUMS")"
    awk '$2!="OK"{print "  " $0}' <<<"$res"
  else
    echo "  (无 md5sums)"
  fi
}

need_tools
prepare_dir
case "${1:-all}" in
  lists)    cmd_lists ;;
  download) cmd_download ;;
  verify)   cmd_verify ;;
  status)   cmd_status ;;
  all)      cmd_lists; cmd_download; cmd_verify; cmd_status ;;
  *)        die "未知子命令: $1（lists|download|verify|status|all）" ;;
esac
