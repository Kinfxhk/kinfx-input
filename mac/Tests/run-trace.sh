#!/usr/bin/env bash
# Execute the real controller trace against actual NSEvents, without IMK install,
# window activation, synthetic keys or daily data. Keep scratch evidence on failure.
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
SCRATCH=${TMPDIR:-"$HOME/.hermes/cache/scratch"}
mkdir -p "$SCRATCH"
B=${KINFX_TEST_OUT:-$(mktemp -d "$SCRATCH/kinfx-trace-test.XXXXXX")}
R=${KINFX_RIME_DIR:-$PWD/build/rime}
SWIFTC=${SWIFTC:-$(xcrun --find swiftc)}
SDK=${SDKROOT:-$(xcrun --show-sdk-path)}
mkdir -p "$B"
printf 'TRACE_EVIDENCE=%s\n' "$B"
clang -isysroot "$SDK" -O2 -mmacosx-version-min=12.0 \
  -c Sources/Shim/kx_shim.c -I "$R/dist/include" -o "$B/kx_shim.o"
"$SWIFTC" -sdk "$SDK" -target "$(uname -m)-apple-macos12.0" -swift-version 5 \
  -module-cache-path "$B/module-cache" -import-objc-header Sources/Shim/kx_shim.h \
  Sources/Engine/*.swift Sources/App/InputController.swift \
  Tests/Trace/Support.swift Tests/Trace/main.swift "$B/kx_shim.o" \
  -L "$R/dist/lib" -lrime -Xlinker -rpath -Xlinker "$R/dist/lib" \
  -o "$B/trace-tests"
"$B/trace-tests" "$B/user"
