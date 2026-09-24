#!/bin/bash
# 測試共用函式。每支測試 source 這個檔案後呼叫 sb_init 建立自己的沙盒。
#
# 安全保證（絕不碰真實 HOME）：
#   1. 沙盒一律是 mktemp -d 產生的 cdmc-test.XXXXXX 目錄；sb_init 驗證名稱、存在，且不是真實 HOME
#      本身或它的上層，否則中止。
#   2. 一律用 env -i 執行（通常經過 run_personal；要加 bash -x 等情況直接寫 env -i，並自己
#      呼叫 sb_guard）：HOME、LOG_DIR、CODE_SIGN_CLONE_BASE、CLAUDE_TMP_DIR 全部指到沙盒，
#      DISABLE_TOOL_COMMANDS=true，PATH 只有沙盒的假工具目錄與 /usr/bin:/bin。
#   3. 帶 --apply 時，HOME、FLUTTER_ROOT、PUB_CACHE 必須在沙盒底下，否則中止（sb_guard）。
#      沙盒外的 HOME（空字串、/ 等拒絕執行的案例）只准用 dry-run 跑。
#   4. 結束時 trap 清掉整個沙盒（包含測試用的背景 process）。

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
PERSONAL="${REPO_DIR}/clean-dev-mac.sh"

PASSES=0
FAILS=0
SKIPS=0
SB=""
BG_PIDS=""

die() {
    echo "ABORT: $1" >&2
    exit 99
}

sb_cleanup() {
    local p
    for p in $BG_PIDS; do kill "$p" 2>/dev/null; done
    wait 2>/dev/null
    case "$SB" in
        */cdmc-test.*)
            chflags -R nouchg "$SB" 2>/dev/null
            chmod -R u+rwx "$SB" 2>/dev/null
            rm -rf "${SB:?}"
            ;;
    esac
}

# sb_init  建立沙盒並設定清理 trap；之後可用 $SB
sb_init() {
    SB="$(mktemp -d "${TMPDIR:-/tmp}/cdmc-test.XXXXXX")" || die "mktemp 失敗"
    SB="$(cd "$SB" && pwd -P)" || die "沙盒無法解析"
    case "$(basename "$SB")" in
        cdmc-test.??????) ;;
        *) die "沙盒名稱不是 mktemp 產生的 cdmc-test.XXXXXX：$SB" ;;
    esac
    [ -d "$SB" ] || die "沙盒不存在：$SB"
    local real_home
    real_home="$(cd ~ 2>/dev/null && pwd -P)"
    case "${real_home}/" in
        "${SB}/"*) die "沙盒是真實 HOME 或它的上層：$SB" ;;
    esac
    trap sb_cleanup EXIT
    trap 'exit 130' INT TERM
}

# sb_guard <路徑>  路徑不在沙盒底下就中止
sb_guard() {
    [ -n "$SB" ] || die "尚未 sb_init"
    case "$1" in
        "${SB}/"*) ;;
        *) die "路徑不在沙盒底下：'$1'（沙盒 ${SB}）" ;;
    esac
    case "$1" in
        */../*|*/..) die "路徑含 ..：'$1'" ;;
    esac
}

