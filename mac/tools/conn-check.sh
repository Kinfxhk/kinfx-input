#!/bin/bash
# Install the fresh build, select KINFX in the GUI session, focus TextEdit, then report
# whether imklaunchagent still refuses the connection name and whether a controller exists.
cd ~/kinfx-input-dev/w/mac
A="$HOME/Library/Input Methods/KINFX Input.app"
for c in "$HOME/Library/Application Support/KINFX Input/log" "$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"; do
  mkdir -p "$c"; touch "$c/trace-on"; rm -f "$c/kx-trace.log"; done
pkill -f 'KINFX Input.app/Contents/MacOS'; sleep 1
rm -rf "$A"; cp -R "build/KINFX Input.app" "$A"
/usr/libexec/PlistBuddy -c 'Print :InputMethodConnectionName' "$A/Contents/Info.plist"
build/kx-tis register "$A"; sleep 2
S=$(date '+%Y-%m-%d %H:%M:%S')
open -a TextEdit; sleep 2
bash tools/gui-run.sh "$PWD/build/kx-tis" select hk.kinfx.inputmethod.KINFXInput.Hant 2>&1 | grep -v sandbox_ext
open -a TextEdit; sleep 4
echo "current: $(build/kx-tis current)"
log show --start "$S" --style compact 2>/dev/null | grep -E 'Refusing connection name|setIMKXPCEndpoint|EndpointInvalid|NO Endpoint' | cut -c1-200
for c in "$HOME/Library/Application Support/KINFX Input/log" "$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"; do
  [[ -s $c/kx-trace.log ]] && { echo "== trace"; cut -c27-200 "$c/kx-trace.log"; }; done
bash tools/gui-run.sh "$PWD/build/kx-tis" select org.openvanilla.inputmethod.OpenVanilla >/dev/null 2>&1
echo "restored: $(build/kx-tis current)"
