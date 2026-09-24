#!/bin/bash

# macOS 開發機暫存清理 Script
#
# 開發機上隨時可能有人正在用 Xcode／Chrome／Android Studio，所以每個項目都先確認擁有者 app 沒在跑。
#
# 預設只報告（dry-run），加 --apply 才真的刪。分三級：
#   A 級（預設）            沒有副作用，或只是重建成本
#   B 級（--include-caches） 套件／瀏覽器快取，清了要重新下載
#   C 級（--projects DIR）   專案內久未動過的 build/ 與 node_modules
#
# 忙碌判斷：每個項目宣告自己的「擁有者 app」，該 app 還在跑就逐項跳過，不等待。
#
# 刻意不清（手動步驟見 docs/disk-space-knowledge.md）：垃圾桶、Android system-images／AVD／NDK、
# iOS simulator runtime、Claude desktop VM、Chrome 裝置端 AI 模型、Docker、
# Time Machine 本機快照、Xcode Archives。
#
# Date: 2026-09-24

set -uo pipefail

# ============================================================
# 設定（每一項都可用同名環境變數覆寫）
# ============================================================
LOG_DIR="${LOG_DIR:-${HOME:-}/logs/clean-dev-mac}"
KEEP_LOGS_DAYS="${KEEP_LOGS_DAYS:-30}"

# 不走 HOME 的路徑：沙盒測試時一定要覆寫，否則會動到真實路徑
if [ -z "${CODE_SIGN_CLONE_BASE:-}" ]; then
    _user_temp="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)"
    if [ -n "$_user_temp" ]; then
        CODE_SIGN_CLONE_BASE="$(dirname "$_user_temp")/X"
    else
        CODE_SIGN_CLONE_BASE=""
    fi
fi
CLAUDE_TMP_DIR="${CLAUDE_TMP_DIR:-/private/tmp/claude-$(id -u)}"

# true = 不執行任何外部清理指令（simctl、brew、npm、pnpm、go、dotnet、dart pub cache gc），只記錄；
#        也不透過 PATH／預設安裝位置找 Flutter SDK，只認明確設定的 FLUTTER_ROOT
DISABLE_TOOL_COMMANDS="${DISABLE_TOOL_COMMANDS:-false}"

DRY_RUN=true
INCLUDE_CACHES=false
PROJECT_DIRS=""
STALE_DAYS=30

# ============================================================
# 參數
# ============================================================
usage() {
    cat <<'EOF'
用法: clean-dev-mac.sh [選項]

預設只報告會清什麼、可釋放多少（dry-run），不刪任何東西。

  --apply              真的刪除
  --include-caches     加跑 B 級：套件管理器與瀏覽器快取（清了會重新下載）
  --projects DIR       加跑 C 級：在 DIR 底下找久未動過的 build/ 與 node_modules
                       可重複指定，或用冒號分隔多個目錄
                       拒絕 ~、/、~ 的上層目錄與 ~/Library 底下；隱藏目錄一律不進去
  --stale-days N       C 級的門檻天數（預設 30，最小 1）；「超過 N 天」＝ mtime 早於
                       執行當下往前 N×24 小時
  -h, --help           顯示這段說明

環境變數：
  LOG_DIR                log 目錄（預設 ~/logs/clean-dev-mac）
  KEEP_LOGS_DAYS         log 保留天數（預設 30，最小 1）；只在 --apply 時刪舊 log
  CODE_SIGN_CLONE_BASE   Chrome／Edge code_sign_clone 的上層目錄
                         （預設 $(dirname $(getconf DARWIN_USER_TEMP_DIR))/X）
  CLAUDE_TMP_DIR         Claude Code 暫存目錄（預設 /private/tmp/claude-<UID>）
  DISABLE_TOOL_COMMANDS  設為 true 時不執行 simctl／brew／npm／dart pub cache gc 等外部清理指令
                         （pub cache 改用路徑清理），且找 Flutter SDK 時只認 FLUTTER_ROOT
                         （不看 PATH 與預設安裝位置）
  FLUTTER_ROOT           Flutter SDK 根目錄；B 級會清它的 bin/cache。沒設時從 PATH 上的
                         flutter 或 ~/development/flutter 等預設位置找。不論哪種來源，
                         都要有 bin/flutter 與 bin/internal、且不是 / 或 ~ 才會清
  PUB_CACHE              pub cache 位置（預設 ~/.pub-cache）；要有 hosted 或
                         global_packages、且不是 / 、~ 或 ~ 的上層目錄才會清

用假的 HOME 做沙盒測試時，CODE_SIGN_CLONE_BASE 與 CLAUDE_TMP_DIR 不走 HOME，
一定要一起覆寫，並設 DISABLE_TOOL_COMMANDS=true，否則會動到真實機器。
FLUTTER_ROOT、PUB_CACHE 也不走 HOME：沙盒測試時要 unset 或指到沙盒裡。
EOF
}

# is_positive_int <值>  1 以上、不帶前導 0 的十進位整數回 0
is_positive_int() {
    case "$1" in
        ''|*[!0-9]*|0*) return 1 ;;
    esac
    return 0
}

