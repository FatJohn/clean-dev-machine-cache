# AGENTS.md

給在本 repo 工作的 AI coding agent。這裡只記程式碼與 `--help` 看不出來的慣例、理由與陷阱；
旗標、環境變數與預設值以 `mac/clean-dev-mac.sh --help` 為準，各項清理內容見 `mac/docs/usage.md`。

## 這個 repo 是什麼

清理開發機快取的 script，依平台分資料夾，目前只有 `mac/` 有實作（`windows/` 只有 README）。
各平台的 script 各自獨立，共通原則是預設只報告（dry-run），加 `--apply` 才刪。
新增平台時照 `mac/` 的結構：一支 script、`docs/`、`tests/`。

## 最高守則

驗證行為時只用 dry-run 或 `mac/tests/` 的沙盒；`--apply` 只在沙盒裡跑，絕不對真實 HOME 跑。
需要手動試 `--apply` 時，照 `mac/docs/usage.md` 的「沙盒測試」段落設好 `env -i` 與假 HOME。

## 安全不變式

改動 `mac/clean-dev-mac.sh` 時，以下每一條都要維持：

- 刪除只經過 `clean` 或 `clean_older`；新增清理項目也呼叫它們，讓防呆與 read-back 集中在一處。
  外部清理指令一律經過 `run_tool`。
- `unsafe_path`（內部用 `is_home_or_above`）拒絕空字串、`/`、HOME 與 HOME 的上層，比對前先正規化並解析 symlink。
- `FLUTTER_ROOT` 要通過 `is_flutter_sdk`、`PUB_CACHE` 要通過 `is_pub_cache` 才清；驗不過就不清，不改找別的路徑。
- `--projects`（`scan_project_dir`）拒絕 `/`、HOME、HOME 的上層與 `~/Library` 底下，掃描時 prune 隱藏目錄。
- 要清的路徑本身是 symlink 就略過，不跟進去、也不刪 symlink 本身。
- 擁有者 app 在跑時該項直接跳過（`skip_if_busy`／`owner_running`），不等待、不殺 process。
- Codex 版本名稱由 `codex_kind` 去掉平台後綴後整串比對；認不出來的判成 unknown 一律保留。
  `tier_a_codex_releases` 永遠保留 current 指向的版本，解析不到 current 就整項略過。
- `DISABLE_TOOL_COMMANDS=true` 時任何外部指令都不執行，連 `pnpm store path`、`brew cleanup -n` 這類查詢型也經過
  `tools_disabled` 擋掉；`detect_flutter_root` 此時也只認明確設定的 `FLUTTER_ROOT`。沙盒測試靠這條保護真實機器。

## 已知陷阱

- macOS（BSD）`find -mtime +N` 會把經過時間進位到整天，實際是「超過 N+1 天」附近。
  所有天數門檻一律用 `-mmin`，分鐘數由 `days_to_min` 換算。
- 必須相容 bash 3.2（macOS 內建 `/bin/bash`）：不用 associative array、`mapfile`、`${var,,}` 等 bash 4 語法。
  逐行讀 find 結果用 heredoc 而不是 pipe，否則 `while` 跑在 subshell，`TOTAL_FREED_KB` 會遺失。
- `/usr/bin/xcrun` 在 `env -i PATH=/usr/bin:/bin` 下仍然解析得到真實工具，所以一般沙盒靠 `DISABLE_TOOL_COMMANDS=true`；
  `t10-tool-commands.sh` 要檢查外部指令參數，改用不含 `/usr/bin` 的 PATH，開跑前確認每個工具都解析到假工具。
- `/opt/flutter` 是寫死在 `detect_flutter_root` 的候選，位於沙盒外。t10 在它存在時整支 SKIP
  （`OUTSIDE_FLUTTER_CANDIDATES`），每次 `--apply` 前先跑 `preflight_flutter` 確認不會碰到沙盒外的 SDK。
- `du` 讀到無權限的子目錄會回非 0 但仍印出部分大小；`dir_kb` 已處理成保證只印一個整數。量大小一律用 `dir_kb`。
- `dart pub cache clean` 會連 `pub global` 裝的工具一起清掉，所以 `tier_b_pub_cache` 改用 `dart pub cache gc --force`，
  沒有 dart 或停用外部指令時退回路徑清理。gc 路徑刻意不清 `hosted-hashes`：gc 自己會刪掉被刪套件的 hash，
  若再清掉，保留下來的套件少了 hash，下次 `pub get` 會整包重新下載。
- 擁有者判斷（`owner_running`）看的是整台機器的 process 命令列，測試會產生假 Xcode／dart／flutter_tools process。
  同一台機器一次只跑一份 `mac/tests/run.sh`，跑的期間也別有其他命令列含這些字串的 process（包括等待迴圈的 `pgrep` pattern），
  否則 t05／t07 等會互相干擾出假 FAIL。

## 完成定義（改到刪除邏輯時）

- `shellcheck` 與 `bash -n` 對所有 `*.sh` 都是 0 warning。
- `bash mac/tests/run.sh` 全綠（SKIP 要說得出原因）。
- 新增的刪除分支要有測試斷言；會呼叫外部指令的分支要進 `t10-tool-commands.sh`。
- 對每個新斷言做反向注入：暫時弄壞對應的 script 行為，確認測試會 FAIL，再還原。
- `usage` 函式的 `--help` 輸出、`mac/README.md` 與 `mac/docs/usage.md` 要跟行為一致，改行為時一起改。

測試沙盒怎麼保證不碰真實 HOME，寫在 `mac/tests/lib.sh` 開頭；改測試基礎設施前先讀那段。

## CI

`.github/workflows/ci.yml` 有兩個 job：`lint` 在 Linux 上對所有 `*.sh` 跑 `shellcheck` 與 `bash -n`、
檢查 `mac/tools/gpscan-summary.py` 的語法；`test` 跑 `bash mac/tests/run.sh`，而且必須在 macOS 上跑，
因為 script 依賴 BSD `find`、`pgrep`、`getconf DARWIN_USER_TEMP_DIR` 與 bash 3.2 的實際行為。
每週排程重跑一次，用來抓 macOS 映像更新造成的行為變化。
