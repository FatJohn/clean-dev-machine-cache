#!/bin/bash
# DISABLE_TOOL_COMMANDS=true：dry-run 與 --apply 都不執行任何外部工具（假工具的呼叫紀錄為空、
# bash -x trace 裡沒有工具的執行行）；沒設 FLUTTER_ROOT 時不透過 PATH／預設位置找 Flutter SDK；
# pub cache 改走路徑清理（_temp、hosted-hashes 也清）。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin
H="$SB/h"; sb_guard "$H"   # 這支直接呼叫 env -i（要加 bash -x），不經過 run_personal，所以自己檢查
# PATH 上有假 flutter、HOME 預設位置有像 SDK 的目錄：DISABLE 模式下兩者都不該被採用
mkflutter_sdk "$H/development/flutter"; mkdir -p "$H/development/flutter/bin/cache/c"
mkflutter_sdk "$SB"; mkdir -p "$SB/bin/cache/c"
mkdir -p "$H/.npm/_cacache/x" "$H/Library/Developer/Xcode"

for mode in dry apply; do
    a=(); [ "$mode" = apply ] && a=(--apply)
    : > "$SB/calls.log"
    P="$H/.pub-cache"
    mkdir -p "$P/hosted/pub.dev/a-1.0.0" "$P/hosted-hashes/pub.dev" "$P/_temp/dirX" "$P/git/g" "$P/bin" "$P/global_packages/g"
    touch "$P/hosted-hashes/pub.dev/a-1.0.0.sha256"
    OUTFILE="$SB/$mode.txt"
    env -i HOME="$H" PATH="$SB/fakebin:/usr/bin:/bin" CODE_SIGN_CLONE_BASE="$SB/X" CLAUDE_TMP_DIR="$SB/ct" \
        LOG_DIR="$SB/logs" DISABLE_TOOL_COMMANDS=true \
        /bin/bash -x "$PERSONAL" ${a[@]+"${a[@]}"} --include-caches --projects "$SB/p" > "$OUTFILE" 2> "$SB/$mode.trace"
    a_eq "$?" 0 "[$mode] exit 0"
    if [ -s "$SB/calls.log" ]; then fail "[$mode] 呼叫了外部工具：$(tr '\n' ';' < "$SB/calls.log")"; else pass "[$mode] 假工具沒有被呼叫"; fi
    n=$(grep -cE '^\++ (/usr/bin/)?(xcrun|brew|npm|pnpm|go|dotnet|dart|flutter)( |$)|^\++ env .*dart' "$SB/$mode.trace")
    a_eq "$n" 0 "[$mode] trace 裡沒有外部工具的執行行"
    a_log "$SB/$mode.trace" "tools_disabled" "[$mode] trace 有走到 tools_disabled（trace 本身有效）"
    a_exists "$H/development/flutter/bin/cache/c" "[$mode] ~/development/flutter/bin/cache 保留"
    a_exists "$SB/bin/cache/c" "[$mode] PATH 上 flutter 所在 SDK 的 bin/cache 保留"
    a_log "$OUTFILE" "DISABLE_TOOL_COMMANDS=true 且未設 FLUTTER_ROOT，略過 Flutter SDK bin/cache" "[$mode] log：不找 Flutter SDK"
    a_log "$OUTFILE" "略過（DISABLE_TOOL_COMMANDS）：不執行 pnpm store path、pnpm store prune" "[$mode] log：pnpm 略過"
    a_log "$OUTFILE" "略過（DISABLE_TOOL_COMMANDS）：不執行 go env、go clean -cache、go clean -modcache" "[$mode] log：go 略過"
    if any_real_busy flutter_tool dart_analyzer; then
        skip "[$mode] 真實機器上 flutter_tools／Dart analysis server 在跑，pub cache 被跳過，略過 pub 斷言"
    elif [ "$mode" = dry ]; then
        a_log "$OUTFILE" "DISABLE_TOOL_COMMANDS=true，不執行 dart pub cache gc，改用路徑清理" "[dry] log：pub cache 不跑 gc"
        a_log "$OUTFILE" "[DRY-RUN] 會清除 pub cache 下載暫存" "[dry] 列出 pub _temp"
        a_log "$OUTFILE" "[DRY-RUN] 會清除 pub cache 套件 hash（隨 hosted 一起失效）" "[dry] 列出 pub hosted-hashes"
        a_exists "$P/_temp/dirX" "[dry] pub _temp 還在"
        a_exists "$P/hosted-hashes" "[dry] pub hosted-hashes 還在"
    else
        a_log "$OUTFILE" "DISABLE_TOOL_COMMANDS=true，不執行 dart pub cache gc，改用路徑清理" "[apply] log：pub cache 不跑 gc"
        a_gone "$P/_temp" "[apply] pub _temp 刪除"
        a_gone "$P/hosted-hashes" "[apply] pub hosted-hashes 刪除"
        a_gone "$P/hosted" "[apply] pub hosted 刪除"
        a_exists "$P/bin" "[apply] pub bin 保留"
        a_exists "$P/global_packages/g" "[apply] pub global_packages 保留"
    fi
done

finish
