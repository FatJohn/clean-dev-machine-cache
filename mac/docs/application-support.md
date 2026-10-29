# `~/Library/Application Support` 怎麼判斷能不能清

讀者：要手動釋放磁碟空間的開發者
型別：參考

`~/Library/Application Support` 是各 app 存放**持久資料**的地方：設定、登入狀態、資料庫、下載的模型與 VM 映像。
它照規範不是快取，所以沒有能整包定期清的東西，`clean-dev-mac.sh` 也不碰；但 Electron app 與瀏覽器常把快取放在這裡，
逐個 app 判斷後可以清出不少空間。照規範可以刪的快取在隔壁的 `~/Library/Caches`，`clean-dev-mac.sh` 的 B 級處理其中已知的項目。

## 先列出大目錄

```bash
du -sh ~/Library/Application\ Support/* 2>/dev/null | sort -h | tail -20
du -sh ~/Library/Containers/* ~/Library/Group\ Containers/* 2>/dev/null | sort -h | tail -10
du -sh ~/Library/Application\ Support/<App>/* 2>/dev/null | sort -h | tail   # 往下一層看是哪個子目錄
```

終端機要有「完整磁碟取用權限」，否則部分 Containers 量不到。互動式瀏覽可以用 `ncdu`，
或 [Mole](https://github.com/tw93/Mole) 的 `mo analyze`（`brew install mole`；Mole.app 本身沒有附 CLI）。

## 子目錄名稱怎麼判斷

app 結束（⌘Q）後再刪；app 開著時刪，可能在它寫回時壞掉或馬上長回來。

| 子目錄名稱 | 是什麼 | 能不能刪 |
|---|---|---|
| `Cache`、`Code Cache`、`GPUCache`、`CachedData`、`DawnCache` | Electron／Chromium 的網頁、程式碼與 GPU 快取 | 可以，app 會重建 |
| `Service Worker/CacheStorage` | 網站或 web app 的離線快取 | 可以，網站重新下載；離線功能要重新連線後才恢復 |
| `CachedExtensionVSIXs`（VS Code 系列） | 安裝過的擴充套件安裝檔副本 | 可以，重裝擴充套件時重新下載 |
| `logs`、`Crashpad` | log 與當機報告 | 可以 |
| 模型、VM 映像（`vm_bundles`、`OptGuideOnDeviceModel`） | app 下載的大型資源 | 可以，但用到時會再下載；要先在 app 裡關掉對應功能才不會回來 |
| `User`、`Local Storage`、`IndexedDB`、`Cookies`、`Preferences`、`workspaceStorage`、`globalStorage` | 設定、登入狀態、本機資料 | 不要刪，刪了等於重設該 app 或登出 |
| 整個 app 資料夾 | app 的全部資料 | 只在 app 已移除、不打算重裝時刪（見[移除 app 後的殘留](#移除-app-後的殘留)） |

## 主力 Mac 的掃描結果（2026-10-29）

大小單位 GiB，用 `du` 量測。

| 路徑（`~/Library/Application Support/` 之下） | 大小 | 是什麼 | 怎麼處理 |
|---|---|---|---|
| `Claude/vm_bundles` | 12.0 | Claude desktop 本機執行工作用的 VM 映像 | 結束 Claude app 後刪除 `vm_bundles`；下次用到本機工作功能時重新下載 |
| `Google/Chrome/OptGuideOnDeviceModel` | 3.98 | Chrome 裝置端 AI 模型 | 先在 Chrome 設定關閉裝置端 AI，重開 Chrome 後再刪，步驟見 [disk-space-knowledge.md 的〈瀏覽器〉](disk-space-knowledge.md#瀏覽器) |
| `Microsoft Edge/Default/Service Worker/CacheStorage` | 3.0 | 網站離線快取 | 結束 Edge 後刪除 `CacheStorage` |
| `Code/CachedExtensionVSIXs` | 1.14 | VS Code 擴充套件安裝檔副本 | 結束 VS Code 後刪除 |
| `Code/Cache`、`Code/CachedData` | 0.45、0.25 | VS Code 的 Electron 快取 | 結束 VS Code 後刪除 |
| `Code/User` | 0.59 | VS Code 設定與各 workspace 的狀態 | 不刪 |
| `Figma/DesktopProfile` | 1.66 | Figma desktop 的瀏覽器 profile，`v43` 佔 1.31，`v37`–`v42`（沒有 `v40`）各 0.06–0.09 | 結束 Figma 後可刪 `v37`–`v42`；`v43` 是使用中的 profile，含登入狀態，不刪 |
| `orca/codex-runtime-home` | 1.53 | Orca 內建 Codex 的 runtime 與登入資料 | 不刪，刪了要重新登入 |
| `Cursor` | 1.21 | Cursor 的資料，`/Applications` 已經沒有 Cursor | 不打算重裝就整個刪除 |
| `Windsurf`、`Codex`、`ClickUp`、`KKBOX`、`GOING13` | 0.01–0.17 | 對應的 app 不在 `/Applications` | 不打算重裝就整個刪除 |

同一次掃描的 `~/Library/Containers` 與 `~/Library/Group Containers`（sandbox app 的資料，結構像一個小 HOME）：

| 路徑 | 大小 | 是什麼 | 怎麼處理 |
|---|---|---|---|
| `Containers/com.docker.docker` | 6.0 | Docker Desktop 的 VM 磁碟 `Docker.raw` | 不要直接刪檔；用 `docker system df` 看完再 `docker system prune`，見 [disk-space-knowledge.md 的〈Docker〉](disk-space-knowledge.md#docker) |
| `Group Containers/VUTU7AKEUR.jp.naver.line.mac` | 4.5 | LINE 的聊天紀錄與媒體 | 從 LINE 的設定刪除聊天資料或快取；不要直接刪資料夾 |
| `Containers/com.tinyspeck.slackmacgap` | 1.7 | Slack，其中 `…/Application Support/Slack/Cache` 佔 1.2 | Slack 選單「Help → Troubleshooting → Clear Cache and Restart」 |
| `Containers/com.apple.CoreDevice.CoreDeviceService` | 0.88 | Xcode 與實機配對、裝置資料 | 不刪 |

## 移除 app 後的殘留

Finder 把 app 拖到垃圾桶只刪掉 `.app` 本身，資料、快取與背景服務都留著。要清乾淨，照下面做：

1. 刪 app 之前先查它的 bundle ID：

   ```bash
   mdls -name kMDItemCFBundleIdentifier -raw /Applications/<App>.app
   ```

2. 結束 app，連同它的背景 process：

   ```bash
   pgrep -lf '<App>'
   ```

3. 卸載它註冊的 LaunchAgent。這一步最容易漏，漏了 app 的背景程式會在 app 刪掉後繼續跑：

   ```bash
   ls ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons | grep -i '<名稱或 bundle ID>'
   launchctl list | grep -i '<名稱或 bundle ID>'
   launchctl print gui/$(id -u)/<Label> | grep -E 'domain|path'    # 找不到就換 user/$(id -u)/<Label>
   launchctl bootout gui/$(id -u)/<Label>                           # 或 user/$(id -u)/<Label>，依上一行的 domain
   sudo launchctl bootout system/<Label>                            # /Library/LaunchDaemons 的服務
   ```

   app 自己用程式註冊的服務不一定有 `~/Library/LaunchAgents` 裡的 plist，`launchctl list` 看得到 Label
   就要 bootout。設了 keepalive 的服務只 `kill` process 會被 launchd 重新拉起來。

4. 用名稱與 bundle ID 各找一次殘留：

   ```bash
   find ~/Library -maxdepth 3 \( -iname '*<名稱>*' -o -iname '*<bundle ID>*' \) 2>/dev/null
   ```

5. 確認每個路徑都屬於這個 app 後再刪。常見位置：

   | 位置 | 內容 |
   |---|---|
   | `~/Library/Application Support/<App>` | app 資料 |
   | `~/Library/Caches/<App 或 bundle ID>` | 快取 |
   | `~/Library/Containers/<bundle ID>`、`~/Library/Group Containers/<團隊 ID>.<bundle ID>` | sandbox app 的全部資料 |
   | `~/Library/Preferences/<bundle ID>.plist` | 設定 |
   | `~/Library/Saved Application State/<bundle ID>.savedState` | 視窗狀態 |
   | `~/Library/HTTPStorages/<bundle ID>`、`~/Library/WebKit/<bundle ID>` | 網路與內嵌網頁資料 |
   | `~/Library/Logs/<App>` | log |
   | `~/Library/LaunchAgents/<Label>.plist` | 登入時自動啟動的背景程式 |

有附官方移除程式的 app（Docker Desktop 的「Troubleshoot → Uninstall」、Adobe、Microsoft Office 等）優先用它。
AppCleaner 或 Mole 的移除功能會自動找上面這些位置，刪之前仍要看過清單。

### 例：Steam

Mac 上的 `Steam.app` 只是啟動器，真正的用戶端與遊戲裝在 `~/Library/Application Support/Steam`，另外註冊兩個 launchd 服務：

| Label | 作用 |
|---|---|
| `com.valvesoftware.steam.ipctool` | `user/<UID>` domain、設了 keepalive 的背景服務，跑 `…/Steam/Steam.AppBundle/Steam/Contents/MacOS/ipcserver`；plist 在 `Application Support/Steam` 裡 |
| `com.valvesoftware.steamclean` | `gui/<UID>` domain，plist 是 `~/Library/LaunchAgents/com.valvesoftware.steamclean.plist`，登入時執行、監看 Steam 目錄 |

只刪 `Steam.app` 時 `ipcserver` 還在跑、`Application Support/Steam` 也還在。完整移除：

```bash
launchctl bootout user/$(id -u)/com.valvesoftware.steam.ipctool
launchctl bootout gui/$(id -u)/com.valvesoftware.steamclean
pkill -f 'Application Support/Steam'               # 還有殘留的 process 才需要
pgrep -lf Steam                                     # 確認沒有輸出
rm ~/Library/LaunchAgents/com.valvesoftware.steamclean.plist
rm -rf ~/Library/Application\ Support/Steam ~/Library/Caches/Steam
```
