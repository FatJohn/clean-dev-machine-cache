#!/bin/bash
# 擁有者 app 判斷：用假 process（叫 Xcode 的小程式、exec -a 偽裝的 GradleDaemon／flutter_tools／
# Dart language server）讓對應項目在 dry-run 與 --apply 都被跳過；假 process 結束後同一批項目會被清掉。
# Flutter SDK fixture 有 bin/flutter 與 bin/internal，確保走到「擁有者跳過」而不是被 SDK 驗證先擋下。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin

if ! command -v cc >/dev/null 2>&1; then
    skip "沒有 cc（Xcode Command Line Tools），無法編出名叫 Xcode 的假 process；直接複製 /bin/sleep 會被 macOS kill"
    finish
fi
mkdir -p "$SB/pbin"
printf '#include <stdlib.h>\n#include <unistd.h>\nint main(int c, char **v) { sleep(c > 1 ? atoi(v[1]) : 300); return 0; }\n' > "$SB/pbin/fake.c"
if ! cc -o "$SB/pbin/Xcode" "$SB/pbin/fake.c" 2> "$SB/pbin/cc.err"; then
    skip "cc 編譯失敗：$(head -1 "$SB/pbin/cc.err")"
    finish
fi

H="$SB/h"; mkdir -p "$H"
FS="$SB/fsdk"
setup() {
    mkdir -p "$H/Library/Developer/Xcode/DerivedData/p1" "$H/Library/Developer/Xcode/Products/x" \
        "$H/Library/Caches/com.apple.dt.Xcode/c" "$H/Library/Caches/org.swift.swiftpm/s" \
        "$H/Library/Developer/Xcode/iOS DeviceSupport/old"
    old "$H/Library/Developer/Xcode/iOS DeviceSupport/old"
    mkdir -p "$H/.gradle/caches/c" "$H/.pub-cache/hosted/h" "$H/.pub-cache/_temp/d" "$FS/bin/cache/c"
    mkflutter_sdk "$FS"
}
ITEMS="DerivedData/p1 Products XcodeCache SwiftPM DevSupportOld GradleCaches PubHosted PubTemp FlutterCache"
state() {
    local p
    for p in "$H/Library/Developer/Xcode/DerivedData/p1" "$H/Library/Developer/Xcode/Products" \
        "$H/Library/Caches/com.apple.dt.Xcode" "$H/Library/Caches/org.swift.swiftpm" \
        "$H/Library/Developer/Xcode/iOS DeviceSupport/old" "$H/.gradle/caches" "$H/.pub-cache/hosted" \
        "$H/.pub-cache/_temp" "$FS/bin/cache"; do
        if [ -e "$p" ]; then printf 1; else printf 0; fi
    done
}

setup
"$SB/pbin/Xcode" 300 & P1=$!
bash -c 'exec -a "java -cp x org.gradle.launcher.daemon.bootstrap.Gradle""Daemon 8.9" sleep 300' & P2=$!
bash -c 'exec -a "/sdk/bin/cache/dart-sdk/bin/dart /sdk/bin/cache/flutter_""tools.snapshot run" sleep 300' & P3=$!
BG_PIDS="$P1 $P2 $P3"
sleep 1
a_eq "$(pgrep -x Xcode | grep -c -x "$P1")" 1 "pgrep -x Xcode 看得到假 Xcode"
a_eq "$(pgrep -f 'Gradle''Daemon' | grep -c -x "$P2")" 1 "pgrep -f GradleDaemon 看得到假 daemon"
a_eq "$(pgrep -f 'flutter_''tools' | grep -c -x "$P3")" 1 "pgrep -f flutter_tools 看得到假 flutter"

