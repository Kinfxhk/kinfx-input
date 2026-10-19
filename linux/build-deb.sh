#!/bin/bash
# Build the KINFX Input .deb on Debian/Ubuntu (needs librime-dev, librime-bin, gcc, dpkg-deb).
#   bash linux/build-deb.sh            -> linux/build/kinfx-input_<ver>_amd64.deb (+ self-test)
# The package carries the KINFX schemas prebuilt; users never install or edit a schema.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd)
B=$PWD/build
VER=$(python3 -c 'import json;print(json.load(open("../app-info.json"))["version"])')
ARCH=$(dpkg --print-architecture)
rm -rf "$B" && mkdir -p "$B"

# share dir = what lands in /usr/share/kinfx-input
S=$B/share; D=$S/data
mkdir -p "$D"
cp "$ROOT"/engine/prelude/*.yaml "$D/"
cp -R "$ROOT"/engine/rime/* "$D/"
python3 - "$D/default.yaml" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s2 = re.sub(r"schema_list:\n(  - schema: \w+\n)+", "schema_list:\n  - schema: kinfx_quick\n", s)
assert s2 != s
open(p, "w").write(s2)
EOF
U=$(mktemp -d); rime_deployer --build "$U" "$D" "$D/build" >/dev/null 2>&1; rm -rf "$U"
for t in kinfx_quick kinfx_quick_phrase kinfx_en kinfx_names kinfx_assoc; do
  [[ -f $D/build/$t.table.bin ]] || { echo "prebuild failed: $t.table.bin missing" >&2; exit 1; }
done
cp "$ROOT"/app-info.json "$ROOT"/settings-spec.json "$S/"
gcc -O2 -fPIC -shared -o "$S/libkxshim.so" "$ROOT/mac/Sources/Shim/kx_shim.c" -I"$ROOT/mac/Sources/Shim" -lrime

# self-test against the staged tree before packaging
T=$(mktemp -d)
KX_SHARE=$S KX_USER=$T python3 selftest.py
rm -rf "$T"

P=$B/pkg
install -d "$P/DEBIAN" "$P/usr/lib/kinfx-input" "$P/usr/bin" "$P/usr/share/ibus/component" \
  "$P/usr/share/applications"
cp -R "$S" "$P/usr/share/kinfx-input"
mv "$P/usr/share/kinfx-input/libkxshim.so" "$P/usr/lib/kinfx-input/"
install -m755 kinfx-ibus "$P/usr/lib/kinfx-input/kinfx-ibus"
install -m644 kxcore.py "$P/usr/lib/kinfx-input/kxcore.py"
install -m755 kinfx-input-settings "$P/usr/bin/kinfx-input-settings"
sed "s/@VERSION@/$VER/" kinfx-input.xml > "$P/usr/share/ibus/component/kinfx-input.xml"
install -m644 kinfx-input-settings.desktop "$P/usr/share/applications/"
cat > "$P/DEBIAN/control" <<EOF
Package: kinfx-input
Version: $VER
Architecture: $ARCH
Maintainer: KINFX <noreply@users.noreply.github.com>
Depends: ibus (>= 1.5), librime1t64 (>= 1.16) | librime1 (>= 1.16), librime-plugin-lua, python3, python3-gi, gir1.2-ibus-1.0, gir1.2-gtk-3.0
Section: utils
Priority: optional
Description: KINFX Input - Cangjie Quick / English mixed input method (IBus)
 Standalone input method with the KINFX Quick dictionaries built in.
 No Rime schema to install, no yaml or lua to edit; settings live in a window.
EOF
install -m755 postinst "$P/DEBIAN/postinst"
fakeroot dpkg-deb --build -Zxz "$P" "$B/kinfx-input_${VER}_${ARCH}.deb" 2>/dev/null \
  || dpkg-deb --root-owner-group --build -Zxz "$P" "$B/kinfx-input_${VER}_${ARCH}.deb"
echo "built: $B/kinfx-input_${VER}_${ARCH}.deb"
