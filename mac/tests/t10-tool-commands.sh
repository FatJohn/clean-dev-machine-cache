#!/bin/bash
# DISABLE_TOOL_COMMANDS=false：外部指令真的會被呼叫時，呼叫的是哪個指令、帶什麼參數。
#   - dry-run 只有查詢型呼叫（見 DRY_ALLOWED），沒有任何 gc／prune／clean／delete
#   - apply 時每個外部指令的參數完全相符；pub cache 用 `dart pub cache gc --force`（不是 clean），
#     PUB_CACHE 指向沙盒，.tmp／_temp 刪除，hosted／git／hosted-hashes／bin／global_packages 保留
#   - flutter_tools 在跑、或 PUB_CACHE=$HOME 時 dart 不會被呼叫
#   - 沒設 FLUTTER_ROOT 時從 PATH 上的 flutter 找到沙盒裡的假 SDK，並清掉它的 bin/cache
#
# 安全：PATH 只有「假工具目錄:系統工具 symlink 目錄:/bin」，不含 /usr/bin（/usr/bin/xcrun 是真的），
# 也不含 Homebrew 等目錄；開跑前先斷言每個工具的 command -v 都解析到假工具目錄，不符就中止。
# 假工具只把「程式名、參數、PUB_CACHE」記到 calls.log，不做任何事。
# Flutter SDK 沒設 FLUTTER_ROOT，由 script 自己偵測；偵測候選含沙盒外的絕對路徑（/opt/flutter），所以：
#   - 開頭：沙盒外的偵測候選（OUTSIDE_FLUTTER_CANDIDATES）只要存在就整支 SKIP，避免測試在偵測退化時碰到真實 SDK
#   - 每次 --apply 前先用相同參數跑 dry-run（preflight_flutter），會清除的 Flutter SDK artifacts 不是
#     $SDK/bin/cache、或 Flutter 相關輸出出現沙盒外路徑，就 die 中止整支測試；run_tools 沒有對應的
#     preflight 就拒絕帶 --apply 執行
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init

# clean-dev-mac.sh 的 detect_flutter_root 裡不在 HOME 底下的偵測候選（改 script 的候選清單時要同步）
OUTSIDE_FLUTTER_CANDIDATES="/opt/flutter"
for c in $OUTSIDE_FLUTTER_CANDIDATES; do
    if [ -e "$c" ] || [ -L "$c" ]; then
        skip "沙盒外的 Flutter SDK 偵測候選 $c 存在；避免測試在偵測退化時碰到真實 SDK，整支 t10 略過"
        finish
    fi
done

FAKE="$SB/tools"
UTILS="$SB/utils"
CALLS="$SB/calls.log"
TPATH="$FAKE:$UTILS:/bin"
TOOLS="dart brew npm pnpm go dotnet xcrun yarn flutter"
# clean-dev-mac.sh 用到、但不在 /bin 的系統工具
SYS_UTILS="awk basename cut dirname du env find getconf grep head id pgrep readlink sed sort tail tr wc"

H="$SB/h"
SDK="$SB/flutter-sdk"
mkdir -p "$FAKE" "$UTILS" "$H" "$SB/pnpm-store/v3" "$SB/go-cache/00" "$SB/go-mod/cache"

# mkfake <名稱> <路徑>  記錄呼叫的假工具；pnpm store path、go env 回傳沙盒裡的路徑
mkfake() {
    cat > "$2" <<EOS
#!/bin/bash
printf '%s\t%s\tPUB_CACHE=%s\n' '$1' "\$*" "\${PUB_CACHE-<unset>}" >> '$CALLS'
case '$1 '"\$*" in
    'pnpm store path')  echo '$SB/pnpm-store' ;;
    'go env GOCACHE')   echo '$SB/go-cache' ;;
    'go env GOMODCACHE') echo '$SB/go-mod' ;;
esac
exit 0
EOS
    chmod +x "$2"
}

# 假 Flutter SDK：結構合法（bin/flutter、bin/internal、bin/cache）；PATH 上的 flutter 是指向它的 symlink，
# detect_flutter_root 會經由 PATH 找到它
mkflutter_sdk "$SDK"
mkfake flutter "$SDK/bin/flutter"
ln -s "$SDK/bin/flutter" "$FAKE/flutter"
for t in $TOOLS; do
    [ "$t" = flutter ] || mkfake "$t" "$FAKE/$t"
done
for u in $SYS_UTILS; do
    [ -x "/usr/bin/$u" ] || die "找不到 /usr/bin/$u"
    ln -s "/usr/bin/$u" "$UTILS/$u"
