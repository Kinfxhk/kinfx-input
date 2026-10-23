"""Linux self-test: the packaged core types vd1 -> 好 and page size 5/9 takes effect.

Run: KX_SHARE=<staged share dir> KX_USER=<empty tmp dir> python3 selftest.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kxcore  # noqa: E402

E = kxcore.Engine()
assert E.start(), "kx_start failed"
fails = 0


def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print("%s %s: got %r want %r" % ("PASS" if ok else "FAIL", name, got, want))


def type_keys(keys):
    s = E.session()
    out = ""
    for k in keys:
        if isinstance(k, tuple):
            E.key(s, k[0], k[1])
        else:
            E.key(s, k, 0)
        out += E.commit(s) or ""
    view = E.view(s)
    E.lib.kx_destroy(s)
    return out, view


codes = lambda t: [ord(c) for c in t]  # noqa: E731
check("vd1", type_keys(codes("vd1"))[0], "好")
check("vd shows 9", len(type_keys(codes("vd"))[1][3]), 9)
check("vd1 Return passes through", (lambda s: (E.key(s, 0x76, 0), E.key(s, 0x64, 0), E.key(s, 0x31, 0),
                                               E.commit(s), E.key(s, 0xff0d, 0))[-1])(E.session()), False)
check("iPhone Space", type_keys(codes("iPhone "))[0], "iPhone ")

# 0.1.1 English fixes (engine/rime/lua/english_mix.lua), same vectors as mac/Tests/SelfTest
RET = 0xFF0D
for name, keys, want in [
    ("word . chinese", codes("hello.vd1"), "hello\u3002\u597d"),
    ("domain stays latin", codes("openai.com "), "openai.com "),
    ("file name stays latin", codes("llama.cpp "), "llama.cpp "),
    ("5-letter prefix + space stays chinese", codes("fogge 1"), "\u708a\u572d\u6c34"),
    ("word Enter", codes("hello") + [RET], "hello"),
    ("chinese Enter unchanged", codes("vd") + [RET], "\u597d"),
    ("word ?", codes("thanks?"), "thanks\uff1f"),
    ("contraction", codes("don't "), "don't "),
    ("gg space", codes("gg "), "gg "),
    ("gg1 still chinese", codes("gg1"), "\u572d"),
    ("ez space still pages", codes("ez "), ""),
    ("/init space", codes("/init "), "/init "),
    ("ofc1", codes("ofc1"), "\u4eba\u985e"),
    ("held top-outs flush before Ctrl+V",
     codes("vdhel") + [(ord("v"), 4)], "\u597d\u53cd"),
    ("plain code drops before Ctrl+V", codes("vd") + [(ord("v"), 4)], ""),
]:
    check(name, type_keys(keys)[0], want)

# 0.1.4 blur (F35 from do_focus_out): what was typed stays; same vectors as windows/tip/selftest.cpp
for code, want in [("hel", "hel"), ("vdhel", "vdhel"), ("vd", "\u597d"),
                   ("vd1hel", "\u597dhel"), ("ofca", "ofca"), ("he", "\u53cd")]:
    check(code + " blur keeps text", type_keys(codes(code) + [0xffe0] + codes("vd1"))[0], want + "\u597d")

# kinfx_blur property (IBus shows it as the COMMIT-mode preedit) == what F35 then commits
for code in ("hel", "vdhel", "vd", "vd1hel", "ofca", "he", "hello", "openai.co", "llama.c", "iPhone"):
    s = E.session()
    for c in code:
        E.key(s, ord(c), 0)
        E.commit(s)
    before = E.blur_text(s)
    E.key(s, 0xffe0, 0)
    check(code + " kinfx_blur == F35 commit", before, E.commit(s) or "")
    E.lib.kx_destroy(s)

for size in ("5", "9"):
    v = dict(E.settings, page_size=size)
    time.sleep(1.1)  # settings.json mtime must change
    kxcore.save(v, E.settings_path)
    check("reload after page %s" % size, E.reload_if_changed(), True)
    check("vd shows %s" % size, len(type_keys(codes("vd"))[1][3]), int(size))

check("bad settings.json falls back", kxcore.load("/nonexistent")["page_size"], "9")
check("donate_url", kxcore.INFO["donate_url"], "https://buymeacoffee.com/kinfxhk")
print("ALL PASS" if not fails else "%d FAIL" % fails)
sys.exit(1 if fails else 0)