add_project_dirs() {
    if [ -z "$PROJECT_DIRS" ]; then
        PROJECT_DIRS="$1"
    else
        PROJECT_DIRS="${PROJECT_DIRS}:$1"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)          DRY_RUN=false ;;
        --include-caches) INCLUDE_CACHES=true ;;
        --projects)
            [ $# -ge 2 ] || { echo "--projects 需要一個目錄參數" >&2; usage; exit 2; }
            add_project_dirs "$2"; shift ;;
        --stale-days)
            [ $# -ge 2 ] || { echo "--stale-days 需要一個數字參數" >&2; usage; exit 2; }
            is_positive_int "$2" || { echo "--stale-days 必須是正整數（最小 1）: $2" >&2; exit 2; }
            STALE_DAYS="$2"; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "未知參數: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

is_positive_int "$KEEP_LOGS_DAYS" || { echo "KEEP_LOGS_DAYS 必須是正整數（最小 1）: ${KEEP_LOGS_DAYS}" >&2; exit 2; }

# ============================================================
# 路徑正規化與 HOME 防呆（在建立 log 之前：HOME 不對就什麼都不做）
# ============================================================

# norm_text <路徑>  純文字正規化：// 壓成 /、去掉 /./ 與結尾的 /. 和 /；不碰檔案系統
norm_text() {
    local p="$1" prev="" sl=/
    [ -n "$p" ] || return 0
    while [ "$p" != "$prev" ]; do
        prev="$p"
        p="${p//\/\//$sl}"
        p="${p//\/.\//$sl}"
        case "$p" in */.) p="${p%/.}" ;; esac
        case "$p" in ?*/) p="${p%/}" ;; esac
    done
    [ -n "$p" ] || p=/
    printf '%s\n' "$p"
}

# norm_phys <路徑>  目錄存在時印出解析 symlink 後的實體路徑；不存在就不印
norm_phys() {
    [ -n "$1" ] && [ -d "$1" ] || return 0
    (cd "$1" 2>/dev/null && pwd -P)
}

case "${HOME:-}" in
    ''|/) echo "HOME 是空的或是 /（'${HOME:-}'），拒絕執行" >&2; exit 2 ;;
esac
if [ ! -d "$HOME" ]; then
    echo "HOME 不是存在的目錄（'${HOME}'），拒絕執行" >&2; exit 2
fi
HOME_T=$(norm_text "$HOME")
HOME_P=$(norm_phys "$HOME")
if [ "$HOME_T" = / ] || [ -z "$HOME_P" ] || [ "$HOME_P" = / ]; then
    echo "HOME 正規化後是 / 或無法解析（'${HOME}'），拒絕執行" >&2; exit 2
fi

# is_home_or_above <路徑>  文字或實體正規化後是 /、HOME 本身、或 HOME 的上層目錄時回 0
is_home_or_above() {
    local form h
    for form in "$(norm_text "$1")" "$(norm_phys "$1")"; do
        [ -n "$form" ] || continue
        [ "$form" = / ] && return 0
        for h in "$HOME_T" "$HOME_P"; do
            [ "$form" = "$h" ] && return 0
            case "${h}/" in "${form}/"*) return 0 ;; esac
        done
    done
    return 1
}

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/clean-dev-mac-$(date +%Y%m%d-%H%M%S).log"

# ============================================================
# 輸出
# ============================================================
# 顏色只在互動式終端啟用，log 檔裡不會混入 ANSI escape code
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; DIM=''; NC=''
fi

HAD_ERROR=false

log() {
    local level="$1" color="$2" message="$3"
    local stamp
    stamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    printf '%b\n' "${stamp} ${color}[${level}]${NC} ${message}"
    printf '%s\n'  "${stamp} [${level}] ${message}" >> "${LOG_FILE}"
}

log_info() { log INFO "${GREEN}"  "$1"; }
log_warn() { log WARN "${YELLOW}" "$1"; }
log_skip() { log SKIP "${DIM}"    "$1"; }
log_error() { log ERROR "${RED}"  "$1"; HAD_ERROR=true; }
log_blank() { printf '\n'; printf '\n' >> "${LOG_FILE}"; }

# ============================================================
# 工具函式
# ============================================================

# 目錄大小（KB）。一定只印一個整數：du 遇到讀不到的子目錄會非 0 結束，但仍會印出部分大小，
#   舊寫法的 `|| echo 0` 會因此多印一行，讓呼叫端的算術運算出錯、整個函式中斷。
dir_kb() {
    [ -e "$1" ] || { echo 0; return; }
    { du -sk "$1" 2>/dev/null || true; } | awk 'NR == 1 {s = $1} END {print s + 0}'
}

# KB -> 人類可讀
human() {
    awk -v kb="${1:-0}" 'BEGIN {
        if (kb >= 1048576)   printf "%.2f GB", kb/1048576;
        else if (kb >= 1024) printf "%.1f MB", kb/1024;
        else                 printf "%d KB", kb;
    }'
}

free_space() {
    df -h / 2>/dev/null | awk 'NR==2 {print $4 " 可用（共 " $2 "）"}'
}

TOTAL_FREED_KB=0

# 防呆：拒絕刪除空字串、根目錄、HOME 本身與 HOME 的上層目錄。
#   先正規化再比對（//、/.、結尾 /），目錄存在時也比對 symlink 解析後的實體路徑。
unsafe_path() {
    [ -n "$1" ] || return 0
    is_home_or_above "$1"
}

# days_to_min <天數>  find -mmin 用的分鐘數。不用 -mtime：實測 BSD find 的 -mtime +N
#   要超過 N+1 天才命中（-mtime +1 要超過 48 小時才命中），與字面差一天。
#   -mmin +M 則是「超過 M 分鐘」，所以「超過 N 天」＝ -mmin +(N×1440)。
days_to_min() {
    echo $(( $1 * 1440 ))
}

