#!/bin/bash
# --apply --include-caches --projects 全跑一次：各級項目的刪除／保留、symlink 一律略過、
# 沙盒外的目標不被動到、DISABLE_TOOL_COMMANDS 下不呼叫任何外部工具、pub cache 走路徑清理。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin
H="$SB/home dir"; mkdir -p "$H"
OUT="$SB/outside"

# 沙盒外（相對於假 HOME）的目標：只能經由 symlink 被碰到
for d in dd hosted fcache nm; do
    mkdir -p "$OUT/$d/sub dir"; echo x > "$OUT/$d/sub dir/f"; echo y > "$OUT/$d/top file"
done
old "$OUT/nm"; echo {} > "$OUT/nm/.package-lock.json"; old "$OUT/nm/.package-lock.json"

# ---- A 級 ----
mkdir -p "$H/Library/Developer/Xcode"
ln -s "$OUT/dd" "$H/Library/Developer/Xcode/DerivedData"
mkdir -p "$H/Library/Developer/Xcode/Products/My App" "$H/Library/Developer/Xcode/Archives/keep me" \
    "$H/Library/Caches/com.apple.dt.Xcode/a b" "$H/Library/Logs/CoreSimulator/s p"
touch "$H/Library/Developer/Xcode/Products/My App/x" "$H/Library/Logs/CoreSimulator/s p/log"
mkdir -p "$SB/X/com.google.Chrome.code_sign_clone/c 1" "$SB/X/com.microsoft.edgemac.code_sign_clone/e 1" "$SB/X/other"
R="$H/.codex/packages/standalone/releases"
mkdir -p "$R/0.8.0" "$R/0.9.0" "$R/0.10.0"
ln -s "$R/0.9.0" "$H/.codex/packages/standalone/current"
mkdir -p "$SB/claude tmp/proj a/old sess" "$SB/claude tmp/proj a/new sess" "$SB/claude tmp/proj b/old2"
old "$SB/claude tmp/proj a/old sess" "$SB/claude tmp/proj b/old2"
CR="$H/.cache/codex-runtimes"
mkdir -p "$CR/codex-runtime-install-old" "$CR/codex-runtime-install-new" "$CR/other-old"
old "$CR/codex-runtime-install-old" "$CR/other-old"

# ---- B 級 ----
mkdir -p "$H/.npm/_logs" "$H/.npm/_cacache/x" "$H/Library/Caches/Yarn/y" "$H/.yarn/berry/cache/z" "$H/.bun/install/cache/b"
mkdir -p "$H/.gradle/caches/c" "$H/.gradle/daemon/d" "$H/.gradle/.tmp/t" "$H/.gradle/wrapper/dists/w"
echo signing > "$H/.gradle/gradle.properties"
mkdir -p "$H/Library/Caches/CocoaPods/p" "$H/Library/Caches/org.swift.swiftpm/s" "$H/.dartServer/d"
P="$H/.pub-cache"
mkdir -p "$P/git/g" "$P/.tmp/t" "$P/_temp/dirAbCd" "$P/hosted-hashes/pub.dev" "$P/bin" "$P/global_packages/melos" "$P/active_roots/00"
touch "$P/hosted-hashes/pub.dev/args-2.7.0.sha256" "$P/bin/melos"
ln -s "$OUT/hosted" "$P/hosted"
FS="$SB/flutter sdk"; mkflutter_sdk "$FS"
ln -s "$OUT/fcache" "$FS/bin/cache"
DS="$H/Library/Developer/Xcode/iOS DeviceSupport"
mkdir -p "$DS/old 1" "$DS/new 1"; old "$DS/old 1"
mkdir -p "$H/Library/Caches/Google/Chrome/cc" "$H/Library/Caches/Microsoft Edge/ec" "$H/Library/Caches/Cursor/cu" \
    "$H/Library/Caches/ms-playwright/chromium-1000" "$H/Library/Caches/ms-playwright/chromium-1100"

