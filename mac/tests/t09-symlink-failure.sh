#!/bin/bash
# symlink 一律略過（clean 與 clean_older 都是）；清除失敗時記 ERROR、exit 1，已清的保留。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin
H="$SB/h"; mkdir -p "$H"

echo "[symlink 的 DerivedData／iOS DeviceSupport]"
mkdir -p "$SB/outside/dd/p1" "$SB/outside/ds/old" "$H/Library/Developer/Xcode"; old "$SB/outside/ds/old"
ln -s "$SB/outside/dd" "$H/Library/Developer/Xcode/DerivedData"
ln -s "$SB/outside/ds" "$H/Library/Developer/Xcode/iOS DeviceSupport"
OUTFILE="$SB/r.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_exists "$SB/outside/dd/p1" "symlink 指到的 DerivedData 內容保留"
a_exists "$SB/outside/ds/old" "symlink 指到的 DeviceSupport 舊項目保留"
if real_busy xcode; then
    skip "真實機器上 Xcode 在跑，DerivedData／DeviceSupport 在 symlink 檢查前就被跳過"
else
    a_log "$OUTFILE" "是 symlink，為安全起見略過：Xcode DerivedData" "log：DerivedData symlink 略過"
    a_log "$OUTFILE" "是 symlink，為安全起見略過：iOS DeviceSupport" "log：DeviceSupport symlink 略過（clean_older）"
fi

echo "[清除失敗：uchg 鎖住的檔案]"
CT="$SB/claude tmp/proj"
mkdir -p "$CT/oldsess/sub" "$CT/gone"; echo x > "$CT/oldsess/sub/locked"
chflags uchg "$CT/oldsess/sub/locked"; old "$CT/oldsess/sub" "$CT/oldsess" "$CT/gone"
OUTFILE="$SB/f1.txt"
run_script "$H" --apply > "$OUTFILE" 2>&1
a_eq "$?" 1 "exit 1"
a_exists "$CT/oldsess/sub/locked" "鎖住的檔案還在"
a_gone "$CT/gone" "同一輪其他舊 session 照樣刪除"
a_log "$OUTFILE" "✗ 清除失敗（權限或檔案被佔用）：Claude Code 暫存 proj" "log：ERROR 清除失敗"
a_log "$OUTFILE" "仍有 1 個超過 7 天的項目" "log：回報剩餘項目數"
chflags -R nouchg "$CT/oldsess"; rm -rf "${CT:?}/oldsess"

echo "[清除失敗：chmod 000 的子目錄]"
mkdir -p "$CT/old2/sub"; echo y > "$CT/old2/sub/f"; chmod 000 "$CT/old2/sub"; old "$CT/old2"
OUTFILE="$SB/f2.txt"
run_script "$H" --apply > "$OUTFILE" 2>&1
a_eq "$?" 1 "exit 1"
a_exists "$CT/old2" "讀不到的子目錄所在 session 還在"
a_log "$OUTFILE" "✗ 清除失敗（權限或檔案被佔用）：Claude Code 暫存 proj" "log：ERROR 清除失敗"
chmod 755 "$CT/old2/sub"

finish
