#!/usr/bin/env bash
# Build KINFX Input for macOS without Xcode (Command Line Tools + swiftc).
#   mac/build.sh selftest      build and run the engine self-test
#   mac/build.sh app [direct]  build build/KINFX Input.app (ad-hoc signed unless SIGN_ID is set)
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd)
B=$PWD/build
mkdir -p "$B"

# librime 1.17.0 universal build with librime-lua (rime/librime release asset).
RIME_URL=https://github.com/rime/librime/releases/download/1.17.0/rime-33e7814-macOS-universal.tar.bz2
RIME_SHA=11d8dc663c6ec06d5ccb6111ba664a9e7b631b703ac6acd07cffbac664021850
R=$B/rime
if [[ ! -f $R/dist/lib/librime.1.dylib ]]; then
  curl -sfL -o "$B/rime.tar.bz2" "$RIME_URL"
  echo "$RIME_SHA  $B/rime.tar.bz2" | shasum -a 256 -c -
  rm -rf "$R" && mkdir -p "$R" && tar -xjf "$B/rime.tar.bz2" -C "$R"
fi

# Shared data = rime-prelude + the KINFX schemas and dictionaries, prebuilt.
stage_data() {
  local D=$B/data
  rm -rf "$D" && mkdir -p "$D"
  cp "$ROOT"/engine/prelude/*.yaml "$D/"
  cp -R "$ROOT"/engine/rime/* "$D/"
  python3 - "$D/default.yaml" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s2 = re.sub(r"schema_list:\n(  - schema: \w+\n)+", "schema_list:\n  - schema: kinfx_quick\n", s)
assert s2 != s
open(p, "w").write(s2)
EOF
  local U; U=$(mktemp -d)
  DYLD_LIBRARY_PATH=$R/dist/lib "$R/dist/bin/rime_deployer" --build "$U" "$D" "$D/build" >/dev/null 2>&1
  rm -rf "$U"
  for t in kinfx_quick kinfx_quick_phrase kinfx_en kinfx_names kinfx_assoc; do
    [[ -f $D/build/$t.table.bin ]] || { echo "prebuild failed: $t.table.bin missing" >&2; exit 1; }
  done
}

SW_FLAGS=(-O -swift-version 5 -import-objc-header Sources/Shim/kx_shim.h -I "$R/dist/include")
compile_shim() {  # $1 = arch flags target
  clang -O2 -c Sources/Shim/kx_shim.c -I "$R/dist/include" -o "$B/kx_shim.o" -arch arm64 -arch x86_64 -mmacosx-version-min=13.0
}

case "${1:-}" in
selftest)
  stage_data
  compile_shim
  swiftc "${SW_FLAGS[@]}" Sources/Engine/*.swift Tests/SelfTest/main.swift "$B/kx_shim.o" \
    -L "$R/dist/lib" -lrime -Xlinker -rpath -Xlinker "$R/dist/lib" -o "$B/kinfx-selftest"
  U=$(mktemp -d)
  "$B/kinfx-selftest" "$B/data" "$U"
  rm -rf "$U"
  ;;
app)
  FLAVOR=${2:-store}
  stage_data
  compile_shim
  APP="$B/KINFX Input.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks/rime-plugins" "$APP/Contents/Resources"
  for arch in arm64 x86_64; do
    swiftc "${SW_FLAGS[@]}" -target $arch-apple-macos13.0 Sources/Engine/*.swift Sources/App/*.swift "$B/kx_shim.o" \
      -L "$R/dist/lib" -lrime -framework InputMethodKit -framework Cocoa \
      -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$B/KINFXInput-$arch"
  done
  lipo -create "$B/KINFXInput-arm64" "$B/KINFXInput-x86_64" -output "$APP/Contents/MacOS/KINFXInput"
  cp -L "$R/dist/lib/librime.1.dylib" "$APP/Contents/Frameworks/librime.1.dylib"
  cp "$R/dist/lib/rime-plugins/librime-lua.dylib" "$APP/Contents/Frameworks/rime-plugins/"
  cp -R "$B/data" "$APP/Contents/Resources/data"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  swift tools/make-icon.swift "$APP/Contents/Resources/KINFX.tiff"
  ENT=Resources/KINFXInput-$FLAVOR.entitlements
  [[ -f $ENT ]] || { echo "unknown flavor $FLAVOR" >&2; exit 2; }
  SIGN=${SIGN_ID:--}
  OPTS=(--force --timestamp=none --sign "$SIGN")
  [[ $SIGN != - ]] && OPTS=(--force --timestamp --options runtime --sign "$SIGN")
  codesign "${OPTS[@]}" "$APP/Contents/Frameworks/rime-plugins/librime-lua.dylib"
  codesign "${OPTS[@]}" "$APP/Contents/Frameworks/librime.1.dylib"
  codesign "${OPTS[@]}" --entitlements "$ENT" "$APP"
  codesign --verify --deep --strict "$APP"
  echo "built: $APP ($FLAVOR, signed with $SIGN)"
  ;;
*)
  echo "usage: $0 selftest | app [store|direct]" >&2; exit 2 ;;
esac
