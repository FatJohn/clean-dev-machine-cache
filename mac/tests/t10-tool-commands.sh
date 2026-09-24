#!/bin/bash
# DISABLE_TOOL_COMMANDS=false：外部指令真的會被呼叫時，呼叫的是哪個指令、帶什麼參數。
#   - dry-run 只有查詢型呼叫（見 DRY_ALLOWED），沒有任何 gc／prune／clean／delete
#   - apply 時每個外部指令的參數完全相符；pub cache 用 `dart pub cache gc --force`（不是 clean），
#     PUB_CACHE 指向沙盒，.tmp／_temp 刪除，hosted／git／hosted-hashes／bin／global_packages 保留
#   - flutter_tools 在跑、或 PUB_CACHE=$HOME 時 dart 不會被呼叫
#   - 沒設 FLUTTER_ROOT 時從 PATH 上的 flutter 找到沙盒裡的假 SDK，並清掉它的 bin/cache
#   - ~/.npm 有不屬於目前使用者的檔案時，dry-run／apply／DISABLE_TOOL_COMMANDS=true 都印出 chown 提示，
#     apply 照樣執行 npm cache clean；沒有時、或沒有 ~/.npm 時不印。這幾個案例用 OTHER_ID 目錄的假 id
#     回傳別的 uid／gid，讓沙盒裡的檔案全部被視為「不屬於目前使用者」
#   - ~/.npm 本身屬於目前使用者、root 擁有的檔案藏在第 4 層時（真實 id，hard link 做出真的 root 擁有檔案），
#     WARN 列出的是那個深層檔案，chown 指令用真實的 uid:gid
#
# 安全：PATH 只有「假工具目錄:系統工具 symlink 目錄:/bin」，不含 /usr/bin（/usr/bin/xcrun 是真的），
# 也不含 Homebrew 等目錄；開跑前先斷言每個工具的 command -v 都解析到假工具目錄，不符就中止。
# run_tools 每次執行前再以最終 PATH（含 XPATH）重驗一次：每個工具與 id 都要解析到沙盒底下，XPATH 不能含冒號。
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

# run_tools [參數...]  選用環境：PC（PUB_CACHE）、XPATH（加在 PATH 最前面的單一沙盒目錄，不可含冒號）、
#   DT（DISABLE_TOOL_COMMANDS，預設 false）
#   帶 --apply 時，必須剛以相同參數與 PC 通過 preflight_flutter，否則中止
PREFLIGHT_OK=""
run_tools() {
    sb_guard "$H"
    [ -z "${PC:-}" ] || sb_guard "$PC"
    if [ -n "${XPATH:-}" ]; then
        # XPATH 必須是單一目錄：帶冒號就能把 /usr/bin（真的 xcrun）或 Homebrew 夾帶進 PATH
        case "$XPATH" in *:*) die "XPATH 不能含冒號（只能是單一沙盒目錄）：'$XPATH'" ;; esac
        sb_guard "$XPATH"
    fi
    local a t got p="${XPATH:+$XPATH:}$TPATH"
    # 最終 PATH 下，每個假工具與 id 都必須解析到沙盒底下，否則中止
    for t in $TOOLS id; do
        got=$(env -i PATH="$p" /bin/bash -c "command -v $t")
        case "$got" in
            "$SB/"*) ;;
            *) die "PATH=$p 下 $t 解析到沙盒外（'$got'）" ;;
        esac
    done
    for a in "$@"; do
        if [ "$a" = --apply ]; then
            [ "$PREFLIGHT_OK" = "PC=${PC:-}|$*" ] || die "--apply 前沒有以相同參數跑 preflight_flutter：$*"
            PREFLIGHT_OK=""
        fi
    done
    reset_sdk
    : > "$CALLS"
    local envs=(HOME="$H" PATH="$p" CODE_SIGN_CLONE_BASE="$SB/X" CLAUDE_TMP_DIR="$SB/ct"
        LOG_DIR="$SB/logs" DISABLE_TOOL_COMMANDS="${DT:-false}")
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
mkdir -p "$H/.npm/_cacache/content-v2"
touch "$H/.npm/_cacache/content-v2/blob"
NPM_HINT="sudo chown -R"
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
a_nolog "$OUTFILE" "$NPM_HINT" "dry-run：~/.npm 全屬於目前使用者，不印 chown 提示"
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
a_nolog "$OUTFILE" "$NPM_HINT" "apply：~/.npm 全屬於目前使用者，不印 chown 提示"
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


