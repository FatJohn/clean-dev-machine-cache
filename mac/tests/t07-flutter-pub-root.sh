#!/bin/bash
# FLUTTER_ROOT／PUB_CACHE 驗證：不像 SDK／pub cache、或是 /、~ 時不清並記 WARN；合法的假 SDK／自訂 pub cache 會清，
# 且 pub cache 的 bin、global_packages 保留。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin

# 拒絕判斷（不像 SDK／pub cache、或是 /、~）在 clean-dev-mac.sh 裡比擁有者 app 的忙碌判斷先做，
# 所以不論真實機器上 flutter_tools／Dart analysis server 有沒有在跑都照樣斷言。
# 只有「會清除」的斷言在它們在跑時會被跳過（script 會跳過 pub cache 與 Flutter SDK 項目），這時改記 SKIP。
BUSY=false
any_real_busy flutter_tool dart_analyzer && BUSY=true
BUSY_REASON="真實機器上 flutter_tools／Dart analysis server 在跑，script 會跳過這一項"

H="$SB/h"; mkdir -p "$H/bin/x"

echo "[FLUTTER_ROOT]"
OUTFILE="$SB/r1.txt"
FR=/ run_script "$H" --include-caches > "$OUTFILE" 2>&1   # 沙盒外的值只跑 dry-run
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK（缺 bin/flutter 或 bin/internal，或是 /、~ 或其上層），不清：/" "FLUTTER_ROOT=/ → WARN 不清"

OUTFILE="$SB/r2.txt"
FR="$H" run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK" "FLUTTER_ROOT=HOME（沒有 ~/bin/cache）→ WARN"
a_exists "$H/bin/x" "HOME/bin 保留"

mkdir -p "$H/bin/cache/userdata"; mkflutter_sdk "$H"   # 連 bin/flutter、bin/internal 都有，仍因為是 HOME 而拒絕
OUTFILE="$SB/r3.txt"
FR="$H" run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_exists "$H/bin/cache/userdata" "FLUTTER_ROOT=HOME 且長得像 SDK：~/bin/cache 保留"
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK" "FLUTTER_ROOT=HOME → WARN"

FS="$SB/fakesdk"; mkflutter_sdk "$FS"; mkdir -p "$FS/bin/cache/c"
OUTFILE="$SB/r4.txt"
FR="$FS" run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
if [ "$BUSY" = true ]; then
    skip "合法的假 SDK 會清 bin/cache：${BUSY_REASON}"
    a_exists "$FS/bin/cache" "忙碌時合法的假 SDK：bin/cache 保留"
    a_log "$OUTFILE" "跳過 Flutter SDK artifacts：" "log：忙碌時跳過 Flutter SDK artifacts"
else
    a_gone "$FS/bin/cache" "合法的假 SDK：bin/cache 刪除"
    a_log "$OUTFILE" "已清除 Flutter SDK artifacts" "log：已清除 Flutter SDK artifacts"
fi

FS2="$SB/halfsdk"; mkdir -p "$FS2/bin/cache/c"; printf '#!/bin/sh\n' > "$FS2/bin/flutter"
OUTFILE="$SB/r5.txt"
FR="$FS2" run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_exists "$FS2/bin/cache/c" "有 bin/flutter 沒有 bin/internal：bin/cache 保留"
a_log "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK" "log：缺 bin/internal → WARN"

echo "[PUB_CACHE]"
H2="$SB/h2"; mkdir -p "$H2/git/myrepo" "$H2/hosted/h" "$H2/.tmp/t" "$H2/_temp/d" "$H2/hosted-hashes/x"
for pc in "$H2" "$H2/"; do
    OUTFILE="$SB/p.txt"
    PC="$pc" run_script "$H2" --apply --include-caches > "$OUTFILE" 2>&1
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
PC="$PCD" run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
if [ "$BUSY" = true ]; then
    skip "自訂 PUB_CACHE 會走路徑清理：${BUSY_REASON}"
    a_exists "$PCD/hosted/pub.dev/x" "忙碌時自訂 PUB_CACHE：hosted 保留"
    a_log "$OUTFILE" "跳過 pub cache：" "log：忙碌時跳過 pub cache"
else
    a_log "$OUTFILE" "DISABLE_TOOL_COMMANDS=true，不執行 dart pub cache gc，改用路徑清理" "自訂 PUB_CACHE：走路徑清理"
    a_gone "$PCD/hosted" "自訂 PUB_CACHE：hosted 刪除"
    a_gone "$PCD/git" "自訂 PUB_CACHE：git 刪除"
    a_gone "$PCD/_temp" "自訂 PUB_CACHE：_temp 刪除"
    a_gone "$PCD/hosted-hashes" "自訂 PUB_CACHE：hosted-hashes 刪除"
    a_gone "$PCD/.tmp" "自訂 PUB_CACHE：.tmp 刪除"
fi
a_exists "$PCD/bin" "自訂 PUB_CACHE：bin 保留"
a_exists "$PCD/global_packages/melos" "自訂 PUB_CACHE：global_packages 保留"

NP="$SB/notpub"; mkdir -p "$NP/git/g" "$NP/bin" "$NP/_temp/d"
OUTFILE="$SB/p3.txt"
PC="$NP" run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_exists "$NP/git/g" "只有 git＋bin 的目錄：git 保留"
a_exists "$NP/_temp/d" "只有 git＋bin 的目錄：_temp 保留"
a_log "$OUTFILE" "不像 pub cache" "只有 git＋bin 的目錄 → WARN"

finish
