#!/usr/bin/env bash
# Isolated ShiftSpace contract + real-engine replay. No live IMK or user settings.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(cd .. && pwd)
B=${KINFX_TEST_OUT:?Set KINFX_TEST_OUT to a scratch output directory}
R=${KINFX_RIME_DIR:-$PWD/build/rime}
SWIFTC=${SWIFTC:-swiftc}
SDK=${SDKROOT:-$(xcrun --show-sdk-path)}
mkdir -p "$B"
FLAGS=(-sdk "$SDK" -target "$(uname -m)-apple-macos13.0" -swift-version 5)
"$SWIFTC" "${FLAGS[@]}" Sources/Engine/RimeKeys.swift Sources/Engine/ShiftEnglish.swift Tests/ShiftSpace/main.swift -o "$B/contract-tests"
"$B/contract-tests" --all "$ROOT"
clang -isysroot "$SDK" -O2 -c Sources/Shim/kx_shim.c -I "$R/dist/include" -o "$B/kx_shim.o" -mmacosx-version-min=13.0
clang -isysroot "$SDK" -O2 -c Tests/ShiftSpace/support.c -I "$R/dist/include" -o "$B/shiftspace-support.o" -mmacosx-version-min=13.0
LINK=("$B/kx_shim.o" -L "$R/dist/lib" -lrime -Xlinker -rpath -Xlinker "$R/dist/lib")
"$SWIFTC" "${FLAGS[@]}" -import-objc-header Tests/ShiftSpace/support.h -I "$R/dist/include" Sources/Engine/*.swift Tests/ShiftSpace/Engine/main.swift "$B/shiftspace-support.o" "${LINK[@]}" -o "$B/engine-tests"
# Compile the complete production app path without launching, bundling, registering
# or installing it. Keeping this binary outside an .app avoids duplicate IMK IDs.
"$SWIFTC" "${FLAGS[@]}" -import-objc-header Sources/Shim/kx_shim.h -I "$R/dist/include" Sources/Engine/*.swift Sources/App/*.swift "${LINK[@]}" -framework InputMethodKit -framework Cocoa -o "$B/KINFXInput-compile-only"
# Each invocation owns a fresh snapshot and user directory. Never reuse the live
# KINFX support directory or another running test's Lua/settings/session state.
D=$(mktemp -d "$B/data.XXXXXX")
U=$(mktemp -d "$B/user.XXXXXX")
cp "$ROOT"/engine/prelude/*.yaml "$D/"
cp -R "$ROOT"/engine/rime/. "$D/"
python3 - "$D/default.yaml" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s, n = re.subn(r"schema_list:\n(  - schema: \w+\n)+", "schema_list:\n  - schema: kinfx_quick\n", s)
assert n == 1
p.write_text(s)
PY
printf 'DATA=%s\nUSER=%s\n' "$D" "$U"
"$B/engine-tests" "$D" "$U" "$B/engine-results.json"
