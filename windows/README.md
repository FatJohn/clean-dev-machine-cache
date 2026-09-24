# Windows

規劃中，尚未實作。目前這個資料夾沒有任何 script。

之後可能涵蓋的方向（只是方向，還沒有決定做法）：

- `%LOCALAPPDATA%` 底下各工具與瀏覽器的快取
- npm、NuGet、Gradle 等套件管理器的快取
- WinSxS 元件存放區：要透過 DISM 處理，不能直接刪
- 系統升級後留下的 `Windows.old`

原則會跟 macOS 版一樣：預設只報告，要明確加旗標才刪。macOS 版的做法見 [../mac/README.md](../mac/README.md)。