# ---- C 級 ----
PR="$SB/projects"
mkdir -p "$PR/app one/build/x"; touch "$PR/app one/pubspec.yaml"; old "$PR/app one/build"
mkdir -p "$PR/app fresh/build/x"; touch "$PR/app fresh/pubspec.yaml"
mkdir -p "$PR/web two/node_modules/dep"; touch "$PR/web two/package.json"
echo {} > "$PR/web two/node_modules/.package-lock.json"; old "$PR/web two/node_modules/.package-lock.json"
mkdir -p "$PR/web fresh/node_modules/dep/node_modules/z" "$PR/web fresh/node_modules/dep/build"
touch "$PR/web fresh/package.json" "$PR/web fresh/node_modules/dep/package.json" "$PR/web fresh/node_modules/dep/pubspec.yaml"
old "$PR/web fresh/node_modules/dep/node_modules" "$PR/web fresh/node_modules/dep/build"
mkdir -p "$PR/gitproj/.git/hooks/node_modules/q"; touch "$PR/gitproj/.git/hooks/package.json"; old "$PR/gitproj/.git/hooks/node_modules"
mkdir -p "$PR/linked"; touch "$PR/linked/package.json"; ln -s "$OUT/nm" "$PR/linked/node_modules"; old "$PR/linked/node_modules"

( cd "$OUT" && find . | sort ) > "$SB/out-before.lst"

OUTFILE="$SB/run.txt"
FR="$FS" run_personal "$H" --apply --include-caches --projects "$PR" > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit code 0"
a_nolog "$OUTFILE" "[ERROR]" "沒有 ERROR"

( cd "$OUT" && find . | sort ) > "$SB/out-after.lst"
if cmp -s "$SB/out-before.lst" "$SB/out-after.lst"; then pass "沙盒外目標完全沒變"; else fail "沙盒外目標被動到：$(diff "$SB/out-before.lst" "$SB/out-after.lst" | tr '\n' ' ')"; fi
if [ -s "$SB/calls.log" ]; then fail "DISABLE_TOOL_COMMANDS 下呼叫了外部工具：$(tr '\n' ';' < "$SB/calls.log")"; else pass "沒有呼叫任何外部工具"; fi

echo "[A 級]"
a_exists "$H/Library/Developer/Xcode/DerivedData" "DerivedData symlink 保留"
a_log "$OUTFILE" "是 symlink，為安全起見略過：Xcode DerivedData" "log：DerivedData 是 symlink 略過"
a_cleaned gone "$H/Library/Developer/Xcode/Products" "Xcode Products" xcode
a_cleaned gone "$H/Library/Caches/com.apple.dt.Xcode" "Xcode 應用程式快取" xcode
a_cleaned empty "$H/Library/Logs/CoreSimulator" "CoreSimulator logs" xcode simulator
a_exists "$H/Library/Developer/Xcode/Archives/keep me" "Xcode Archives 不碰"
a_cleaned empty "$SB/X/com.google.Chrome.code_sign_clone" "Chrome code_sign_clone" chrome
a_cleaned empty "$SB/X/com.microsoft.edgemac.code_sign_clone" "Edge code_sign_clone" edge
a_exists "$SB/X/other" "code_sign_clone 以外的目錄不碰"
a_gone "$R/0.8.0" "Codex 舊版 0.8.0 刪除"
a_exists "$R/0.9.0" "Codex current 0.9.0 保留"
a_exists "$R/0.10.0" "Codex 最新 0.10.0 保留"
a_log "$OUTFILE" "Codex CLI：保留 current=0.9.0、最新=0.10.0" "log：Codex 保留 current 與最新"
a_gone "$SB/claude tmp/proj a/old sess" "Claude 暫存 7 天前的 session 刪除"
a_exists "$SB/claude tmp/proj a/new sess" "Claude 暫存新 session 保留"
a_gone "$SB/claude tmp/proj b/old2" "Claude 暫存另一專案的舊 session 刪除"
a_exists "$SB/claude tmp/proj b" "Claude 暫存專案目錄本身保留"
a_gone "$CR/codex-runtime-install-old" "codex-runtime-install 舊暫存刪除"
a_exists "$CR/codex-runtime-install-new" "codex-runtime-install 新暫存保留"
a_exists "$CR/other-old" "不符合命名的舊目錄保留"

