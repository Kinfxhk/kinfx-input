#!/usr/bin/env bash
# Run a command inside the logged-in GUI session (TIS calls made from ssh do not
# stick). Wraps the command in a throwaway .app and starts it with `open -W`.
#   mac/tools/gui-run.sh <command...>     output is printed after it finishes
set -euo pipefail
D=$(mktemp -d)/KXRun.app
mkdir -p "$D/Contents/MacOS"
OUT=$(mktemp)
{
  echo '#!/bin/bash'
  printf 'exec >%q 2>&1\n' "$OUT"
  printf '%q ' "$@"; echo
} > "$D/Contents/MacOS/KXRun"
chmod +x "$D/Contents/MacOS/KXRun"
cat > "$D/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KXRun</string>
<key>CFBundleIdentifier</key><string>hk.kinfx.kxrun</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
open -W -n "$D"
cat "$OUT"
rm -rf "$(dirname "$D")" "$OUT"
