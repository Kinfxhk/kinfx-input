#!/usr/bin/env bash
# Isolated native AppKit tests: invisible windows, no IMK registration or keys.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(cd .. && pwd)
B=${KINFX_TEST_OUT:-$PWD/build/interaction-tests}
R=${KINFX_RIME_DIR:-$PWD/build/rime}
SWIFTC=${SWIFTC:-swiftc}
SDK=${SDKROOT:-$(xcrun --show-sdk-path)}
mkdir -p "$B"
FLAGS=(-sdk "$SDK" -target "$(uname -m)-apple-macos13.0" -swift-version 5
       -import-objc-header Sources/Shim/kx_shim.h -I "$R/dist/include")
clang -isysroot "$SDK" -O2 -c Sources/Shim/kx_shim.c -I "$R/dist/include" -o "$B/kx_shim.o" -mmacosx-version-min=13.0
LINK=("$B/kx_shim.o" -L "$R/dist/lib" -lrime -framework Cocoa -Xlinker -rpath -Xlinker "$R/dist/lib")
"$SWIFTC" "${FLAGS[@]}" Sources/Engine/*.swift Sources/App/CandidatePanel*.swift Tests/CandidatePanel/main.swift "${LINK[@]}" -o "$B/candidate-panel-tests"
"$B/candidate-panel-tests"
"$SWIFTC" "${FLAGS[@]}" Sources/Engine/*.swift Sources/App/SettingsWindow.swift Sources/App/AppInfo.swift Tests/Settings/main.swift "${LINK[@]}" -o "$B/settings-tests"
KINFX_TEST_OUT="$B/settings-reload" bash Tests/run-settings-reload.sh
KINFX_TEST_OUT="$B/trace" bash Tests/run-trace.sh
"$B/settings-tests" "$ROOT" "$B"
