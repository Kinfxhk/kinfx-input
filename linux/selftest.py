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

for size in ("5", "9"):
    v = dict(E.settings, page_size=size)
    time.sleep(1.1)  # settings.json mtime must change
    kxcore.save(v, E.settings_path)
    check("reload after page %s" % size, E.reload_if_changed(), True)
    check("vd shows %s" % size, len(type_keys(codes("vd"))[1][3]), int(size))

check("bad settings.json falls back", kxcore.load("/nonexistent")["page_size"], "9")
check("donate_url", kxcore.INFO["donate_url"], "https://linktr.ee/kinfx")
print("ALL PASS" if not fails else "%d FAIL" % fails)
sys.exit(1 if fails else 0)
