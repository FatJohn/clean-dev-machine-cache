# macOS 開發機磁碟空間知識庫

哪些東西會在開發機上默默長大、在哪裡、怎麼清、清了要付什麼代價。
可以當手動查詢用的手冊，也說明 `clean-dev-mac.sh` 涵蓋到哪裡。

「script」欄的意思：**A**／**B**／**C** 是 `clean-dev-mac.sh` 的等級
（見 [usage.md](usage.md)）；**不涵蓋**代表只能照本文手動處理。
典型大小是量級參考，實際依使用習慣差很多；有標「實例」的出自下方 2026-09-24 那台機器。

## 先找出大東西在哪

### GrandPerspective ＋ `tools/gpscan-summary.py`

[GrandPerspective](https://grandperspectiv.sourceforge.net/) 用方塊圖顯示整顆磁碟。掃完後用
「File → Save Scan Data」存成 `.gpscan`，再交給本 repo 的工具分析，不必在圖上一格一格點。
以下指令在 `mac/` 目錄執行（`tools/` 在 `mac/` 底下）：

```bash
tools/gpscan-summary.py scan.gpscan --depth 2 --min-size 5G         # 整顆磁碟兩層
tools/gpscan-summary.py scan.gpscan --root ~/Library --depth 1      # 只看 ~/Library
tools/gpscan-summary.py scan.gpscan --root ~ --depth 3 --min-size 500M --top-files 30
```

| 參數 | 預設 | 作用 |
|---|---|---|
| `FILE` | — | `.gpscan` 檔（gzip 壓縮或純 XML 都可以） |
| `--depth N` | 3 | 樹狀展開深度 |
| `--min-size` | `1G` | 只列出至少這麼大的目錄，可寫 `500M`、`1.5G` |
| `--root PATH` | `/` | 從這個子樹開始展開，`~` 會展開成執行者的家目錄（要跟掃描時是同一個帳號） |
| `--top-files N` | 20 | 列出最大的 N 個檔案 |

輸出包含：ScanInfo 摘要（volume 大小、剩餘、掃到的總量、差距）、目錄樹、最大檔案、
已知 pattern 彙總（`node_modules`、`build`、`.gradle`、`DerivedData`、`Caches`、`.git`、`.dart_tool`、
`Pods`、`__pycache__`、`.venv`／`venv`、`.next`、`.pub-cache`、`*.code_sign_clone`；同名只算最外層）。
單位一律是 GiB。只用 Python 標準函式庫，數百萬個檔案的掃描檔約 10 秒跑完。

「已用空間」和「掃到的總量」的差距，通常是 APFS 快照、其他 volume（系統 volume 等）或掃描權限不足
而看不到的部分。

### 其他方式

```bash
du -sh ~/Library/* 2>/dev/null | sort -h | tail -20   # 最直接，但大目錄要等
du -xhd 1 ~ 2>/dev/null | sort -h                     # 一層，不跨 volume
brew install ncdu   # 或 gdu：終端機裡的互動式瀏覽，可以邊看邊刪
ncdu ~
```

- **「系統設定 → 一般 → 儲存空間」**（舊版叫「關於這台 Mac → 儲存空間」）：看得到分類與
  「開發者」「iOS 檔案」等項目，但分類很粗。
- **終端機要有「完整磁碟取用權限」**，否則 `~/Library` 底下有些目錄（例如 `~/.Trash`、部分
  Containers）會量不到，數字會偏小。

### Purgeable 空間與 APFS 快照

Finder 顯示的「可用」通常包含 purgeable（系統認為需要時可以自動清掉的空間，例如 Time Machine
本機快照、iCloud 可移除的本機副本）；`df` 顯示的是扣掉這些之後的數字，所以兩者會不同。

```bash
tmutil listlocalsnapshots /                  # 列出本機快照
tmutil deletelocalsnapshots <日期>           # 刪掉一個，日期取自上一行的輸出
diskutil apfs listSnapshots /                # 另一種看法
```

快照刪掉的東西要等 APFS 回收才會反映在 `df`，通常幾分鐘內。

## Xcode／iOS

| 項目 | 路徑 | 典型大小 | 是什麼 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|---|
| DerivedData | `~/Library/Developer/Xcode/DerivedData` | 數 GB（實例 3.47） | 各專案的 build 產物與 index | 清空內容 | 下次 build 從頭來 | A |
| Products | `~/Library/Developer/Xcode/Products` | 實測 3.0 MB | Xcode 產生的 build 產物 | 刪除 | 下次 build 重新產生 | A |
| Xcode 應用程式快取 | `~/Library/Caches/com.apple.dt.Xcode` | 實測 980 KB | Xcode 自己的快取 | 刪除 | Xcode 重建 | A |
| 失效模擬器 | `~/Library/Developer/CoreSimulator/Devices` | 實例 4.51（全部模擬器） | runtime 已移除的模擬器 | `xcrun simctl delete unavailable` | 無 | A |
| CoreSimulator logs | `~/Library/Logs/CoreSimulator` | 數十 MB | 模擬器 log | 清空內容 | 無 | A |
| iOS／watchOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport`、`watchOS DeviceSupport` | 每個 OS 版本數 GB | 接實機時抽出的 symbol | 刪掉舊版本目錄 | 再接該版本的實機要重新抽 | B（90 天） |
| SwiftPM 快取 | `~/Library/Caches/org.swift.swiftpm` | 1 GB 上下 | 套件 clone | 刪除 | 重新 resolve | B |
| CocoaPods 快取 | `~/Library/Caches/CocoaPods` | 數百 MB | pod 下載快取 | 刪除，或 `pod cache clean --all` | 重新下載 | B |
| simulator runtime | `/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime`（新版 Xcode）或 `/Library/Developer/CoreSimulator` | 每個 7–9 GB（實例合計 16.02） | 各 iOS 版本的模擬器系統映像 | 見下方 | 要測該版本時重新下載 | 不涵蓋 |
| CoreSimulator Caches | `/Library/Developer/CoreSimulator/Caches` | 實例 3.53 | dyld shared cache 等 | 刪掉對應 runtime 時一起消失 | — | 不涵蓋 |
| Archives | `~/Library/Developer/Xcode/Archives` | 每個數百 MB | 上架用的封存與 dSYM | Xcode Organizer 裡逐個刪 | 失去該版本的 crash symbolication | 不涵蓋 |

**刪 simulator runtime（手動）：**

```bash
xcrun simctl runtime list                 # 列出已安裝的 runtime 與 ID
xcrun simctl list devices                 # 看哪些模擬器還在用哪個 runtime
xcrun simctl runtime delete <ID>          # 刪掉用不到的版本
```

`/System/Library/AssetsV2` 受 SIP 保護，不要直接 `rm`，一律透過 `simctl runtime delete` 或
Xcode「Settings → Components」刪除。

## Android

| 項目 | 路徑 | 典型大小 | 是什麼 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|---|
| system-images | `~/Library/Android/sdk/system-images` | 每個 2–8 GB（實例 21.56） | emulator 的系統映像 | `sdkmanager --uninstall` | 建該版本的 AVD 要重新下載 | 不涵蓋 |
| AVD | `~/.android/avd/*.avd` | 每台數 GB（實例兩台 18.61） | 模擬器的使用者資料與快照 | Device Manager 刪除，或 `avdmanager delete avd -n <名稱>` | 模擬器內資料全失 | 不涵蓋 |
| AVD 快照 | `~/.android/avd/<名稱>.avd/snapshots/default_boot/ram.bin` | 約等於模擬器 RAM（實例各約 3.8） | Quick Boot 用的記憶體快照 | 刪 `snapshots/default_boot`，或 AVD 設定改成 Cold Boot | 下次開機變慢 | 不涵蓋 |
| NDK | `~/Library/Android/sdk/ndk/<版本>` | 每版 2–3 GB（實例 4 版 10.56） | 原生編譯工具鏈 | `sdkmanager --uninstall "ndk;<版本>"` | 需要該版本的專案會重新下載 | 不涵蓋 |
| Gradle caches | `~/.gradle/caches` | 10 GB 以上很常見（實例 14.80） | 依賴、transform、build cache，舊版 Gradle 的目錄不會自己消失 | 刪除 `~/.gradle/caches` | 下次 build 重新下載 | B |
| Gradle daemon log／暫存 | `~/.gradle/daemon`、`~/.gradle/.tmp` | 實測 daemon 9.2 MB | daemon 的 log 與暫存 | 刪除 | 無 | B |
| Gradle wrapper | `~/.gradle/wrapper/dists` | 每版約 200 MB（實例 1.74） | 各版 Gradle 本體 | 刪掉沒在用的版本目錄 | 用到時重新下載 | 不涵蓋（script 刻意保留；`~/.gradle/gradle.properties` 常含 signing 設定，也保留） |
| Kotlin/Native | `~/.konan` | 實例 2.50 | KMP 的 Kotlin/Native 工具鏈 | 刪除 | 下次 KMP build 重新下載 | 不涵蓋 |

**看 AVD 用的是哪個 system-image：**

```bash
grep image.sysdir.1 ~/.android/avd/*.avd/config.ini
# ~/.android/avd/Pixel_6.avd/config.ini:image.sysdir.1=system-images/android-33/google_apis/arm64-v8a/
```

沒有出現在這份清單裡的 system-image 就是沒有 AVD 在用的，可以移除：

```bash
SDK=~/Library/Android/sdk
$SDK/cmdline-tools/latest/bin/sdkmanager --list_installed
$SDK/cmdline-tools/latest/bin/sdkmanager --uninstall "system-images;android-36.1;google_apis_playstore;arm64-v8a"
$SDK/cmdline-tools/latest/bin/sdkmanager --uninstall "ndk;26.3.11579264"
```

套件名稱就是路徑把 `/` 換成 `;`。清理前先關掉 Android Studio 與所有 emulator。

## Flutter／Dart

| 項目 | 路徑 | 典型大小 | 是什麼 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|---|
| 專案 `build/` | `<專案>/build` | 單一專案可達數 GB（實例最大 4.61） | 各平台 build 產物 | `flutter clean`，或刪除 | 下次 build 從頭來 | C |
| `.dart_tool` | `<專案>/.dart_tool` | 數百 MB | 套件設定與產生的檔案 | `flutter clean` | 要重跑 `pub get` | 不涵蓋 |
| pub cache | `~/.pub-cache`（或 `$PUB_CACHE`） | 1–3 GB（實例 1.46） | 下載的套件 | `dart pub cache gc --force` 只刪沒被引用的套件；或刪除 `hosted`、`hosted-hashes`、`git`。兩者都另清 `.tmp`、`_temp`，保留 `bin` 與 `global_packages`（`dart pub cache clean -f` 會連 `pub global` 裝的工具一起清掉） | gc：只有被刪的套件要重新下載；刪路徑：每個專案要重新 `pub get` | B（有 `dart` 且未設 `DISABLE_TOOL_COMMANDS=true` 時跑 gc，否則刪路徑） |
| analysis server 快取 | `~/.dartServer` | 1–5 GB（實例 1.62） | IDE 分析快取 | 刪除 | IDE 第一次開專案較慢 | B |
| SDK artifacts | `$FLUTTER_ROOT/bin/cache` | 數 GB（實測 3.42） | 各平台 engine 與內含的 Dart SDK | 刪除 `bin/cache`，下次執行 `flutter` 會自動重新下載（也可手動 `flutter precache`） | 重新下載 | B（`DISABLE_TOOL_COMMANDS=true` 時只認 `FLUTTER_ROOT`） |

## Node（npm／pnpm／yarn）

| 項目 | 路徑 | 典型大小 | 是什麼 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|---|
| `node_modules` | `<專案>/node_modules` | 每個數百 MB，加總很可觀（實例合計 26.05） | 專案依賴 | 刪除 | 要重新 install | C |
| npm cache | `~/.npm/_cacache` | 1–10 GB（實例 `~/.npm` 2.70） | 下載快取 | `npm cache clean --force` | 重新下載 | B |
| pnpm store | `pnpm store path` 的結果（實例 `~/Library/pnpm/store/v11`） | 數 GB（實例 5.88） | content-addressable store | `pnpm store prune`（只刪沒被引用的） | 幾乎沒有 | B |
| pnpm 自己的版本管理 | `~/Library/pnpm/package-manager-store` | 實例 1.81 | pnpm 管理自身版本時下載的 pnpm 本體 | `pnpm store prune` 清不到；用 `du -sh ~/Library/pnpm/package-manager-store` 與 `ls ~/Library/pnpm/package-manager-store` 看內容，確認沒有在用的版本再手動刪 | 用到舊版時重新下載 | 不涵蓋 |
| 舊的 pnpm store | 換過安裝方式後遺留的舊目錄 | 實例 6.10 | 已停用的 store | 確認 `pnpm store path` 不是它之後手動刪除 | 無 | 不涵蓋 |
| npm log | `~/.npm/_logs` | 實測 44 KB | npm 的除錯 log | 刪除 | 無 | B |
| yarn cache | `~/Library/Caches/Yarn`（v1）、`~/.yarn/berry/cache`（Berry） | 數 GB | 下載快取 | 刪除（`yarn` 實際跑 v1 還是 Berry 取決於 corepack 與所在目錄，兩版 `yarn cache clean` 清的位置不同） | 重新下載 | B |
| bun cache | `~/.bun/install/cache` | 實測 12.5 MB | 下載快取 | 刪除 | 重新下載 | B |
| `.next` 等框架產物 | `<專案>/.next` | 數百 MB | build 產物 | 刪除 | 重新 build | 不涵蓋 |

### npm cache 裡有 root 擁有的檔案

- **症狀**：`npm cache clean --force` 失敗，錯誤碼 `EACCES`、失敗的 syscall 是 `unlink`，npm 提示 cache 裡有
  root-owned files。能刪的檔案照樣會被刪掉，只剩 root 擁有的那些（實例：`~/.npm` 原本 2.70 GiB；`--force` 在 root 擁有的檔案上失敗後，`~/.npm/_cacache` 只剩約 35 MiB，幾乎全是一個 root 擁有、約 34.7 MiB 的 tarball）。
- **原因**：以前用 `sudo npm`（例如 `sudo npm install -g`）裝過東西，npm 以 root 身分把 tarball 與索引寫進家目錄的
  `~/.npm/_cacache`。
- **修法**：`sudo chown -R "$(id -u):$(id -g)" ~/.npm`，把 `~/.npm` 整個改回自己擁有，再清一次。
  檢查還有沒有：`/usr/bin/find ~/.npm ! -user "$(id -un)" | head`。script 碰到這種情況會記 WARN、印出
  這行指令（uid:gid 已展開），但不會自己呼叫 `sudo`。
- **預防**：全域套件不要用 `sudo` 安裝；node 裝在家目錄（mise、nvm 這類版本管理工具）就不需要 `sudo`。

### Playwright

`~/Library/Caches/ms-playwright` 底下是 `<瀏覽器>-<revision>`，每升級一次 Playwright 就多一組，
舊的不會自己刪（實例 `ms-playwright` 2.13、`ms-playwright-mcp` 1.56）。script 只在 B 級報告大小
與「同一瀏覽器的舊 revision」，不清。手動方式：

```bash
ls ~/Library/Caches/ms-playwright
npx playwright uninstall         # 在專案目錄裡跑：移除這個 Playwright 安裝所用的瀏覽器
npx playwright uninstall --all   # 移除所有 Playwright 安裝用過的瀏覽器，用到時再 npx playwright install
```

Playwright 會記錄哪些安裝還在用哪個 revision，`npx playwright install` 時會順便移除已經沒人用的版本；
專案已經刪掉、不會再跑 install 的話，舊 revision 就會一直留著。這時直接刪掉舊 revision 的目錄也可以，
哪個版本還需要，下次跑測試時會報錯（`Executable doesn't exist … Please run … install`），
要重跑 `npx playwright install` 才能恢復。

## Go

| 項目 | 路徑 | 典型大小 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|
| build cache | `go env GOCACHE`（macOS 預設 `~/Library/Caches/go-build`） | 1–5 GB（實例 2.13） | `go clean -cache` | 重新編譯 | B |
| module cache | `go env GOMODCACHE`（預設 `~/go/pkg/mod`） | 數 GB（實例 5.55） | `go clean -modcache`（檔案是唯讀的，不要用 `rm -rf` 硬砍） | 重新下載 | B |

## .NET

| 項目 | 路徑 | 典型大小 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|
| NuGet 套件 | `~/.nuget/packages` | 數 GB（實例 4.10） | `dotnet nuget locals all --clear` | 重新 restore | B |
| 專案產物 | `<專案>/bin`、`<專案>/obj` | 數百 MB | `dotnet clean` 或刪除 | 重新 build | 不涵蓋 |

## Python

| 項目 | 路徑 | 怎麼清 | 代價 | script |
|---|---|---|---|---|
| pip cache | `~/Library/Caches/pip` | `pip cache purge` | 重新下載 | 不涵蓋 |
| uv cache | `~/.cache/uv` | `uv cache clean` | 重新下載 | 不涵蓋 |
| 虛擬環境 | `<專案>/.venv`、`venv` | 刪除後重建 | 要重新安裝依賴 | 不涵蓋 |
| `__pycache__` | 到處都是 | `find . -name __pycache__ -prune -exec rm -rf {} +` | 無 | 不涵蓋 |

## Docker

Docker Desktop 把所有映像、container、volume 放在一個磁碟映像檔
`~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`（實例 4.01）。

```bash
docker system df                  # 映像、container、volume、build cache 各佔多少
docker system prune               # 停止的 container、沒用到的網路、dangling 映像
docker system prune -a --volumes  # 連沒在用的映像與 volume 一起刪（volume 裡可能有資料庫）
docker builder prune              # build cache
```

`Docker.raw` 是 sparse file，Finder 顯示的大小可能遠大於實際佔用，用 `du -h` 量比較準。
script 不涵蓋：volume 裡可能有資料，一定要先看過 `docker system df -v`。

## 瀏覽器

| 項目 | 路徑 | 典型大小 | 是什麼 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|---|
| Chrome code_sign_clone | `$(dirname $(getconf DARWIN_USER_TEMP_DIR))/X/com.google.Chrome.code_sign_clone` | 每份約 1.4 GB，會累積多份（實例 10 份 13.86） | 更新時驗章用的整份 app 副本殘留 | 結束 Chrome 後清空該目錄 | 無 | A |
| Edge code_sign_clone | 同上，`com.microsoft.edgemac.code_sign_clone` | 實例 1.07 | 同上 | 結束 Edge 後清空 | 無 | A |
| Chrome 快取 | `~/Library/Caches/Google/Chrome` | 數百 MB | 網頁快取 | 清空 | 網頁重新載入 | B |
| Edge 快取 | `~/Library/Caches/Microsoft Edge` | 實例 2.01 | 網頁快取 | 清空 | 同上 | B |
| Chrome 裝置端 AI 模型 | `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel` | 實例 3.98 | Chrome 內建 AI 功能的模型 | 見下方 | 相關功能無法使用 | 不涵蓋 |

**Chrome 裝置端 AI 模型：** 直接刪資料夾，Chrome 會再下載回來。要在 Chrome 的「設定 → 系統」
關閉「裝置端 AI」相關選項（名稱依版本略有不同），重新啟動 Chrome 後再刪除上面那個資料夾。

## AI 工具

| 項目 | 路徑 | 典型大小 | 是什麼 | 怎麼清 | 代價 | script |
|---|---|---|---|---|---|---|
| Claude desktop VM | `~/Library/Application Support/Claude/vm_bundles` | 實例 11.24（`rootfs.img` 8.93） | desktop app 執行本機工作用的 VM 映像 | 結束 app 後刪除 `vm_bundles` | 下次使用相關功能時重新下載 | 不涵蓋 |
| Claude desktop Cache | `~/Library/Application Support/Claude/Cache` | 實例 1.17 | app 快取 | 結束 app 後刪除 | 無 | 不涵蓋 |
| Claude Code 暫存 | `/private/tmp/claude-<UID>` | 實例 4.60 | 各 session 的暫存與 scratchpad | 刪除超過一週的 session 目錄 | 無法回頭看舊 session 的暫存檔 | A（7 天） |
| Claude Code 對話紀錄 | `~/.claude/projects` | 實例 2.41 | 各專案的 session transcript | 刪除舊的 `.jsonl`；或在 settings 設 `cleanupPeriodDays` 讓它自動清 | 無法 resume 舊 session | 不涵蓋 |
| Codex CLI 舊版本 | `~/.codex/packages/standalone/releases` | 每版約 270 MB（實例 24 版 6.45） | 自動更新留下的各版本 | 保留 `current` 指向的版本、最新的穩定版與無法辨識的名稱（去掉平台後綴後，整串不符穩定版或預發行版格式的），其餘刪除 | 無 | A |
| Codex runtime | `~/.cache/codex-runtimes` | 實例 3.53 | runtime 與安裝暫存 | 刪除 `codex-runtime-install-*` | 無 | A（1 天） |
| 編輯器 extensions | `~/.vscode/extensions`、`~/.cursor/extensions`、`~/.windsurf/extensions` | 數百 MB 到數 GB | 各 extension，更新後舊版目錄可能殘留 | 同一 extension 有多個版本目錄時，刪掉舊的 | 無 | 不涵蓋 |
| Cursor 快取 | `~/Library/Caches/Cursor` | 實例 1.83 | app 快取 | 清空 | 無 | B |

## macOS 系統

| 項目 | 路徑 | 典型大小 | 是什麼 | 怎麼處理 | script |
|---|---|---|---|---|---|
| per-user 暫存 | `/private/var/folders/<xx>/<yyy>/{C,T,X}` | 數 GB 到數十 GB（實例 17.70） | 各 app 的暫存（T）、快取（C）、code sign clone（X） | 不要整個刪；重新開機會清掉部分暫存。已知的大項目（code_sign_clone）另外處理 | 部分（A） |
| sleepimage | `/private/var/vm/sleepimage` | 大小依 hibernatemode 與機型而定（實例 2.00；該機 RAM 36 GiB、hibernatemode 3） | 休眠時寫出的記憶體映像 | 不要刪，系統會重建；由 `pmset` 的 hibernatemode 控制 | 不涵蓋 |
| APFS 快照 | 看不到路徑 | 可達數十 GB | Time Machine 本機快照、系統更新快照 | `tmutil listlocalsnapshots /`、`tmutil deletelocalsnapshots <日期>` | 不涵蓋 |
| AssetsV2 | `/System/Library/AssetsV2` | 數 GB 到數十 GB | 系統下載的資產（simulator runtime、字典、語音、文件等） | 受 SIP 保護，透過擁有它的工具刪（例如 `simctl runtime delete`） | 不涵蓋 |
| 系統 log | `/private/var/log`、`/private/var/db/diagnostics` | 數百 MB 到數 GB（實例 `/private/var/db` 5.22） | unified log 與診斷資料 | 系統會輪替，一般不需要手動處理 | 不涵蓋 |
| 垃圾桶 | `~/.Trash` | 實例 16.84 | 已刪除但未清空的檔案 | Finder 清空垃圾桶 | 不涵蓋（TCC 擋、而且是使用者決定） |

## 實例：2026-09-24 主力開發機

用 GrandPerspective 掃描後以 `tools/gpscan-summary.py` 分析。單位 GiB，除非另外註明。
有「實測」字樣的是同一天在機器上直接查到的。

**整體：** volume 494 GB（460.43 GiB），剩 84 GB（78.58 GiB）。已用 381.85，掃到的總量 367.55，
差距 14.30 屬於 APFS 快照／其他 volume 等掃不到的部分。家目錄 259.29。

| 分類 | 項目 | 大小 | 處理 |
|---|---|---|---|
| 瀏覽器 | Chrome code_sign_clone（10 份，各約 1.38；實測仍在） | 13.86 | A |
| | Edge code_sign_clone | 1.07 | A |
| | Chrome 裝置端 AI 模型（OptGuideOnDeviceModel） | 3.98 | 手動 |
| 使用者 | 垃圾桶 | 16.84 | 手動 |
| | 已停用的舊 pnpm store 目錄 | 6.10 | 手動 |
| AI 工具 | Codex releases（24 版） | 6.45 | A |
| | `~/.cache/codex-runtimes` | 3.53 | A（安裝暫存部分） |
| | Claude Code `/private/tmp/claude-<UID>` | 4.60 | A |
| | `~/.claude/projects` | 2.41 | 手動 |
| | Claude desktop `vm_bundles`（`rootfs.img` 8.93） | 11.24 | 手動 |
| | Claude desktop Cache | 1.17 | 手動 |
| Android | `~/Library/Android/sdk` 合計 | 35.41 | — |
| | system-images（android-33 8.17、android-37.2-beta3 8.16、37.0 2.89、36.1 2.34；只有 33 與 37.2-beta3 有 AVD 在用） | 21.56 | 手動 |
| | NDK（4 版） | 10.56 | 手動 |
| | AVD（兩台，各有約 3.8 的 snapshot `ram.bin`） | 18.61 | 手動 |
| Xcode／iOS | iOS simulator runtime（AssetsV2） | 16.02 | 手動 |
| | `/Library/Developer/CoreSimulator/Caches` | 3.53 | 手動 |
| | CoreSimulator Devices | 4.51 | A（僅失效的） |
| | DerivedData | 3.47 | A |
| 套件快取 | `~/Library/Caches` 合計（go-build 2.13、ms-playwright 2.13、ms-playwright-mcp 1.56、Edge 2.01、Cursor 1.83、pnpm 1.69） | 17.90 | B（部分） |
| | Gradle caches（含舊版 9.3.1 的 1.85） | 14.80 | B |
| | Gradle wrapper | 1.74 | 手動 |
| | `go/pkg/mod` | 5.55 | B |
| | `.nuget` | 4.10 | B |
| | `.npm` | 2.70 | B |
| | pnpm store（`pnpm store path`＝`~/Library/pnpm/store/v11`） | 5.88 | B |
| | `~/Library/pnpm/package-manager-store`（pnpm 自己的版本管理） | 1.81 | 手動 |
| | `.pub-cache` | 1.46 | B |
| | `.dartServer` | 1.62 | B |
| | `.konan` | 2.50 | 手動 |
| 專案 | `node_modules` 合計 | 26.05 | C |
| | `build` 目錄合計（單一 Flutter 專案最大 4.61） | 15.95 | C（僅 Flutter） |
| 其他 | Docker.raw | 4.01 | 手動 |
| 系統 | `/System` 35.71、`/Applications` 31.09、`/private/var/folders` 17.70、`/private/var/db` 5.22、sleepimage 2.00 | — | 大多不處理 |

觀察：

- 單一最大宗是 Android（SDK＋AVD 合計超過 50），其中一半是沒有 AVD 在用的 system-image、
  多版 NDK 與 Quick Boot 快照。這些都要人判斷，所以留在手動清單。
- Chrome code_sign_clone 是「不知道它存在就永遠不會清」的典型：一份 1.4 GiB、每次更新可能多一份。
- 單位要小心：`df` 與「系統設定」用 GB（10⁹），`gpscan-summary.py` 與 `du -h` 用 GiB（2³⁰）。
  494 GB 的 volume 在工具裡是 460 GiB。
