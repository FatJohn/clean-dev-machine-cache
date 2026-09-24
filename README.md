# clean-dev-machine-cache

> **English summary.** Scripts that find and remove caches and leftovers that silently fill up the disk of a developer machine (Xcode, Android, Flutter/Dart, Node, Go, .NET, browsers, AI CLIs).
> Every script defaults to a report-only dry run and deletes nothing unless you pass `--apply`.
> Items whose owning app is running are skipped, symlinks are never followed, and target roots are validated before anything is removed.
> macOS is supported today (`mac/`); Windows is planned (`windows/`).
> To try it: clone the repo and run `./mac/clean-dev-mac.sh` from the repo root, which only prints what it would clean. Docs are in Traditional Chinese.

開發機的磁碟常被各種工具的快取、舊版本與 build 殘留吃滿，而且大多數藏在 `~/Library`、`~/.gradle`、
`/private/var/folders` 這類平常不會去看的地方。這個 repo 收集清理用的 script，以及「哪裡會長大、
清了要付什麼代價」的筆記。

## 平台

| 平台 | 狀態 | 位置 |
|---|---|---|
| macOS | 可用 | [mac/README.md](mac/README.md) |
| Windows | 規劃中，尚未實作 | [windows/README.md](windows/README.md) |

每個平台的 script 各自獨立，不共用程式碼；共通原則是預設只報告、要明確加旗標才刪。

## 快速開始（macOS）

```bash
git clone https://github.com/FatJohn/clean-dev-machine-cache.git
cd clean-dev-machine-cache
./mac/clean-dev-mac.sh    # 在 repo 根目錄執行；dry-run：只列出會清什麼、可釋放多少
```

細節見 [mac/README.md](mac/README.md)。

## 授權

[MIT](LICENSE)
