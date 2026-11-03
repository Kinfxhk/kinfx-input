# KINFX Input


**[☕ Buy Me a Coffee](https://buymeacoffee.com/kinfxhk)** · [GitHub Sponsors](https://github.com/sponsors/Kinfxhk)

獨立輸入法。引擎用現有 KINFX 速成（librime + schema），殼是自己的。公開 repo `kinfx-ime` 停在 v0.5.10，這裡不要再推回去。

**Android 版封閉測試招募中（名額有限，先到先得）** — Google Play 要求新開發者帳戶先完成 12 人 × 連續 14 天的封閉測試，所以想找真實用家幫忙試。想試就[用這個表單留下 Gmail](https://docs.google.com/forms/d/e/1FAIpQLSdvbBoJQNDaiJCzGrdQ1OkEcVN0wNLcTaekRPusxvGasP6kZw/viewform)，我會逐個加入測試名單；Play 審核通過後（通常一星期內）會收到測試連結。安裝後照平時打字，有問題回報即可，不需要寫評論。

免費直裝包：Windows 用 [v0.1.10](https://github.com/Kinfxhk/kinfx-input/releases/tag/v0.1.10)（修正選字框殘留在畫面）；macOS／Linux 仍然是 [v0.1.5](https://github.com/Kinfxhk/kinfx-input/releases/tag/v0.1.5)。未簽名、未公證。設定只用視窗，不必改碼。

## 安裝包

### macOS

下載 `KINFX-Input-0.1.5-macOS.pkg`，雙擊安裝。輸入法會放到你的 `~/Library/Input Methods`，不用管理員權限。然後到系統設定 → 鍵盤 → 輸入法，加入 KINFX Input。

新裝可能要登出再登入一次，系統才會把按鍵交給新輸入法。MacBook Neo 用同一個包。

### Windows

下載 [`KINFX-Input-0.1.10-Windows-x64.exe`](https://github.com/Kinfxhk/kinfx-input/releases/download/v0.1.10/KINFX-Input-0.1.10-Windows-x64.exe)，右鍵以系統管理員執行。安裝完成後，在工作列輸入法選 KINFX Input（速）。不依賴小狼毫。

### Linux（amd64，要 IBus）

```sh
sudo apt install ./kinfx-input_0.1.5_amd64.deb
ibus restart
```

然後在 IBus 偏好設定加入 KINFX Input。不必自己安裝 Rime schema。

## 中英切換與標點

- **中英切換**：`Ctrl+Space` 或 `Ctrl+Shift`（Windows 由輸入法自己接管，不會跳到第二個輸入法；安裝時會備份並接管系統舊熱鍵，卸載自動還原）。
- **Alt+Shift**：留作 Windows 系統語言切換（切換到英文鍵盤），與微軟輸入法一致。
- **標點**：一鍵一字，**永遠不會彈出候選**。中文模式輸出中文標點（`,。？！；：（）「」『』《》`），全英文模式（中英切換後）輸出 ASCII；`/ - _ + = ~ $ % @ # ^ & * | \`` 保持 ASCII，打 code／網址不會出錯。
- **全形**：`Shift+Space` 切換（進階用，平時不需要）。
- **模式提示**：caret 旁會有「中」／「英」；系統指示器可以按（會 toggle）。

## 平台

| 殼 | 系統 API | 備註 |
| --- | --- | --- |
| macOS | Input Method Kit | MacBook Neo 是 macOS，用同一個殼。上架要 sandbox，不能依賴用戶另外安裝鼠鬚管。 |
| Windows | TSF | 不依賴小狼毫。 |
| iPad / iOS | Keyboard Extension | 與 macOS 不是同一個二進位。 |
| Android | IME | Google Play。不是 Google Books。 |

三個桌面殼已經有安裝包，見上文。iPad、Android 未有包。設定格式三端共用 `settings.json`。

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

## 進度（macOS 殼）

| 項目 | 狀態 | 證據 |
| --- | --- | --- |
| 引擎封入 app（librime 1.17.0 + lua，詞庫預先編譯） | 完成 | `mac/build.sh selftest` 全部 PASS（kin-studio，macOS 27.0.1） |
| `vd1` → 好 | 引擎 self-test 通過；真鍵未證實 | 見下文「真鍵」 |
| 設定視窗改每頁 5／9 | 引擎 self-test 通過（`vd` 空白 1 → 媒）；設定視窗未在真機按過 | `Tests/SelfTest` |
| App Store 版（sandbox） | build 與 ad-hoc 簽名通過 | entitlements：app-sandbox、mach-register `_Connection` |
| 直裝版 | build 通過；未有 Developer ID，未公證 | 需要 Apple Developer 帳號 |

真鍵：輸入法已經登記、啟用，亦能選到（`TISSelectInputSource` 0），系統會啟動 KINFX 程序，IMK 亦有呼叫 `activateServer`。不過 TextEdit 的按鍵仍然交給了鼠鬚管，`handle` 沒有被呼叫過。macOS 要登出再登入一次，才會重建這個登入 session 的輸入法清單，而我沒有在 kin-studio 登出。
