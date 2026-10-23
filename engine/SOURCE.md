# engine/

- `rime/`：由 Kinfxhk/kinfx-ime tag v0.5.10（`2c4b38e691c268ef71564b58ed1560d6b3d75ee1`）抄過嚟。schemas/kinfx-quick、lexicon/hk、lexicon/en、schemas/rime.lua、schemas/lua。之後喺呢度改過：
  - `lua/assoc.lua`：揀字後 Enter 關聯想並換行（72b72a2）。
  - `kinfx_en_names.txt`：短英文 token（7580700）；0.1.1 加 init mcp gank rekt pog kekw copium gg wp gl，刪走錯碼嘅 `yml	ym`。
  - 0.1.1 `lua/english_mix.lua`：英文詞＋「.」＋中文唔再卡住（hello.vd1 → hello。好，只有 com／js／md 等後綴先留英文）；Enter ? ! : ; ) 上屏英文詞；刪走「5 個字母英文開頭撳空白上屏」（fogge␣1 變返 炊圭水）；縮寫 don't／it's；名表 2 個字母詞只限空白上屏；唔同 session 唔再共用未上屏英文。
  - 0.1.1 `kinfx_quick.schema.yaml`：recognizer url 加縮寫 pattern。
  - 0.1.2 `lua/english_mix.lua`：打緊字撳貼嘢（Ctrl+V）嗰陣，已頂字嘅中文照上屏，字母清走，再交返 app 貼（同「先 Esc 再貼」結果一樣）。Mac 嘅 ⌘V 唔經過引擎；TextEdit 貼嘢會保留未上屏字母，連 Apple 內建輸入法都係咁，IMK 層面冇得修，做法係先 Esc 再貼。
  - 0.1.4 `lua/english_mix.lua`：失焦（撳滑鼠去第二度、轉視窗）時，殼送 F35（0xffe0）。英文字母照打出嚟咁上屏（hel → hel，vdhel → vdhel），速成碼照 Enter 上屏（vd → 好），唔會成段消失。Windows 殼喺 OnCompositionTerminated 寫入；Mac／Linux 殼仲未接。
- `prelude/`：rime/rime-prelude `082425ea0684bca36474415d4a0e8db9b016487e`（default、key_bindings、punctuation、symbols，LGPL-3.0）。
- `licenses/`：kinfx-ime 嘅 LICENSE、NOTICE，同詞庫 NOTICE。

要改打字行為就喺呢度改，唔好返去改公開 repo `kinfx-ime`（停喺 v0.5.10）。
