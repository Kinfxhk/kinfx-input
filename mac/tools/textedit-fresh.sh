#!/bin/bash
# Fresh TextEdit with exactly one scratch document titled 未命名 (the test's own window).
# Only run when TextEdit holds nothing but test scratch documents.
pkill -9 -x TextEdit; sleep 1
rm -f "$HOME/Library/Containers/com.apple.TextEdit/Data/Library/Autosave Information/"*.rtf
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
defaults write com.apple.TextEdit RichText -int 0
open -a TextEdit; sleep 4
D=/Applications/CuaDriver.app/Contents/MacOS/cua-driver
P=$(pgrep -x TextEdit | head -1)
$D call list_windows "{\"pid\":$P}" | python3 -c '
import json,sys; d=json.load(sys.stdin)
for w in d["windows"]:
  if w["is_on_screen"]: print(w["window_id"], repr(w["title"]))'
