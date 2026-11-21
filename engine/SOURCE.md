# engine/

本目錄的 `rime/` 由核心引擎倉庫 [`Kinfxhk/kinfx-ime`](https://github.com/Kinfxhk/kinfx-ime) 自動同步，**請勿直接手改 `engine/rime/`**。

- **單一核心引擎來源**：`Kinfxhk/kinfx-ime`
- **Schema 版本**：`v0.6.0`
- **同步來源參考**：`main`（commit `e6c2d31aa35cd7511e37399509503c2b2f14c692`）
- **同步時間（UTC）**：`2026-11-21T14:12:57Z`

## 如何更新引擎

所有中英混打、速成次序、聯想詞與詞庫改動，一律先在 `kinfx-ime` 修改並通過回歸測試，再於本 repo 執行：

```bash
# 由本地鄰近目錄同步
python3 scripts/sync-engine.py --from-dir ../kinfx-ime

# 或由 GitHub 指定 tag 同步
python3 scripts/sync-engine.py --ref v0.6.0

# 檢查本目錄與上游是否零漂移（CI 用）
python3 scripts/sync-engine.py --from-dir ../kinfx-ime --check
```

## 獨立版專屬覆寫（Overlay）

`scripts/sync-engine.py` 在同步 `kinfx_quick.schema.yaml` 時只會套用兩項最小覆寫，其餘所有 Lua 與詞庫均與 `kinfx-ime` 逐位元一致：

1. **移除 `punctuator/half_shape`**：由 `engine/prelude/punctuation.yaml` 統一控制三平台單鍵標點與半形預設，避免兩份標點表衝突。
2. **移除 `recognizer/patterns/reverse_lookup`**：讓反引號 `` ` `` 直接輸出半形 ASCII，不彈出拼音反查選單。

## 其他目錄

- `prelude/`：`rime/rime-prelude` 基底加上 KINFX Input 共用 `punctuation.yaml`（LGPL-3.0）。
- `licenses/`：由 `kinfx-ime` 同步的 `LICENSE`、`NOTICE` 與詞庫授權說明。
