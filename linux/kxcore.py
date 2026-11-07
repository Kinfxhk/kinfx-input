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
        lib.kx_select_candidate_on_current_page.argtypes = [ctypes.c_size_t, ctypes.c_int]
        lib.kx_select_candidate_on_current_page.restype = ctypes.c_int
        for n in ("kx_take_commit", "kx_context"):
            getattr(lib, n).argtypes = [ctypes.c_size_t]
            getattr(lib, n).restype = ctypes.c_void_p
        lib.kx_property.argtypes = [ctypes.c_size_t, ctypes.c_char_p]
        lib.kx_property.restype = ctypes.c_void_p
        lib.kx_redeploy.argtypes = []
        lib.kx_redeploy.restype = ctypes.c_int
        lib.kx_has_pending.argtypes = [ctypes.c_size_t]
        lib.kx_has_pending.restype = ctypes.c_int
        lib.kx_option.argtypes = [ctypes.c_size_t, ctypes.c_char_p]
        lib.kx_option.restype = ctypes.c_int
        lib.kx_set_option.argtypes = [ctypes.c_size_t, ctypes.c_char_p, ctypes.c_int]
        for n in ("kx_idle_punct_tail", "kx_idle_digit_tail"):
            getattr(lib, n).argtypes = [ctypes.c_size_t]
            getattr(lib, n).restype = ctypes.c_int
        for n in ("kx_restore_idle_punct_tail", "kx_restore_idle_digit_tail"):
            getattr(lib, n).argtypes = [ctypes.c_size_t, ctypes.c_int]
            getattr(lib, n).restype = ctypes.c_int
        self.lib = lib
        self.libc = ctypes.CDLL(None)
        self.libc.free.argtypes = [ctypes.c_void_p]
        # Owner/pending/undrained registry (port of mac/Sources/Engine/Engine.swift).
        # A logical handle is the owner identity; the native RimeSessionId is resolved
        # on every call. Reloads remap handle->sid, so a handle survives any number of
        # reloads (no single-hop remap, no orphaned intermediate session).
        self.SWITCHES = ("ascii_mode", "full_shape", "simplification", "ascii_punct")
        self.sessions = {}        # logical handle -> native session id
        self.next_handle = 0
        self.undrained = set()    # logical handles whose native commit queue is unread
        self.retry_runtime = {}   # logical handle -> idle snapshot kept across a failed redeploy
        self.native_rebuild_failed = False
        self.reload_pending = False
        # Authoritative global full_shape. librime's Shift+Space toggle is a
        # per-context option, so the width would otherwise be lost on any
        # window/app switch. The engine keeps the global width here, restores it
        # on every new owner at creation and broadcasts it to every live owner
        # after a toggle (bidirectional follow). full_shape_error is the
        # fail-closed marker: None = healthy, else "invalid"/"unreadable"/
        # "unwritable". Missing state file is a legitimate first run, not an error.
        self.full_shape = 0
        self.full_shape_error = None
        self.full_shape_state_path = os.path.join(user, "kinfx_full_shape.state")
        # App-side fallback (the host app inserts an unhandled printable key
        # literally, e.g. the fallback2 '2'): per-owner marker so clear()/blur()
        # of a failed owner keeps its latin/digit tail (half-width punctuation)
        # instead of revoking it. Mirrors mac Engine.appFallback.
        self.app_fallback = {}   # logical handle -> inserted char was an ASCII digit

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
        self._load_full_shape_state()
        return ok != 0

    def _load_full_shape_state(self):
        """Load the authoritative global width (fail-closed).

        Missing file = first run -> half-width default, not an error. Unreadable
        or invalid content is an explicit error, never silently treated as
        persistence success.
        """
        self.full_shape = 0
        self.full_shape_error = None
        try:
            with open(self.full_shape_state_path, encoding="ascii") as f:
                v = f.read().strip()
        except FileNotFoundError:
            return
        except (UnicodeError, OSError):
            # UnicodeError = malformed (non-ASCII) bytes like 0xff 0xfe; OSError =
            # unreadable (permission). Both fail-closed, never silent persistence.
            self.full_shape_error = "unreadable"
            return
        if v == "1":
            self.full_shape = 1
        elif v == "0":
            self.full_shape = 0
        else:
            self.full_shape_error = "invalid"

    def _persist_full_shape(self, v):
        """Atomically persist the global width; report failure, never claim success."""
        tmp = self.full_shape_state_path + ".tmp"
        try:
            with open(tmp, "w", encoding="ascii") as f:
                f.write("1" if v else "0")
            os.replace(tmp, self.full_shape_state_path)
            self.full_shape_error = None
            return True
        except OSError:
            self.full_shape_error = "unwritable"
            return False

    def _broadcast_full_shape(self, v):
        """Apply the global width to every live owner immediately (bidirectional
        follow), and update kept reservations so a later retry restores it too."""
        for h, sid in list(self.sessions.items()):
            if self.lib.kx_alive(sid):
                self.lib.kx_set_option(sid, b"full_shape", v)
        for snap in self.retry_runtime.values():
            opts = list(snap["options"])
            opts[1] = v
            snap["options"] = opts

    # -- owner registry / native resolution -----------------------------------
    def native_session(self, h):
        """Resolve a logical owner handle to its current native session id (0 if unknown)."""
        return self.sessions.get(h, 0)

    def _idle(self):
        """Drop handles whose native session died; True when every live owner is drained and idle."""
        for h in list(self.sessions):
            if not self.lib.kx_alive(self.sessions[h]):
                self.sessions.pop(h, None)
                self.undrained.discard(h)
        for h in list(self.sessions):
            if h in self.undrained:
                return False
            if self.lib.kx_has_pending(self.sessions[h]) != 0:
                return False
        return True

    def _capture(self, h):
        """Snapshot one idle owner's runtime; None when its script/digit tail is unknown."""
        sid = self.sessions[h]
        options = [self.lib.kx_option(sid, k.encode()) for k in self.SWITCHES]
        tail = self.lib.kx_idle_punct_tail(sid)
        digit = self.lib.kx_idle_digit_tail(sid)
        if tail < 0 or digit < 0:
            return None
        return {"options": options, "tail": tail, "digit": digit}

    def _maybe_reload(self):
        """Apply a pending reload once every owner is idle/drained, preserving each owner's runtime."""
        if not self.reload_pending:
            return False
        if not self._idle():
            return False
        # Snapshot source: live owners, plus kept reservations from a failed redeploy.
        snapshots = {}
        for h in list(self.sessions):
            snap = self._capture(h)
            if snap is None:
                return False  # unknown input: defer, never destroy
            snapshots[h] = snap
        for h, snap in self.retry_runtime.items():
            snapshots[h] = snap
        if not snapshots:
            ok = self.lib.kx_redeploy() != 0
            # A rebuild attempt consumes the explicit request whether it succeeds
            # or fails; a failure latches native_rebuild_failed and must be retried
            # only by a later explicit changed-settings reload, never implicitly.
            self.reload_pending = False
            self.native_rebuild_failed = not ok
            return ok
        ok = self.lib.kx_redeploy() != 0
        restored = {}
        if ok:
            for h, snap in snapshots.items():
                new_sid = self.lib.kx_session(SCHEMA.encode())
                if not new_sid:
                    ok = False
                    break
                for k, v in zip(self.SWITCHES, snap["options"]):
                    self.lib.kx_set_option(new_sid, k.encode(), v)
                if self.lib.kx_restore_idle_punct_tail(new_sid, snap["tail"]) == 0:
                    ok = False
                    break
                if self.lib.kx_restore_idle_digit_tail(new_sid, snap["digit"]) == 0:
                    ok = False
                    break
                restored[h] = new_sid
        if ok:
            # Handles stay stable; only the native ids are remapped. Each owner's
            # full_shape is already the global (broadcast keeps them in sync), so
            # the snapshot restore carries the current width through the rebuild.
            self.sessions = dict(restored)
            self.retry_runtime = {}
            self.app_fallback = {}
            self.undrained.clear()
        else:
            # Keep the idle snapshot: the native sessions are gone (cleanup_all_sessions)
            # but the owner->runtime reservation survives for the explicit retry.
            self.retry_runtime = snapshots
            self.sessions = {}
            self.undrained.clear()
            for new_sid in restored.values():
                self.lib.kx_destroy(new_sid)
        # Consume the explicit request on both outcomes. A failed rebuild is
        # failed-latched: commit()/destroy() must not implicitly re-deploy, only a
        # later explicit changed-settings retry may re-arm and rebuild.
        self.reload_pending = False
        self.native_rebuild_failed = not ok
        return ok

    def reload_if_changed(self):
        """The settings window is another process; it only writes settings.json.

        Deferred until every owner is drained and idle, then redeploys and restores
        each owner's 4 switches + script tail + digit tail. Pending/undrained/unknown
        owners block the redeploy (they are never destroyed mid-composition).
        """
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
        self.reload_pending = True
        return self._maybe_reload()

    def session(self):
        """Create an owner and return its stable logical handle (0 on failure)."""
        if self.native_rebuild_failed:
            return 0
        sid = self.lib.kx_session(SCHEMA.encode())
        if not sid:
            return 0
        # A new owner starts from the schema default (half-width). Adopt the
        # global width at creation so it follows the last toggle even before its
        # first key (destroy A / open B restores immediately, not lazily).
        self.lib.kx_set_option(sid, b"full_shape", self.full_shape)
        self.next_handle += 1
        self.sessions[self.next_handle] = sid
        return self.next_handle

    def owns(self, h):
        """True when h is a live owner or holds a kept idle reservation across a failed rebuild."""
        return bool(h) and (self.alive(h) or h in self.retry_runtime)

    def destroy(self, h):
        sid = self.sessions.pop(h, None)
        if sid:
            self.lib.kx_destroy(sid)
        self.undrained.discard(h)
        self.retry_runtime.pop(h, None)
        self.app_fallback.pop(h, None)
        self._maybe_reload()

    def note_app_fallback(self, h, is_ascii_digit):
        """Record that the host app inserted a literal character for an unhandled
        key (fallback2 contract). The engine never saw that text, so a later
        clear/blur of a failed owner must keep — not revoke — this owner's tail so
        a following period stays half-width. `is_ascii_digit` marks a digit-led
        run (e.g. the '2' in "hello2"). Mirrors mac Engine.noteAppFallback."""
        self.app_fallback[h] = is_ascii_digit

    def _revoke_routing(self, h):
        """Same-owner explicit finalization while native is unavailable: empty only
        this owner's routing metadata (script tail + digit tail). The logical owner
        and its four runtime switches stay, so a later explicit retry still restores
        width under the same handle (C transition). An app-side fallback marker keeps
        the latin/digit tail instead of revoking it (half-width punctuation)."""
        snap = self.retry_runtime.get(h)
        if snap is None:
            return
        if h in self.app_fallback:
            # The app inserted text the engine never saw: keep the script tail so the
            # next punctuation stays half-width, and mark a digit-led run for a digit.
            is_digit = self.app_fallback[h]
            self.retry_runtime[h] = {"options": snap["options"], "tail": snap["tail"],
                                     "digit": 1 if is_digit else snap["digit"]}
            return
        self.retry_runtime[h] = {"options": snap["options"], "tail": 0, "digit": 0}

    def clear(self, h):
        sid = self.native_session(h)
        if sid:
            self.undrained.add(h)
            self.lib.kx_clear(sid)
        else:
            self._revoke_routing(h)

    def alive(self, h):
        return bool(h) and self.lib.kx_alive(self.native_session(h)) != 0

    def key(self, h, code, mask):
        sid = self.native_session(h)
        alive = bool(h) and self.lib.kx_alive(sid) != 0
        if alive:
            self.undrained.add(h)
        pre = self.lib.kx_option(sid, b"full_shape") if alive else None
        handled = self.lib.kx_key(sid, code, mask) != 0
        if alive:
            post = self.lib.kx_option(sid, b"full_shape")
            # Only the Shift+Space key_binder toggle changes full_shape inside a
            # single key (the formatter's width_internal bypass restores it
            # before returning). A change here is the toggle signal: adopt it,
            # broadcast to every live owner and persist (fail-closed). Shortcut
            # chords (Ctrl/Alt/Super) and modifier releases never flip the
            # option, so they can never reach this persist path.
            if post != pre:
                self.full_shape = post
                self._broadcast_full_shape(post)
                self._persist_full_shape(post)
        return handled

    def select_candidate(self, h, index):
        return self.lib.kx_select_candidate_on_current_page(self.native_session(h), index) != 0

    def _take(self, p):
        if not p:
            return None
        try:
            return ctypes.string_at(p).decode("utf-8")
        finally:
            self.libc.free(p)

    def commit(self, h):
        text = self._take(self.lib.kx_take_commit(self.native_session(h)))
        self.undrained.discard(h)
        self._maybe_reload()
        return text

    def property(self, h, name):
        return self._take(self.lib.kx_property(self.native_session(h), name.encode())) or ""

    def blur_text(self, h):
        """What F35 (focus left) would commit now; english_mix.lua keeps it in a context property."""
        return self.property(h, "kinfx_blur")

    def view(self, h):
        """(preedit, cursor_chars, page_size, candidates[(text, comment)])."""
        raw = self._take(self.lib.kx_context(self.native_session(h)))
        if raw is None:
            return "", 0, 0, []
        f = raw.split("\x1f")
        pre = f[0]
        cur = len(pre.encode("utf-8")[: int(f[1] or 0)].decode("utf-8", "ignore"))
        cands = [tuple((c.split("\x1e", 1) + [""])[:2]) for c in f[6:]]
        return pre, cur, int(f[2] or 0), cands
