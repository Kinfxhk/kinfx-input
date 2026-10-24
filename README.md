# KINFX Input

獨立輸入法。引擎用現有 KINFX 速成（librime + schema），殼係自己的。公開 repo `kinfx-ime` 停喺 v0.5.10，呢度唔好再推返去。

免費直裝包：macOS／Linux／Windows 都用 [v0.1.5](https://github.com/Kinfxhk/kinfx-input/releases/tag/v0.1.5)。未簽名、未公證。設定只用視窗，唔使改碼。

## 安裝包

### macOS

下載 `KINFX-Input-0.1.5-macOS.pkg`，雙擊安裝。輸入法會放到你的 `~/Library/Input Methods`，唔使管理員。然後到系統設定 → 鍵盤 → 輸入法，加入 KINFX Input。

新裝可能要登出再登入一次，系統先把按鍵交俾新輸入法。MacBook Neo 用同一個包。

### Windows

下載 [`KINFX-Input-0.1.5-Windows-x64.exe`](https://github.com/Kinfxhk/kinfx-input/releases/download/v0.1.5/KINFX-Input-0.1.5-Windows-x64.exe)，右鍵以系統管理員執行。裝完在工作列輸入法揀 KINFX Input（速）。唔靠小狼毫。

### Linux（amd64，要 IBus）

```sh
sudo apt install ./kinfx-input_0.1.5_amd64.deb
ibus restart
```

然後在 IBus 偏好設定加入 KINFX Input。唔使自己裝 Rime schema。

## 平台

| 殼 | 系統 API | 備註 |
| --- | --- | --- |
| macOS | Input Method Kit | MacBook Neo 係 macOS，用同一個殼。上架要 sandbox，唔可以靠用戶另裝鼠鬚管。 |
| Windows | TSF | 唔靠小狼毫。 |
| iPad / iOS | Keyboard Extension | 同 macOS 唔係同一個二進位。 |
| Android | IME | Google Play。唔係 Google Books。 |

三個桌面殼已經有安裝包，見上面。iPad、Android 未有包。設定格式三邊共用 `settings.json`。

## 用戶唔改碼

設定只經視窗。程式把開關寫入 `settings.json`，再生成 Rime custom，用戶唔好見到 yaml／lua。

開關只此幾項：

- 每頁候選：9 或 5
- 英文空白：安全／只限長詞／關
- 聯想詞：開／關
- 揀字後空白：翻頁（預設，同 Windows 速成）／打出空格
- 常用詞前綴：熱門／全部／關
- 左 Shift 無輸入時：不做／臨時英文
- 預編輯：字母／字根

唔好把 `unknown_space_min`、`hold_min` 等數字暴露成用戶欄位。

## 進度（macOS 殼）

| 項目 | 狀態 | 證據 |
| --- | --- | --- |
| 引擎封入 app（librime 1.17.0 + lua，詞庫預先編譯） | 完成 | `mac/build.sh selftest` 全部 PASS（kin-studio，macOS 27.0.1） |
| `vd1` → 好 | 引擎 self-test 通過；真鍵未證實 | 見下面「真鍵」 |
| 設定視窗改每頁 5／9 | 引擎 self-test 通過（`vd` 空白 1 → 媒）；設定視窗未喺真機撳過 | `Tests/SelfTest` |
| App Store 版（sandbox） | build 同 ad-hoc 簽名通過 | entitlements：app-sandbox、mach-register `_Connection` |
| 直裝版 | build 通過；未有 Developer ID，未公證 | 需要 Apple Developer 帳號 |

真鍵：輸入法已經登記、啟用，亦揀得到（`TISSelectInputSource` 0），系統會啟動 KINFX 程序，IMK 亦有叫 `activateServer`。不過 TextEdit 嘅按鍵仲係交咗俾鼠鬚管，`handle` 冇被叫過。macOS 要登出再登入一次，先會重建呢個登入 session 嘅輸入法清單，而我冇喺 kin-studio 登出。
