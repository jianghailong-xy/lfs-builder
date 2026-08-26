#!/usr/bin/env bash
# 按手册小节顺序编排已有的宿主机侧 run-<节号>.sh；不改动 package 脚本。
set -euo pipefail

LFS_ROOT="${LFS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PKG_DIR="$LFS_ROOT/scripts/pkg"
PKG_LOGS_DIR="${PKG_LOGS_DIR:-$LFS_ROOT/logs/packages}"

die() { printf '错误：%s\n' "$*" >&2; exit 1; }

section_log() {
    local run="$1" section declared base candidates=() candidate
    # 每个既有 run 脚本都有唯一 LOG= 声明；读取文本而不 source/执行它。
    declared="$(sed -n 's/^LOG=//p' "$run" | head -1)"
    if [ -n "$declared" ]; then
        base="${declared##*/}"
        base="${base%\"}"; base="${base#\"}"
        printf '%s/%s\n' "$PKG_LOGS_DIR" "$base"
        return
    fi
    # 历史上的 §8.74 驱动没有 LOG= 声明；仅接受唯一的主 .log，排除检查日志。
    section="${run##*/run-}"; section="${section%.sh}"
    shopt -s nullglob
    for candidate in "$PKG_LOGS_DIR/$section-"*.log; do
        case "$candidate" in *.check.log) ;; *) candidates+=("$candidate") ;; esac
    done
    shopt -u nullglob
    [ "${#candidates[@]}" -eq 1 ] || return 1
    printf '%s\n' "${candidates[0]}"
}

log_succeeded() {
    local log="$1"
    # run 脚本统一在日志末尾记录成功标记；只接受末尾窗口中的标记。
    # 某些多阶段 runner（如 §7.13）会在中途记录子步骤“退出码：0”，
    # 之后的备份步骤仍可能失败；扫描整份日志会把这种失败误判为可跳过。
    tail -n 40 "$log" | awk '/退出码：[0-9]+$/ || /退出码: ?[0-9]+$/ || /^HOST_EXIT_CODE: [0-9]+$/ || /^FINAL_RESULT: / || /^##### 最终结论：/ || /^##### Complete:/ || /^===== §[0-9.]+ 全部完成/ { line=$0 }
         END { exit !(line ~ /退出码：0$/ || line ~ /退出码: ?0$/ || line ~ /HOST_EXIT_CODE: 0$/ || line ~ /FINAL_RESULT: SUCCESS$/ || line ~ /最终结论：SUCCESS/ || line ~ /^##### Complete:/ || line ~ /全部完成/) }'
}

run_chapter() {
    local chapter="$1" scripts=() run section log rc done_count=0 skip_count=0
    shopt -s nullglob
    scripts=("$PKG_DIR/run-$chapter."*.sh)
    shopt -u nullglob
    [ "${#scripts[@]}" -gt 0 ] || die "第 $chapter 章没有 run-*.sh：$PKG_DIR"
    mapfile -t scripts < <(printf '%s\n' "${scripts[@]}" | sort -V)

    printf '\n===== LFS 第 %s 章（%s 个可执行小节）=====\n' "$chapter" "${#scripts[@]}"
    for run in "${scripts[@]}"; do
        section="${run##*/run-}"
        section="${section%.sh}"
        log=""
        if log="$(section_log "$run")" && [ -f "$log" ] && log_succeeded "$log"; then
            printf '[SKIP] §%s 已成功：%s\n' "$section" "$log"
            skip_count=$((skip_count + 1))
            continue
        fi

        if [ "${CHECK_ONLY:-0}" = 1 ]; then
            printf '[NEED] §%s 未找到带成功退出标记的日志：%s\n' "$section" "${log:-$PKG_LOGS_DIR/$section-*.log}"
            done_count=$((done_count + 1))
            continue
        fi

        printf '[RUN ] §%s：%s\n' "$section" "$run"
        set +e
        bash "$run"
        rc=$?
        set -e
        log="$(section_log "$run" 2>/dev/null || true)"
        if [ "$rc" -ne 0 ]; then
            printf '\n[FAIL] 停在 §%s（退出码 %s）\n' "$section" "$rc" >&2
            printf '       日志：%s\n' "${log:-$PKG_LOGS_DIR/$section-*.log}" >&2
            printf '       修复后运行 make build-chapter%s（或 make build-all）即可从此处续跑。\n' "$chapter" >&2
            exit "$rc"
        fi
        [ -n "$log" ] && log_succeeded "$log" \
            || die "§$section 返回成功，但日志没有记录成功退出码：${log:-$PKG_LOGS_DIR/$section-*.log}"
        done_count=$((done_count + 1))
    done
    printf '[ OK ] 第 %s 章完成：新执行 %s，跳过 %s。\n' "$chapter" "$done_count" "$skip_count"
    if [ "${CHECK_ONLY:-0}" = 1 ] && [ "$done_count" -ne 0 ]; then return 2; fi
}

[ "$#" -gt 0 ] || die "用法：$0 <5|6|7|8|10> [...]"
for chapter in "$@"; do
    case "$chapter" in 5|6|7|8|10) run_chapter "$chapter" ;; *) die "不支持的章节：$chapter" ;; esac
done
