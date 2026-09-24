# macOS：`clean-dev-mac.sh`

清理 macOS 開發機上的快取與殘留。預設只報告，不刪任何東西。

完整說明（每一項的路徑、做法、擁有者 app、環境變數、排程範例）在 [docs/usage.md](docs/usage.md)；
哪些東西會在開發機上長大、怎麼手動清，在 [docs/disk-space-knowledge.md](docs/disk-space-knowledge.md)。

## 安全設計

- **預設只報告**：不加 `--apply` 時只列出會清什麼、可釋放多少。
- **擁有者 app 在跑就跳過**：每個項目宣告自己的擁有者（Xcode、Chrome、Android Studio、Gradle daemon、
  flutter 指令等），其中一個在跑就跳過這一項，不等待。對照表見 [擁有者 app 跳過機制](docs/usage.md#擁有者-app-跳過機制)。
- **先驗證根目錄**：`HOME` 是空的、`/` 或不存在時直接以 exit code 2 結束。每個要刪的路徑先正規化，
  是 `/`、`~` 或 `~` 的上層目錄就不刪。`FLUTTER_ROOT`、`PUB_CACHE` 要通過結構檢查才清；
  `--projects` 拒絕 `~`、`/`、`~` 的上層目錄與 `~/Library` 底下。
- **symlink 一律略過**：要清的路徑本身是 symlink 時不跟進去，也不刪 symlink 本身。
- **刻意不碰**：垃圾桶、Android system-images／AVD／NDK、iOS simulator runtime、Claude desktop VM、
  Chrome 裝置端 AI 模型、Docker、Time Machine 本機快照、Xcode Archives。這些要人判斷，
  手動步驟見 [docs/disk-space-knowledge.md](docs/disk-space-knowledge.md)。

## 快速開始

以下指令都在 `mac/` 目錄執行。已經 clone 過（例如照根目錄 README 做過）的話，從 repo 根目錄 `cd mac` 就好，
不要再 clone 一次，否則會在 repo 裡多出一份巢狀的副本：

```bash
cd mac                                                   # 從 repo 根目錄
```

還沒 clone 的話，先 clone 再進 `mac/`：

```bash
git clone https://github.com/FatJohn/clean-dev-machine-cache.git
cd clean-dev-machine-cache/mac
```

進到 `mac/` 之後：

```bash
./clean-dev-mac.sh --include-caches                      # 先看 A + B 級會清什麼
./clean-dev-mac.sh --projects ~/Projects                 # 看 A + C 級
./clean-dev-mac.sh --apply --include-caches              # 確認沒問題再真的刪
```

log 寫在 `~/logs/clean-dev-mac/`（可用 `LOG_DIR` 覆寫），`--apply` 時會刪掉超過 30 天的舊 log。
清之前先結束 Xcode、Chrome、Android Studio，否則對應項目會被跳過。

## 三個等級

| 等級 | 旗標 | 清什麼 | 代價 |
|---|---|---|---|
| A | 預設 | Chrome／Edge code_sign_clone、Xcode DerivedData／Products／應用程式快取、失效模擬器、CoreSimulator logs、Codex CLI 舊版本、Claude Code 舊 session 暫存、Homebrew（`brew cleanup --prune=all`）、Codex runtime 安裝暫存 | 沒有副作用，或只是重建成本 |
| B | `--include-caches` | npm、pnpm、Yarn、Bun、Go、.NET、Gradle、CocoaPods、SwiftPM、pub cache、Flutter SDK artifacts、Dart analysis server、舊的 iOS／watchOS DeviceSupport、Chrome／Edge／Cursor 快取；Playwright 只報告 | 下次用到時重新下載 |
| C | `--projects DIR` | DIR 底下久未動過（`--stale-days`，預設 30 天）的 Flutter `build/` 與 `node_modules` | 下次打開專案要重新 build／install |

各項目的路徑與做法見 [docs/usage.md 的「三個等級」](docs/usage.md#三個等級)。

## `tools/gpscan-summary.py`

分析 [GrandPerspective](https://grandperspectiv.sourceforge.net/) 存下的掃描檔（File → Save Scan Data），
印出目錄樹、最大檔案，以及 `node_modules`、`DerivedData`、`Caches` 等已知 pattern 的彙總，單位 GiB。
以下指令在 `mac/` 目錄執行：

```bash
tools/gpscan-summary.py scan.gpscan --depth 2 --min-size 5G
tools/gpscan-summary.py scan.gpscan --root ~/Library --depth 1
```

參數說明見 [docs/disk-space-knowledge.md](docs/disk-space-knowledge.md#grandperspective--toolsgpscan-summarypy)。

## 測試

```bash
bash tests/run.sh       # 在 mac/ 目錄執行；-v 印出每支測試的完整輸出
```

`run.sh` 用自己的位置找測試，從 repo 根目錄跑 `bash mac/tests/run.sh` 也可以。
每支測試都在 `mktemp -d` 建的沙盒裡用 `env -i` 執行，`HOME`、`LOG_DIR` 等路徑全部指到沙盒，
並設 `DISABLE_TOOL_COMMANDS=true`，不碰真實家目錄。例外是 `t10-tool-commands.sh`：它要檢查外部指令的呼叫參數，
所以設 `DISABLE_TOOL_COMMANDS=false`，改讓 PATH 只含假工具目錄、系統工具 symlink 目錄與 `/bin`（不含 `/usr/bin` 等會解析到真實清理工具的目錄），
開跑前先確認每個工具都解析到假工具。安全保證的細節寫在 `tests/lib.sh` 開頭。
擁有者 app 的判斷看的是整台機器的 process，所以測試時開著 Chrome／Edge 等，對應斷言會改成檢查「有跳過」。

## 相容性

- macOS（用到 `getconf DARWIN_USER_TEMP_DIR`、`xcrun simctl`、`pgrep` 等；在 macOS 以外不保證能跑）
- bash 3.2（macOS 內建的 `/bin/bash`）
- `tools/gpscan-summary.py`：Python 3，只用標準函式庫