done

echo "[PATH 確認]"
echo "  PATH=$TPATH"
IFS=':' read -r -a comps <<< "$TPATH"
for c in "${comps[@]}"; do
    case "$c" in
        /usr/bin|/usr/local/bin|/opt/homebrew/bin|/usr/sbin|/sbin) die "PATH 含系統工具目錄 $c" ;;
    esac
done
case ":$TPATH:" in *:/usr/bin:*) die "PATH 含 /usr/bin" ;; esac
pass "PATH 不含 /usr/bin、/usr/local/bin、/opt/homebrew/bin"
for t in $TOOLS; do
    got=$(env -i PATH="$TPATH" /bin/bash -c "command -v $t")
    echo "  command -v $t = $got"
    [ "$got" = "$FAKE/$t" ] || die "$t 沒有解析到假工具目錄（$got）"
    pass "command -v $t 解析到假工具目錄"
done
for u in $SYS_UTILS; do
    case " $TOOLS " in *" $u "*) die "系統工具 $u 與假工具同名" ;; esac
done

# reset_sdk  每次執行前重建假 SDK 的 bin/cache（上一輪 apply 會把它刪掉）。沒有 bin/cache 時
#   detect_flutter_root 會改找 HOME 底下與 /opt/flutter 等預設位置；沙盒外的防線是開頭的
#   OUTSIDE_FLUTTER_CANDIDATES 檢查與 preflight_flutter，不是這裡。
reset_sdk() {
    mkdir -p "$SDK/bin/cache/dart-sdk/bin" "$SDK/bin/cache/artifacts"
}

# mkpub <目錄>  完整的 pub cache 結構
mkpub() {
    rm -rf "${1:?}"
    mkdir -p "$1/hosted/pub.dev/a-1.0.0" "$1/git/g" "$1/hosted-hashes/pub.dev" "$1/bin" \
        "$1/global_packages/melos" "$1/.tmp/t" "$1/_temp/d"
    touch "$1/hosted-hashes/pub.dev/a-1.0.0.sha256"
}

# run_tools [參數...]  選用環境：PC（PUB_CACHE）
#   帶 --apply 時，必須剛以相同參數與 PC 通過 preflight_flutter，否則中止
PREFLIGHT_OK=""
run_tools() {
    sb_guard "$H"
    [ -z "${PC:-}" ] || sb_guard "$PC"
    local a
    for a in "$@"; do
        if [ "$a" = --apply ]; then
            [ "$PREFLIGHT_OK" = "PC=${PC:-}|$*" ] || die "--apply 前沒有以相同參數跑 preflight_flutter：$*"
            PREFLIGHT_OK=""
        fi
    done
    reset_sdk
    : > "$CALLS"
    local envs=(HOME="$H" PATH="$TPATH" CODE_SIGN_CLONE_BASE="$SB/X" CLAUDE_TMP_DIR="$SB/ct"
        LOG_DIR="$SB/logs" DISABLE_TOOL_COMMANDS=false)
    [ -n "${PC:-}" ] && envs+=(PUB_CACHE="$PC")
    env -i "${envs[@]}" /bin/bash "$SCRIPT" "$@"
}

# preflight_flutter <sdk|none> [參數...]  用相同參數（去掉 --apply）先跑 dry-run，檢查 apply 會清的 Flutter SDK：
#   sdk  會清除的 Flutter SDK artifacts 恰好一筆且是 $SDK/bin/cache
#   none 不會清除任何 Flutter SDK artifacts（擁有者在跑等預期不偵測／跳過的情境）
#   兩者都要求 Flutter 相關輸出行裡的絕對路徑全部在沙盒底下。不符就 die，中止整支測試。
preflight_flutter() {
    local want="$1" a out got outside
    shift
    local dargs=()
    for a in "$@"; do [ "$a" = --apply ] || dargs+=("$a"); done
    out="$SB/preflight.txt"
    run_tools ${dargs[@]+"${dargs[@]}"} > "$out" 2>&1
    got=$(grep -F '[DRY-RUN] 會清除 Flutter SDK artifacts' "$out" | sed 's/.* — //')
    # Flutter 相關行裡每個絕對路徑的起點（行首或前一個字元不是路徑字元的 /）都必須接著 "$SB/"
    outside=$(grep -iF flutter "$out" | LC_ALL=C awk -v sb="$SB/" '{
        n = length($0)
        for (i = 1; i <= n; i++) {
            if (substr($0, i, 1) != "/") continue
            p = (i == 1) ? "" : substr($0, i - 1, 1)
            if (p ~ /[A-Za-z0-9._~\/-]/) continue
            if (substr($0, i, length(sb)) != sb) { print; next }
        }
    }')
    [ -z "$outside" ] || die "preflight：Flutter 相關輸出出現沙盒外路徑，中止（$*）：$outside"
    case "$want" in
        sdk)  [ "$got" = "$SDK/bin/cache" ] || die "preflight：會清除的 Flutter SDK artifacts 不是 $SDK/bin/cache，中止（$*）：'${got}'" ;;
        none) [ -z "$got" ] || die "preflight：預期不清 Flutter SDK artifacts，實際會清，中止（$*）：'${got}'" ;;
        *)    die "preflight_flutter：未知的預期 '$want'" ;;
    esac
    pass "preflight：dry-run 的 Flutter SDK 清除目標符合預期（${want}）"
    PREFLIGHT_OK="PC=${PC:-}|$*"
}

