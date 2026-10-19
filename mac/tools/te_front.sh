#!/bin/bash
# Keep TextEdit frontmost, select the source while it is focused, then type and read back.
#   te_front.sh <source id> <key>...   keys use cua-driver names
cd ~/kinfx-input-dev/w/mac
D=/Applications/CuaDriver.app/Contents/MacOS/cua-driver
echo "per-context input: $(defaults read com.apple.HIToolbox AppleGlobalTextInputProperties 2>/dev/null | tr -d '\n ')"
P=$(pgrep -x TextEdit | head -1)
W=$($D call list_windows "{\"pid\":$P}" | python3 -c '
import json,sys; d=json.load(sys.stdin); print([w["window_id"] for w in d["windows"] if w["is_on_screen"] and w["title"]=="未命名"][0])')
st() { $D call get_window_state "{\"pid\":$P,\"window_id\":$W}"; }
SRC=$1; shift
TOK=$(st | python3 -c 'import json,sys; d=json.load(sys.stdin); print([e["element_token"] for e in d["elements"] if e.get("role")=="AXTextArea"][0])')
$D call set_value "{\"pid\":$P,\"window_id\":$W,\"element_token\":\"$TOK\",\"value\":\"\"}" >/dev/null
$D call bring_to_front "{\"pid\":$P,\"window_id\":$W}" | head -c 120; echo
sleep 1
build/kx-tis select "$SRC" >/dev/null; sleep 0.5
echo "before keys: $(build/kx-tis current)"
for k in "$@"; do
  $D call press_key "{\"pid\":$P,\"window_id\":$W,\"key\":\"$k\",\"delivery_mode\":\"foreground\"}" >/dev/null
  sleep 0.25
done
sleep 0.8
echo "after keys: $(build/kx-tis current)"
st | python3 -c 'import json,sys; d=json.load(sys.stdin); print("TEXT [%s]" % [(e.get("value") or "") for e in d["elements"] if e.get("role")=="AXTextArea"][0])'
build/kx-mods
