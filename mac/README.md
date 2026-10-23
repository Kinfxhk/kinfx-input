# KINFX Input — macOS 殼

同一個殼行 Mac Studio 同 MacBook Neo（都係 macOS）。引擎係 librime 1.17.0 加 librime-lua，KINFX 詞庫同 schema 預先編譯好，一齊封入 app，唔使裝鼠鬚管。

## 結構

| 路徑 | 內容 |
| --- | --- |
| `Sources/Shim/` | 包住 librime C API 嘅一層 C 程式，Swift 唔使理 C struct |
| `Sources/Engine/` | `Settings`（settings.json 同 Rime patch）、`Engine`、按鍵對照，冇 UI，self-test 都用呢部分 |
| `Sources/App/` | IMK 入口、`KINFXInputController`、候選窗、設定視窗 |
| `Tests/SelfTest/` | 唔使 GUI：設定、按鍵對照、`vd1` → 好、每頁 5／9 切換 |
| `Resources/` | Info.plist；entitlements 分 `store`（sandbox）、`direct`（sandbox，加用戶揀檔唯讀）、`dev`（冇 sandbox，只係本機排錯用） |
| `../engine/` | 由 kinfx-ime v0.5.10（`2c4b38e691`）抄過嚟嘅 schema、詞庫、Lua，加 rime-prelude |

## 設定

只有設定視窗會寫 `settings.json`，程式再由佢生成 `kinfx_quick.custom.yaml`，用戶唔會見到 yaml 或者 lua。欄位喺 `Settings.specs`，其他平台嘅殼都用同一套 key 同值：

`page_size` 9/5 · `english_space` safe/long/off · `association` true/false · `space_after_pick` page/type · `phrase_capture` hot/all/off · `empty_shift` noop/ascii · `preedit` letters/radicals

## 建置（唔使 Xcode，Command Line Tools 就得）

```sh
mac/build.sh selftest            # 引擎 self-test
mac/build.sh app store           # build/KINFX Input.app（sandbox）
mac/build.sh app direct          # 直裝版
SIGN_ID="Developer ID Application: …" mac/build.sh app direct   # 正式簽名，加 hardened runtime
mac/install-dev.sh               # 裝去 ~/Library/Input Methods 並啟用（本機開發用）
mac/install-dev.sh --remove      # 移除，輸入法清單還原
```

## 已知

- 冇 Developer ID 嘅 ad-hoc 簽名，macOS 27 唔會俾 `TISEnableInputSource` 生效。`install-dev.sh` 會直接寫入已啟用清單。
- 新裝嘅輸入法要登出再登入一次，系統先會將按鍵交俾佢。其他第三方輸入法都有同一個限制。
- `tools/` 入面係真機測試用嘅腳本（cua-driver 打真鍵入 TextEdit），唔會入 app。
