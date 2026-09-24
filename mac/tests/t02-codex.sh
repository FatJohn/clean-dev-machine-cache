#!/bin/bash
# Codex CLI 舊版本：保留 current 與「最新」。最新＝最新的穩定版；完全沒有穩定版才取整體最新。
# 目錄名稱可能帶 -<arch>-apple-darwin 平台後綴；去掉後是純數字版本才是穩定版，接 -alpha／-beta／-rc／-pre／-dev
# 開頭的是預發行版，其他（不認得的後綴，例如 -linux）一律保留並記 log。
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
    run_script "$H" --apply > "$OUTFILE" 2>&1
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
    local u
    for u in ${UNKNOWN:-}; do
        a_logend "$OUTFILE" "Codex CLI：無法辨識版本名稱，保留 ${u}" "[$name] log：無法辨識 ${u}，保留"
    done
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

# 不認得的後綴：不分類、一律保留，不當成預發行版刪掉
NONE='（沒有可辨識的版本）'
KEEP_NEWEST=0.1.0-aarch64-apple-darwin UNKNOWN=0.3.0-linux codex_case unk-newer-than-stable 0.1.0-aarch64-apple-darwin \
    "0.1.0-aarch64-apple-darwin 0.3.0-linux" 0.1.0-aarch64-apple-darwin 0.3.0-linux
KEEP_NEWEST="$NONE" UNKNOWN=0.2.0-linux codex_case unk-all 0.1.0-linux "0.1.0-linux 0.2.0-linux" 0.1.0-linux 0.2.0-linux
KEEP_NEWEST="$NONE" codex_case unk-cur-only 0.1.0-linux "0.1.0-linux" 0.1.0-linux
KEEP_NEWEST=0.2.0 codex_case unk-cur-stable-newer 0.1.0-linux "0.1.0-linux 0.2.0" 0.0.9 0.1.0-linux 0.2.0
KEEP_NEWEST=0.3.0-aarch64-apple-darwin UNKNOWN="0.4.0-linux 0.5.0-aarch64-foo 0.6.0-weird-apple-darwin-x nightly" \
    codex_case unk-mixed-with-old 0.2.0-aarch64-apple-darwin \
    "0.2.0-aarch64-apple-darwin 0.3.0-aarch64-apple-darwin 0.4.0-linux 0.5.0-aarch64-foo 0.6.0-weird-apple-darwin-x nightly" \
    0.1.0-aarch64-apple-darwin 0.2.0-aarch64-apple-darwin 0.3.0-aarch64-apple-darwin 0.4.0-linux \
    0.5.0-aarch64-foo 0.6.0-weird-apple-darwin-x nightly 0.3.0-beta.1-aarch64-apple-darwin

# 混合架構：依去掉後綴後的版本比較
KEEP_NEWEST=0.10.0-aarch64-apple-darwin codex_case mixed-arch 0.9.0-x86_64-apple-darwin \
    "0.10.0-aarch64-apple-darwin 0.9.0-x86_64-apple-darwin" \
    0.9.0-x86_64-apple-darwin 0.10.0-aarch64-apple-darwin 0.8.0-aarch64-apple-darwin
KEEP_NEWEST=0.10.0-x86_64-apple-darwin codex_case mixed-arch-pre 0.9.0-aarch64-apple-darwin \
    "0.10.0-x86_64-apple-darwin 0.9.0-aarch64-apple-darwin" \
    0.9.0-aarch64-apple-darwin 0.10.0-x86_64-apple-darwin 0.11.0-rc.1-aarch64-apple-darwin 0.8.0-x86_64-apple-darwin

# 其他預發行版組合
KEEP_NEWEST=0.12.0 codex_case alpha-cur-newer-stable 0.11.0-alpha.1 "0.11.0-alpha.1 0.12.0" 0.9.0 0.11.0-alpha.1 0.12.0
KEEP_NEWEST=0.10.0-alpha.10 codex_case all-pre 0.9.0-beta.1 "0.10.0-alpha.10 0.9.0-beta.1" \
    0.9.0-beta.1 0.10.0-alpha.2 0.10.0-alpha.9 0.10.0-alpha.10 0.10.0-alpha.1
KEEP_NEWEST=0.10.0-rc.1 codex_case all-pre-cur-newest 0.10.0-rc.1 "0.10.0-rc.1" 0.10.0-alpha.1 0.10.0-beta.2 0.10.0-rc.1
KEEP_NEWEST=0.157.0-alpha.2-aarch64-apple-darwin codex_case real-arm-allpre 0.157.0-alpha.1-aarch64-apple-darwin \
    "0.157.0-alpha.1-aarch64-apple-darwin 0.157.0-alpha.2-aarch64-apple-darwin" \
    0.157.0-alpha.1-aarch64-apple-darwin 0.157.0-alpha.2-aarch64-apple-darwin

finish
