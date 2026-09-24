#!/bin/bash
# C 級（--projects）：參數驗證、門檻、相對路徑、不存在的目錄、glob 不展開、拒絕 ~／/／~ 的上層／~/Library、
# 隱藏目錄不進去。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin
H="$SB/h"; mkdir -p "$H"

mkp() {
    rm -rf "${SB:?}/projects"
    P="$SB/projects"
    mkdir -p "$P/fresh app/build/x" "$P/fresh web/node_modules/d"
    touch "$P/fresh app/pubspec.yaml" "$P/fresh web/package.json"
}
left() { find "$P" -mindepth 2 -maxdepth 2 \( -name build -o -name node_modules \) | wc -l | tr -d ' '; }

echo "[--stale-days 驗證]"
for v in -1 abc 1.5 '' 0 00 07; do
    mkp
    OUTFILE="$SB/r.txt"
    run_personal "$H" --apply --projects "$P" --stale-days "$v" > "$OUTFILE" 2>&1
    a_eq "$?" 2 "--stale-days '$v' → exit 2"
    a_eq "$(left)" 2 "--stale-days '$v' 什麼都沒刪"
    a_nolog "$OUTFILE" "模式：" "--stale-days '$v' 在開始清理前就結束"
done

echo "[預設 30 天，新專案不刪]"
mkp; OUTFILE="$SB/r.txt"
run_personal "$H" --apply --projects "$P" > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_eq "$(left)" 2 "新的 build／node_modules 都保留"
a_log "$OUTFILE" "底下沒有超過 30 天的 build/ 或 node_modules" "log：沒有可清項目"

echo "[相對路徑]"
mkp; mkdir -p "$P/old rel/build"; touch "$P/old rel/pubspec.yaml"; old "$P/old rel/build"
OUTFILE="$SB/r.txt"
( cd "$SB" && run_personal "$H" --apply --projects projects > "$OUTFILE" 2>&1 )
a_gone "$P/old rel/build" "相對路徑 projects 底下的舊 build 刪除"
a_exists "$P/fresh app/build" "新 build 保留"
a_log "$OUTFILE" "掃描 projects（maxdepth 4" "log：掃描相對路徑"

echo "[不存在的目錄、字面上的 ~]"
OUTFILE="$SB/r.txt"
run_personal "$H" --apply --projects "$SB/nope" --projects '~' > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_log "$OUTFILE" "專案目錄不存在：$SB/nope" "log：不存在的目錄"
a_log "$OUTFILE" "專案目錄不存在：~" "log：字面 ~ 不展開"

echo "[glob 不展開]"
mkdir -p "$SB/pX1/a/build" "$SB/pX2/b/build"; touch "$SB/pX1/a/pubspec.yaml" "$SB/pX2/b/pubspec.yaml"; old "$SB/pX1/a/build" "$SB/pX2/b/build"
OUTFILE="$SB/r.txt"
run_personal "$H" --apply --projects "$SB/pX*" > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_exists "$SB/pX1/a/build" "pX1 的 build 保留"
a_exists "$SB/pX2/b/build" "pX2 的 build 保留"
a_log "$OUTFILE" "專案目錄不存在：$SB/pX*" "log：glob 當成字面路徑"

echo "[--projects 指到 HOME：拒絕並 exit 1，其他級照跑]"
mkdir -p "$H/Library/Developer/Xcode/Products/x" "$H/.cursor/extensions/e/node_modules/d" "$H/work/p/node_modules/d"
touch "$H/.cursor/extensions/e/package.json" "$H/work/p/package.json"
old "$H/.cursor/extensions/e/node_modules" "$H/work/p/node_modules"
OUTFILE="$SB/r.txt"
run_personal "$H" --apply --projects "$H" > "$OUTFILE" 2>&1
a_eq "$?" 1 "exit 1"
a_log "$OUTFILE" "拒絕掃描 ${H}：這是 /、~ 或 ~ 的上層目錄" "log：拒絕掃描 HOME"
a_cleaned gone "$H/Library/Developer/Xcode/Products" "Xcode Products" xcode
a_exists "$H/.cursor/extensions/e/node_modules" "HOME/.cursor 底下的 node_modules 保留"
a_exists "$H/work/p/node_modules" "HOME/work 底下的 node_modules 保留（整個 HOME 被拒絕）"
a_nolog "$OUTFILE" "extensions" "輸出沒提到 extensions"

mkdir -p "$H/Library/Application Support"
for r in "$H/" "$H/." "$SB" "/" "$H/Library" "$H/Library/Application Support"; do
    OUTFILE="$SB/r2.txt"
    run_personal "$H" --projects "$r" > "$OUTFILE" 2>&1
    a_eq "$?" 1 "dry-run --projects '$r' → exit 1"
    a_log "$OUTFILE" "拒絕掃描 ${r}：" "log：拒絕掃描 '$r'"
    a_nolog "$OUTFILE" "掃描 ${r}（" "沒有開始掃描 '$r'"
done

echo "[隱藏目錄不進去]"
PR="$SB/proj-root"
mkdir -p "$PR/.hidden/x/node_modules/d" "$PR/.cursor/extensions/e/node_modules/d" "$PR/app/node_modules/d" "$PR/.hidproj/build/b"
touch "$PR/.hidden/x/package.json" "$PR/.cursor/extensions/e/package.json" "$PR/app/package.json" "$PR/.hidproj/pubspec.yaml"
old "$PR/.hidden/x/node_modules" "$PR/.cursor/extensions/e/node_modules" "$PR/app/node_modules" "$PR/.hidproj/build"
OUTFILE="$SB/dry.txt"
run_personal "$H" --projects "$PR" > "$OUTFILE" 2>&1
a_eq "$?" 0 "dry-run exit 0"
a_eq "$(grep -cE '\.hidden|\.cursor|\.hidproj' "$OUTFILE")" 0 "dry-run 沒列出隱藏目錄"
a_count "$OUTFILE" "app/node_modules" 1 "dry-run 列出 app/node_modules"
OUTFILE="$SB/apply.txt"
run_personal "$H" --apply --projects "$PR" > "$OUTFILE" 2>&1
a_eq "$?" 0 "apply exit 0"
a_exists "$PR/.hidden/x/node_modules" ".hidden 底下保留"
a_exists "$PR/.cursor/extensions/e/node_modules" ".cursor 底下保留"
a_exists "$PR/.hidproj/build" ".hidproj 底下保留"
a_gone "$PR/app/node_modules" "app/node_modules 刪除"

finish
