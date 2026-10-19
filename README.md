# KINFX Input

獨立輸入法。引擎用現有 KINFX 速成（librime + schema），殼係自己的。公開 repo `kinfx-ime` 停喺 v0.5.10，呢度唔好再推返去。

## 平台

| 殼 | 系統 API | 備註 |
| --- | --- | --- |
| macOS | Input Method Kit | MacBook Neo 係 macOS，用同一個殼。上架要 sandbox，唔可以靠用戶另裝鼠鬚管。 |
| Windows | TSF | 唔靠小狼毫。 |
| iPad / iOS | Keyboard Extension | 同 macOS 唔係同一個二進位。 |
| Android | IME | Google Play。唔係 Google Books。 |

先做 macOS 殼。其他殼之後接同一個 `settings.json`，唔好先寫四套。

## 用戶唔改碼

設定只經視窗。程式把開關寫入 `settings.json`，再生成 Rime custom，用戶唔好見到 yaml／lua。

開關只此幾項：

- 每頁候選：9 或 5
- 英文空白：安全／只限長詞／關
- 聯想詞：開／關
- 揀字後空白：打出空格／翻頁
- 常用詞前綴：熱門／全部／關
- 左 Shift 無輸入時：不做／臨時英文
- 預編輯：字母／字根

唔好把 `unknown_space_min`、`hold_min` 等數字暴露成用戶欄位。
