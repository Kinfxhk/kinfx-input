#!/bin/bash
# Real keys into the scratch TextEdit window 未命名, KINFX selected in the GUI session,
# trace on; prints app text and the controller trace.  Usage: tools/rk.sh <key>...
#   keys: cua-driver names; "shift+p" = P with Shift held.
cd ~/kinfx-input-dev/w/mac
D=/Applications/CuaDriver.app/Contents/MacOS/cua-driver
P=$(pgrep -x TextEdit | head -1)
W=$($D call list_windows "{\"pid\":$P}" | python3 -c '
import json,sys; d=json.load(sys.stdin); print([w["window_id"] for w in d["windows"] if w["is_on_screen"] and w["title"]=="未命名"][0])')
st() { $D call get_window_state "{\"pid\":$P,\"window_id\":$W}"; }
for c in "$HOME/Library/Application Support/KINFX Input/log" "$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"; do
  mkdir -p "$c"; touch "$c/trace-on"; rm -f "$c/kx-trace.log"; done
TOK=$(st | python3 -c 'import json,sys; d=json.load(sys.stdin); print([e["element_token"] for e in d["elements"] if e.get("role")=="AXTextArea"][0])')
$D call set_value "{\"pid\":$P,\"window_id\":$W,\"element_token\":\"$TOK\",\"value\":\"\"}" >/dev/null
$D call bring_to_front "{\"pid\":$P,\"window_id\":$W}" >/dev/null; sleep 1
bash tools/gui-run.sh "$PWD/build/kx-tis" select hk.kinfx.inputmethod.KINFXInput.Hant 2>&1 | grep -v sandbox_ext >/dev/null
$D call bring_to_front "{\"pid\":$P,\"window_id\":$W}" >/dev/null; sleep 1
echo "source: $(build/kx-tis current)"
for k in "$@"; do
  mods="[]"; key=$k
  if [[ $k == *+* ]]; then mods="[\"${k%%+*}\"]"; key=${k#*+}; fi
  $D call press_key "{\"pid\":$P,\"window_id\":$W,\"key\":\"$key\",\"modifiers\":$mods,\"delivery_mode\":\"foreground\"}" >/dev/null
  sleep 0.25
done
sleep 0.8
st | python3 -c 'import json,sys; d=json.load(sys.stdin); print("TEXT [%s]" % [(e.get("value") or "") for e in d["elements"] if e.get("role")=="AXTextArea"][0])'
for c in "$HOME/Library/Application Support/KINFX Input/log" "$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"; do
  [[ -s $c/kx-trace.log ]] && cut -c27-200 "$c/kx-trace.log"; rm -f "$c/trace-on" "$c/kx-trace.log"; done
build/kx-tis select org.openvanilla.inputmethod.OpenVanilla >/dev/null
bash tools/gui-run.sh "$PWD/build/kx-tis" select org.openvanilla.inputmethod.OpenVanilla >/dev/null 2>&1
build/kx-mods
