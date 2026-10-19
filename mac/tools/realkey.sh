#!/bin/bash
# One clean real-key run: system-launched IM, trace on, TextEdit front, keys, then evidence.
#   tools/realkey.sh <key>...
cd ~/kinfx-input-dev/w/mac
C1="$HOME/Library/Application Support/KINFX Input/log"
C2="$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"
for c in "$C1" "$C2"; do mkdir -p "$c"; touch "$c/trace-on"; rm -f "$c/kx-trace.log"; done
S=$(date '+%Y-%m-%d %H:%M:%S')
bash tools/te_front.sh hk.kinfx.inputmethod.KINFXInput.Hant "$@" | grep -E 'TEXT|keys:'
echo "== KINFX processes"; pgrep -fl KINFXInput | cut -c1-100
for c in "$C1" "$C2"; do [[ -s $c/kx-trace.log ]] && { echo "== trace $c"; cut -c1-170 "$c/kx-trace.log" | tail -15; }; done
echo "== imklaunchagent"
log show --start "$S" --style compact --predicate 'process == "imklaunchagent"' 2>/dev/null | grep -vE 'activating connection|listener port' | tail -8 | cut -c1-220
ls -t ~/Library/Logs/DiagnosticReports | grep -i kinfx | head -3
