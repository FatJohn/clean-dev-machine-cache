#!/bin/bash
# 天數門檻（-mmin +N×1440）的邊界、本 script 舊 log 的保留／刪除、KEEP_LOGS_DAYS 驗證。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin
H="$SB/h"; mkdir -p "$H"

echo "[dry-run 不刪舊 log]"
mkdir -p "$SB/logs"; touch "$SB/logs/clean-dev-mac-20250101-000000.log"; old "$SB/logs/clean-dev-mac-20250101-000000.log"
OUTFILE="$SB/r.txt"
run_script "$H" > "$OUTFILE" 2>&1
a_eq "$?" 0 "dry-run exit 0"
a_exists "$SB/logs/clean-dev-mac-20250101-000000.log" "dry-run：舊 log 保留"
a_log "$OUTFILE" "[DRY-RUN] 會刪除 1 個超過 30 天的本 script log" "log：只報告 1 個舊 log"

echo "[天數邊界]"
P="$SB/p"
mkdir -p "$P/25h/build" "$P/23h/build"; touch "$P/25h/pubspec.yaml" "$P/23h/pubspec.yaml"
ago 25H "$P/25h/build"; ago 23H "$P/23h/build"
mkdir -p "$P/d3p1h/node_modules" "$P/d2p23h/node_modules"; touch "$P/d3p1h/package.json" "$P/d2p23h/package.json"
ago 73H "$P/d3p1h/node_modules"; ago 71H "$P/d2p23h/node_modules"
OUTFILE="$SB/r1.txt"
run_script "$H" --apply --projects "$P/25h:$P/23h" --stale-days 1 > "$OUTFILE" 2>&1
a_gone "$P/25h/build" "--stale-days 1：25 小時前的 build 刪除"
a_exists "$P/23h/build" "--stale-days 1：23 小時前的 build 保留"
OUTFILE="$SB/r2.txt"
run_script "$H" --apply --projects "$P/d3p1h:$P/d2p23h" --stale-days 3 > "$OUTFILE" 2>&1
a_gone "$P/d3p1h/node_modules" "--stale-days 3：3 天又 1 小時的 node_modules 刪除"
a_exists "$P/d2p23h/node_modules" "--stale-days 3：2 天 23 小時的 node_modules 保留"

CT="$SB/claude tmp/proj"; mkdir -p "$CT/s7p1" "$CT/s6p23"; ago 169H "$CT/s7p1"; ago 167H "$CT/s6p23"
CR="$H/.cache/codex-runtimes"; mkdir -p "$CR/codex-runtime-install-25h" "$CR/codex-runtime-install-23h"
ago 25H "$CR/codex-runtime-install-25h"; ago 23H "$CR/codex-runtime-install-23h"
touch "$SB/logs/clean-dev-mac-49h.log" "$SB/logs/clean-dev-mac-47h.log" "$SB/logs/other-49h.log"
ago 49H "$SB/logs/clean-dev-mac-49h.log" "$SB/logs/other-49h.log"; ago 47H "$SB/logs/clean-dev-mac-47h.log"
OUTFILE="$SB/r3.txt"
KLD=2 run_script "$H" --apply > "$OUTFILE" 2>&1
a_eq "$?" 0 "KEEP_LOGS_DAYS=2 --apply exit 0"
a_gone "$CT/s7p1" "Claude 暫存 7 天又 1 小時刪除"
a_exists "$CT/s6p23" "Claude 暫存 6 天 23 小時保留"
a_gone "$CR/codex-runtime-install-25h" "codex runtime 暫存 25 小時刪除"
a_exists "$CR/codex-runtime-install-23h" "codex runtime 暫存 23 小時保留"
a_gone "$SB/logs/clean-dev-mac-49h.log" "KEEP_LOGS_DAYS=2：49 小時的 log 刪除"
a_exists "$SB/logs/clean-dev-mac-47h.log" "KEEP_LOGS_DAYS=2：47 小時的 log 保留"
a_exists "$SB/logs/other-49h.log" "不符合命名的舊檔保留"
a_gone "$SB/logs/clean-dev-mac-20250101-000000.log" "--apply：30 天以上的舊 log 刪除"

echo "[KEEP_LOGS_DAYS 驗證]"
for v in abc 0 07 -1; do
    OUTFILE="$SB/k.txt"
    KLD="$v" run_script "$H" > "$OUTFILE" 2>&1
    a_eq "$?" 2 "KEEP_LOGS_DAYS='${v}' → exit 2"
    a_log "$OUTFILE" "KEEP_LOGS_DAYS 必須是正整數" "KEEP_LOGS_DAYS='${v}' log"
done

finish
