#!/bin/bash
# Codex CLI 舊版本：保留 current 與「最新」。最新＝最新的穩定版；完全沒有穩定版才取整體最新。
# 目錄名稱可能帶 -<arch>-apple-darwin 平台後綴，去掉後還有 - 的是預發行版。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin

# codex_case <名稱> <current 形式> <預期保留（空白分隔，已排序）> <版本...>
#   current 形式：none（沒有 current）、broken（指到不存在的版本）、rel:<版本>（相對 symlink）、<版本>
codex_case() {
    local name="$1" cur="$2" expect="$3"
    shift 3
    local C="$SB/$name" H B R v
    H="$C/h"; B="$H/.codex/packages/standalone"; R="$B/releases"
    mkdir -p "$R"
    for v in "$@"; do mkdir -p "$R/$v"; done
    case "$cur" in
        none) ;;
        broken) ln -s "$R/9.9.9" "$B/current" ;;
        rel:*) ln -s "releases/${cur#rel:}" "$B/current" ;;
        *) ln -s "$R/$cur" "$B/current" ;;
    esac
    OUTFILE="$C/run.txt"
    run_personal "$H" --apply > "$OUTFILE" 2>&1
    a_eq "$?" 0 "[$name] exit 0"
    local left; left=$(find "$R" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
    a_eq "$left" "$expect" "[$name] 保留的版本"
    case "$cur" in
        none|broken) a_log "$OUTFILE" "解析不到 Codex current 指向的版本，整項略過" "[$name] log：整項略過" ;;
        *)
            local curname="${cur#rel:}" newest="${KEEP_NEWEST:-}"
            a_logend "$OUTFILE" "Codex CLI：保留 current=${curname}、最新=${newest}" "[$name] log：current=${curname}、最新=${newest}"
            ;;
    esac
}

KEEP_NEWEST=0.10.0 codex_case newest-is-current 0.10.0 "0.10.0" 0.8.0 0.9.0 0.10.0
KEEP_NEWEST=0.10.0 codex_case current-old 0.9.0 "0.10.0 0.9.0" 0.8.0 0.9.0 0.10.0
codex_case broken broken "0.10.0 0.8.0 0.9.0" 0.8.0 0.9.0 0.10.0
codex_case missing none "0.10.0 0.8.0 0.9.0" 0.8.0 0.9.0 0.10.0
KEEP_NEWEST=0.9.0 codex_case single 0.9.0 "0.9.0" 0.9.0
KEEP_NEWEST=0.10.0 codex_case relative rel:0.9.0 "0.10.0 0.9.0" 0.8.0 0.9.0 0.10.0
KEEP_NEWEST=0.144.10-aarch64-apple-darwin codex_case realnames 0.144.9-aarch64-apple-darwin \
    "0.144.10-aarch64-apple-darwin 0.144.9-aarch64-apple-darwin" \
    0.144.10-aarch64-apple-darwin 0.144.9-aarch64-apple-darwin 0.99.0-aarch64-apple-darwin 0.144.1-aarch64-apple-darwin

# 預發行版
KEEP_NEWEST=0.10.0 codex_case pre-stable-coexist 0.8.0 "0.10.0 0.8.0" 0.8.0 0.9.0 0.10.0 0.10.0-alpha.1
KEEP_NEWEST=0.10.0 codex_case pre-newer-than-stable 0.9.0 "0.10.0 0.9.0" 0.9.0 0.10.0 0.11.0-alpha.1
KEEP_NEWEST=0.10.0-alpha.2 codex_case pre-only 0.9.0-beta.1 "0.10.0-alpha.2 0.9.0-beta.1" \
    0.9.0-beta.1 0.10.0-alpha.1 0.10.0-alpha.2
KEEP_NEWEST=0.10.0 codex_case current-is-alpha 0.11.0-alpha.1 "0.10.0 0.11.0-alpha.1" 0.9.0 0.10.0 0.11.0-alpha.1
KEEP_NEWEST=0.156.0-aarch64-apple-darwin codex_case pre-with-suffix 0.155.0-aarch64-apple-darwin \
    "0.155.0-aarch64-apple-darwin 0.156.0-aarch64-apple-darwin" \
    0.155.0-aarch64-apple-darwin 0.156.0-aarch64-apple-darwin 0.157.0-alpha.1-aarch64-apple-darwin 0.154.0-aarch64-apple-darwin
KEEP_NEWEST=0.10.0-x86_64-apple-darwin codex_case x86-suffix 0.8.0-x86_64-apple-darwin \
    "0.10.0-x86_64-apple-darwin 0.8.0-x86_64-apple-darwin" \
    0.8.0-x86_64-apple-darwin 0.9.0-x86_64-apple-darwin 0.10.0-x86_64-apple-darwin 0.10.0-rc.1-x86_64-apple-darwin

finish
