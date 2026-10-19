#!/bin/bash
# Full sequence: refresh session list (toggle an unused mode), restart TextEdit,
# select KINFX inside the GUI session, type, show who handled it.
#   tools/realkey2.sh <key>...
cd ~/kinfx-input-dev/w/mac
C="$HOME/Library/Application Support/KINFX Input/log"
mkdir -p "$C"; touch "$C/trace-on"; rm -f "$C/kx-trace.log"
bash tools/tis-refresh.sh >/dev/null 2>&1
pkill -9 -x TextEdit; sleep 1
rm -f "$HOME/Library/Containers/com.apple.TextEdit/Data/Library/Autosave Information/"*.rtf 2>/dev/null
open -a TextEdit; sleep 4
bash tools/te_gui.sh "$@"
