# KINFX Input

**[☕ Buy Me a Coffee](https://buymeacoffee.com/kinfxhk)** · [GitHub Sponsors](https://github.com/sponsors/Kinfxhk)

香港繁體速成輸入法，獨立直裝版。引擎（librime + KINFX 速成詞庫）已封入程式，毋須另裝小狼毫、鼠鬚管或 Fcitx。候選字次序與 Windows 11 微軟速成逐頁一致，打英文毋須切換模式。

**最新版本：[v0.1.11](https://github.com/Kinfxhk/kinfx-input/releases/tag/v0.1.11)**（macOS／Windows／Linux）

> 想用新版本，請用這個 repo。舊的 Rime 方案包 [KINFX IME](https://github.com/Kinfxhk/kinfx-ime)（v0.5.12）已進入維護模式，不再新增功能。

## 特色

- **免裝宿主**：不依賴小狼毫、鼠鬚管或 Fcitx5-Rime，下載安裝包即可使用。
- **設定用視窗**：所有開關在設定視窗修改，改動即時生效，毋須編輯任何 yaml／lua 檔案。
- **中英混打**：直接打英文詞按空白上屏（`startup` → `startup `）；短字按一下左 Shift（`of` → `of`）。
- **認得常用名稱**：公司、品牌、網站名自動大小寫（`adsense` → `AdSense`、`openai` → `OpenAI`）。
- **港字齊全**：㗎、嘅、𠻹、𨋢 等字都有，排在 Windows 候選之後，不打亂原有位置。
- **標點一鍵一字**：中文標點（`，。？！；：（）「」『』《》`）永不出候選。
- **三平台引擎一致**：macOS／Windows／Linux 共用同一套引擎與詞庫，中英混打行為一致。

## 對比表：獨立版 vs 方案包

| | **KINFX Input**（本 repo，獨立版） | **KINFX IME**（Rime 方案包） |
| --- | --- | --- |
| 安裝 | 直接下載安裝包 | 先裝宿主（小狼毫／鼠鬚管／Fcitx）再裝方案 |
| 引擎 | 內嵌 librime，隨安裝包 | 依賴宿主提供 |
| 設定 | 設定視窗，即時生效 | 編輯 yaml／lua |
| 更新 | 下載新安裝包 | 更新方案檔 |
| 狀態 | 持續維護 | 維護模式（v0.5.12） |

## 安裝

免費直裝包（三平台）。未簽名、未公證。

### macOS

下載 [`KINFX-Input-0.1.11-macOS.pkg`](https://github.com/Kinfxhk/kinfx-input/releases/download/v0.1.11/KINFX-Input-0.1.11-macOS.pkg)，雙擊安裝（首次請右鍵 → 開啟）。輸入法會放到你的 `~/Library/Input Methods`，毋須管理員權限。然後到系統設定 → 鍵盤 → 輸入法，加入 KINFX Input。

新裝可能要登出再登入一次，系統才會把按鍵交給新輸入法。MacBook Neo 用同一個包。

### Windows

下載 [`KINFX-Input-0.1.11-Windows-x64.exe`](https://github.com/Kinfxhk/kinfx-input/releases/download/v0.1.11/KINFX-Input-0.1.11-Windows-x64.exe)，右鍵以系統管理員執行。安裝完成後，在工作列輸入法選 KINFX Input（速）。不依賴小狼毫。

### Linux（amd64，需要 IBus）

```sh
sudo apt install ./kinfx-input_0.1.11_amd64.deb
ibus restart
```

然後在 IBus 偏好設定加入 KINFX Input。毋須自行安裝 Rime schema。

## 各平台差異

三個桌面版共用同一套引擎與詞庫，僅系統行為略有不同：

| 行為 | macOS | Windows | Linux |
| --- | --- | --- | --- |
| 中英切換 | Ctrl+Space／Ctrl+Shift | Ctrl+Space／Ctrl+Shift（輸入法自行接管，不會跳到第二個輸入法） | Ctrl+Space／Ctrl+Shift |
| Alt+Shift | 無特別用途 | 系統語言切換（切換到英文鍵盤） | 無特別用途 |
| 首次啟用 | 或需登出再登入一次 | 安裝後直接選用 | `ibus restart` |
| 簽名 | 未簽名，右鍵開啟 | 未簽名 | 未簽名 |

## 中英切換與標點

- **中英切換**：`Ctrl+Space` 或 `Ctrl+Shift`（Windows 由輸入法自己接管，不會跳到第二個輸入法；安裝時會備份並接管系統舊熱鍵，卸載自動還原）。
- **Alt+Shift**：留作 Windows 系統語言切換（切換到英文鍵盤），與微軟輸入法一致。
- **標點**：一鍵一字，永遠不會彈出候選。中文模式輸出中文標點（`，。？！；：（）「」『』《》`），英文模式輸出 ASCII；`/ - _ + = ~ $ % @ # ^ & * | \`` 保持 ASCII，打 code／網址不會出錯。
- **全形**：`Shift+Space` 切換（進階用，平時不需要）。
- **模式提示**：caret 旁有「中」／「英」；系統指示器可以按（會 toggle）。

## 平台

| 殼 | 系統 API | 狀態 |
| --- | --- | --- |
| macOS | Input Method Kit | 已推出 |
| Windows | TSF | 已推出 |
| Linux | IBus（amd64） | 已推出 |
| iPad / iOS | Keyboard Extension | 未推出 |
| Android | IME | 未推出 |

三個桌面版已有安裝包，見上文。設定格式三端共用 `settings.json`。

## 用戶不改碼

設定只經視窗。程式把開關寫入 `settings.json`，再生成 Rime custom，用戶不應看到 yaml／lua。

開關只此幾項：

- 每頁候選：9 或 5
- 英文空白：安全／只限長詞／關
- 聯想詞：開／關
- 選字後空白：翻頁（預設，與 Windows 速成相同）／打出空格
- 常用詞前綴：熱門／全部／關
- 左 Shift 無輸入時：不做／臨時英文
- 預編輯：字母／字根

不要把 `unknown_space_min`、`hold_min` 等數字暴露為用戶欄位。
