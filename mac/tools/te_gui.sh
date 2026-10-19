#!/bin/bash
# Select KINFX from inside the GUI session (not from ssh), front TextEdit, type, read back.
#   tools/te_gui.sh <key>...
cd ~/kinfx-input-dev/w/mac
D=/Applications/CuaDriver.app/Contents/MacOS/cua-driver
P=$(pgrep -x TextEdit | head -1)
W=$($D call list_windows "{\"pid\":$P}" | python3 -c '
import json,sys; d=json.load(sys.stdin); print([w["window_id"] for w in d["windows"] if w["is_on_screen"] and w["title"]=="未命名"][0])')
st() { $D call get_window_state "{\"pid\":$P,\"window_id\":$W}"; }
TOK=$(st | python3 -c 'import json,sys; d=json.load(sys.stdin); print([e["element_token"] for e in d["elements"] if e.get("role")=="AXTextArea"][0])')
$D call set_value "{\"pid\":$P,\"window_id\":$W,\"element_token\":\"$TOK\",\"value\":\"\"}" >/dev/null
$D call bring_to_front "{\"pid\":$P,\"window_id\":$W}" >/dev/null
sleep 1
bash tools/gui-run.sh "$PWD/build/kx-tis" select hk.kinfx.inputmethod.KINFXInput.Hant 2>&1 | grep -v sandbox_ext
$D call bring_to_front "{\"pid\":$P,\"window_id\":$W}" >/dev/null
sleep 1
echo "before keys: $(build/kx-tis current)"
for k in "$@"; do
  $D call press_key "{\"pid\":$P,\"window_id\":$W,\"key\":\"$k\",\"delivery_mode\":\"foreground\"}" >/dev/null
  sleep 0.25
done
sleep 0.8
st | python3 -c 'import json,sys; d=json.load(sys.stdin); print("TEXT [%s]" % [(e.get("value") or "") for e in d["elements"] if e.get("role")=="AXTextArea"][0])'
echo "kinfx: $(pgrep -f 'KINFX Input.app/Contents/MacOS' | tr '\n' ' ') squirrel: $(pgrep -f 'Squirrel.app/Contents/MacOS/Squirrel' | tr '\n' ' ')"
cut -c1-150 "$HOME/Library/Application Support/KINFX Input/log/kx-trace.log" 2>/dev/null | tail -8
build/kx-mods
