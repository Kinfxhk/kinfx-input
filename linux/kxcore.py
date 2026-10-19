"""KINFX Input core for Linux: settings.json, Rime patch, librime via the shared C shim.

Mirrors mac/Sources/Engine (Engine.swift + Settings.swift). Spec, defaults and
about/help text come from the shared JSON files in the repo root.
"""
import ctypes
import json
import os
import shutil

SCHEMA = "kinfx_quick"
TEXT_FILES = ["kinfx_capture.txt", "kinfx_en_unsafe.txt", "kinfx_en_names.txt"]
SHARE = os.environ.get("KX_SHARE", "/usr/share/kinfx-input")
USER = os.environ.get("KX_USER", os.path.expanduser("~/.local/share/kinfx-input"))


def _json(name):
    with open(os.path.join(SHARE, name), encoding="utf-8") as f:
        return json.load(f)


SPEC = _json("settings-spec.json")["settings"]
INFO = _json("app-info.json")


def defaults():
    return {s["key"]: s["options"][0][0] for s in SPEC}


def load(path):
    """settings.json is a trust boundary: unknown keys dropped, bad values -> default."""
    out = defaults()
    try:
        with open(path, encoding="utf-8") as f:
            obj = json.load(f)
    except (OSError, ValueError):
        return out
    if not isinstance(obj, dict):
        return out
    for s in SPEC:
        raw = obj.get(s["key"])
        if isinstance(raw, bool):
            v = "true" if raw else "false"
        elif isinstance(raw, (int, str)):
            v = str(raw)
        else:
            continue
        if any(o[0] == v for o in s["options"]):
            out[s["key"]] = v
    return out


def save(values, path):
    obj = {}
    for s in SPEC:
        v = values.get(s["key"], s["options"][0][0])
        obj[s["key"]] = int(v) if s["key"] == "page_size" else (v == "true") if s["key"] == "association" else v
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(tmp, path)


def rime_custom(values):
    out = "# 由 KINFX Input 設定視窗產生，請勿手動修改。\npatch:\n"
    for s in SPEC:
        if not s["rime_key"]:
            continue
        v = values.get(s["key"], s["options"][0][0])
        v = s.get("rime_value", {}).get(v, v)
        out += '  "%s": %s\n' % (s["rime_key"], v)
    return out


class Engine:
    def __init__(self, share=SHARE, user=USER):
        self.shared = os.path.join(share, "data")
        self.user = user
        self.settings_path = os.path.join(user, "settings.json")
        self.custom_path = os.path.join(user, SCHEMA + ".custom.yaml")
        self.settings = defaults()
        self.stamp = None
        here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "libkxshim.so")  # package: /usr/lib/kinfx-input
        lib = ctypes.CDLL(here if os.path.exists(here) else os.path.join(share, "libkxshim.so"))
        lib.kx_start.argtypes = [ctypes.c_char_p] * 3 + [ctypes.c_int]
        lib.kx_session.argtypes = [ctypes.c_char_p]
        lib.kx_session.restype = ctypes.c_size_t
        for n in ("kx_alive", "kx_destroy", "kx_clear", "kx_commit_composition"):
            getattr(lib, n).argtypes = [ctypes.c_size_t]
        lib.kx_key.argtypes = [ctypes.c_size_t, ctypes.c_int, ctypes.c_int]
        for n in ("kx_take_commit", "kx_context"):
            getattr(lib, n).argtypes = [ctypes.c_size_t]
            getattr(lib, n).restype = ctypes.c_void_p
        self.lib = lib
        self.libc = ctypes.CDLL(None)
        self.libc.free.argtypes = [ctypes.c_void_p]

    def _mtime(self):
        try:
            return os.stat(self.settings_path).st_mtime_ns
        except OSError:
            return None

    def _write_custom(self):
        text = rime_custom(self.settings)
        try:
            with open(self.custom_path, encoding="utf-8") as f:
                if f.read() == text:
                    return
        except OSError:
            pass
        with open(self.custom_path, "w", encoding="utf-8") as f:
            f.write(text)

    def start(self):
        os.makedirs(os.path.join(self.user, "log"), exist_ok=True)
        # The Lua scripts read their word lists from the user dir; keep it equal to the package.
        for n in TEXT_FILES:
            src, dst = os.path.join(self.shared, n), os.path.join(self.user, n)
            if not os.path.exists(dst) or open(src, "rb").read() != open(dst, "rb").read():
                shutil.copyfile(src, dst)
        self.settings = load(self.settings_path)
        self._write_custom()
        ok = self.lib.kx_start(self.shared.encode(), self.user.encode(),
                               os.path.join(self.user, "log").encode(), 0)
        self.stamp = self._mtime()
        return ok != 0

    def reload_if_changed(self):
        """The settings window is another process; it only writes settings.json."""
        if self._mtime() == self.stamp:
            return False
        self.settings = load(self.settings_path)
        self.stamp = self._mtime()
        self._write_custom()
        # Rime compares mtimes in whole seconds; drop the built schema so it is rebuilt.
        try:
            os.remove(os.path.join(self.user, "build", SCHEMA + ".schema.yaml"))
        except OSError:
            pass
        self.lib.kx_redeploy()
        return True

    def session(self):
        return self.lib.kx_session(SCHEMA.encode())

    def alive(self, s):
        return bool(s) and self.lib.kx_alive(s) != 0

    def key(self, s, code, mask):
        return self.lib.kx_key(s, code, mask) != 0

    def _take(self, p):
        if not p:
            return None
        try:
            return ctypes.string_at(p).decode("utf-8")
        finally:
            self.libc.free(p)

    def commit(self, s):
        return self._take(self.lib.kx_take_commit(s))

    def view(self, s):
        """(preedit, cursor_chars, page_size, candidates[(text, comment)])"""
        raw = self._take(self.lib.kx_context(s))
        if raw is None:
            return "", 0, 0, []
        f = raw.split("\x1f")
        pre = f[0]
        cur = len(pre.encode("utf-8")[: int(f[1] or 0)].decode("utf-8", "ignore"))
        cands = [tuple((c.split("\x1e", 1) + [""])[:2]) for c in f[6:]]
        return pre, cur, int(f[2] or 0), cands
