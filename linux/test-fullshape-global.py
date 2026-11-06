#!/usr/bin/env python3
"""Permanent Linux full_shape global persistence + broadcast regression suite.

Covers (TDD RED->GREEN against the supervisor-20261106T2320 baseline):
- bidirectional broadcast: an already-typed existing owner follows the toggling
  owner in both directions (half<->full), not just on a fresh first key
- destroy / new owner: a new owner opened after the toggle owner is destroyed
  restores the global width immediately (before its first key)
- settings reload/retry: the width follows the global across a redeploy
- failed-retry: after a schema-broken redeploy fails and is repaired, the explicit
  retry restores each owner following the global width (not the schema default)
- formatter no-persist: the width_internal half-width bypass for an English commit
  never flips nor persists the global width (only a real Shift+Space press does)
- state file fail-closed: invalid / unreadable / unwritable never silently pass
  nor fake persistence success (missing = legitimate first run, half-width)
- shortcut no-persist: Ctrl/Alt/Super chords (also combined with Shift) and
  modifier releases never flip or persist the width (only a real Shift+Space does)

Each scenario runs in its own child interpreter (the shared C shim is a
per-process singleton) with a disposable share/user copy. Each input-producing
helper is evaluated exactly once and its result reused for both the assertion and
the evidence fields, so the fixture's committed text is a single input, not two.

Run: KX_SHARE=<staged share> KX_LIB=<dir with libkxshim.so> python3 test-fullshape-global.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

SHIFT = 1
RELEASE = 1 << 30
CTRL = 1 << 2
ALT = 1 << 3
SUPER = 1 << 26


def _run_scenario(kind):
    import kxcore  # noqa: E402

    SHARE = os.environ["KX_SHARE"]
    root = tempfile.mkdtemp(prefix="kinfx-fullshape-%s-" % kind)
    share = os.path.join(root, "share")
    shutil.copytree(SHARE, share)
    shim_src = os.path.join(os.environ.get("KX_LIB", os.path.dirname(kxcore.__file__)), "libkxshim.so")
    if os.path.exists(shim_src):
        shutil.copy2(shim_src, os.path.join(share, "libkxshim.so"))
    user = os.path.join(root, "user")
    os.makedirs(user, exist_ok=True)
    state_path = os.path.join(user, "kinfx_full_shape.state")

    if kind == "state-invalid":
        with open(state_path, "w", encoding="ascii") as f:
            f.write("xyz\n")
    elif kind == "state-unreadable":
        with open(state_path, "w", encoding="ascii") as f:
            f.write("1\n")
        os.chmod(state_path, 0o000)
    elif kind == "state-malformed":
        with open(state_path, "wb") as f:
            f.write(b"\xff\xfe")

    e = kxcore.Engine(share, user)
    assert e.start(), "kx_start failed"

    checks = []

    def check(ok, name, **detail):
        r = dict(case=name, **detail)
        r["pass"] = bool(ok)
        checks.append(r)

    def width(h):
        return e.lib.kx_option(e.native_session(h), b"full_shape")

    def cjk_period(h):
        out = ""
        for c in "vd1.":
            e.key(h, ord(c), 0)
            out += e.commit(h) or ""
        return out

    def toggle(h):
        e.key(h, 0x20, SHIFT)
        e.key(h, 0x20, SHIFT | RELEASE)
        e.commit(h)  # drain the toggle keys so the owner is idle for a later reload

    try:
        if kind == "bidirectional":
            a = e.session()
            b = e.session()
            # B is typed BEFORE the toggle, so under the old first-key restore its
            # restore slot is already consumed; it must still follow A via broadcast.
            first = cjk_period(b)
            check(first == "好.", "b-typed-half-before-toggle", got=first)
            toggle(a)
            check(width(a) == 1 and width(b) == 1 and e.full_shape == 1,
                  "toggle-half-to-full-broadcasts-to-existing-b",
                  a=width(a), b=width(b), global_width=e.full_shape)
            full_period = cjk_period(b)
            check(full_period == "好。", "b-full-width-period-after-follow", got=full_period)
            toggle(a)
            check(width(a) == 0 and width(b) == 0 and e.full_shape == 0,
                  "toggle-full-to-half-broadcasts-to-existing-b",
                  a=width(a), b=width(b), global_width=e.full_shape)
            half_period = cjk_period(b)
            check(half_period == "好.", "b-half-width-period-after-follow", got=half_period)
        elif kind == "destroy-new-owner":
            a = e.session()
            toggle(a)
            check(e.full_shape == 1, "a-toggled-full", global_width=e.full_shape)
            e.destroy(a)
            b = e.session()
            check(width(b) == 1, "new-b-restores-global-before-first-key", got=width(b))
            full_period = cjk_period(b)
            check(full_period == "好。", "new-b-full-width-period", got=full_period)
        elif kind == "reload-follows-global":
            a = e.session()
            toggle(a)
            check(e.full_shape == 1, "a-toggled-full", global_width=e.full_shape)
            v = dict(e.settings)
            v["page_size"] = "5"
            kxcore.save(v, e.settings_path)
            check(e.reload_if_changed(), "settings-reload-applies")
            check(width(a) == 1 and e.full_shape == 1, "width-follows-global-after-reload",
                  a=width(a), global_width=e.full_shape)
            b = e.session()
            check(width(b) == 1, "new-owner-follows-global-after-reload", got=width(b))
        elif kind == "state-invalid":
            check(e.full_shape_error == "invalid" and e.full_shape == 0,
                  "invalid-state-file-fails-closed-to-half",
                  error=e.full_shape_error, global_width=e.full_shape)
        elif kind == "state-unreadable":
            check(e.full_shape_error == "unreadable" and e.full_shape == 0,
                  "unreadable-state-file-fails-closed-to-half",
                  error=e.full_shape_error, global_width=e.full_shape)
        elif kind == "state-malformed":
            check(e.full_shape_error == "unreadable" and e.full_shape == 0,
                  "malformed-state-file-fails-closed-to-half",
                  error=e.full_shape_error, global_width=e.full_shape)
        elif kind == "state-unwritable":
            a = e.session()
            b = e.session()
            os.chmod(user, 0o555)  # no write -> persist must fail closed
            try:
                toggle(a)
                check(e.full_shape == 1, "toggle-still-applies-in-memory",
                      global_width=e.full_shape)
                check(width(a) == 1 and width(b) == 1,
                      "broadcast-still-applies-to-existing-b", a=width(a), b=width(b))
                check(e.full_shape_error == "unwritable",
                      "unwritable-state-file-reports-failure-not-fake-success",
                      error=e.full_shape_error)
            finally:
                os.chmod(user, 0o755)
        elif kind == "state-missing":
            check(e.full_shape_error is None and e.full_shape == 0,
                  "missing-state-file-is-legitimate-first-run-half",
                  error=e.full_shape_error, global_width=e.full_shape)
        elif kind == "shortcut-no-persist":
            a = e.session()
            toggle(a)  # now global = 1, state file = "1"
            check(e.full_shape == 1, "setup-toggle-full", global_width=e.full_shape)
            before = width(a)
            # Shortcut chords and modifier releases must never flip/persist width.
            e.key(a, 0x20, CTRL)        # Ctrl+Space (ascii_mode, not full_shape)
            e.key(a, 0x20, ALT)         # Alt+Space
            e.key(a, 0x20, SUPER)       # Super+Space
            e.key(a, 0x20, SHIFT | RELEASE)  # Shift+Space release (not a press)
            check(width(a) == before and e.full_shape == before,
                  "shortcut-chords-and-release-never-flip-width",
                  a=width(a), global_width=e.full_shape)
            check(os.path.exists(state_path) and open(state_path).read().strip() == "1",
                  "shortcut-chords-never-persist", state=open(state_path).read().strip())
            # Shift combined with Ctrl/Alt/Super is still not a plain Shift+Space
            # press: it must not toggle nor persist (only a real Shift+Space does).
            e.key(a, 0x20, CTRL | SHIFT)    # Ctrl+Shift+Space
            e.key(a, 0x20, ALT | SHIFT)     # Alt+Shift+Space
            e.key(a, 0x20, SUPER | SHIFT)   # Super+Shift+Space
            check(width(a) == before and e.full_shape == before,
                  "ctrl-alt-super-shift-space-chords-never-flip-width",
                  a=width(a), global_width=e.full_shape)
            check(os.path.exists(state_path) and open(state_path).read().strip() == "1",
                  "ctrl-alt-super-shift-space-chords-never-persist",
                  state=open(state_path).read().strip())
        elif kind == "formatter-no-persist":
            a = e.session()
            toggle(a)  # global -> full = 1, state file "1"
            check(e.full_shape == 1, "a-toggled-full", global_width=e.full_shape)
            # An English word commit runs the formatter's width_internal bypass:
            # it briefly sets full_shape=false to render half-width, then restores
            # it. That temporary switch is not a user toggle and must not persist.
            out = ""
            for c in "hello":
                e.key(a, ord(c), 0)
                out += e.commit(a) or ""
            e.key(a, 0xFF0D, 0)  # Return commits the word
            out += e.commit(a) or ""
            check(out == "hello", "english-word-stays-half-width-under-full-shape", got=out)
            check(e.full_shape == 1, "formatter-bypass-does-not-flip-global-width",
                  global_width=e.full_shape)
            check(open(state_path).read().strip() == "1", "formatter-bypass-does-not-persist",
                  state=open(state_path).read().strip())
            check(e.full_shape_error is None, "formatter-bypass-leaves-no-error",
                  error=e.full_shape_error)
        elif kind == "failed-retry":
            a = e.session()
            toggle(a)  # global -> full = 1, state file "1"
            check(e.full_shape == 1, "a-toggled-full-before-failure", global_width=e.full_shape)
            schema = os.path.join(share, "data", kxcore.SCHEMA + ".schema.yaml")
            with open(schema, encoding="utf-8") as f:
                valid = f.read()
            # Break the schema -> the explicit reload fails and keeps the idle snapshot.
            with open(schema, "w", encoding="utf-8") as f:
                f.write("schema: [broken\n")
            v = dict(e.settings)
            v["page_size"] = "5"
            kxcore.save(v, e.settings_path)
            check(not e.reload_if_changed(), "failed-reload-truthful")
            check(e.owns(a) and not e.alive(a), "idle-reservation-survives-failure")
            # Repair and explicitly retry: the restored owner follows the global width.
            with open(schema, "w", encoding="utf-8") as f:
                f.write(valid)
            v = dict(e.settings)
            v["page_size"] = "9"
            kxcore.save(v, e.settings_path)
            check(e.reload_if_changed(), "explicit-retry-applies")
            check(e.full_shape == 1 and width(a) == 1,
                  "width-follows-global-after-failed-retry",
                  a=width(a), global_width=e.full_shape)
            check(open(state_path).read().strip() == "1", "state-still-full-after-failed-retry",
                  state=open(state_path).read().strip())
        else:
            raise ValueError(kind)
    finally:
        for x in set(e.sessions) | set(e.retry_runtime):
            e.destroy(x)
        if kind == "state-unreadable":
            os.chmod(state_path, 0o644)
        shutil.rmtree(root, ignore_errors=True)
    return checks


class FullShapeGlobal(unittest.TestCase):
    def _run(self, kind):
        return subprocess.run(
            [sys.executable, os.path.abspath(__file__), kind],
            capture_output=True, text=True, env=dict(os.environ))

    def _assert_green(self, kind):
        p = self._run(kind)
        self.assertEqual(p.returncode, 0, "%s failed:\n%s%s" % (kind, p.stdout, p.stderr))

    def test_bidirectional_broadcast_to_existing_owner(self):
        self._assert_green("bidirectional")

    def test_destroy_new_owner_restores_global(self):
        self._assert_green("destroy-new-owner")

    def test_settings_reload_follows_global(self):
        self._assert_green("reload-follows-global")

    def test_invalid_state_file_fails_closed(self):
        self._assert_green("state-invalid")

    def test_unreadable_state_file_fails_closed(self):
        self._assert_green("state-unreadable")

    def test_malformed_state_file_fails_closed(self):
        self._assert_green("state-malformed")

    def test_unwritable_state_file_fails_closed(self):
        self._assert_green("state-unwritable")

    def test_missing_state_file_is_first_run(self):
        self._assert_green("state-missing")

    def test_shortcut_chords_never_persist(self):
        self._assert_green("shortcut-no-persist")

    def test_formatter_width_internal_never_persists(self):
        self._assert_green("formatter-no-persist")

    def test_failed_retry_width_follows_global(self):
        self._assert_green("failed-retry")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        rows = _run_scenario(sys.argv[1])
        for r in rows:
            print(json.dumps(r, ensure_ascii=False), flush=True)
        sys.exit(0 if all(r["pass"] for r in rows) else 1)
    unittest.main(verbosity=2)
