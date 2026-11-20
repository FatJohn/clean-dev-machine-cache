#!/bin/bash
# D 級（--include-simulators）與 B 級的 Android 快取，DISABLE_TOOL_COMMANDS=true 的沙盒：
#   - 沒指定旗標時整級略過，AVD 不動
#   - dry-run 列出 AVD 與 system-images，什麼都不刪
#   - apply 清空 ~/.android/avd，保留 ~/.android 的其他東西與 system-images；iOS 模擬器因 DISABLE 整項略過、不呼叫 xcrun
# 會呼叫 xcrun 的 iOS 路徑（delete all、runtime delete、Booted 跳過、失敗）由 t10 用假 xcrun 驗證。
# 擁有者判斷改用沙盒裡的假 pgrep（run_script 的 PATH 以 $SB/fakebin 開頭）：$SB/busy 裡的每一行是一個
# 「在跑」的 pgrep pattern，命中才回 0。這樣不受真實機器上開著的 Android Studio／emulator 影響。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin
H="$SB/home dir"; mkdir -p "$H"
: > "$SB/busy"
cat > "$SB/fakebin/pgrep" <<EOS
#!/bin/bash
args="\$*"
while IFS= read -r p; do
    [ -n "\$p" ] || continue
    case "\$args" in *"\$p"*) exit 0 ;; esac
done < '$SB/busy'
exit 1
EOS
chmod +x "$SB/fakebin/pgrep"
a_eq "$(env -i PATH="$SB/fakebin:/usr/bin:/bin" /bin/bash -c 'command -v pgrep')" "$SB/fakebin/pgrep" "pgrep 解析到沙盒裡的假 pgrep"

mkavd() {
    rm -rf "${H:?}/.android" "${H:?}/Library/Android"
    mkdir -p "$H/.android/avd/Pixel 6.avd/snapshots/default_boot" "$H/Library/Android/sdk/system-images/android-35/x"
    echo ram > "$H/.android/avd/Pixel 6.avd/snapshots/default_boot/ram.bin"
    echo "path=$H/.android/avd/Pixel 6.avd" > "$H/.android/avd/Pixel 6.ini"
    echo k > "$H/.android/adbkey"
    mkdir -p "$H/Library/Developer/CoreSimulator/Devices/DEV-1/data"
}

echo "[沒有 --include-simulators：D 級略過]"
mkavd
OUTFILE="$SB/none.txt"
run_script "$H" --apply > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_log "$OUTFILE" "=== D 級：未指定 --include-simulators，略過 ===" "log：D 級略過"
a_exists "$H/.android/avd/Pixel 6.avd/snapshots/default_boot/ram.bin" "AVD 保留"

echo "[dry-run：列出 D 級項目，不刪]"
mkavd
OUTFILE="$SB/dry.txt"
run_script "$H" --include-simulators > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_log "$OUTFILE" "=== D 級：所有模擬器（含裡面的 app 與資料） ===" "log：D 級標題"
a_log "$OUTFILE" "[DRY-RUN] 會清除 Android 模擬器 AVD（含快照與模擬器內資料） — " "dry-run 列出 AVD"
a_log "$OUTFILE" "略過（DISABLE_TOOL_COMMANDS）：不執行 xcrun simctl list devices" "dry-run：DISABLE 下 iOS 模擬器整項略過"
a_log "$OUTFILE" "[只報告] Android system-images — " "dry-run 報告 system-images 大小"
a_exists "$H/.android/avd/Pixel 6.ini" "dry-run：AVD 還在"