echo "[B 級]"
a_exists "$H/.npm/_cacache/x" "npm _cacache 保留（DISABLE 下不跑 npm cache clean）"
a_log "$OUTFILE" "略過（DISABLE_TOOL_COMMANDS）：不執行 npm cache clean --force" "log：npm 因 DISABLE 略過"
a_gone "$H/.npm/_logs" "npm _logs 刪除"
a_gone "$H/Library/Caches/Yarn" "Yarn v1 快取刪除"
a_gone "$H/.yarn/berry/cache" "Yarn Berry 快取刪除"
a_gone "$H/.bun/install/cache" "Bun 快取刪除"
if any_real_busy android_studio gradle_daemon emulator; then
    a_exists "$H/.gradle/caches" "真實機器上 Gradle 擁有者在跑，Gradle caches 保留"
    a_log "$OUTFILE" "跳過 Gradle caches／daemon／.tmp：" "log：Gradle 跳過"
else
    a_gone "$H/.gradle/caches" "Gradle caches 刪除"
    a_gone "$H/.gradle/daemon" "Gradle daemon 刪除"
    a_gone "$H/.gradle/.tmp" "Gradle .tmp 刪除"
fi
a_exists "$H/.gradle/wrapper/dists/w" "Gradle wrapper 保留"
a_exists "$H/.gradle/gradle.properties" "gradle.properties 保留"
a_gone "$H/Library/Caches/CocoaPods" "CocoaPods 快取刪除"
a_cleaned gone "$H/Library/Caches/org.swift.swiftpm" "SwiftPM 快取" xcode
a_gone "$H/.dartServer" "假 HOME 的 .dartServer 刪除"
if any_real_busy flutter_tool dart_analyzer; then
    skip "真實機器上 flutter_tools／Dart analysis server 在跑，pub cache 與 Flutter SDK 項目改由 t05 驗證"
    a_log "$OUTFILE" "跳過 pub cache：" "log：pub cache 跳過"
else
    a_log "$OUTFILE" "DISABLE_TOOL_COMMANDS=true，不執行 dart pub cache gc，改用路徑清理" "log：pub cache 走路徑清理"
    a_exists "$P/hosted" "pub hosted symlink 保留"
    a_log "$OUTFILE" "是 symlink，為安全起見略過：pub cache hosted 套件" "log：pub hosted 是 symlink 略過"
    a_gone "$P/git" "pub git 刪除"
    a_gone "$P/.tmp" "pub .tmp 刪除"
    a_gone "$P/_temp" "pub _temp 刪除"
    a_gone "$P/hosted-hashes" "pub hosted-hashes 刪除"
    a_exists "$P/bin/melos" "pub bin 保留"
    a_exists "$P/global_packages/melos" "pub global_packages 保留"
    a_exists "$P/active_roots" "pub active_roots 保留"
    a_exists "$FS/bin/cache" "Flutter bin/cache symlink 保留"
    a_log "$OUTFILE" "是 symlink，為安全起見略過：Flutter SDK artifacts" "log：Flutter bin/cache 是 symlink 略過（SDK 驗證有通過）"
fi
a_cleaned gone "$DS/old 1" "iOS DeviceSupport" xcode
a_exists "$DS/new 1" "iOS DeviceSupport 90 天內保留"
a_cleaned empty "$H/Library/Caches/Google/Chrome" "Chrome 快取" chrome
a_cleaned empty "$H/Library/Caches/Microsoft Edge" "Edge 快取" edge
a_cleaned empty "$H/Library/Caches/Cursor" "Cursor 快取" cursor
a_exists "$H/Library/Caches/ms-playwright/chromium-1000" "Playwright 只報告不刪"
a_log "$OUTFILE" "[只報告] Playwright 舊 revision：chromium-1000" "log：Playwright 舊 revision 只報告"

echo "[C 級]"
a_gone "$PR/app one/build" "久未更新的 Flutter build 刪除"
a_exists "$PR/app fresh/build/x" "新的 Flutter build 保留"
a_gone "$PR/web two/node_modules" "久未安裝的 node_modules 刪除"
a_exists "$PR/web fresh/node_modules/dep/node_modules/z" "node_modules 裡的巢狀 node_modules 不進去"
a_exists "$PR/web fresh/node_modules/dep/build" "node_modules 裡的 build 不進去"
a_exists "$PR/gitproj/.git/hooks/node_modules/q" "隱藏目錄不進去"
a_exists "$PR/linked/node_modules" "node_modules symlink 保留"
a_log "$OUTFILE" "是 symlink，為安全起見略過：node_modules" "log：node_modules symlink 略過"

finish
