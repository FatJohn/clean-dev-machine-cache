# 使用說明：`clean-dev-mac.sh`

開發機上 Xcode、Chrome、Android Studio 隨時可能開著，也沒有「等它閒下來」這種時段。
所以這支 script 預設**只報告**，加 `--apply` 才刪；每個項目宣告自己的擁有者 app，擁有者在跑就**逐項跳過**，不等待。
Xcode Archives 一律不碰（要留著做 crash symbolication）；依賴快取要加 `--include-caches` 才清。
log 寫在 `~/logs/clean-dev-mac/`。

## 用法

以下指令在 `mac/` 目錄執行（在 repo 根目錄就把 `./clean-dev-mac.sh` 換成 `./mac/clean-dev-mac.sh`）：

```bash
./clean-dev-mac.sh                     # A 級，只報告
./clean-dev-mac.sh --include-caches    # A + B 級，只報告
./clean-dev-mac.sh --projects ~/Projects --stale-days 60   # A + C 級，只報告
./clean-dev-mac.sh --apply             # 實際清 A 級
./clean-dev-mac.sh --apply --include-caches --projects ~/Projects:~/work
```

| 旗標 | 作用 |
|---|---|
| `--apply` | 真的刪除；沒有這個旗標時只報告 |
| `--include-caches` | 加跑 B 級 |
| `--projects DIR` | 加跑 C 級；可重複指定，或用冒號分隔多個目錄。DIR 不做 glob 展開；`~`、`/`、`~` 的上層目錄與 `~/Library` 底下會被拒絕（見 C 級） |
| `--stale-days N` | C 級的門檻天數（預設 30，最小 1）；天數語意見[天數怎麼算](#天數怎麼算) |
| `-h`, `--help` | 顯示說明 |

未知參數、`--stale-days` 或 `KEEP_LOGS_DAYS` 不是 1 以上的整數、`HOME` 是空的／`/`／不存在的目錄時，
以 exit code 2 結束，什麼都不刪。任何一項清除失敗（包括「只刪超過 N 天的項目」這類部分清除）或
`--projects` 指到被拒絕的目錄，會記 ERROR 並繼續跑其他項目，最後以 exit code 1 結束。

| 環境變數 | 預設 | 作用 |
|---|---|---|
| `LOG_DIR` | `~/logs/clean-dev-mac` | log 目錄，裡面的 `clean-dev-mac-*.log` 超過 `KEEP_LOGS_DAYS` 天會在 `--apply` 時刪除；dry-run 只報告數量 |
| `KEEP_LOGS_DAYS` | 30 | log 保留天數，最小 1 |
| `CODE_SIGN_CLONE_BASE` | `$(dirname $(getconf DARWIN_USER_TEMP_DIR))/X` | Chrome／Edge code_sign_clone 的上層目錄 |
| `CLAUDE_TMP_DIR` | `/private/tmp/claude-<UID>` | Claude Code 暫存目錄 |
| `DISABLE_TOOL_COMMANDS` | false | 設為 `true` 時不執行 simctl、brew、npm、pnpm、go、dotnet、`dart pub cache gc` 等外部指令（連 `pnpm store path`、`go env` 這種只查路徑的也不跑），log 記「略過（DISABLE_TOOL_COMMANDS）」；pub cache 改走路徑清理，log 記「DISABLE_TOOL_COMMANDS=true，不執行 dart pub cache gc，改用路徑清理」；找 Flutter SDK 時也只認 `FLUTTER_ROOT`，不看 PATH 與預設安裝位置 |
| `FLUTTER_ROOT` | 未設 | Flutter SDK 根目錄，B 級會清它的 `bin/cache`。沒設時依序找 PATH 上的 `flutter`、`~/development/flutter`、`~/flutter`、`~/sdk/flutter`、`/opt/flutter`。有設就只用它，驗證不過就不清、也不改找別的位置 |
| `PUB_CACHE` | `~/.pub-cache` | pub cache 位置；要通過驗證才清（見 B 級說明） |

輸出開頭與結尾都會印 `df -h /` 的可用空間，最後印「可釋放」（dry-run）或「已釋放」（`--apply`）總量。
dry-run 的總量是估計值：B 級用官方指令清的項目以目前目錄大小計，是上限（例如 `pnpm store prune`
只刪沒被引用的套件）；Homebrew 的量另外印出，不計入總量。

## 三個等級

### A 級：預設就跑，沒有副作用或只是重建成本

| 項目 | 路徑 | 做法 | 擁有者 app |
|---|---|---|---|
| Chrome code_sign_clone | `$CODE_SIGN_CLONE_BASE/com.google.Chrome.code_sign_clone` | 清空內容 | Google Chrome |
| Edge code_sign_clone | `$CODE_SIGN_CLONE_BASE/com.microsoft.edgemac.code_sign_clone` | 清空內容 | Microsoft Edge |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` | 清空內容 | Xcode |
| Xcode Products | `~/Library/Developer/Xcode/Products` | 整個刪除 | Xcode |
| Xcode 應用程式快取 | `~/Library/Caches/com.apple.dt.Xcode` | 整個刪除 | Xcode |
| 失效的模擬器 | — | `xcrun simctl delete unavailable` | Xcode、Simulator |
| CoreSimulator logs | `~/Library/Logs/CoreSimulator` | 清空內容 | Xcode、Simulator |
| Codex CLI 舊版本 | `~/.codex/packages/standalone/releases/*` | 保留 `current` 指到的版本與最新的穩定版（完全沒有穩定版時保留最新的預發行版）；無法辨識的名稱一律保留，其餘刪除 | — |
| Claude Code 暫存 | `$CLAUDE_TMP_DIR/<專案>/<session>` | 每個專案目錄下超過 7 天的 session | — |
| Homebrew | — | `brew cleanup --prune=all`（dry-run 用 `-n`） | — |
| Codex runtime 安裝暫存 | `~/.cache/codex-runtimes/codex-runtime-install-*` | 超過 1 天的才刪 | — |

- **code_sign_clone** 是 Chrome 更新時為了驗章複製出來的整份 app，照理說用完會刪，實際上會殘留。
  實測一台機器累積 10 份、共約 14 GiB。瀏覽器開著時裡面可能有正在使用的那份，所以瀏覽器在跑就跳過；
  要清就先完全結束 Chrome（⌘Q）。
- **Codex CLI**：`current` symlink 解析不到時整項跳過，不刪任何版本。目錄名稱像
  `0.156.0-aarch64-apple-darwin`，先去掉 `-<arch>-apple-darwin` 平台後綴（沒有後綴的也可以）。剩下的字串**整串**比對，不是只看開頭：
  整串是數字版本（`^[0-9]+(\.[0-9]+)*$`，例如 `0.10.0`）就是穩定版；整串是數字版本接 `-alpha`、`-beta`、`-rc`、
  `-pre`、`-dev`，後面只再接可有可無的數字段（`^[0-9]+(\.[0-9]+)*-(alpha|beta|rc|pre|dev)(\.?[0-9]+)*$`，例如
  `0.10.0-alpha.1`、`0.3.0-rc1`、`0.3.0-beta`）是預發行版；其他名稱（例如 `0.3.0-linux`、`0.3.0-devbuild`、
  `0.3.0-alpha.1-linux`）一律保留，
  並記「無法辨識版本名稱，保留」，也不參與「最新」的判斷。「最新」取最新的穩定版；完全沒有穩定版時才取最新的
  預發行版（去掉平台後綴後以 `sort -V` 比較，所以不同架構的名稱也能互相比較）。
  `current` 永遠保留，所以 `current` 是預發行版時，它和最新的穩定版都會留下。
- **Claude Code 暫存**的第一層是專案目錄、第二層才是各 session。script 只刪第二層超過 7 天沒動過的
  session，不直接刪整個專案目錄，以免連帶清掉還在跑的 session。判斷依據是 session 目錄本身的 mtime，
  連續跑超過 7 天、期間又沒有在該目錄第一層新增檔案的 session，理論上可能被誤判。

### B 級：`--include-caches`，清了會重新下載

npm、pnpm、Go、.NET 用官方指令；pub cache 有 `dart` 時用官方的 `dart pub cache gc`；其餘直接刪路徑
（理由見表下說明）。同一個路徑只清一次。

| 項目 | 做法 | 量測路徑 | 擁有者 app |
|---|---|---|---|
| npm | `npm cache clean --force` | `~/.npm/_cacache` | — |
| pnpm | `pnpm store prune` | `pnpm store path` 的結果 | — |
| npm log | 刪除 `~/.npm/_logs` | 同左 | — |
| Yarn | 刪除 `~/Library/Caches/Yarn`（v1）與 `~/.yarn/berry/cache`（Berry） | 同左 | — |
| Bun | 刪除 `~/.bun/install/cache` | 同左 | — |
| Go | `go clean -cache`、`go clean -modcache` | `go env GOCACHE`、`go env GOMODCACHE` | — |
| .NET | `dotnet nuget locals all --clear` | `~/.nuget/packages` | — |
| Gradle | 刪除 `~/.gradle/caches`、`daemon`、`.tmp`（保留 `wrapper` 與 `gradle.properties`） | 同左 | Android Studio、Gradle daemon、Android emulator |
| CocoaPods | 刪除 `~/Library/Caches/CocoaPods` | 同左 | — |
| SwiftPM | 刪除 `~/Library/Caches/org.swift.swiftpm` | 同左 | Xcode |
| Dart analysis server | 刪除 `~/.dartServer` | 同左 | — |
| pub cache | 有 `dart` 且沒設 `DISABLE_TOOL_COMMANDS=true`：`PUB_CACHE=<路徑> dart pub cache gc --force`，再刪 `.tmp`、`_temp`。否則刪除 `hosted`、`hosted-hashes`、`git`、`.tmp`、`_temp`。路徑是 `$PUB_CACHE`（預設 `~/.pub-cache`），兩種做法都保留 `bin` 與 `global_packages`；要先通過驗證 | 整個 pub cache 目錄（gc）；各路徑（路徑清理） | flutter 指令、Dart analysis server |
| Flutter SDK artifacts | 刪除 `$FLUTTER_ROOT/bin/cache`；要先通過驗證 | 同左 | flutter 指令、Dart analysis server |
| iOS DeviceSupport | 刪除 `~/Library/Developer/Xcode/iOS DeviceSupport` 下超過 90 天的項目 | 同左 | Xcode |
| watchOS DeviceSupport | 刪除 `~/Library/Developer/Xcode/watchOS DeviceSupport` 下超過 90 天的項目 | 同左 | Xcode |
| Chrome 快取 | 清空 `~/Library/Caches/Google/Chrome` | 同左 | Google Chrome |
| Edge 快取 | 清空 `~/Library/Caches/Microsoft Edge` | 同左 | Microsoft Edge |
| Cursor 快取 | 清空 `~/Library/Caches/Cursor` | 同左 | Cursor |
| Playwright | **只報告**，不清 | `~/Library/Caches/ms-playwright*` | — |

- **pub cache** 有兩種做法：
  - 有 `dart` 且沒設 `DISABLE_TOOL_COMMANDS=true` 時跑 `dart pub cache gc --force`。它只刪沒被任何
    active root（`~/.pub-cache/active_roots` 記的、跑過 `pub get` 的專案與 `pub global` 工具）引用的套件，
    作用中專案的依賴不必重新下載。`--force` 跳過確認提示；不加 `--collect-recent` 時，最近才加入的
    檔案不會被刪。這條路徑不清 `hosted-hashes`：gc 會自己刪掉被刪套件的 hash，但保留下來的套件少了
    hash，下次 `pub get` 會整包重新下載（`pub get -v` 印出 `has no content-hash - redownloading`）。
  - 否則退回路徑清理：刪 `hosted`、`git`，`hosted-hashes`（已下載 archive 的 hash）隨 `hosted` 一起失效，
    一起刪；清掉後每個 Flutter 專案下次都要 `flutter pub get`。
  - 兩種做法都清 `.tmp`（舊版 pub 暫存）與 `_temp`（新版 pub 的下載暫存）。
  - 不用 dart 官方的 cache clean 子指令，因為它會清整個 `PUB_CACHE`，連 `dart pub global activate`
    裝的工具（melos、fvm 等）一起刪掉；兩種做法都保留 `bin` 與 `global_packages`，這些工具清完仍可用。
  清之前先驗證：路徑不是 `/`、`~` 或 `~` 的上層目錄，而且底下有 `hosted` 或 `global_packages` 其中之一；
  不符合就記 WARN 不清。不看目錄名稱（預設路徑一定叫 `.pub-cache`，明確設定的 `PUB_CACHE` 可以是任何名字，
  名稱擋不到東西），也不把 `bin` 當標記（`~/bin` 很常見，擋不住 `PUB_CACHE=$HOME`）。
- **Gradle** 只清 `caches`、`daemon`、`.tmp`。`wrapper` 是各版 Gradle 本體，`gradle.properties` 常含
  signing 設定，兩者都保留。
- **Yarn** 直接刪路徑，不跑 `yarn cache clean`：`yarn` 實際跑的是 v1 還是 Berry 取決於 corepack 與所在目錄，
  兩版的 `yarn cache clean` 清的位置不同；刪路徑則兩版都涵蓋，也不會同一份快取清兩次。
- **Flutter SDK artifacts** 清掉後，下次執行 `flutter` 會自動重新下載（precache）。SDK 位置依序看
  `FLUTTER_ROOT`、PATH 上的 `flutter`、預設安裝位置；`DISABLE_TOOL_COMMANDS=true` 時只認明確設定的
  `FLUTTER_ROOT`，沒設就跳過。這是為了沙盒測試：假 HOME 擋不住 PATH，若照常從 PATH 找，會找到真實機器上的
  SDK 並把它的 `bin/cache` 刪掉。
  不論 SDK 位置從哪來，都要有 `bin/flutter` 與 `bin/internal`、而且不是 `/`、`~` 或 `~` 的上層目錄，
  才算 Flutter SDK；例如 `FLUTTER_ROOT=$HOME` 時 `~/bin/cache` 不會被刪。明確設定的 `FLUTTER_ROOT`
  驗證不過會記 WARN；自動偵測的候選驗證不過就換下一個。
- **Playwright** 只列出各目錄大小，以及同一瀏覽器有多個 revision 時較舊的那幾個。
  Playwright 有自己的 revision 對應規則，砍錯會讓測試報錯（`Executable doesn't exist …`），要重跑
  `npx playwright install` 才能恢復，所以留給人手動處理，
  步驟見 [disk-space-knowledge.md 的 Playwright 一節](disk-space-knowledge.md#playwright)。

### C 級：`--projects DIR`，專案內久未動過的產物

在每個 DIR 底下用 `find -maxdepth 4` 找專案，並跳過（prune）DIR 底下所有隱藏目錄（`.git`、`.cursor`、
`.npm` 等以 `.` 開頭的）以及 `node_modules`、`build`、`Pods`，避免往深處爬、也避免把編輯器外掛或 npx 快取
裡的 `node_modules` 當成專案產物。DIR 本身是隱藏目錄時照樣掃，只是不進它底下的隱藏目錄。

DIR 是 `/`、`~`、`~` 的上層目錄（例如 `/Users`），或在 `~/Library` 底下時，拒絕掃描這個 DIR：記 ERROR
並建議改指定 `~/Projects` 之類的專案資料夾，其他等級與其他 DIR 照跑，最後 exit code 1。比對時會先正規化
（去掉結尾 `/`、`//`、`/.`，並解析 symlink）。`--projects` 的參數不做 glob 展開，`"~/p*"` 會被當成字面上的
目錄名稱。

| 找到 | 清什麼 | 什麼時候清 |
|---|---|---|
| `pubspec.yaml` | 同層的 `build/` | `build/` 的 mtime 超過 `--stale-days` 天 |
| `package.json` | 同層的 `node_modules` | `node_modules/.package-lock.json`（沒有就看 `node_modules` 本身）的 mtime 超過 `--stale-days` 天 |

報告逐項列出路徑和大小。清掉的代價是下次打開那個專案要重新 `flutter build`／`npm install`。

## 安全檢查

- **HOME**：`HOME` 是空的、`/`、正規化後是 `/`（例如 `//`），或不是存在的目錄時，開頭就以 exit code 2 結束，
  不建立 log、不刪任何東西。
- **危險路徑**：每個要刪的路徑先正規化（去掉結尾 `/`、`//`、`/.`；目錄存在時也比對解析 symlink 後的實體路徑），
  是 `/`、`~` 或 `~` 的上層目錄就記 ERROR 不刪。
- **symlink**：要清的路徑本身是 symlink 時一律略過並記「是 symlink，為安全起見略過」，不跟進去清，
  也不刪 symlink 本身。
- **部分清除失敗**：「只刪超過 N 天的項目」這類清除，刪除指令失敗或刪完後仍有符合條件的項目，會記 ERROR。

### 天數怎麼算

所有「超過 N 天」都是指 mtime 早於「執行當下往前 N×24 小時」，用 `find -mmin +(N×1440)` 判斷。
不用 `find -mtime +N`：macOS 的 `-mtime` 會把經過時間進位到整天再比較，實際門檻比字面多一天。
適用於 `--stale-days`（最小 1）、`KEEP_LOGS_DAYS`（最小 1）、Claude Code 暫存的 7 天、Codex runtime 安裝暫存的
1 天、iOS／watchOS DeviceSupport 的 90 天。例如 `--stale-days 1` 時，25 小時前的 `build/` 會清、
23 小時前的不會。

## 擁有者 app 跳過機制

每個項目宣告自己的擁有者，只要其中一個在跑就跳過這一項，繼續下一項，不等待。
dry-run 也照樣判斷，會印出「會跳過 X：Y 正在執行」並附上目前大小。

| 擁有者 | 判斷方式 | 影響的項目 |
|---|---|---|
| Xcode | `pgrep -x Xcode` | DerivedData、Products、Xcode 應用程式快取、simctl、CoreSimulator logs、SwiftPM、iOS／watchOS DeviceSupport |
| Simulator | `pgrep -x Simulator` | simctl、CoreSimulator logs |
| Google Chrome | `pgrep -x "Google Chrome"` | Chrome code_sign_clone、Chrome 快取 |
| Microsoft Edge | `pgrep -x "Microsoft Edge"` | Edge code_sign_clone、Edge 快取 |
| Cursor | `pgrep -x Cursor` | Cursor 快取 |
| Android Studio | `pgrep -f 'Android Studio.app'` | Gradle caches／daemon／.tmp |
| Gradle daemon | `pgrep -f GradleDaemon` | Gradle caches／daemon／.tmp |
| Android emulator | `pgrep -f qemu-system` | Gradle caches／daemon／.tmp（所有 Android 相關項目） |
| flutter 指令 | `pgrep -f flutter_tools` | pub cache、Flutter SDK artifacts |
| Dart analysis server | `pgrep -f 'dart.*(analysis_server\|language-server)'` | pub cache、Flutter SDK artifacts |

Gradle daemon 在 Android Studio 關掉後還會常駐一段時間；急著清的話先跑 `./gradlew --stop`。

Flutter 相關兩項不把 Xcode、Android Studio 列為擁有者：它們開著不代表在用 Flutter。真的在 build Flutter
專案時（包含 Xcode 與 Gradle 發起的 build）會有 `flutter_tools` process；IDE 開著 Dart 專案時會有
analysis server，而它就是從 `bin/cache/dart-sdk` 執行的，也會讀 pub cache 的套件。

## 刻意不清的項目

以下只寫在 [disk-space-knowledge.md](disk-space-knowledge.md)，script 不處理：

| 項目 | 不自動化的理由 |
|---|---|
| 垃圾桶 | TCC（隱私權限）會擋，終端機沒有「完整磁碟取用權限」就讀不到 `~/.Trash`；而且清空是使用者的決定 |
| Android system-images、AVD、NDK | 要判斷哪個 AVD 還在用、專案要哪個 NDK 版本 |
| iOS simulator runtime | 要判斷專案還要測哪些 iOS 版本 |
| Claude desktop VM（`vm_bundles`） | app 自己管理，刪了下次啟動會重新下載，而且可能正在使用 |
| Chrome 裝置端 AI 模型 | 要從 Chrome 設定關閉，直接刪會被重新下載 |
| Docker | 映像與 volume 可能有資料，要用 `docker system df` 看過再決定 |
| Time Machine 本機快照 | 屬於備份，由系統管理 |
| Xcode Archives | 要留著對應 dSYM 做 crash symbolication |

## 建議節奏

- **每月一次**：先跑 dry-run 看清單，確認沒問題再加 `--apply`（在 `mac/` 目錄執行）。

  ```bash
  ./clean-dev-mac.sh --include-caches --projects ~/Projects
  ./clean-dev-mac.sh --apply --include-caches --projects ~/Projects
  ```

- **磁碟吃緊時**：先結束 Xcode、Chrome、Android Studio 再跑，否則對應項目會被跳過；
  還不夠就照 [disk-space-knowledge.md](disk-space-knowledge.md) 從最大的項目手動處理。
- A 級可以放心排程；B、C 級清了會讓下次 build 變慢，建議手動跑。

## 選用：排程

本 repo 不提供安裝器，需要時自己建。以下範例只跑 A 級。

launchd（每月 1 日 12:30；把 script 路徑換成 clone 的位置、`/Users/你的帳號` 換成自己的家目錄，
存成 `~/Library/LaunchAgents/local.clean-dev-mac.plist`）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.clean-dev-mac</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/你的帳號/Projects/clean-dev-machine-cache/mac/clean-dev-mac.sh</string>
        <string>--apply</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Day</key>
        <integer>1</integer>
        <key>Hour</key>
        <integer>12</integer>
        <key>Minute</key>
        <integer>30</integer>
    </dict>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>StandardErrorPath</key>
    <string>/Users/你的帳號/logs/clean-dev-mac/launchd.err</string>
</dict>
</plist>
```

plist 裡一律寫完整路徑，不要寫 `~` 或 `$HOME`（`man launchd.plist` 沒有保證會展開）。script 自己會把 log 寫到
`LOG_DIR`（預設 `~/logs/clean-dev-mac/`），`launchd.err` 只用來記錄 launchd 啟動 script 時的錯誤。
手冊只說 `StandardErrorPath` 的檔案不存在時會建立，沒說會建立上層目錄，所以先 `mkdir -p ~/logs/clean-dev-mac`。

```bash
mkdir -p ~/logs/clean-dev-mac
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.clean-dev-mac.plist
launchctl bootout gui/$(id -u)/local.clean-dev-mac      # 移除
```

launchd 的 PATH 很短，沒設 `PATH` 的話 brew 等指令會找不到，對應項目會記成「沒有 brew，略過」。

crontab（`crontab -e`）：

```
30 12 1 * * /bin/bash "$HOME/Projects/clean-dev-machine-cache/mac/clean-dev-mac.sh" --apply >> "$HOME/logs/clean-dev-mac/cron.log" 2>&1
```

路徑換成 clone 的位置。script 自己會把 log 寫到 `LOG_DIR`（預設 `~/logs/clean-dev-mac/`）；`cron.log` 是用來記錄
cron 本身的啟動錯誤（例如路徑打錯、檔案不存在），script 印到終端機的輸出也會一併附在這裡。
`>>` 不會建立目錄，第一次排程前先 `mkdir -p ~/logs/clean-dev-mac`。

## 沙盒測試

要驗證 `--apply` 的行為時，不要在真的家目錄上跑。code_sign_clone 與 Claude Code 暫存不在 HOME
底下，外部指令也不看 HOME，所以三個變數都要一起設。`FLUTTER_ROOT`、`PUB_CACHE` 同樣不走 HOME，
下面的 `env -i` 已經把它們清掉；要測 Flutter SDK 那一項就把 `FLUTTER_ROOT` 指到沙盒裡的假 SDK。
以下指令在 `mac/` 目錄執行：

```bash
FAKE=/tmp/fakehome
env -i HOME="$FAKE" PATH=/usr/bin:/bin LOG_DIR="$FAKE/logs" \
    CODE_SIGN_CLONE_BASE="$FAKE/csc" CLAUDE_TMP_DIR="$FAKE/ctmp" DISABLE_TOOL_COMMANDS=true \
    bash ./clean-dev-mac.sh --apply --projects "$FAKE/Projects"
```

擁有者 app 的判斷看的是整台機器的 process，所以沙盒測試時，真的有開著的 Chrome／Edge 仍然會讓對應項目被跳過。
