#!/usr/bin/env bash
# Developer install for KINFX Input on this Mac (user scope, no sudo):
#   mac/install-dev.sh            install build/KINFX Input.app and enable it
#   mac/install-dev.sh --remove   remove it and restore the input source lists
# macOS 26+ ignores TISEnableInputSource for an ad-hoc signed input method, so the
# enabled-source lists get the two entries a manual "+" in System Settings adds.
set -euo pipefail
cd "$(dirname "$0")"
ID=hk.kinfx.inputmethod.KINFXInput
MODE=$ID.Hant
DEST="$HOME/Library/Input Methods/KINFX Input.app"
BK="$HOME/Library/Application Support/KINFX Input dev"
LISTS=("HIToolbox AppleEnabledInputSources" "inputsources AppleEnabledThirdPartyInputSources")
mkdir -p "$BK"

if [[ ${1:-} == --remove ]]; then
  pkill -f "$DEST/Contents/MacOS/KINFXInput" || true
  for d in HIToolbox inputsources; do
    [[ -f $BK/$d.plist ]] && defaults import com.apple.$d "$BK/$d.plist"
  done
  rm -rf "$DEST"
  killall TextInputMenuAgent 2>/dev/null || true
  echo "removed; input source lists restored from $BK"
  exit 0
fi

[[ -d "build/KINFX Input.app" ]] || { echo "run mac/build.sh app first" >&2; exit 1; }
for d in HIToolbox inputsources; do
  [[ -f $BK/$d.plist ]] || defaults export com.apple.$d "$BK/$d.plist"
done
pkill -f "$DEST/Contents/MacOS/KINFXInput" || true
rm -rf "$DEST"
cp -R "build/KINFX Input.app" "$DEST"
swiftc -O tools/kx-tis.swift -o build/kx-tis 2>/dev/null
build/kx-tis register "$DEST"
for pair in "${LISTS[@]}"; do
  read -r dom key <<<"$pair"
  if ! defaults read com.apple.$dom "$key" 2>/dev/null | grep -q "$MODE"; then
    defaults write com.apple.$dom "$key" -array-add \
      "<dict><key>Bundle ID</key><string>$ID</string><key>InputSourceKind</key><string>Keyboard Input Method</string></dict>" \
      "<dict><key>Bundle ID</key><string>$ID</string><key>Input Mode</key><string>$MODE</string><key>InputSourceKind</key><string>Input Mode</string></dict>"
  fi
done
killall TextInputMenuAgent 2>/dev/null || true
sleep 2
build/kx-tis select "$MODE"
build/kx-tis current