echo "[~/.npm 有不屬於目前使用者的檔案：印出 chown 提示]"
# 假 id：-u／-g 回傳別的 uid／gid，其他參數交給真的 id。沙盒裡的檔案都屬於真實 uid，
# 對 script 來說就全部「不屬於目前使用者」
OTHER_ID="$SB/other-id"
mkdir -p "$OTHER_ID"
cat > "$OTHER_ID/id" <<'EOS'
#!/bin/bash
case "$*" in
    -u) echo 424242 ;;
    -g) echo 4343 ;;
    *)  exec /usr/bin/id "$@" ;;
esac
EOS
chmod +x "$OTHER_ID/id"
a_eq "$(env -i PATH="$OTHER_ID:$TPATH" /bin/bash -c 'command -v id; id -u; id -g' | tr '\n' ' ')" "$OTHER_ID/id 424242 4343 " "假 id 在 PATH 最前面，回傳別的 uid／gid"
[ "$(id -u)" != 424242 ] || die "真實 uid 剛好是 424242，假 id 無法模擬別的使用者"
NPM_FIX="請自己執行：sudo chown -R 424242:4343 ~/.npm"
NPM_DESC="npm cache；有不屬於你的檔案，見上方 WARN 的 chown 提示"
rm -rf "${H:?}/.npm"
mkdir -p "$H/.npm/_cacache/content-v2" "$H/.npm/_cacache/index-v5"
touch "$H/.npm/_cacache/content-v2/blob" "$H/.npm/_cacache/index-v5/entry"

OUTFILE="$SB/npm-dry.txt"
XPATH="$OTHER_ID" run_tools --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "dry-run exit 0"
# 假 id 下 ~/.npm 裡每一項都不屬於目前使用者；find 最先檢查起點 ~/.npm 本身，所以只列一個時必定是它，
# 與遍歷順序無關。-quit 失效時路徑後面會接換行與其他項目，WARN 就不再是「例如 ~/.npm），」
a_log "$OUTFILE" "[WARN] npm 的目錄 ~/.npm 底下有不屬於你的檔案（例如 $H/.npm），通常是" "dry-run：WARN 只列出一個路徑（第一個不屬於目前使用者的 ~/.npm）"
a_nolog "$OUTFILE" "content-v2/blob" "dry-run：WARN 沒有列出第二個檔案 content-v2/blob"
a_nolog "$OUTFILE" "index-v5/entry" "dry-run：WARN 沒有列出第二個檔案 index-v5/entry"
a_log "$OUTFILE" "通常是以前用 sudo 執行過 npm 留下的；不修的話 npm cache clean 會在這些檔案上失敗（EACCES）" "dry-run：WARN 說明原因與不修的後果"
a_logend "$OUTFILE" "$NPM_FIX" "dry-run：chown 指令展開成實際的 uid:gid"
a_log "$OUTFILE" "[DRY-RUN] 會執行 \`npm cache clean --force\` 清除 ${NPM_DESC}" "dry-run：仍列出 npm cache clean"
a_count "$OUTFILE" "sudo" 1 "dry-run：sudo 只出現在提示裡一次"
a_eq "$(calls | grep -c '^npm ')" 0 "dry-run：npm 沒被呼叫"

OUTFILE="$SB/npm-apply.txt"
XPATH="$OTHER_ID" preflight_flutter "$FL_WANT" --apply --include-caches
XPATH="$OTHER_ID" run_tools --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "apply exit 0"
a_logend "$OUTFILE" "$NPM_FIX" "apply：印出 chown 提示"
a_eq "$(calls | grep -cxF 'npm cache clean --force')" 1 "apply：npm cache clean --force 照樣執行"
a_log "$OUTFILE" "已執行 \`npm cache clean --force\`（${NPM_DESC}）" "apply：npm 的結果行帶上提示"

echo "[~/.npm 有不屬於目前使用者的檔案，npm 失敗：ERROR 指向提示、exit 1]"
FAIL_NPM="$SB/fail-npm"
mkdir -p "$FAIL_NPM"
cp "$OTHER_ID/id" "$FAIL_NPM/id"
printf '#!/bin/bash\necho "npm error code EACCES" >&2\nexit 1\n' > "$FAIL_NPM/npm"
chmod +x "$FAIL_NPM/npm"
OUTFILE="$SB/npm-fail.txt"
XPATH="$FAIL_NPM" preflight_flutter "$FL_WANT" --apply --include-caches
XPATH="$FAIL_NPM" run_tools --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 1 "npm 失敗：exit 1"
a_logend "$OUTFILE" "$NPM_FIX" "npm 失敗：仍印出 chown 提示"
a_log "$OUTFILE" "[ERROR] ✗ 指令失敗：\`npm cache clean --force\`（${NPM_DESC}）" "npm 失敗：ERROR 指向上方的 chown 提示"