# clean <purge|empty> <path> <描述>
#   purge — 連目錄本身一起刪
#   empty — 保留目錄本身，只清內容
clean() {
    local mode="$1" path="$2" desc="$3"

    if unsafe_path "$path"; then
        log_error "拒絕清除危險路徑：${desc} — '${path}'"
        return 0
    fi

    if [ -L "$path" ]; then
        log_skip "是 symlink，為安全起見略過：${desc} — ${path}"
        return 0
    fi

    if [ ! -e "$path" ]; then
        log_skip "不存在，略過：${desc}"
        return 0
    fi

    local kb; kb=$(dir_kb "$path")

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] 會清除 ${desc} — $(human "$kb") — ${path}"
        TOTAL_FREED_KB=$((TOTAL_FREED_KB + kb))
        return 0
    fi

    local ok=true
    if [ "$mode" = "empty" ]; then
        find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || ok=false
    else
        rm -rf "$path" 2>/dev/null || ok=false
        [ -e "$path" ] && ok=false   # read-back：確認真的不見了
    fi

    if [ "$ok" = true ]; then
        log_info "✓ 已清除 ${desc} — 釋放 $(human "$kb") — ${path}"
        TOTAL_FREED_KB=$((TOTAL_FREED_KB + kb))
    else
        log_error "✗ 清除失敗（權限或檔案被佔用）：${desc} — ${path}"
    fi
}

# clean_older <path> <天數> <描述>  只刪第一層中超過 N 天沒動過的項目
clean_older() {
    local path="$1" days="$2" desc="$3"

    if unsafe_path "$path"; then
        log_error "拒絕清除危險路徑：${desc} — '${path}'"
        return 0
    fi

    if [ -L "$path" ]; then
        log_skip "是 symlink，為安全起見略過：${desc} — ${path}"
        return 0
    fi

    if [ ! -d "$path" ]; then
        log_skip "不存在，略過：${desc}"
        return 0
    fi

    local before; before=$(dir_kb "$path")
    local mins; mins=$(days_to_min "$days")

    if [ "$DRY_RUN" = true ]; then
        local n kb
        n=$(find "$path" -mindepth 1 -maxdepth 1 -mmin "+${mins}" 2>/dev/null | wc -l | tr -d ' ')
        kb=$(find "$path" -mindepth 1 -maxdepth 1 -mmin "+${mins}" -exec du -sk {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
        log_info "[DRY-RUN] 會清除 ${desc} 中 ${n} 個超過 ${days} 天的項目 — $(human "$kb") — ${path}"
        TOTAL_FREED_KB=$((TOTAL_FREED_KB + kb))
        return 0
    fi

    # 失敗判斷兩道：find 的 exit code（任何一次 rm 失敗都會讓它非 0），以及刪完再找一次
    # 符合條件卻還在的項目（只刪掉一部分的目錄 mtime 會被更新，所以不能只靠第二道）。
    local ok=true left
    find "$path" -mindepth 1 -maxdepth 1 -mmin "+${mins}" -exec rm -rf {} + 2>>"${LOG_FILE}" || ok=false
    left=$(find "$path" -mindepth 1 -maxdepth 1 -mmin "+${mins}" 2>/dev/null | wc -l | tr -d ' ')
    [ "$left" = 0 ] || ok=false

    local after; after=$(dir_kb "$path")
    local freed=$((before - after))
    [ "$freed" -lt 0 ] && freed=0
    TOTAL_FREED_KB=$((TOTAL_FREED_KB + freed))
    if [ "$ok" = true ]; then
        log_info "✓ 已清除 ${desc}（保留 ${days} 天內）— 釋放 $(human "$freed")"
    else
        log_error "✗ 清除失敗（權限或檔案被佔用）：${desc} — ${path}（仍有 ${left} 個超過 ${days} 天的項目；已釋放 $(human "$freed")，錯誤見 ${LOG_FILE}）"
    fi
}

# ============================================================
# 擁有者 app 判斷：在跑就逐項跳過，不等待
# ============================================================

# owner_running <key>  在跑回 0
owner_running() {
    case "$1" in
        xcode)          pgrep -x Xcode >/dev/null 2>&1 ;;
        simulator)      pgrep -x Simulator >/dev/null 2>&1 ;;
        chrome)         pgrep -x "Google Chrome" >/dev/null 2>&1 ;;
        edge)           pgrep -x "Microsoft Edge" >/dev/null 2>&1 ;;
        cursor)         pgrep -x Cursor >/dev/null 2>&1 ;;
        android_studio) pgrep -f 'Android Studio.app' >/dev/null 2>&1 ;;
        gradle_daemon)  pgrep -f GradleDaemon >/dev/null 2>&1 ;;
        emulator)       pgrep -f qemu-system >/dev/null 2>&1 ;;
        flutter_tool)   pgrep -f flutter_tools >/dev/null 2>&1 ;;
        dart_analyzer)  pgrep -f 'dart.*(analysis_server|language-server)' >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

owner_label() {
    case "$1" in
        xcode)          echo "Xcode" ;;
        simulator)      echo "Simulator" ;;
        chrome)         echo "Google Chrome" ;;
        edge)           echo "Microsoft Edge" ;;
        cursor)         echo "Cursor" ;;
        android_studio) echo "Android Studio" ;;
        gradle_daemon)  echo "Gradle daemon" ;;
        emulator)       echo "Android emulator（qemu-system）" ;;
        flutter_tool)   echo "flutter 指令（flutter_tools）" ;;
        dart_analyzer)  echo "Dart analysis server" ;;
        *)              echo "$1" ;;
    esac
}

# busy_owner <key...>  印出第一個在跑的擁有者名稱；都沒在跑就回 1
busy_owner() {
    local key
    for key in "$@"; do
        if owner_running "$key"; then
            owner_label "$key"
            return 0
        fi
    done
    return 1
}

