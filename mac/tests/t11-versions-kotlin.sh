#!/bin/bash
# B 級的 Kotlin／Android 項目：keep_newest_versions 每組前綴只留最新版（.konan、Android Studio 快取），
# 認不出版本的名稱（含 -RC1、-Beta2 這類結尾是數字的預發行版）與 symlink 一律保留；擁有者在跑時跳過。
# Kotlin LSP workspace 索引只清整個目錄 14 天內都沒有更新的，LSP 在跑時整項跳過。
# 以及 A 級的只報告項目（AVD、Claude Code／Codex 對話紀錄）不刪任何東西。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin

H="$SB/h"; mkdir -p "$H"
K="$H/.konan"
G="$H/Library/Caches/Google"
WS="$H/Library/Caches/JetBrains/IntelliJServer/workspaces"
setup() {
    mkdir -p "$K/kotlin-native-prebuilt-macos-aarch64-1.9.23/bin" "$K/kotlin-native-prebuilt-macos-aarch64-1.10.1/bin" \
        "$K/kotlin-native-prebuilt-macos-aarch64-2.0.0/bin" "$K/kotlin-native-prebuilt-macos-x86_64-1.9.23/bin" \
        "$K/kotlin-native-prebuilt-macos-x86_64-1.8.0/bin" "$K/kotlin-native-prebuilt-macos-x86_64-1.10.0/bin" "$K/kotlin-native-prebuilt-macos-aarch64-2.1.0-RC/bin" \
        "$K/kotlin-native-prebuilt-macos-aarch64-2.0.20-Beta1/bin" "$K/kotlin-native-prebuilt-macos-aarch64-2.0.20-Beta2/bin" \
        "$K/kotlin-native-prebuilt-macos-aarch64-2.2.0-dev-1234/bin" "$K/kotlin-native-prebuilt-macos-aarch64-2.2.0-dev-1300/bin" \
        "$K/dependencies/llvm" "$SB/elsewhere/kotlin-native-prebuilt-macos-aarch64-0.9.0"
    ln -sfn "$SB/elsewhere/kotlin-native-prebuilt-macos-aarch64-0.9.0" "$K/kotlin-native-prebuilt-macos-aarch64-0.9.0"
    mkdir -p "$G/AndroidStudio2024.3.2/c" "$G/AndroidStudio2026.1.1/c" "$G/AndroidStudioPreview2026.1/c" "$G/AndroidStudioPreview2025.3/c" "$G/DriveFS/c"
    # old：整個目錄 15 天沒動；recent：深層檔案 13 天前更新；deep：只有深層檔案今天更新，第一層目錄是 30 天前
    mkdir -p "$WS/old/index/kotlin-server" "$WS/recent/index/kotlin-server" "$WS/deep/index/kotlin-server"
    touch "$WS/old/index/kotlin-server/f" "$WS/recent/index/kotlin-server/f" "$WS/deep/index/kotlin-server/f"
    ago 15d "$WS/old/index/kotlin-server/f" "$WS/old/index/kotlin-server" "$WS/old/index" "$WS/old"
    ago 13d "$WS/recent/index/kotlin-server/f"
    ago 15d "$WS/recent/index/kotlin-server" "$WS/recent/index" "$WS/recent"
    ago 30d "$WS/deep/index/kotlin-server" "$WS/deep/index" "$WS/deep"
    mkdir -p "$H/.android/avd/Pixel_10.avd" "$H/.claude/projects/p" "$H/.codex/sessions/2026"
    printf 'x' > "$H/.android/avd/Pixel_10.avd/userdata-qemu.img.qcow2"
}

echo "[dry-run 不刪]"
setup
OUTFILE="$SB/dry.txt"
run_script "$H" --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "dry-run exit 0"
a_exists "$K/kotlin-native-prebuilt-macos-aarch64-1.9.23" "dry-run：舊 Kotlin/Native 保留"
a_exists "$G/AndroidStudio2024.3.2" "dry-run：舊 Android Studio 快取保留"
a_exists "$WS/old" "dry-run：舊 workspace 索引保留"
if any_real_busy gradle_daemon kotlin_daemon android_studio intellij; then
    skip "真實機器上 Gradle／Android Studio 在跑，略過 dry-run 的 Kotlin/Native log 斷言"
else
    a_log "$OUTFILE" "[DRY-RUN] 會清除 Kotlin/Native 工具鏈 舊版本 kotlin-native-prebuilt-macos-aarch64-1.9.23" "dry-run log：列出舊 Kotlin/Native"
fi

echo "[apply]"
OUTFILE="$SB/apply.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "apply exit 0"
if any_real_busy gradle_daemon kotlin_daemon android_studio intellij; then
    skip "真實機器上 Gradle／Android Studio 在跑，略過 Kotlin/Native 斷言"
    a_exists "$K/kotlin-native-prebuilt-macos-aarch64-1.9.23" "擁有者在跑：舊 Kotlin/Native 保留"
