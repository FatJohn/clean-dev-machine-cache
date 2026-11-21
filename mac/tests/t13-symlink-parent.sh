#!/bin/bash
# 要清的路徑在 HOME 底下、HOME 與它之間有任何一層是 symlink 時略過（clean 與 clean_older 都是），
# symlink 指到的 HOME 外目錄完整保留；HOME 本身是 symlink 時照常清理。
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"
sb_init
mkfakebin

# mkout <目錄>  HOME 外的目標：放一個檔案，結束時檢查它還在
mkout() { mkdir -p "$1"; echo keep > "$1/keep"; }

echo "[~/.kube 本身是 symlink]"
H="$SB/h1"; mkdir -p "$H"
mkout "$SB/out1/cache/discovery"; mkout "$SB/out1/cache/http"; echo cfg > "$SB/out1/config"
ln -s "$SB/out1" "$H/.kube"
OUTFILE="$SB/r1.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_exists "$SB/out1/cache/discovery/keep" "HOME 外的 kube discovery 保留"
a_exists "$SB/out1/cache/http/keep" "HOME 外的 kube http 保留"
a_exists "$SB/out1/config" "HOME 外的 kube config 保留"
a_log "$OUTFILE" "路徑中間有 symlink（${H}/.kube），為安全起見略過：kubectl discovery 快取" "log：.kube symlink 略過 discovery"
a_log "$OUTFILE" "路徑中間有 symlink（${H}/.kube），為安全起見略過：kubectl HTTP 快取" "log：.kube symlink 略過 http"

echo "[~/.kube/cache 是 symlink]"
H="$SB/h2"; mkdir -p "$H/.kube"
mkout "$SB/out2/discovery"; mkout "$SB/out2/http"
ln -s "$SB/out2" "$H/.kube/cache"
OUTFILE="$SB/r2.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_exists "$SB/out2/discovery/keep" "HOME 外的 kube cache/discovery 保留"
a_exists "$SB/out2/http/keep" "HOME 外的 kube cache/http 保留"
a_log "$OUTFILE" "路徑中間有 symlink（${H}/.kube/cache），為安全起見略過：kubectl discovery 快取" "log：.kube/cache symlink 略過"

echo "[~/.cache 是 symlink]"
H="$SB/h3"; mkdir -p "$H"
mkout "$SB/out3/typescript"; mkout "$SB/out3/swift-package-manager"; mkout "$SB/out3/node/corepack"
mkout "$SB/out3/codex-runtimes/codex-runtime-install-1"; old "$SB/out3/codex-runtimes/codex-runtime-install-1"
ln -s "$SB/out3" "$H/.cache"
OUTFILE="$SB/r3.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_exists "$SB/out3/typescript/keep" "HOME 外的 TypeScript 快取保留"
a_exists "$SB/out3/node/corepack/keep" "HOME 外的 Corepack 快取保留（兩層深）"
a_exists "$SB/out3/codex-runtimes/codex-runtime-install-1/keep" "HOME 外的 codex runtime 暫存保留（A 級）"
a_log "$OUTFILE" "路徑中間有 symlink（${H}/.cache），為安全起見略過：TypeScript 型別定義快取" "log：.cache symlink 略過 TypeScript"
if any_real_busy xcode xcodebuild; then
    skip "真實機器上 Xcode／xcodebuild 在跑，SwiftPM 全域快取在 symlink 檢查前就被跳過"
else
    a_exists "$SB/out3/swift-package-manager/keep" "HOME 外的 SwiftPM 全域快取保留"
fi

echo "[~/Library/Developer 是 symlink（clean_older）]"
H="$SB/h4"; mkdir -p "$H/Library"
mkout "$SB/out4/Xcode/iOS DeviceSupport/old"; old "$SB/out4/Xcode/iOS DeviceSupport/old"
ln -s "$SB/out4" "$H/Library/Developer"
OUTFILE="$SB/r4.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_exists "$SB/out4/Xcode/iOS DeviceSupport/old/keep" "HOME 外的 iOS DeviceSupport 舊項目保留"
if real_busy xcode; then
    skip "真實機器上 Xcode 在跑，DeviceSupport 在 symlink 檢查前就被跳過"
else
    a_log "$OUTFILE" "路徑中間有 symlink（${H}/Library/Developer），為安全起見略過：iOS DeviceSupport" "log：clean_older 中間層 symlink 略過"
fi

echo "[HOME 本身是 symlink：照常清理]"
R="$SB/realhome"; H="$SB/homelink"
mkdir -p "$R/.kube/cache/discovery" "$R/.cache/typescript" "$R/Library/Developer/Xcode/iOS DeviceSupport/old"
echo x > "$R/.kube/cache/discovery/f"; echo x > "$R/.cache/typescript/f"
old "$R/Library/Developer/Xcode/iOS DeviceSupport/old"
ln -s "$R" "$H"
OUTFILE="$SB/r5.txt"
run_script "$H" --apply --include-caches > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_gone "$R/.kube/cache/discovery" "kubectl discovery 快取已刪除"
a_gone "$R/.cache/typescript" "TypeScript 快取已刪除"
a_cleaned gone "$R/Library/Developer/Xcode/iOS DeviceSupport/old" "iOS DeviceSupport" xcode
a_nolog "$OUTFILE" "路徑中間有 symlink" "log：沒有誤判中間層 symlink"

echo "[明確指定的根目錄經過 HOME 底下的 symlink：從根目錄開始查，照常清理]"
H="$SB/h6"; E="$SB/out6"; mkdir -p "$H"
mkdir -p "$E/sdks/pub/hosted/a" "$E/sdks/pub/global_packages/g" "$E/sdks/flutter/bin/cache/x"
mkflutter_sdk "$E/sdks/flutter"
mkdir -p "$E/proj/app/node_modules/m"; echo '{}' > "$E/proj/app/package.json"
old "$E/proj/app/node_modules/m" "$E/proj/app/node_modules"
ln -s "$E/sdks" "$H/sdks"; ln -s "$E/proj" "$H/Projects"
OUTFILE="$SB/r6.txt"
FR="$H/sdks/flutter" PC="$H/sdks/pub" run_script "$H" --apply --include-caches --projects "$H/Projects/" > "$OUTFILE" 2>&1
a_eq "$?" 0 "exit 0"
a_gone "$E/sdks/pub/hosted" "PUB_CACHE 經 symlink：hosted 已刪除"
a_exists "$E/sdks/pub/global_packages/g" "PUB_CACHE 的 global_packages 保留"
a_cleaned gone "$E/sdks/flutter/bin/cache" "Flutter SDK artifacts" flutter_tool dart_analyzer
a_gone "$E/proj/app/node_modules" "--projects 經 symlink：node_modules 已刪除"
a_nolog "$OUTFILE" "路徑中間有 symlink" "log：明確根目錄沒有被當成中間層 symlink"

finish
