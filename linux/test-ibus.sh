#!/bin/bash
# No-root install test of the built .deb: unpack it, point a private ibus-daemon at it,
# type vd1 Return iPhone Space through IBus, then change page size to 5 and check.
set -euo pipefail
cd "$(dirname "$0")"
DEB=$(ls build/kinfx-input_*.deb | tail -1)
X=$(mktemp -d); dpkg-deb -x "$DEB" "$X"
H=$(mktemp -d)  # fake home: fresh user dir and ibus config
C=$X/comp; mkdir -p "$C"
# same <exec> as installed, through a wrapper that points at the unpacked tree and keeps stderr
cat > "$X/w.sh" <<EOF
#!/bin/sh
exec env KX_SHARE=$X/usr/share/kinfx-input KX_USER=$H/kx /usr/bin/python3 $X/usr/lib/kinfx-input/kinfx-ibus "\$@" 2>>$H/engine.log
EOF
chmod +x "$X/w.sh"
sed "s|<exec>.*</exec>|<exec>$X/w.sh --ibus</exec>|" "$X/usr/share/ibus/component/kinfx-input.xml" > "$C/kinfx-input.xml"
export HOME=$H XDG_CONFIG_HOME=$H/.config XDG_CACHE_HOME=$H/.cache IBUS_COMPONENT_PATH=$C
run() {
  dbus-run-session -- bash -c '
    ibus-daemon --panel=disable --emoji-extension=disable --cache=none --xim=no --config=disable 2>/dev/null &
    for i in $(seq 50); do ibus address >/dev/null 2>&1 && break; sleep 0.1; done; sleep 1
    python3 '"$PWD"'/test-ibus.py '"$1"'; r=$?; kill %1 2>/dev/null; exit $r'
}
echo "== default (page 9)"; run 9
mkdir -p "$H/kx"
KX_SHARE=$X/usr/share/kinfx-input KX_USER=$H/kx python3 -c "
import sys; sys.path.insert(0, '$X/usr/lib/kinfx-input'); import kxcore
v = kxcore.load('$H/kx/settings.json'); v['page_size'] = '5'; kxcore.save(v, '$H/kx/settings.json')"
echo "== after settings page 5"; run 5
[ -s "$H/engine.log" ] && { echo "== engine.log"; tail -20 "$H/engine.log"; }
rm -rf "$X" "$H"
