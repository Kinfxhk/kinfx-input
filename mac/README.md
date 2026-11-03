# KINFX Input — macOS 殼

同一個殼運行 Mac Studio 與 MacBook Neo（都是 macOS）。引擎是 librime 1.17.0 加 librime-lua，KINFX 詞庫與 schema 預先編譯好，一起封入 app，不必安裝鼠鬚管。

## 結構

| 路徑 | 內容 |
| --- | --- |
| `Sources/Shim/` | 一層包裝 librime C API 的 C 程式，Swift 不必理會 C struct |
| `Sources/Engine/` | `Settings`（settings.json 與 Rime patch）、`Engine`、按鍵對照，沒有 UI，self-test 都用這部分 |
| `Sources/App/` | IMK 入口、`KINFXInputController`、候選窗、設定視窗 |
| `Tests/SelfTest/` | 不用 GUI：設定、按鍵對照、`vd1` → 好、每頁 5／9 切換 |
| `Resources/` | Info.plist；entitlements 分 `store`（sandbox）、`direct`（sandbox，加用戶選取檔案唯讀）、`dev`（沒有 sandbox，只供本機排錯） |
| `../engine/` | 由 kinfx-ime v0.5.10（`2c4b38e691`）複製過來的 schema、詞庫、Lua，加 rime-prelude |

## 設定

只有設定視窗會寫 `settings.json`，程式再由它生成 `kinfx_quick.custom.yaml`，用戶不會看到 yaml 或者 lua。欄位在 `Settings.specs`，其他平台的殼都用同一套 key 與值：

`page_size` 9/5 · `english_space` safe/long/off · `association` true/false · `space_after_pick` page/type · `phrase_capture` hot/all/off · `empty_shift` noop/ascii · `preedit` letters/radicals

## 建置（不必 Xcode，Command Line Tools 即可）

```sh
mac/build.sh selftest            # 引擎 self-test
mac/build.sh app store           # build/KINFX Input.app（sandbox）
mac/build.sh app direct          # 直裝版
SIGN_ID="Developer ID Application: …" mac/build.sh app direct   # 正式簽名，加 hardened runtime
mac/install-dev.sh               # 安裝到 ~/Library/Input Methods 並啟用（本機開發用）
mac/install-dev.sh --remove      # 移除，輸入法清單還原
```

## 已知

- 沒有 Developer ID 的 ad-hoc 簽名，macOS 27 不會讓 `TISEnableInputSource` 生效。`install-dev.sh` 會直接寫入已啟用清單。
- 新裝的輸入法要登出再登入一次，系統才會把按鍵交給它。其他第三方輸入法都有同一個限制。
- `tools/` 裡面是真機測試用的腳本（cua-driver 在 TextEdit 打真鍵），不會納入 app。