echo "[DISABLE_TOOL_COMMANDS=true：仍檢查並提示]"
OUTFILE="$SB/npm-disabled.txt"
DT=true XPATH="$OTHER_ID" run_tools --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_logend "$OUTFILE" "$NPM_FIX" "DISABLE_TOOL_COMMANDS=true：仍印出 chown 提示"
a_log "$OUTFILE" "略過（DISABLE_TOOL_COMMANDS）：不執行 npm cache clean --force" "DISABLE_TOOL_COMMANDS=true：npm cache clean 不執行"
a_eq "$(calls)" "" "DISABLE_TOOL_COMMANDS=true：沒有任何外部指令被呼叫"

echo "[沒有 ~/.npm：不檢查、不報錯]"
rm -rf "${H:?}/.npm"
OUTFILE="$SB/npm-none.txt"
XPATH="$OTHER_ID" run_tools --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_nolog "$OUTFILE" "$NPM_HINT" "沒有 ~/.npm：不印 chown 提示"
a_nolog "$OUTFILE" "No such file" "沒有 ~/.npm：沒有找不到檔案的錯誤"
a_nolog "$OUTFILE" "[ERROR]" "沒有 ~/.npm：沒有 ERROR"

echo "[~/.npm 屬於目前使用者，深層有 root 擁有的檔案：WARN 指向那個檔案]"
# 真實情況是 ~/.npm 本身屬於使用者，root 擁有的 tarball 藏在 _cacache 深處。這個案例用真實的 id（不設 XPATH），
# 用 hard link 在沙盒裡做出真的 root 擁有檔案：/private/etc/hosts 連到 ~/.npm/_cacache/index-v5/aa/root-entry
# （第 4 層；find 只查起點或只往下一層都抓不到）。
# 安全：這是 hard link，刪除只會移除連結這個名字；原檔擁有者是 root，本來就刪不到原檔。
#   - 只跑 dry-run，不跑 --apply；script 本身也不刪 ~/.npm/_cacache（只交給 npm cache clean，而這裡的 npm 是假的）
#   - 案例結束時明確 rm -f 連結（先過 sb_guard），不靠 sb_cleanup 的 rm -rf；中途中止時 EXIT trap 也先刪連結
#   - ln 失敗（例如暫存目錄與 /private/etc 不在同一個 volume）時只略過這個案例，不算 FAIL
ROOT_SRC="/private/etc/hosts"
ROOT_LINK="$H/.npm/_cacache/index-v5/aa/root-entry"
rm_root_link() {
    sb_guard "$ROOT_LINK"
    rm -f "$ROOT_LINK"
}
sb_guard "$H/.npm"
rm -rf "${H:?}/.npm"
mkdir -p "$H/.npm/_cacache/index-v5/aa" "$H/.npm/_cacache/content-v2"
touch "$H/.npm/_cacache/content-v2/mine"
sb_guard "$ROOT_LINK"
trap 'rm_root_link; sb_cleanup' EXIT
src_links=$(/usr/bin/stat -f %l "$ROOT_SRC" 2>/dev/null)
if ! ln_err=$(/bin/ln "$ROOT_SRC" "$ROOT_LINK" 2>&1); then
    skip "無法在沙盒裡 hard link ${ROOT_SRC}（${ln_err}），略過「~/.npm 深層有 root 擁有的檔案」案例"
else
    a_eq "$(/usr/bin/stat -f %Su "$ROOT_LINK")" root "hard link 的擁有者是 root"
    a_eq "$(/usr/bin/stat -f %u "$H/.npm")" "$(id -u)" "沙盒的 ~/.npm 本身屬於目前使用者"
    OUTFILE="$SB/npm-nested.txt"
    run_tools --include-caches > "$OUTFILE" 2>&1
    a_eq "$?" 0 "dry-run exit 0"
    a_log "$OUTFILE" "[WARN] npm 的目錄 ~/.npm 底下有不屬於你的檔案（例如 ${ROOT_LINK}），通常是" "dry-run：WARN 的例子是深層的 root-entry"
    a_nolog "$OUTFILE" "（例如 $H/.npm）" "dry-run：WARN 的例子不是 ~/.npm 本身"
    a_nolog "$OUTFILE" "content-v2/mine" "dry-run：WARN 沒有列出屬於目前使用者的檔案"
    a_logend "$OUTFILE" "請自己執行：sudo chown -R $(id -u):$(id -g) ~/.npm" "dry-run：chown 指令用真實的 uid:gid"
    a_eq "$(calls | grep -c '^npm ')" 0 "dry-run：npm 沒被呼叫"
fi
rm_root_link
trap sb_cleanup EXIT
a_gone "$ROOT_LINK" "hard link 已移除"
a_eq "$(/usr/bin/stat -f %l "$ROOT_SRC" 2>/dev/null)" "$src_links" "原檔 $ROOT_SRC 的連結數回到原值"

finish