# calls  印出 calls.log 的「程式 參數」（不含環境變數欄）
calls() { cut -f 1,2 "$CALLS" | tr '\t' ' '; }
dart_count() { grep -c "^dart	" "$CALLS"; }

XCODE_BUSY=false; any_real_busy xcode simulator && XCODE_BUSY=true
FLUTTER_BUSY=false; any_real_busy flutter_tool dart_analyzer && FLUTTER_BUSY=true

echo "[dry-run：只有查詢型呼叫]"
# dry-run 允許的呼叫：brew 的 -n（只列出會清什麼），以及取量測路徑用的 pnpm store path、go env
DRY_ALLOWED="brew cleanup -n --prune=all
pnpm store path
go env GOCACHE
go env GOMODCACHE"
mkpub "$H/.pub-cache"
OUTFILE="$SB/dry.txt"
run_tools --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "dry-run exit 0"
a_nolog "$OUTFILE" "command not found" "dry-run 沒有找不到的指令"
echo "  calls: $(calls | tr '\n' ';')"
bad=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$DRY_ALLOWED" | grep -qxF -- "$line" || bad="${bad}${line};"
done <<EOF
$(calls)
EOF
a_eq "$bad" "" "dry-run 的呼叫都在允許清單內"
a_eq "$(calls)" "$DRY_ALLOWED" "dry-run 的呼叫與允許清單完全相符"
a_eq "$(calls | grep -cE '(^| )(gc|prune|clean|delete|--clear|-cache|-modcache)( |$)')" 0 "dry-run 沒有 gc／prune／clean／delete 類呼叫"
a_exists "$H/.pub-cache/_temp/d" "dry-run：pub _temp 還在"
a_exists "$SDK/bin/cache/artifacts" "dry-run：假 SDK bin/cache 還在"
if [ "$FLUTTER_BUSY" = true ]; then
    skip "真實機器上 flutter_tools／Dart analysis server 在跑，dry-run 不會列出 dart pub cache gc"
else
    a_log "$OUTFILE" "[DRY-RUN] 會執行 \`env PUB_CACHE=$H/.pub-cache dart pub cache gc --force\`" "dry-run 列出 dart pub cache gc"
fi

echo "[apply：每個外部指令的參數]"
mkpub "$H/.pub-cache"
OUTFILE="$SB/apply.txt"
FL_WANT=sdk; [ "$FLUTTER_BUSY" = true ] && FL_WANT=none
preflight_flutter "$FL_WANT" --apply --include-caches
run_tools --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "apply exit 0"
a_nolog "$OUTFILE" "command not found" "apply 沒有找不到的指令"
echo "  calls: $(calls | tr '\n' ';')"
expect=""
if [ "$XCODE_BUSY" = true ]; then
    skip "真實機器上 Xcode／Simulator 在跑，script 會跳過 xcrun simctl delete unavailable，預期清單不含它"
else
    expect="xcrun simctl delete unavailable
"
fi
expect="${expect}brew cleanup --prune=all
npm cache clean --force
pnpm store path
pnpm store prune
go env GOCACHE
go clean -cache
go env GOMODCACHE
go clean -modcache
dotnet nuget locals all --clear"
if [ "$FLUTTER_BUSY" = true ]; then
    skip "真實機器上 flutter_tools／Dart analysis server 在跑，script 會跳過 pub cache 與 Flutter SDK，略過 dart gc 與 bin/cache 斷言"
else
    expect="${expect}