for mode in dry apply; do
    a=(); [ "$mode" = apply ] && a=(--apply)
    OUTFILE="$SB/$mode-busy.txt"
    FR="$FS" run_personal "$H" ${a[@]+"${a[@]}"} --include-caches > "$OUTFILE" 2>&1
    a_eq "$?" 0 "[$mode busy] exit 0"
    a_eq "$(state)" 111111111 "[$mode busy] ${ITEMS} 全部保留"
    a_log "$OUTFILE" "跳過 Xcode DerivedData：Xcode 正在執行" "[$mode busy] log：DerivedData 因 Xcode 跳過"
    a_log "$OUTFILE" "跳過 Xcode Products：Xcode 正在執行" "[$mode busy] log：Products 因 Xcode 跳過"
    a_log "$OUTFILE" "跳過 SwiftPM 快取：Xcode 正在執行" "[$mode busy] log：SwiftPM 因 Xcode 跳過"
    a_log "$OUTFILE" "跳過 iOS DeviceSupport：Xcode 正在執行" "[$mode busy] log：DeviceSupport 因 Xcode 跳過"
    a_log "$OUTFILE" "跳過 Gradle caches／daemon／.tmp：" "[$mode busy] log：Gradle 跳過"
    a_log "$OUTFILE" "跳過 pub cache：" "[$mode busy] log：pub cache 跳過"
    a_log "$OUTFILE" "跳過 Flutter SDK artifacts：flutter 指令（flutter_tools） 正在執行" "[$mode busy] log：Flutter SDK artifacts 因 flutter_tools 跳過"
    a_nolog "$OUTFILE" "FLUTTER_ROOT 不像 Flutter SDK" "[$mode busy] Flutter SDK 驗證有通過"
done

kill "$P1" "$P2" "$P3" 2>/dev/null; wait 2>/dev/null; BG_PIDS=""
a_eq "$(pgrep -x Xcode | grep -c -x "$P1")" 0 "假 Xcode 已結束"

echo "[假 process 結束後的對照組]"
OUTFILE="$SB/apply-idle.txt"
FR="$FS" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "[apply idle] exit 0"
a_cleaned gone "$H/Library/Developer/Xcode/DerivedData/p1" "Xcode DerivedData" xcode
a_cleaned gone "$H/Library/Developer/Xcode/Products" "Xcode Products" xcode
a_cleaned gone "$H/Library/Caches/com.apple.dt.Xcode" "Xcode 應用程式快取" xcode
a_cleaned gone "$H/Library/Caches/org.swift.swiftpm" "SwiftPM 快取" xcode
a_cleaned gone "$H/Library/Developer/Xcode/iOS DeviceSupport/old" "iOS DeviceSupport" xcode
if any_real_busy android_studio gradle_daemon emulator; then
    skip "真實機器上 Gradle 擁有者在跑，略過 Gradle 對照組"
else
    a_gone "$H/.gradle/caches" "Gradle caches 刪除"
fi
if any_real_busy flutter_tool dart_analyzer; then
    skip "真實機器上 flutter_tools／Dart analysis server 在跑，略過 pub cache 與 Flutter SDK 對照組"
else
    a_gone "$H/.pub-cache/hosted" "pub hosted 刪除"
    a_gone "$H/.pub-cache/_temp" "pub _temp 刪除"
    a_gone "$FS/bin/cache" "Flutter SDK bin/cache 刪除"
    a_log "$OUTFILE" "已清除 Flutter SDK artifacts" "log：已清除 Flutter SDK artifacts"
fi

echo "[Dart language server 在跑]"
setup
bash -c 'exec -a "/sdk/bin/cache/dart-sdk/bin/dart language-server --protocol=lsp" sleep 300' & P4=$!
BG_PIDS="$P4"
sleep 1
OUTFILE="$SB/apply-dart.txt"
FR="$FS" run_personal "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "[apply dart-ls] exit 0"
a_exists "$H/.pub-cache/hosted" "pub hosted 保留"
a_exists "$H/.pub-cache/_temp" "pub _temp 保留"
a_exists "$FS/bin/cache" "Flutter SDK bin/cache 保留"
a_log "$OUTFILE" "跳過 pub cache：Dart analysis server 正在執行" "log：pub cache 因 Dart analysis server 跳過"
a_log "$OUTFILE" "跳過 Flutter SDK artifacts：Dart analysis server 正在執行" "log：Flutter SDK artifacts 因 Dart analysis server 跳過"
kill "$P4" 2>/dev/null; wait 2>/dev/null; BG_PIDS=""

finish
