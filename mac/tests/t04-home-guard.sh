#!/bin/bash
# HOME 防呆：HOME 空、/、//、/.、不存在或沒設時 exit 2，什麼都不做（連 log 目錄都不建）；
# unsafe_path 的單元測試（直接從 script 以函式名抽出 norm_text／norm_phys／is_home_or_above／unsafe_path）。
# 沙盒外的 HOME 只用 dry-run 跑：HOME 檢查在分辨 dry-run／--apply 之前，兩種模式走同一段程式。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin
mkdir -p "$SB/X/com.google.Chrome.code_sign_clone/c1"

snap() { ( cd "$SB" && find . ! -name '*.lst' ! -name 'r.txt' | sort ) > "$SB/$1.lst"; }

for h in "" "/" "//" "/." "$SB/does-not-exist"; do
    snap b
    OUTFILE="$SB/r.txt"
    run_script "$h" --include-caches > "$OUTFILE" 2>&1
    a_eq "$?" 2 "HOME='${h}' → exit 2"
    snap a
    if cmp -s "$SB/b.lst" "$SB/a.lst"; then pass "HOME='${h}' 沙盒沒有任何變動（沒建 log 目錄）"; else fail "HOME='${h}' 沙盒有變動：$(diff "$SB/b.lst" "$SB/a.lst" | tr '\n' ' ')"; fi
    a_log "$OUTFILE" "拒絕執行" "HOME='${h}' log：拒絕執行"
    a_nolog "$OUTFILE" "會清除" "HOME='${h}' 沒有任何清除項目"
done

echo "[HOME 沒設]"
OUTFILE="$SB/r.txt"
env -i PATH="$SB/fakebin:/usr/bin:/bin" CODE_SIGN_CLONE_BASE="$SB/X" CLAUDE_TMP_DIR="$SB/ct" LOG_DIR="$SB/logs" \
    DISABLE_TOOL_COMMANDS=true /bin/bash "$SCRIPT" > "$OUTFILE" 2>&1
a_eq "$?" 2 "HOME 沒設 → exit 2"
a_nolog "$OUTFILE" "unbound variable" "沒有 unbound variable"
a_log "$OUTFILE" "HOME 是空的或是 /" "log：HOME 空"

echo "[unsafe_path 單元測試]"
H="$SB/h"; mkdir -p "$H/Library"
# mktemp 的路徑在 /var/folders 底下，而 /var 是 /private/var 的 symlink：拿兩種寫法測實體路徑比對
ALT_H="$H"
case "$H" in
    /private/var/*) ALT_H="${H#/private}" ;;
esac
OUTFILE="$SB/unit.txt"
env -i HOME="$H" PATH=/usr/bin:/bin ALT_H="$ALT_H" SB="$SB" /bin/bash -s "$SCRIPT" > "$OUTFILE" 2>&1 <<'EOS'
eval "$(sed -n "/^norm_text()/,/^}/p;/^norm_phys()/,/^}/p;/^is_home_or_above()/,/^}/p;/^unsafe_path()/,/^}/p" "$1")"
HOME_T=$(norm_text "$HOME"); HOME_P=$(norm_phys "$HOME")
for p in "" / "$HOME" "$HOME/" // /. "$HOME/." "$HOME//" "$SB" "$ALT_H" "$HOME/Library"; do
    if unsafe_path "$p"; then echo "REJECT|$p"; else echo "allow|$p"; fi
done
EOS
for p in "" / "$H" "$H/" // /. "$H/." "$H//" "$SB" "$ALT_H"; do
    a_line "$OUTFILE" "REJECT|${p}" "unsafe_path '${p}' → 拒絕"
done
a_line "$OUTFILE" "allow|$H/Library" "unsafe_path HOME/Library → 允許"
a_count "$OUTFILE" "|" 11 "11 個案例都有結果"

finish
