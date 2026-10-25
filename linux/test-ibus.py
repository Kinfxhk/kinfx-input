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

# 0.1.1 English fixes through real IBus key events (Shift+/ arrives as "?" with the shift mask)
SHIFT = IBus.ModifierType.SHIFT_MASK
for keys, want in [("hello.vd1", "hello.\u597d"), ("hello\r", "hello"), ("thanks?", "thanks?"),
                   ("don't ", "don't "), ("gg ", "gg "), ("fogge 1", "\u708a\u572d\u6c34")]:
    out.clear()
    for c in keys:
        if c == "\r":
            send(0xff0d)
        elif c == "?":
            send(0xffe1)  # Shift_L press, then ?, then release: what a keyboard sends
            send(ord(c), SHIFT)
        else:
            send(ord(c))
    pump(0.3)
    got = "".join(out)
    print("%s %r: got %r want %r" % ("PASS" if got == want else "FAIL", keys, got, want))
    ok = ok and got == want

# 0.1.2: Ctrl+V mid-composition flushes the held top-outs (Windows model)
out.clear()
for c in "vdhel":
    send(ord(c))
send(ord("v"), IBus.ModifierType.CONTROL_MASK)
pump(0.3)
got = "".join(out)
print("%s %r: got %r want %r" % ("PASS" if got == "\u597d\u53cd" else "FAIL", "vdhel ctrl+v", got, "\u597d\u53cd"))
ok = ok and got == "\u597d\u53cd"

# 0.1.4: what was typed stays in the field being left (COMMIT-mode preedit), never in the next one
ic2 = bus.create_input_context("kx-test2")
ic2.set_capabilities(IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.LOOKUP_TABLE | IBus.Capabilite.FOCUS)
out2 = []
ic2.connect("commit-text", lambda _ic, t: out2.append(t.get_text()))
for keys, want, leave in [("hel", "hel", "focus"), ("vdhel", "vdhel", "focus"), ("vd", "\u597d", "focus"),
                          ("vdhel", "vdhel", "reset")]:
    out.clear()
    out2.clear()
    for c in keys:
        send(ord(c))
    if leave == "focus":
        ic.focus_out()  # a click into another field: the client sends focus-out, then the new field focus-in
        ic2.focus_in()
    else:
        ic.reset()  # click inside the same field
    pump(0.5)
    got = ("".join(out), "".join(out2))
    print("%s %r %s: got %r want %r" % ("PASS" if got == (want, "") else "FAIL", keys, leave, got, (want, "")))
    ok = ok and got == (want, "")
    if leave == "focus":
        ic.focus_in()
        pump(0.5)
# nothing typed: leaving commits nothing
out.clear()
out2.clear()
ic.focus_out()
ic2.focus_in()
pump(0.5)
got = ("".join(out), "".join(out2))
print("%s empty focus: got %r want %r" % ("PASS" if got == ("", "") else "FAIL", got, ("", "")))
ok = ok and got == ("", "")

# GTK clients (client_commit_preedit) commit the COMMIT-mode preedit themselves on focus-out:
# the last preedit they hold must be the blur text in COMMIT mode
ic3 = bus.create_input_context("kx-test3")
ic3.set_capabilities(IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.LOOKUP_TABLE | IBus.Capabilite.FOCUS)
ic3.set_client_commit_preedit(True)
pre3 = []
ic3.connect("update-preedit-text-with-mode", lambda _ic, t, c, v, m: pre3.append((t.get_text(), v, int(m))))
ic3.focus_in()
pump(0.5)
for c in "vd":
    ic3.process_key_event(ord(c), 0, 0)
    ic3.process_key_event(ord(c), 0, IBus.ModifierType.RELEASE_MASK)
    pump(0.15)
got = pre3[-1] if pre3 else None
want = ("\u597d", True, int(IBus.PreeditFocusMode.COMMIT))
print("%s 'vd' client preedit: got %r want %r" % ("PASS" if got == want else "FAIL", got, want))
ok = ok and got == want
ic3.focus_out()
pump(0.3)

# 0.1.8: punctuation is one key, one character, no candidate list. 半形 (default) = ASCII,
# 全形 (Shift+Space) = Chinese punctuation, same as Windows Quick.
punct = [(',', ','), ('.', '.'), ('?', '?'), ('!', '!'), (';', ';'), (':', ':'),
         ('(', '('), (')', ')'), ('[', '['), (']', ']'), ('{', '{'), ('}', '}'),
         ('<', '<'), ('>', '>'), ('/', '/'), ('\\', '\\'), ("'", "'"), ('"', '"'), ('-', '-'), ('$', '$'), ('%', '%'), ('*', '*'), ('~', '~')]
for key, want in punct:
    out.clear()
    n_before = len(tables)
    send(ord(key), SHIFT if key in '?<>{}' else 0)
    pump(0.2)
    got = "".join(out)
    menu = len(tables) != n_before
    print("%s punct %r: got %r want %r menu=%s" % ("PASS" if got == want and not menu else "FAIL", key, got, want, menu))
    ok = ok and got == want and not menu

# Shift+Space = 全形: the same keys now give Chinese punctuation, still no menu
send(0x20, IBus.ModifierType.SHIFT_MASK)
pump(0.3)
for key, want in [(',', '，'), ('[', '「'), ('/', '／')]:
    out.clear()
    n_before = len(tables)
    send(ord(key), SHIFT if key in '<>{}' else 0)
    pump(0.2)
    got = "".join(out)
    menu = len(tables) != n_before
    print("%s full_shape %r: got %r want %r menu=%s" % ("PASS" if got == want and not menu else "FAIL", key, got, want, menu))
    ok = ok and got == want and not menu
send(0x20, IBus.ModifierType.SHIFT_MASK)
pump(0.3)

# bare Ctrl+Shift -> toggle ascii_mode (Rime owns it through key_bindings.yaml)
def bare_chord():
    for kv, down in ((IBus.KEY_Control_L, True), (IBus.KEY_Shift_L, True),
                     (IBus.KEY_Shift_L, False), (IBus.KEY_Control_L, False)):
        ic.process_key_event(kv, 0, 0 if down else IBus.ModifierType.RELEASE_MASK)
        pump(0.05)
    pump(0.3)

for label, ascii_mode in (("after chord 1", True), ("after chord 2", False)):
    bare_chord()
    out.clear()
    handled = [send(ord(c)) for c in "vd1"]
    pump(0.4)
    got = "".join(out)
    # ascii_mode: Rime lets the keys through (the app types them), so nothing is committed here
    want = "" if ascii_mode else "\u597d"
    ok_ascii = (not any(handled)) if ascii_mode else bool(any(handled))
    print("%s %s: got %r want %r keys_passed=%s" % ("PASS" if got == want and ok_ascii else "FAIL", label, got, want, not any(handled)))
    ok = ok and got == want and ok_ascii

print("ALL PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
