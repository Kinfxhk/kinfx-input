#!/usr/bin/python3
"""IBus-level test with no root: a private ibus-daemon loads only the KINFX component
from the unpacked .deb, an InputContext sends real IBus key events, and we collect
commit-text. Run inside dbus-run-session with IBUS_COMPONENT_PATH set (see test-ibus.sh).
"""
import sys
import time

import gi
gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402

IBus.init()
bus = IBus.Bus()
for _ in range(50):
    if bus.is_connected():
        break
    time.sleep(0.1)
assert bus.is_connected(), "no ibus-daemon"
names = [e.get_name() for e in bus.list_engines()]
print("engines:", names)
assert "kinfx" in names, "kinfx engine not listed"

# ibus uses one global engine by default; set it before the context takes focus.
assert bus.set_global_engine("kinfx"), "set_global_engine failed"
time.sleep(2)
ic = bus.create_input_context("kx-test")
ic.set_capabilities(IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.LOOKUP_TABLE | IBus.Capabilite.FOCUS)
out, tables = [], []
ic.connect("commit-text", lambda _ic, t: out.append(t.get_text()))
ic.connect("update-lookup-table", lambda _ic, t, v: tables.append(t.get_number_of_candidates()))
ic.focus_in()
ctx = GLib.MainContext.default()


def pump(sec=0.3):
    end = time.time() + sec
    while time.time() < end:
        ctx.iteration(False)
        time.sleep(0.01)


pump(1.5)
print("engine:", ic.get_engine().get_name())
passed = {}


def send(keyval, state=0):
    h = ic.process_key_event(keyval, 0, state)
    ic.process_key_event(keyval, 0, state | IBus.ModifierType.RELEASE_MASK)
    pump(0.15)
    return h


for c in "vd":
    send(ord(c))
passed["vd shows %s" % sys.argv[1] if len(sys.argv) > 1 else "vd shows 9"] = tables[-1] if tables else None
send(ord("1"))
r = send(0xff0d)
for c in "iPhone ":
    send(ord(c))
pump(0.5)
text = "".join(out)
print("commits:", out, "return handled:", r, "last table:", passed)
want_n = int(sys.argv[1]) if len(sys.argv) > 1 else 9
ok = text == "好iPhone " and r is False and list(passed.values())[0] == want_n
print("ALL PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
