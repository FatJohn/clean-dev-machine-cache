#!/bin/bash
# tools/gpscan-summary.py：手工 fixture 的數字（預期值是照 fixture.xml 的檔案大小手算的，見該檔註解），
# 以及壞檔（截斷的 gzip、非 XML、gzip 過的非 XML、空檔、不存在）與找不到 --root 時的 exit code。
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname "$0")/../lib.sh"
sb_init
GP="${REPO_DIR}/tools/gpscan-summary.py"
FX="${TESTS_DIR}/gpscan/fixture.gpscan"

if ! command -v python3 >/dev/null 2>&1; then
    skip "沒有 python3"
    finish
fi

if gunzip -c "$FX" | cmp -s - "${TESTS_DIR}/gpscan/fixture.xml"; then pass "fixture.gpscan 就是 fixture.xml 的 gzip"; else fail "fixture.gpscan 與 fixture.xml 不一致"; fi

echo "[整個 volume]"
OUTFILE="$SB/all.txt"
python3 "$GP" "$FX" --depth 5 --min-size 0 --top-files 3 > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_line "$OUTFILE" "volume 大小      10.00" "volume 大小 10.00"
a_line "$OUTFILE" "剩餘空間          2.00" "剩餘 2.00"
a_line "$OUTFILE" "已用空間          8.00" "已用 8.00"
a_line "$OUTFILE" "掃到的總量        6.75  (fileSizeMeasure=physical)" "掃到的總量 6.75"
a_log "$OUTFILE" "差距              1.25" "差距 1.25"
a_line "$OUTFILE" "    6.75  /" "根目錄 6.75"
a_line "$OUTFILE" "          3.50  /Users/me/proj" "proj 3.50"
a_line "$OUTFILE" "            1.50  /Users/me/proj/node_modules" "proj/node_modules 含巢狀 1.50"
a_line "$OUTFILE" "              0.50  /Users/me/proj/node_modules/dep" "巢狀 dep 0.50"
a_line "$OUTFILE" "    3.00  /Library/big.dat" "最大檔案 big.dat 3.00"
a_count "$OUTFILE" "/Users/me/proj/node_modules/a.js" 1 "top 3 包含 a.js"
a_nolog "$OUTFILE" "/Users/me/web/node_modules/c.js" "top 3 不包含第 5 大的 c.js"
a_line "$OUTFILE" "    1.75  node_modules          2 處   最大：/Users/me/proj/node_modules (1.50)" "node_modules 只算最外層：2 處 1.75"
a_line "$OUTFILE" "    2.00  build                 1 處   最大：/Users/me/proj/build (2.00)" "build 1 處 2.00"

echo "[--root 子樹]"
OUTFILE="$SB/root.txt"
python3 "$GP" "$FX" --root /Users/me --depth 1 --min-size 0 --top-files 0 > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_line "$OUTFILE" "    3.75  /Users/me" "/Users/me 3.75"
a_line "$OUTFILE" "      0.25  /Users/me/web" "/Users/me/web 0.25"
a_nolog "$OUTFILE" "最大的" "--top-files 0 不印最大檔案"

OUTFILE="$SB/min.txt"
python3 "$GP" "$FX" --depth 5 --min-size 1G --top-files 0 > "$OUTFILE" 2>&1
a_eq "$?" 0 "--min-size 1G exit 0"
a_nolog "$OUTFILE" "/Users/me/web" "--min-size 1G 不列 0.25 GiB 的目錄"
a_line "$OUTFILE" "            1.50  /Users/me/proj/node_modules" "--min-size 1G 仍列 1.50 的目錄"

echo "[壞檔與錯誤]"
bad() {  # <名稱> <檔案> <預期 stderr 片段> [額外參數...]
    local name="$1" f="$2" msg="$3"
    shift 3
    OUTFILE="$SB/$name.out"
    python3 "$GP" "$f" "$@" > "$SB/$name.stdout" 2> "$OUTFILE"
    a_eq "$?" 1 "[$name] exit 1"
    a_log "$OUTFILE" "$msg" "[$name] 錯誤訊息"
    a_nolog "$OUTFILE" "Traceback" "[$name] 沒有 Python traceback"
}
head -c 200 "$FX" > "$SB/trunc.gpscan"
bad trunc "$SB/trunc.gpscan" "讀取失敗："
printf 'this is not xml\n' > "$SB/text.gpscan"
bad text "$SB/text.gpscan" "讀取失敗："
printf 'this is not xml\n' | gzip -n > "$SB/gztext.gpscan"
bad gztext "$SB/gztext.gpscan" "讀取失敗："
: > "$SB/empty.gpscan"
bad empty "$SB/empty.gpscan" "讀取失敗："
bad missing "$SB/no-such.gpscan" "讀取失敗："
bad noroot "$FX" "scan 裡找不到 --root 指定的路徑：/nope" --root /nope

finish