echo "[apply：清空 AVD，其他保留]"
mkavd
OUTFILE="$SB/apply.txt"
run_script "$H" --apply --include-simulators > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_nolog "$OUTFILE" "[ERROR]" "沒有 ERROR"
a_empty_dir "$H/.android/avd" "AVD 目錄保留且清空（.avd 與 .ini 都刪）"
a_log "$OUTFILE" "已清除 Android 模擬器 AVD（含快照與模擬器內資料）" "log：已清除 AVD"
a_exists "$H/.android/adbkey" ".android/adbkey 保留"
a_exists "$H/Library/Android/sdk/system-images/android-35/x" "system-images 只報告不刪"
a_log "$OUTFILE" "略過（DISABLE_TOOL_COMMANDS）：不執行 xcrun simctl list devices、xcrun simctl delete all、xcrun simctl runtime delete" "DISABLE：iOS 模擬器整項略過"
a_exists "$H/Library/Developer/CoreSimulator/Devices/DEV-1/data" "不經 simctl 時不直接刪 CoreSimulator/Devices"
if [ -s "$SB/calls.log" ]; then fail "DISABLE_TOOL_COMMANDS 下呼叫了外部工具：$(tr '\n' ';' < "$SB/calls.log")"; else pass "沒有呼叫任何外部工具"; fi

for who in "qemu-system:Android emulator（qemu-system）" "Android Studio[^/]*:Android Studio"; do
    pat="${who%%:*}"; label="${who#*:}"
    echo "[擁有者在跑（${pat}）：AVD 跳過]"
    mkavd
    echo "$pat" > "$SB/busy"
    OUTFILE="$SB/busy.txt"
    run_script "$H" --apply --include-simulators > "$OUTFILE" 2>&1
    a_eq "$?" 0 "exit 0"
    a_exists "$H/.android/avd/Pixel 6.avd/snapshots/default_boot/ram.bin" "${label} 在跑：AVD 保留"
    a_log "$OUTFILE" "跳過 Android AVD：${label} 正在執行" "log：跳過 AVD（${label}）"
    : > "$SB/busy"
done

mkandroid_cache() {
    rm -rf "${H:?}/.android/cache" "${H:?}/.android/build-cache" "${H:?}/Library/Caches/Google"
    mkdir -p "$H/.android/cache/c" "$H/.android/build-cache/b" "$H/Library/Caches/Google/AndroidStudio2025.1/caches/i" "$H/Library/Caches/Google/AndroidStudio2025.1/index/x" "$H/Library/Caches/Google/AndroidStudio2025.1/tmp/t" \
        "$H/Library/Caches/Google/AndroidStudio2025.1/LocalHistory/changes" "$H/Library/Caches/Google/AndroidStudio2025.1/plugins/p" \
        "$H/Library/Caches/Google/AndroidStudio2024.3/o"
}

echo "[B 級 Android Studio 快取 dry-run：舊版本只由 keep_newest_versions 列一次，不重複列為清空]"
mkavd; mkandroid_cache
OUTFILE="$SB/b-android-dry.txt"
run_script "$H" --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_count "$OUTFILE" "AndroidStudio2024.3" 1 "dry-run：舊版本 AndroidStudio2024.3 只出現一次"
a_log "$OUTFILE" "[DRY-RUN] 會清除 Android Studio 快取 舊版本 AndroidStudio2024.3 — " "dry-run：舊版本列為整個刪除"
a_log "$OUTFILE" "[DRY-RUN] 會清除 Android Studio 快取 AndroidStudio2025.1/caches — " "dry-run：最新版的 caches 列為清空"
a_nolog "$OUTFILE" "LocalHistory" "dry-run：LocalHistory 不列入"
a_exists "$H/Library/Caches/Google/AndroidStudio2024.3/o" "dry-run：舊版本還在"

