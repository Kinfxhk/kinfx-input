#!/bin/bash
# Let the system (imklaunchagent) start the input method instead of `open`, then type.
cd ~/kinfx-input-dev/w/mac
pkill -f 'KINFX Input.app/Contents/MacOS/KINFXInput'; sleep 1
C1="$HOME/Library/Application Support/KINFX Input/log"
C2="$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"
for c in "$C1" "$C2"; do mkdir -p "$c"; touch "$c/trace-on"; rm -f "$c/kx-trace.log"; done
bash tools/te_front.sh hk.kinfx.inputmethod.KINFXInput.Hant v d 1 | grep -E 'keys|TEXT'
pgrep -fl KINFXInput | cut -c1-110
for c in "$C1" "$C2"; do echo "== $c"; cut -c1-170 "$c/kx-trace.log" 2>/dev/null | tail -8; done
log show --last 40s --style compact --predicate 'process == "imklaunchagent"' 2>/dev/null | tail -8 | cut -c1-260
