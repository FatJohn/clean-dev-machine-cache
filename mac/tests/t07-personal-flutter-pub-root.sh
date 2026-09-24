#!/bin/bash
# FLUTTER_ROOT／PUB_CACHE 驗證：不像 SDK／pub cache、或是 /、~ 時不清並記 WARN；合法的假 SDK／自訂 pub cache 會清，
# 且 pub cache 的 bin、global_packages 保留。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin

# pub／flutter 的斷言在真實機器上 flutter_tools／Dart analysis server 在跑時會被跳過，這時整支略過
if any_real_busy flutter_tool dart_analyzer; then
    skip "真實機器上 flutter_tools／Dart analysis server 在跑，pub cache 與 Flutter SDK 項目都會被跳過"
    finish
fi

H="$SB/h"; mkdir -p "$H/bin/x"

echo "[FLUTTER_ROOT]"
OUTFILE="$SB/r1.txt"
FR=/ run_personal "$H" --include-caches > "$OUTFILE" 2>&1   # 沙盒外的值只跑 dry-run
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK（缺 bin/flutter 或 bin/internal，或是 /、~ 或其上層），不清：/" "FLUTTER_ROOT=/ → WARN 不清"

OUTFILE="$SB/r2.txt"
FR="$H" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK" "FLUTTER_ROOT=HOME（沒有 ~/bin/cache）→ WARN"
a_exists "$H/bin/x" "HOME/bin 保留"

mkdir -p "$H/bin/cache/userdata"; mkflutter_sdk "$H"   # 連 bin/flutter、bin/internal 都有，仍因為是 HOME 而拒絕
OUTFILE="$SB/r3.txt"
FR="$H" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_exists "$H/bin/cache/userdata" "FLUTTER_ROOT=HOME 且長得像 SDK：~/bin/cache 保留"
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK" "FLUTTER_ROOT=HOME → WARN"

FS="$SB/fakesdk"; mkflutter_sdk "$FS"; mkdir -p "$FS/bin/cache/c"
OUTFILE="$SB/r4.txt"
FR="$FS" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_gone "$FS/bin/cache" "合法的假 SDK：bin/cache 刪除"
a_log "$OUTFILE" "已清除 Flutter SDK artifacts" "log：已清除 Flutter SDK artifacts"

FS2="$SB/halfsdk"; mkdir -p "$FS2/bin/cache/c"; printf '#!/bin/sh\n' > "$FS2/bin/flutter"
OUTFILE="$SB/r5.txt"
FR="$FS2" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_exists "$FS2/bin/cache/c" "有 bin/flutter 沒有 bin/internal：bin/cache 保留"
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK" "log：缺 bin/internal → WARN"

echo "[PUB_CACHE]"
H2="$SB/h2"; mkdir -p "$H2/git/myrepo" "$H2/hosted/h" "$H2/.tmp/t" "$H2/_temp/d" "$H2/hosted-hashes/x"
for pc in "$H2" "$H2/"; do
    OUTFILE="$SB/p.txt"
    PC="$pc" run_personal "$H2" --apply --include-caches > "$OUTFILE" 2>&1
    a_exists "$H2/git/myrepo" "PUB_CACHE='${pc}'：~/git 保留"
    a_exists "$H2/hosted/h" "PUB_CACHE='${pc}'：~/hosted 保留"
    a_exists "$H2/.tmp/t" "PUB_CACHE='${pc}'：~/.tmp 保留"
    a_exists "$H2/_temp/d" "PUB_CACHE='${pc}'：~/_temp 保留"
    a_exists "$H2/hosted-hashes/x" "PUB_CACHE='${pc}'：~/hosted-hashes 保留"
    a_log "$OUTFILE" "不像 pub cache（是 /、~ 或其上層，或底下沒有 hosted／global_packages），不清：${pc}" "PUB_CACHE='${pc}' → WARN"
done

PCD="$SB/mypub"
mkdir -p "$PCD/hosted/pub.dev/x" "$PCD/git/g" "$PCD/bin" "$PCD/global_packages/melos" "$PCD/_temp/d" "$PCD/hosted-hashes/pub.dev" "$PCD/.tmp/t"
OUTFILE="$SB/p2.txt"
PC="$PCD" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_log "$OUTFILE" "DISABLE_TOOL_COMMANDS=true，不執行 dart pub cache gc，改用路徑清理" "自訂 PUB_CACHE：走路徑清理"
a_gone "$PCD/hosted" "自訂 PUB_CACHE：hosted 刪除"
a_gone "$PCD/git" "自訂 PUB_CACHE：git 刪除"
a_gone "$PCD/_temp" "自訂 PUB_CACHE：_temp 刪除"
a_gone "$PCD/hosted-hashes" "自訂 PUB_CACHE：hosted-hashes 刪除"
a_gone "$PCD/.tmp" "自訂 PUB_CACHE：.tmp 刪除"
a_exists "$PCD/bin" "自訂 PUB_CACHE：bin 保留"
a_exists "$PCD/global_packages/melos" "自訂 PUB_CACHE：global_packages 保留"

NP="$SB/notpub"; mkdir -p "$NP/git/g" "$NP/bin" "$NP/_temp/d"
OUTFILE="$SB/p3.txt"
PC="$NP" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_exists "$NP/git/g" "只有 git＋bin 的目錄：git 保留"
a_exists "$NP/_temp/d" "只有 git＋bin 的目錄：_temp 保留"
a_log "$OUTFILE" "不像 pub cache" "只有 git＋bin 的目錄 → WARN"

finish