echo "[B 級 Android 快取：擁有者沒在跑時清掉（同一個假 pgrep，不受真實機器影響）]"
mkavd; mkandroid_cache
OUTFILE="$SB/b-android.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_gone "$H/.android/cache" "Android SDK 快取刪除"
a_gone "$H/.android/build-cache" "Android build 快取刪除"
a_empty_dir "$H/Library/Caches/Google/AndroidStudio2025.1/caches" "Android Studio 最新版 caches 清空"
a_empty_dir "$H/Library/Caches/Google/AndroidStudio2025.1/index" "Android Studio 最新版 index 清空"
a_empty_dir "$H/Library/Caches/Google/AndroidStudio2025.1/tmp" "Android Studio 最新版 tmp 清空"
a_exists "$H/Library/Caches/Google/AndroidStudio2025.1/LocalHistory/changes" "Android Studio LocalHistory（本機修改歷史）保留"
a_exists "$H/Library/Caches/Google/AndroidStudio2025.1/plugins/p" "Android Studio 其他子目錄保留"
a_gone "$H/Library/Caches/Google/AndroidStudio2024.3" "Android Studio 舊版本快取整個刪除"
a_nolog "$OUTFILE" "[ERROR]" "沒有 ERROR"
a_exists "$H/.android/avd/Pixel 6.ini" "B 級不碰 AVD"
a_exists "$H/.android/adbkey" "B 級不碰 adbkey"

echo "[B 級 Android 快取：Android Studio 在跑時跳過]"
mkandroid_cache
echo "Android Studio[^/]*" > "$SB/busy"
OUTFILE="$SB/b-android-busy.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_exists "$H/.android/cache/c" "Android Studio 在跑：Android SDK 快取保留"
a_exists "$H/Library/Caches/Google/AndroidStudio2025.1/caches/i" "Android Studio 在跑：Android Studio 快取保留"
a_exists "$H/Library/Caches/Google/AndroidStudio2024.3/o" "Android Studio 在跑：舊版本快取保留"
a_log "$OUTFILE" "跳過 Android SDK／build 快取：Android Studio 正在執行" "log：跳過 Android SDK／build 快取"
a_log "$OUTFILE" "跳過 Android Studio 快取 AndroidStudio2025.1：Android Studio 正在執行" "log：跳過 Android Studio 快取"
: > "$SB/busy"

for who in "launchd_sim:開機中的模擬器（launchd_sim）" "xcodebuild:xcodebuild"; do
    pat="${who%%:*}"; label="${who#*:}"
    echo "[A 級 CoreSimulator 快取／XCTestDevices：${pat} 在跑時跳過（命令列的 xcodebuild test、headless 模擬器）]"
    mkdir -p "$H/Library/Developer/CoreSimulator/Caches/dyld/x" "$H/Library/Developer/XCTestDevices/AB-CD/data"
    echo "$pat" > "$SB/busy"
    OUTFILE="$SB/a-sim-busy.txt"
    run_script "$H" --apply > "$OUTFILE" 2>&1
    a_exists "$H/Library/Developer/CoreSimulator/Caches/dyld/x" "${label} 在跑：CoreSimulator 快取保留"
    a_exists "$H/Library/Developer/XCTestDevices/AB-CD/data" "${label} 在跑：XCTestDevices 保留"
    a_log "$OUTFILE" "跳過 XCTestDevices：${label} 正在執行" "log：跳過 XCTestDevices（${label}）"
    : > "$SB/busy"
done
echo "[A 級 CoreSimulator 快取／XCTestDevices：沒有擁有者在跑時清空]"
OUTFILE="$SB/a-sim.txt"
run_script "$H" --apply > "$OUTFILE" 2>&1
a_empty_dir "$H/Library/Developer/CoreSimulator/Caches" "CoreSimulator 快取清空"
a_empty_dir "$H/Library/Developer/XCTestDevices" "XCTestDevices 清空"

echo "[AVD 是 symlink：略過]"
mkavd
rm -rf "${H:?}/.android/avd"
mkdir -p "$SB/outside avd/x.avd"
ln -s "$SB/outside avd" "$H/.android/avd"
OUTFILE="$SB/link.txt"
run_script "$H" --apply --include-simulators > "$OUTFILE" 2>&1
a_exists "$SB/outside avd/x.avd" "symlink 指到的 AVD 不動"
a_exists "$H/.android/avd" "AVD symlink 本身保留"
a_log "$OUTFILE" "是 symlink，為安全起見略過：Android 模擬器 AVD" "log：AVD symlink 略過"

finish