dart pub cache gc --force"
fi
a_eq "$(calls)" "$expect" "apply 的外部指令與參數完全相符"
if [ "$FLUTTER_BUSY" != true ]; then
    a_eq "$(dart_count)" 1 "dart 只呼叫一次"
    a_line "$CALLS" "dart	pub cache gc --force	PUB_CACHE=$H/.pub-cache" "dart 參數是 pub cache gc --force，PUB_CACHE 指向沙盒"
    a_gone "$H/.pub-cache/.tmp" "pub .tmp 刪除"
    a_gone "$H/.pub-cache/_temp" "pub _temp 刪除"
    for d in hosted git hosted-hashes bin global_packages; do
        a_exists "$H/.pub-cache/$d" "pub $d 保留"
    done
    a_gone "$SDK/bin/cache" "PATH 上找到的假 SDK：bin/cache 刪除"
    a_log "$OUTFILE" "已清除 Flutter SDK artifacts（下次執行 flutter 會自動 precache） — 釋放" "log：已清除 Flutter SDK artifacts"
    a_logend "$OUTFILE" "$SDK/bin/cache" "log：清的是 PATH 上 flutter 所在的假 SDK"
    a_exists "$SDK/bin/flutter" "假 SDK 的 bin/flutter 保留"
fi

if [ "$FLUTTER_BUSY" != true ]; then
    echo "[apply：明確設定的 PUB_CACHE]"
    PCD="$SB/mypub"; mkpub "$PCD"
    OUTFILE="$SB/apply-pc.txt"
    PC="$PCD" preflight_flutter sdk --apply --include-caches
    PC="$PCD" run_tools --apply --include-caches > "$OUTFILE" 2>&1
    a_eq "$?" 0 "exit 0"
    a_eq "$(dart_count)" 1 "dart 只呼叫一次"
    a_line "$CALLS" "dart	pub cache gc --force	PUB_CACHE=$PCD" "PUB_CACHE 指向明確設定的沙盒路徑"
    a_gone "$PCD/_temp" "_temp 刪除"
    a_exists "$PCD/global_packages/melos" "global_packages 保留"
fi

echo "[flutter_tools 在跑：dart 不呼叫]"
/bin/bash -c 'exec -a "/sdk/bin/cache/dart-sdk/bin/dart /sdk/bin/cache/flutter_''tools.snapshot run" sleep 120' &
BG_PIDS="$BG_PIDS $!"
bp=$!
n=0
until pgrep -f flutter_tools >/dev/null 2>&1 || [ "$n" -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
pgrep -f flutter_tools >/dev/null 2>&1 || die "假的 flutter_tools process 沒有起來"
PCD="$SB/mypub"; mkpub "$PCD"
OUTFILE="$SB/busy.txt"
PC="$PCD" preflight_flutter none --apply --include-caches
PC="$PCD" run_tools --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
kill "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
a_eq "$(dart_count)" 0 "flutter_tools 在跑：dart 呼叫 0 次"
a_log "$OUTFILE" "跳過 pub cache：flutter 指令（flutter_tools） 正在執行" "log：跳過 pub cache"
a_exists "$PCD/_temp/d" "flutter_tools 在跑：pub _temp 保留"
a_exists "$SDK/bin/cache/artifacts" "flutter_tools 在跑：假 SDK bin/cache 保留"

echo "[PUB_CACHE=\$HOME：dart 不呼叫]"
mkdir -p "$H/hosted/h" "$H/global_packages/g" "$H/.tmp/t" "$H/_temp/d"
for pc in "$H" "$H/"; do
    OUTFILE="$SB/home.txt"
    PC="$pc" preflight_flutter "$FL_WANT" --apply --include-caches
    PC="$pc" run_tools --apply --include-caches > "$OUTFILE" 2>&1
    a_eq "$?" 0 "PUB_CACHE='$pc'：exit 0"
    a_eq "$(dart_count)" 0 "PUB_CACHE='$pc'：dart 呼叫 0 次"
    a_log "$OUTFILE" "不像 pub cache（是 /、~ 或其上層，或底下沒有 hosted／global_packages），不清：${pc}" "PUB_CACHE='$pc' → WARN"
    a_exists "$H/.tmp/t" "PUB_CACHE='$pc'：~/.tmp 保留"
    a_exists "$H/_temp/d" "PUB_CACHE='$pc'：~/_temp 保留"
    a_exists "$H/hosted/h" "PUB_CACHE='$pc'：~/hosted 保留"
done

finish