else
    a_gone "$K/kotlin-native-prebuilt-macos-aarch64-1.9.23" "Kotlin/Native aarch64 1.9.23 刪除"
    a_gone "$K/kotlin-native-prebuilt-macos-aarch64-1.10.1" "Kotlin/Native aarch64 1.10.1 刪除（依版本排序，不是字串排序）"
    a_exists "$K/kotlin-native-prebuilt-macos-aarch64-2.0.0" "aarch64 最新版 2.0.0 保留"
    a_exists "$K/kotlin-native-prebuilt-macos-x86_64-1.10.0" "x86_64 是另一組，最新版 1.10.0 保留（字串排序會選 1.9.23）"
    a_gone "$K/kotlin-native-prebuilt-macos-x86_64-1.9.23" "x86_64 舊版 1.9.23 刪除"
    a_gone "$K/kotlin-native-prebuilt-macos-x86_64-1.8.0" "x86_64 舊版 1.8.0 刪除"
    a_exists "$K/kotlin-native-prebuilt-macos-aarch64-2.1.0-RC" "認不出版本（RC）保留"
    a_exists "$K/kotlin-native-prebuilt-macos-aarch64-2.0.20-Beta1" "預發行版 Beta1 保留（結尾數字不是版本）"
    a_exists "$K/kotlin-native-prebuilt-macos-aarch64-2.0.20-Beta2" "預發行版 Beta2 保留"
    a_exists "$K/kotlin-native-prebuilt-macos-aarch64-2.2.0-dev-1234" "預發行版 dev-1234 保留"
    a_exists "$K/dependencies/llvm" "dependencies 保留"
    a_exists "$K/kotlin-native-prebuilt-macos-aarch64-0.9.0" "symlink 本身保留"
    a_exists "$SB/elsewhere/kotlin-native-prebuilt-macos-aarch64-0.9.0" "symlink 指向的目錄保留"
    a_log "$OUTFILE" "Kotlin/Native 工具鏈：保留最新版 kotlin-native-prebuilt-macos-aarch64-2.0.0" "log：保留 aarch64 最新版"
    a_log "$OUTFILE" "Kotlin/Native 工具鏈：無法辨識版本，保留 kotlin-native-prebuilt-macos-aarch64-2.1.0-RC" "log：RC 無法辨識"
fi
if any_real_busy android_studio; then
    skip "真實機器上 Android Studio 在跑，略過 Android Studio 快取斷言"
    a_exists "$G/AndroidStudio2024.3.2" "擁有者在跑：舊 Android Studio 快取保留"
else
    a_gone "$G/AndroidStudio2024.3.2" "Android Studio 2024.3.2 快取刪除"
    a_exists "$G/AndroidStudio2026.1.1" "Android Studio 最新版快取保留"
    a_exists "$G/AndroidStudioPreview2026.1" "Preview 是另一組，最新版保留"
    a_gone "$G/AndroidStudioPreview2025.3" "Preview 舊版刪除"
fi
a_exists "$G/DriveFS/c" "Caches/Google 底下其他目錄不動"
if any_real_busy kotlin_lsp; then
    skip "真實機器上 Kotlin LSP 在跑，略過 workspace 索引斷言"
    a_exists "$WS/old" "擁有者在跑：舊 workspace 索引保留"
else
    a_gone "$WS/old" "15 天前的 workspace 索引刪除"
    a_exists "$WS/recent" "深層檔案 13 天前更新的 workspace 索引保留"
    a_exists "$WS/deep" "第一層目錄是舊的、深層檔案今天更新的 workspace 索引保留"
fi
a_exists "$H/.android/avd/Pixel_10.avd/userdata-qemu.img.qcow2" "只報告：AVD 不刪"
a_exists "$H/.claude/projects/p" "只報告：Claude Code 對話紀錄不刪"
a_exists "$H/.codex/sessions/2026" "只報告：Codex 對話紀錄不刪"
a_log "$OUTFILE" "[只報告] Android 模擬器 Pixel_10 — " "log：報告 AVD"
a_log "$OUTFILE" "[只報告] Claude Code 對話紀錄 — " "log：報告 Claude Code 對話紀錄"
a_log "$OUTFILE" "[只報告] Codex 對話紀錄 — " "log：報告 Codex 對話紀錄"

echo "[Kotlin LSP 在跑]"
setup
bash -c 'exec -a "/opt/kotlin-lsp/bin/intellij-''server --stdio" sleep 300' & P1=$!
BG_PIDS="$P1"
sleep 1
a_eq "$(pgrep -f 'intellij-''server' | grep -c -x "$P1")" 1 "pgrep -f intellij-server 看得到假 LSP"
OUTFILE="$SB/apply-lsp.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "[apply lsp] exit 0"
a_exists "$WS/old" "LSP 在跑：舊 workspace 索引保留"
a_log "$OUTFILE" "跳過 Kotlin LSP workspace 索引：Kotlin LSP 正在執行" "log：workspace 索引因 LSP 跳過"
kill "$P1" 2>/dev/null; wait 2>/dev/null; BG_PIDS=""

echo "[Kotlin compile daemon 在跑]"
setup
bash -c 'exec -a "java -cp x org.jetbrains.kotlin.daemon.KotlinCompile''Daemon" sleep 300' & P2=$!
BG_PIDS="$P2"
sleep 1
OUTFILE="$SB/apply-kdaemon.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "[apply kotlin daemon] exit 0"
a_exists "$K/kotlin-native-prebuilt-macos-aarch64-1.9.23" "Kotlin compile daemon 在跑：舊 Kotlin/Native 保留"
a_log "$OUTFILE" "跳過 Kotlin/Native 舊版本：Kotlin compile daemon 正在執行" "log：Kotlin/Native 因 Kotlin compile daemon 跳過"
kill "$P2" 2>/dev/null; wait 2>/dev/null; BG_PIDS=""

echo "[Android Studio Preview 在跑]"
setup
bash -c 'exec -a "/Applications/Android Studio Pre''view.app/Contents/MacOS/studio" sleep 300' & P3=$!
BG_PIDS="$P3"
sleep 1
OUTFILE="$SB/apply-preview.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "[apply preview] exit 0"
a_exists "$G/AndroidStudioPreview2025.3" "Preview 在跑：舊 Android Studio 快取保留"
a_log "$OUTFILE" "跳過 Android Studio 舊版本快取：Android Studio 正在執行" "log：Android Studio 快取因 Preview 跳過"
kill "$P3" 2>/dev/null; wait 2>/dev/null; BG_PIDS=""

finish
