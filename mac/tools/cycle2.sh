#!/bin/bash
# Rebuild + reinstall (keeps the session registration), restart KINFX via the system,
# make sure Squirrel is not running, type, show trace.
#   tools/cycle2.sh <flavor> <key>...
cd ~/kinfx-input-dev/w/mac
FLAVOR=$1; shift
bash build.sh app "$FLAVOR" 2>&1 | grep -E 'error|built:'
A="$HOME/Library/Input Methods/KINFX Input.app"
pkill -f 'KINFX Input.app/Contents/MacOS'; sleep 1
rm -rf "$A"; cp -R "build/KINFX Input.app" "$A"
for c in "$HOME/Library/Application Support/KINFX Input/log" "$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"; do
  mkdir -p "$c"; touch "$c/trace-on"; rm -f "$c/kx-trace.log"; done
pkill -f '/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel'
bash tools/te_front.sh hk.kinfx.inputmethod.KINFXInput.Hant "$@" | grep -E 'TEXT|keys:'
echo "kinfx: $(pgrep -f 'KINFX Input.app/Contents/MacOS' | tr '\n' ' ') squirrel: $(pgrep -f 'Squirrel.app/Contents/MacOS/Squirrel' | tr '\n' ' ')"
for c in "$HOME/Library/Application Support/KINFX Input/log" "$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"; do
  [[ -s $c/kx-trace.log ]] && { echo "== $c"; cut -c1-170 "$c/kx-trace.log" | tail -14; }; done