# ---------- 斷言 ----------
pass() { PASSES=$((PASSES + 1)); echo "  ok   $1"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL $1"; }
skip() { SKIPS=$((SKIPS + 1)); echo "SKIP: $1"; }

a_eq() {  # <實際> <預期> <說明>
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3（預期 '$2'，實際 '$1'）"; fi
}
a_exists() {  # <路徑> [說明]
    if [ -e "$1" ] || [ -L "$1" ]; then pass "${2:-保留} — ${1#"$SB"/}"; else fail "${2:-應保留} 但不見了 — $1"; fi
}
a_gone() {
    if [ -e "$1" ] || [ -L "$1" ]; then fail "${2:-應刪除} 但還在 — $1"; else pass "${2:-已刪除} — ${1#"$SB"/}"; fi
}
a_empty_dir() {
    if [ -d "$1" ] && [ -z "$(find "$1" -mindepth 1 -maxdepth 1)" ]; then pass "${2:-目錄保留且已清空} — ${1#"$SB"/}"; else fail "${2:-應保留目錄並清空內容} — $1（內容：$(find "$1" -mindepth 1 -maxdepth 1 2>&1 | tr '\n' ' ')）"; fi
}
a_log() {  # <檔案> <固定字串> <說明>
    if grep -q -F -- "$2" "$1"; then pass "$3"; else fail "$3（輸出沒有：$2）"; fi
}
a_line() {  # <檔案> <整行固定字串> <說明>  整行完全相符
    if grep -q -x -F -- "$2" "$1"; then pass "$3"; else fail "$3（輸出沒有這一整行：$2）"; fi
}
a_logend() {  # <檔案> <固定字串> <說明>  有某一行以這個字串結尾
    if awk -v s="$2" 'length($0) >= length(s) && substr($0, length($0) - length(s) + 1) == s { f = 1 } END { exit !f }' "$1"; then
        pass "$3"
    else
        fail "$3（沒有以這個字串結尾的行：$2）"
    fi
}
a_nolog() {
    if grep -q -F -- "$2" "$1"; then fail "$3（輸出不應有：$2）"; else pass "$3"; fi
}
a_count() {  # <檔案> <固定字串> <預期次數> <說明>
    local n; n=$(grep -c -F -- "$2" "$1")
    a_eq "$n" "$3" "$4"
}

finish() {
    echo "  -- ${PASSES} ok, ${FAILS} fail, ${SKIPS} skip"
    if [ "$FAILS" -gt 0 ]; then exit 1; fi
    if [ "$PASSES" -eq 0 ] && [ "$SKIPS" -gt 0 ]; then exit 3; fi
    exit 0
}

# ---------- fixture ----------
old() { touch -h -t 202601010000 "$@"; }                            # 約 9 個月前
ago() { touch -h -t "$(date -v"-$1" +%Y%m%d%H%M.%S)" "${@:2}"; }   # ago 25H 路徑...

# mkfakebin  在 $SB/fakebin 放假的外部工具：只把呼叫記到 $SB/calls.log
mkfakebin() {
    mkdir -p "$SB/fakebin"
    local t
    for t in npm pnpm go dotnet dart brew xcrun flutter; do
        printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$t" "$SB/calls.log" > "$SB/fakebin/$t"
        chmod +x "$SB/fakebin/$t"
    done
}

# mkflutter_sdk <根目錄>  通過 is_flutter_sdk 檢查的假 SDK（bin/flutter＋bin/internal）
mkflutter_sdk() {
    mkdir -p "$1/bin/internal"
    printf '#!/bin/sh\nexit 0\n' > "$1/bin/flutter"
    chmod +x "$1/bin/flutter"
}

# real_busy <key>  真實機器上該擁有者 app 正在跑回 0（pattern 與 clean-dev-mac.sh 相同）
real_busy() {
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

# any_real_busy <key...>
any_real_busy() {
    local k
    for k in "$@"; do real_busy "$k" && return 0; done
    return 1
}

# a_cleaned <gone|empty> <路徑> <log 裡的描述> <擁有者 key...>
#   擁有者真的在跑（例如測試時開著 Edge）→ 斷言保留且 log 有「跳過 <描述>」；否則斷言已清
a_cleaned() {
    local mode="$1" path="$2" desc="$3" out="$OUTFILE"
    shift 3
    if [ $# -gt 0 ] && any_real_busy "$@"; then
        a_exists "$path" "真實機器上擁有者在跑，應保留：${desc}"
        a_log "$out" "跳過 ${desc}：" "log 記錄跳過 ${desc}"
        return
    fi
    if [ "$mode" = empty ]; then a_empty_dir "$path" "$desc 已清空"; else a_gone "$path" "$desc 已刪除"; fi
}

# ---------- 執行 ----------
# run_personal <HOME> [參數...]  選用環境：FR（FLUTTER_ROOT）、PC（PUB_CACHE）、KLD（KEEP_LOGS_DAYS）
run_personal() {
    local home="$1" a apply=false
    shift
    for a in "$@"; do [ "$a" = --apply ] && apply=true; done
    if [ "$apply" = true ]; then
        sb_guard "$home"
        [ -z "${FR:-}" ] || sb_guard "$FR"
        [ -z "${PC:-}" ] || sb_guard "$PC"
    fi
    local envs=(HOME="$home" PATH="$SB/fakebin:/usr/bin:/bin"
        CODE_SIGN_CLONE_BASE="$SB/X" CLAUDE_TMP_DIR="$SB/claude tmp" LOG_DIR="$SB/logs"
        DISABLE_TOOL_COMMANDS=true)
    [ -n "${FR:-}" ] && envs+=(FLUTTER_ROOT="$FR")
    [ -n "${PC:-}" ] && envs+=(PUB_CACHE="$PC")
    [ -n "${KLD:-}" ] && envs+=(KEEP_LOGS_DAYS="$KLD")
    env -i "${envs[@]}" /bin/bash "$PERSONAL" "$@"
}