# skip_if_busy <path> <描述> <owner...>  有擁有者在跑就記錄並回 0（呼叫端應跳過）
skip_if_busy() {
    local path="$1" desc="$2"
    shift 2
    local who
    if who=$(busy_owner "$@"); then
        local size=""
        [ -n "$path" ] && [ -e "$path" ] && size=" — $(human "$(dir_kb "$path")")"
        if [ "$DRY_RUN" = true ]; then
            log_skip "[DRY-RUN] 會跳過 ${desc}：${who} 正在執行${size}"
        else
            log_skip "跳過 ${desc}：${who} 正在執行${size}"
        fi
        return 0
    fi
    return 1
}

have() { command -v "$1" >/dev/null 2>&1; }

tools_disabled() {
    if [ "$DISABLE_TOOL_COMMANDS" = true ]; then
        log_skip "略過（DISABLE_TOOL_COMMANDS）：不執行 $1"
        return 0
    fi
    return 1
}

# run_tool <描述> <量測路徑> <指令...>
#   用官方指令清理。dry-run 只量目錄、列出會執行的指令；apply 時比對前後大小。
run_tool() {
    local desc="$1" measure="$2"
    shift 2
    local cmd_text="$*"

    if tools_disabled "$cmd_text"; then
        return 0
    fi

    local before=0
    [ -n "$measure" ] && before=$(dir_kb "$measure")

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] 會執行 \`${cmd_text}\` 清除 ${desc} — 目前 $(human "$before") — ${measure:-（無量測路徑）}"
        TOTAL_FREED_KB=$((TOTAL_FREED_KB + before))
        return 0
    fi

    if "$@" >> "${LOG_FILE}" 2>&1; then
        local after=0 freed
        [ -n "$measure" ] && after=$(dir_kb "$measure")
        freed=$((before - after))
        [ "$freed" -lt 0 ] && freed=0
        TOTAL_FREED_KB=$((TOTAL_FREED_KB + freed))
        log_info "✓ 已執行 \`${cmd_text}\`（${desc}）— 釋放 $(human "$freed")"
    else
        log_error "✗ 指令失敗：\`${cmd_text}\`（${desc}），輸出見 ${LOG_FILE}"
    fi
}

# ============================================================
# A 級：預設就跑
# ============================================================

tier_a_code_sign_clone() {
    if [ -z "$CODE_SIGN_CLONE_BASE" ]; then
        log_skip "取不到 DARWIN_USER_TEMP_DIR，略過 code_sign_clone"
        return 0
    fi
    local chrome="${CODE_SIGN_CLONE_BASE}/com.google.Chrome.code_sign_clone"
    local edge="${CODE_SIGN_CLONE_BASE}/com.microsoft.edgemac.code_sign_clone"

    skip_if_busy "$chrome" "Chrome code_sign_clone" chrome \
        || clean empty "$chrome" "Chrome code_sign_clone（更新留下的簽章副本）"
    skip_if_busy "$edge" "Edge code_sign_clone" edge \
        || clean empty "$edge" "Edge code_sign_clone（更新留下的簽章副本）"
}

tier_a_xcode() {
    local dd="${HOME}/Library/Developer/Xcode/DerivedData"
    skip_if_busy "$dd" "Xcode DerivedData" xcode \
        || clean empty "$dd" "Xcode DerivedData"

    local products="${HOME}/Library/Developer/Xcode/Products"
    skip_if_busy "$products" "Xcode Products" xcode \
        || clean purge "$products" "Xcode Products"

    local xcache="${HOME}/Library/Caches/com.apple.dt.Xcode"
    skip_if_busy "$xcache" "Xcode 應用程式快取" xcode \
        || clean purge "$xcache" "Xcode 應用程式快取"

    if have xcrun; then
        if ! skip_if_busy "" "simctl delete unavailable" xcode simulator; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY-RUN] 會執行 \`xcrun simctl delete unavailable\`（刪除已無對應 runtime 的模擬器）"
            elif ! tools_disabled "xcrun simctl delete unavailable"; then
                if xcrun simctl delete unavailable >> "${LOG_FILE}" 2>&1; then
                    log_info "✓ 已執行 \`xcrun simctl delete unavailable\`"
                else
                    log_error "✗ 指令失敗：\`xcrun simctl delete unavailable\`"
                fi
            fi
        fi
    else
        log_skip "沒有 xcrun，略過 simctl delete unavailable"
    fi

    local simlogs="${HOME}/Library/Logs/CoreSimulator"
    skip_if_busy "$simlogs" "CoreSimulator logs" xcode simulator \
        || clean empty "$simlogs" "CoreSimulator logs"
}

# codex_core <目錄名>  去掉平台後綴（-aarch64-apple-darwin、-x86_64-apple-darwin 等 -<arch>-apple-darwin）
codex_core() {
    printf '%s\n' "$1" | sed -E 's/-[A-Za-z0-9_]+-apple-darwin$//'
}

# codex_kind <目錄名>  印出 stable、pre 或 unknown
#   名稱＝版本＋可有可無的 -<arch>-apple-darwin 平台後綴。去掉後綴後，剩下的字串整串比對（不是只看開頭）：
#     ^[0-9]+(\.[0-9]+)*$                                      → stable（0.10.0）
#     ^[0-9]+(\.[0-9]+)*-(alpha|beta|rc|pre|dev)(\.?[0-9]+)*$  → pre（0.10.0-alpha.1、0.3.0-rc1、0.3.0-beta）
#     其他（0.3.0-linux、0.3.0-devbuild、0.3.0-alpha.1-linux 等） → unknown，一律保留，不參與「最新」的判斷
codex_kind() {
    local core; core=$(codex_core "$1")
    if printf '%s\n' "$core" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
        echo stable
    elif printf '%s\n' "$core" | grep -Eq '^[0-9]+(\.[0-9]+)*-(alpha|beta|rc|pre|dev)(\.?[0-9]+)*$'; then
        echo pre
    else
        echo unknown
    fi
}

# codex_newest <releases 目錄>  印出要當成「最新」保留的版本目錄名；沒有可辨識的版本就不印
#   有穩定版時取最新的穩定版；完全沒有穩定版才取最新的預發行版。依去掉平台後綴後的版本排序（sort -V），
#   不同架構的名稱也能互相比較。不把穩定版和預發行版混在一起 sort -V：它會把 0.10.0-alpha.1 排在
#   0.10.0 後面，結果穩定版被刪、alpha 被當成最新保留。
codex_newest() {
    local stable="" pre="" name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$(codex_kind "$name")" in
            stable) stable="${stable}$(codex_core "$name")	${name}
" ;;
            pre)    pre="${pre}$(codex_core "$name")	${name}
" ;;
        esac
    done <<EOF
$(find "$1" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
EOF
    local pool="$stable"
    [ -n "$pool" ] || pool="$pre"
    [ -n "$pool" ] || return 0
    printf '%s' "$pool" | sort -V | tail -n 1 | cut -f 2
}

tier_a_codex_releases() {
    local base="${HOME}/.codex/packages/standalone"
    local releases="${base}/releases"

    if [ ! -d "$releases" ]; then
        log_skip "不存在，略過：Codex CLI 舊版本"
        return 0
    fi

    local target current
    target=$(readlink "${base}/current" 2>/dev/null)
    current=$(basename "${target:-}")
    if [ -z "$target" ] || [ ! -d "${releases}/${current}" ]; then
        log_skip "解析不到 Codex current 指向的版本，整項略過（不刪任何版本）"
        return 0
    fi

    local newest
    newest=$(codex_newest "$releases")
    log_info "Codex CLI：保留 current=${current}、最新=${newest:-（沒有可辨識的版本）}"

    # 用 heredoc 而不是 pipe：pipe 會讓 while 跑在 subshell，TOTAL_FREED_KB 會遺失
    local name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        [ "$name" = "$current" ] && continue
        [ "$name" = "$newest" ] && continue
        if [ "$(codex_kind "$name")" = unknown ]; then
            log_info "Codex CLI：無法辨識版本名稱，保留 ${name}"
            continue
        fi
        clean purge "${releases}/${name}" "Codex CLI 舊版本 ${name}"
    done <<EOF
$(find "$releases" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -V)
EOF
}

tier_a_claude_tmp() {
    # 第一層是專案目錄、第二層才是各 session；對每個專案只清超過 7 天的 session，
    # 避免整個專案目錄被刪掉時連帶清掉還在跑的 session。
    if [ ! -d "$CLAUDE_TMP_DIR" ]; then
        log_skip "不存在，略過：Claude Code 暫存（${CLAUDE_TMP_DIR}）"
        return 0
    fi
    local project
    while IFS= read -r project; do
        [ -n "$project" ] || continue
        clean_older "$project" 7 "Claude Code 暫存 $(basename "$project")"
    done <<EOF
$(find "$CLAUDE_TMP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
EOF
}

tier_a_homebrew() {
    if ! have brew; then
        log_skip "沒有 brew，略過 Homebrew cleanup"
        return 0
    fi
    if tools_disabled "brew cleanup --prune=all"; then
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        local summary
        summary=$(brew cleanup -n --prune=all 2>/dev/null | grep -i 'would free' | tail -n 1)
        log_info "[DRY-RUN] 會執行 \`brew cleanup --prune=all\` — ${summary:-沒有可清的項目}（未計入總量）"
        return 0
    fi
    local out
    if out=$(brew cleanup --prune=all 2>&1); then
        printf '%s\n' "$out" >> "${LOG_FILE}"
        log_info "✓ 已執行 \`brew cleanup --prune=all\` — $(printf '%s\n' "$out" | grep -i 'freed' | tail -n 1)"
    else
        printf '%s\n' "$out" >> "${LOG_FILE}"
        log_error "✗ 指令失敗：\`brew cleanup --prune=all\`"
    fi
}

tier_a_codex_runtimes() {
    local dir="${HOME}/.cache/codex-runtimes"
    if [ ! -d "$dir" ]; then
        log_skip "不存在，略過：codex-runtimes 安裝暫存"
        return 0
    fi
    local found=false p
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        found=true
        clean purge "$p" "Codex runtime 安裝暫存 $(basename "$p")"
    done <<EOF
$(find "$dir" -mindepth 1 -maxdepth 1 -name 'codex-runtime-install-*' -mmin "+$(days_to_min 1)" 2>/dev/null)
EOF
    [ "$found" = true ] || log_skip "沒有超過 1 天的 codex-runtime-install-* 暫存"
}

run_tier_a() {
    log_info "=== A 級：沒有副作用或只是重建成本 ==="
    tier_a_code_sign_clone
    tier_a_xcode
    tier_a_codex_releases
    tier_a_claude_tmp
    tier_a_homebrew
    tier_a_codex_runtimes
}

# ============================================================
# B 級：--include-caches，會重新下載
# ============================================================

tier_b_packages() {
    if have npm; then
        run_tool "npm cache" "${HOME}/.npm/_cacache" npm cache clean --force
    else
        log_skip "沒有 npm，略過 npm cache"
    fi

    # pnpm／go 的量測路徑要呼叫工具本身才拿得到，所以 DISABLE 判斷要放在取路徑之前
    if ! have pnpm; then
        log_skip "沒有 pnpm，略過 pnpm store"
    elif ! tools_disabled "pnpm store path、pnpm store prune"; then
        local store
        store=$(pnpm store path 2>/dev/null)
        run_tool "pnpm store（只刪沒被任何專案引用的套件）" "$store" pnpm store prune
    fi

    clean purge "${HOME}/.npm/_logs" "npm log"

    # Yarn／Bun 直接清路徑，不用 `yarn cache clean`：yarn 指令實際跑 v1 還是 Berry 取決於
    # corepack 與所在目錄，兩版清的位置不同；直接清路徑則兩版都涵蓋。
    # 每個路徑只清這一次，不再另跑官方指令。
    clean purge "${HOME}/Library/Caches/Yarn"  "Yarn v1 快取"
    clean purge "${HOME}/.yarn/berry/cache"    "Yarn Berry 快取"
    clean purge "${HOME}/.bun/install/cache"   "Bun 快取"

    if ! have go; then
        log_skip "沒有 go，略過 Go cache"
    elif ! tools_disabled "go env、go clean -cache、go clean -modcache"; then
        run_tool "Go build cache" "$(go env GOCACHE 2>/dev/null)" go clean -cache
        run_tool "Go module cache" "$(go env GOMODCACHE 2>/dev/null)" go clean -modcache
    fi

    if have dotnet; then
        run_tool "NuGet 快取" "${HOME}/.nuget/packages" dotnet nuget locals all --clear
    else
        log_skip "沒有 dotnet，略過 NuGet 快取"
    fi

    # Gradle：保留 wrapper（Gradle 本體）與 gradle.properties（常含 signing 設定），只清下面三個
    if ! skip_if_busy "${HOME}/.gradle" "Gradle caches／daemon／.tmp" android_studio gradle_daemon emulator; then
        log_info "Gradle：保留 wrapper（Gradle 本體）與 gradle.properties（常含 signing 設定）"
        clean purge "${HOME}/.gradle/caches" "Gradle caches"
        clean purge "${HOME}/.gradle/daemon" "Gradle daemon log"
        clean purge "${HOME}/.gradle/.tmp"   "Gradle 暫存"
    fi

    clean purge "${HOME}/Library/Caches/CocoaPods" "CocoaPods 快取"

    local spm="${HOME}/Library/Caches/org.swift.swiftpm"
    skip_if_busy "$spm" "SwiftPM 快取" xcode \
        || clean purge "$spm" "SwiftPM 快取"

    clean purge "${HOME}/.dartServer" "Dart analysis server 快取"

    tier_b_pub_cache
    tier_b_flutter_sdk
}

# is_pub_cache <路徑>  長得像 pub cache 回 0
#   條件：不是 /、HOME 或 HOME 的上層目錄，且底下有 hosted 或 global_packages 其中之一。
#   不看目錄名稱：預設路徑一定叫 .pub-cache，而明確設定的 PUB_CACHE 可以是任何名字，
#   所以名稱擋不到任何東西。也不把 bin 當標記：bin 太常見（~/bin 就有），擋不住 PUB_CACHE=$HOME。
is_pub_cache() {
    [ -n "$1" ] && [ -d "$1" ] || return 1
    is_home_or_above "$1" && return 1
    [ -d "$1/hosted" ] || [ -d "$1/global_packages" ]
}

# pub cache：保留 bin 與 global_packages（pub global 裝的 melos、fvm 等）。
# 不用 dart 官方的 cache clean 子指令：它會連 global 工具一起清掉。
#
# 有 dart 且沒設 DISABLE_TOOL_COMMANDS 時用 `dart pub cache gc --force`：只刪沒被任何
#   active root（跑過 pub get 的專案與 global 工具）引用的套件，作用中專案的依賴不必重新下載。
#   這條路徑不清 hosted-hashes：gc 會自己刪掉被刪套件的 hash，而保留下來的套件少了 hash，
#   下次 pub get 會整包重新下載（pub -v 的訊息：has no content-hash - redownloading）。
# 否則退回路徑清理：hosted、git 整個清掉，hosted-hashes 隨 hosted 一起失效，也一起清。
# 兩條路徑都清 .tmp（舊版 pub 暫存）與 _temp（新版 pub 下載暫存）。
tier_b_pub_cache() {
    local pub="${PUB_CACHE:-${HOME}/.pub-cache}"
    if [ ! -d "$pub" ]; then
        log_skip "不存在，略過：pub cache（${pub}）"
        return 0
    fi
    if ! is_pub_cache "$pub"; then
        log_warn "不像 pub cache（是 /、~ 或其上層，或底下沒有 hosted／global_packages），不清：${pub}"
        return 0
    fi
    skip_if_busy "$pub" "pub cache" flutter_tool dart_analyzer && return 0

    if [ "$DISABLE_TOOL_COMMANDS" != true ] && have dart; then
        log_info "pub cache：用 dart pub cache gc 只清沒被引用的套件；保留 bin、global_packages 與 hosted-hashes"
        run_tool "pub cache 沒被任何專案引用的套件" "$pub" env PUB_CACHE="$pub" dart pub cache gc --force
    else
        if [ "$DISABLE_TOOL_COMMANDS" = true ]; then
            log_skip "DISABLE_TOOL_COMMANDS=true，不執行 dart pub cache gc，改用路徑清理"
        else
            log_skip "沒有 dart，不執行 dart pub cache gc，改用路徑清理"
        fi
        log_info "pub cache：保留 bin 與 global_packages（pub global 裝的工具）"
        clean purge "${pub}/hosted"        "pub cache hosted 套件"
        clean purge "${pub}/hosted-hashes" "pub cache 套件 hash（隨 hosted 一起失效）"
        clean purge "${pub}/git"           "pub cache git 套件"
    fi
    clean purge "${pub}/.tmp"  "pub cache 暫存"
    clean purge "${pub}/_temp" "pub cache 下載暫存"
}

# is_flutter_sdk <路徑>  看起來是 Flutter SDK 根目錄回 0：要有 bin/flutter 與 bin/internal，
#   且不是 /、HOME 或 HOME 的上層目錄（例如 FLUTTER_ROOT=$HOME 時 ~/bin/cache 不是 SDK 的東西）
is_flutter_sdk() {
    [ -n "$1" ] && [ -d "$1" ] || return 1
    is_home_or_above "$1" && return 1
    [ -f "$1/bin/flutter" ] && [ -d "$1/bin/internal" ]
}

# detect_flutter_root  印出 Flutter SDK 根目錄候選；找不到就不印
#   有設 FLUTTER_ROOT 就只用它（驗證交給呼叫端，驗不過就不清，不改找別的）。
#   自動偵測的候選要通過 is_flutter_sdk 且有 bin/cache 才採用。
#   DISABLE_TOOL_COMMANDS=true 時只認明確設定的 FLUTTER_ROOT：假 HOME 沙盒若透過 PATH
#   或預設位置找，會找到真實機器上的 SDK 並把它的 bin/cache 刪掉。
detect_flutter_root() {
    if [ -n "${FLUTTER_ROOT:-}" ]; then
        echo "${FLUTTER_ROOT}"; return
    fi
    [ "$DISABLE_TOOL_COMMANDS" = true ] && return
    local bin; bin=$(command -v flutter 2>/dev/null || true)
    if [ -n "$bin" ]; then
        local resolved; resolved=$(readlink "$bin" 2>/dev/null || echo "$bin")
        case "$resolved" in
            /*) ;;
            *) resolved="$(dirname "$bin")/$resolved" ;;
        esac
        local root; root=$(cd "$(dirname "$resolved")/.." 2>/dev/null && pwd)
        is_flutter_sdk "$root" && [ -d "${root}/bin/cache" ] && { echo "$root"; return; }
    fi
    local c
    for c in "${HOME}/development/flutter" "${HOME}/flutter" "${HOME}/sdk/flutter" "/opt/flutter"; do
        is_flutter_sdk "$c" && [ -d "${c}/bin/cache" ] && { echo "$c"; return; }
    done
}

# Flutter SDK artifacts：下次執行 flutter 會自動 precache。
# 擁有者：flutter_tools（flutter run／build 在用 engine；Xcode 與 Gradle 建 Flutter 專案時也經由它）、
# Dart analysis server（IDE 開著時它就是從 bin/cache/dart-sdk 執行的）。
# 不把 Xcode／Android Studio 本身列為擁有者：它們開著不代表在用 Flutter，真正在用時會有上面兩個 process。
tier_b_flutter_sdk() {
    local root
    root=$(detect_flutter_root)
    if [ -z "$root" ]; then
        if [ "$DISABLE_TOOL_COMMANDS" = true ]; then
            log_skip "DISABLE_TOOL_COMMANDS=true 且未設 FLUTTER_ROOT，略過 Flutter SDK bin/cache"
        else
            log_skip "找不到 Flutter SDK，略過 bin/cache"
        fi
        return 0
    fi
    if ! is_flutter_sdk "$root"; then
        log_warn "FLUTTER_ROOT 不像 Flutter SDK（缺 bin/flutter 或 bin/internal，或是 /、~ 或其上層），不清：${root}"
        return 0
    fi
    local cache="${root}/bin/cache"
    if [ ! -e "$cache" ] && [ ! -L "$cache" ]; then
        log_skip "不存在，略過：Flutter SDK artifacts（${cache}）"
        return 0
    fi
    skip_if_busy "$cache" "Flutter SDK artifacts" flutter_tool dart_analyzer \
        || clean purge "$cache" "Flutter SDK artifacts（下次執行 flutter 會自動 precache）"
}

# Playwright 只報告：同一瀏覽器有多個 revision 時，舊 revision 可手動刪（見文件）
tier_b_playwright_report() {
    local d
    for d in "${HOME}"/Library/Caches/ms-playwright*; do
        [ -d "$d" ] || continue
        log_info "[只報告] $(basename "$d") — $(human "$(dir_kb "$d")") — ${d}"
    done
    local pw="${HOME}/Library/Caches/ms-playwright"
    [ -d "$pw" ] || return 0
    # 名稱格式為 <browser>-<revision>；每個 browser 只留最新 revision，其餘列為可手動清
    find "$pw" -mindepth 1 -maxdepth 1 -type d -name '*-[0-9]*' -exec basename {} \; \
        | awk -F- '{rev=$NF; name=substr($0, 1, length($0)-length(rev)-1); print name "\t" rev}' \
        | sort -k1,1 -k2,2n \
        | awk -F'\t' '{ if ($1 == prev) print prev_full; prev=$1; prev_full=$1 "-" $2 }' \
        | while IFS= read -r old; do
            log_info "[只報告] Playwright 舊 revision：${old} — $(human "$(dir_kb "${pw}/${old}")")（手動刪除方式見 docs/disk-space-knowledge.md）"
        done
}

tier_b_xcode_browsers() {
    local ds="${HOME}/Library/Developer/Xcode/iOS DeviceSupport"
    skip_if_busy "$ds" "iOS DeviceSupport" xcode \
        || clean_older "$ds" 90 "iOS DeviceSupport"
    ds="${HOME}/Library/Developer/Xcode/watchOS DeviceSupport"
    skip_if_busy "$ds" "watchOS DeviceSupport" xcode \
        || clean_older "$ds" 90 "watchOS DeviceSupport"

    local c
    c="${HOME}/Library/Caches/Google/Chrome"
    skip_if_busy "$c" "Chrome 快取" chrome || clean empty "$c" "Chrome 快取"
    c="${HOME}/Library/Caches/Microsoft Edge"
    skip_if_busy "$c" "Edge 快取" edge || clean empty "$c" "Edge 快取"
    c="${HOME}/Library/Caches/Cursor"
    skip_if_busy "$c" "Cursor 快取" cursor || clean empty "$c" "Cursor 快取"
}

run_tier_b() {
    log_info "=== B 級：套件與瀏覽器快取（會重新下載） ==="
    tier_b_packages
    tier_b_playwright_report
    tier_b_xcode_browsers
}

# ============================================================
# C 級：--projects DIR
# ============================================================

# is_stale <path>  mtime 超過 STALE_DAYS 天回 0
is_stale() {
    [ -n "$(find "$1" -maxdepth 0 -mmin "+$(days_to_min "$STALE_DAYS")" 2>/dev/null)" ]
}

scan_project_dir() {
    local root="$1"
    if [ ! -d "$root" ]; then
        log_warn "專案目錄不存在：${root}"
        return 0
    fi
    # ~、/、~ 的上層與 ~/Library 都不是專案目錄：底下有編輯器外掛、npx 快取、app 資料等
    # 帶 package.json 的東西，照規則掃會把它們的 node_modules 當成專案產物刪掉。
    local phys; phys=$(norm_phys "$root")
    if is_home_or_above "$root"; then
        log_error "拒絕掃描 ${root}：這是 /、~ 或 ~ 的上層目錄，不是專案目錄。請改指定 ~/Projects 之類的專案資料夾"
        return 0
    fi
    case "${phys}/" in
        "${HOME_P}/Library/"*)
            log_error "拒絕掃描 ${root}：~/Library 底下不是專案目錄。請改指定 ~/Projects 之類的專案資料夾"
            return 0 ;;
    esac
    case "$(norm_text "$root")/" in
        "${HOME_T}/Library/"*)
            log_error "拒絕掃描 ${root}：~/Library 底下不是專案目錄。請改指定 ~/Projects 之類的專案資料夾"
            return 0 ;;
    esac
    log_info "掃描 ${root}（maxdepth 4，門檻 ${STALE_DAYS} 天）"

    local manifest dir target ref found=false
    while IFS= read -r manifest; do
        [ -n "$manifest" ] || continue
        dir=$(dirname "$manifest")
        case "$(basename "$manifest")" in
            pubspec.yaml)
                target="${dir}/build"
                [ -d "$target" ] || continue
                is_stale "$target" || continue
                found=true
                clean purge "$target" "Flutter build（${STALE_DAYS} 天未更新）"
                ;;
            package.json)
                target="${dir}/node_modules"
                [ -d "$target" ] || continue
                ref="${target}/.package-lock.json"
                [ -e "$ref" ] || ref="$target"
                is_stale "$ref" || continue
                found=true
                clean purge "$target" "node_modules（${STALE_DAYS} 天未安裝）"
                ;;
        esac
    done <<EOF
$(find "$root" -mindepth 1 -maxdepth 4 \( -name '.*' -o -name node_modules -o -name build -o -name Pods \) -prune \
    -o \( -name pubspec.yaml -o -name package.json \) -type f -print 2>/dev/null)
EOF
    [ "$found" = true ] || log_skip "${root} 底下沒有超過 ${STALE_DAYS} 天的 build/ 或 node_modules"
}

run_tier_c() {
    log_info "=== C 級：專案內久未動過的 build/ 與 node_modules ==="
    # 用 read -a 切冒號：不經過 pathname expansion，--projects "~/p*" 這類參數不會被 glob 展開
    local dirs=() d
    IFS=':' read -r -a dirs <<< "$PROJECT_DIRS"
    for d in ${dirs[@]+"${dirs[@]}"}; do
        [ -n "$d" ] && scan_project_dir "$d"
    done
}

# ============================================================
# 主流程
# ============================================================

if [ "$DRY_RUN" = true ]; then
    log_info "模式：DRY-RUN（只報告，不刪除；加 --apply 才會真的清）"
else
    log_info "模式：APPLY（會實際刪除）"
fi
log_info "開始前磁碟 /：$(free_space)"
log_blank

run_tier_a
log_blank

if [ "$INCLUDE_CACHES" = true ]; then
    run_tier_b
else
    log_skip "=== B 級：未指定 --include-caches，略過 ==="
fi
log_blank

if [ -n "$PROJECT_DIRS" ]; then
    run_tier_c
else
    log_skip "=== C 級：未指定 --projects，略過 ==="
fi
log_blank

# 本 script 自己的 log：只刪符合命名的舊檔；dry-run 只報告
if [ "$DRY_RUN" = true ]; then
    old_logs=$(find "${LOG_DIR}" -maxdepth 1 -name 'clean-dev-mac-*.log' -type f -mmin "+$(days_to_min "$KEEP_LOGS_DAYS")" 2>/dev/null | wc -l | tr -d ' ')
    log_info "[DRY-RUN] 會刪除 ${old_logs} 個超過 ${KEEP_LOGS_DAYS} 天的本 script log"
else
    find "${LOG_DIR}" -maxdepth 1 -name 'clean-dev-mac-*.log' -type f -mmin "+$(days_to_min "$KEEP_LOGS_DAYS")" -delete 2>/dev/null || true
fi

if [ "$DRY_RUN" = true ]; then
    log_info "可釋放（估計；官方指令項目以目錄大小計，為上限；brew 未計入）：$(human "$TOTAL_FREED_KB")"
else
    log_info "已釋放（依目錄前後大小計；brew 未計入）：$(human "$TOTAL_FREED_KB")"
fi
log_info "結束後磁碟 /：$(free_space)"
log_info "log：${LOG_FILE}"

if [ "$HAD_ERROR" = true ]; then
    exit 1
fi
exit 0
