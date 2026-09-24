#!/bin/bash
# 依序跑 tests/t*.sh 與 tests/gpscan/t*.sh，印出每支的 PASS／FAIL／SKIP，最後總結；任一 FAIL 就 exit 1。
# 每支測試都在自己的 mktemp -d 沙盒裡跑，不碰真實 HOME（保證怎麼做到見 tests/lib.sh 開頭）。
#
# 用法：tests/run.sh [-v]     -v 印出每支測試的完整輸出

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
VERBOSE=false
[ "${1:-}" = -v ] && VERBOSE=true

OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cdmc-run.XXXXXX")" || { echo "mktemp 失敗" >&2; exit 2; }
case "$(basename "$OUT_DIR")" in
    cdmc-run.??????) ;;
    *) echo "輸出目錄不是 mktemp 產生的：$OUT_DIR" >&2; exit 2 ;;
esac
trap 'rm -rf "${OUT_DIR:?}"' EXIT

n_pass=0; n_fail=0; n_skip=0; failed=""
for t in "$TESTS_DIR"/t*.sh "$TESTS_DIR"/gpscan/t*.sh; do
    [ -f "$t" ] || continue
    name="${t#"$TESTS_DIR"/}"
    log="$OUT_DIR/$(echo "$name" | tr '/' '_').log"
    /bin/bash "$t" > "$log" 2>&1
    rc=$?
    summary=$(grep -E '^  -- [0-9]+ ok' "$log" | tail -n 1 | sed 's/^  -- //')
    case "$rc" in
        0) n_pass=$((n_pass + 1)); echo "PASS  $name  (${summary})" ;;
        3) n_skip=$((n_skip + 1)); echo "SKIP  $name" ;;
        *) n_fail=$((n_fail + 1)); failed="${failed} ${name}"
           echo "FAIL  $name  (exit ${rc}${summary:+；${summary}})" ;;
    esac
    # 部分斷言被略過時，把原因一起印出來
    grep -E '^SKIP: ' "$log" | sed 's/^/      /'
    if [ "$rc" != 0 ] && [ "$rc" != 3 ]; then
        grep -E '^  FAIL |^ABORT: ' "$log" | sed 's/^/      /'
    fi
    [ "$VERBOSE" = true ] && sed 's/^/    | /' "$log"
done

echo
echo "總結：${n_pass} PASS、${n_fail} FAIL、${n_skip} SKIP"
if [ "$n_fail" -gt 0 ]; then
    echo "失敗：${failed}"
    exit 1
fi
exit 0
