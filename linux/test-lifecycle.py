#!/usr/bin/env python3
"""Permanent Linux lifecycle regression suite (engine level, no GI/IBus).

Covers the owner/pending/undrained registry and the failed-rebuild latch:

- double-reload:       60 -> reload -> reload -> cm1 == 60cm1 (digit-tail survives)
- failed-retry:        failed redeploy keeps the idle snapshot; an explicit retry
                       restores it (width + digit-tail preserved)
- pending-defer:       a pending owner blocks the redeploy and is never destroyed
- failed-clear:        same-owner clear inside the failed gap revokes the latin
                       routing, so an explicit retry then types hello。 (not hello.)
- failed-implicit-retry: commit() must not rebuild a failed-latched engine; only
                       a later explicit changed-settings retry may re-deploy
- destroy-reservation: destroy unregisters both the native and idle reservations
- reset-clear-slash:      explicit clear after a CJK commit revokes the script tail
                       so a following slash is half-width (人類/), not full-width
- reset-clear-slash-preserve: no clear -> the slash still follows full_shape (好／)

The shared C shim is a per-process singleton (kx_start -> setup() may run once
per process), so each scenario runs in its own child interpreter; the unittest
wrapper spawns those children and asserts their exit status. Each scenario also
uses a disposable share/user copy, so the schema corruption is data-isolated.

Run (disposable dirs only, never the live user):
  KX_SHARE=<staged share> KX_LIB=<dir with libkxshim.so> python3 test-lifecycle.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RET = 0xFF0D


def _run_scenario(kind):
    """One engine, one fresh process: run `kind` and return its check rows."""
    import kxcore  # noqa: E402

    SHARE = os.environ["KX_SHARE"]
    root = tempfile.mkdtemp(prefix="kinfx-lifecycle-%s-" % kind)
    share = os.path.join(root, "share")
    shutil.copytree(SHARE, share)
    shim_src = os.path.join(os.environ.get("KX_LIB", os.path.dirname(kxcore.__file__)), "libkxshim.so")
    if os.path.exists(shim_src):
        shutil.copy2(shim_src, os.path.join(share, "libkxshim.so"))
    user = os.path.join(root, "user")
    os.makedirs(user, exist_ok=True)

    e = kxcore.Engine(share, user)
    assert e.start(), "kx_start failed"
    schema = os.path.join(share, "data", kxcore.SCHEMA + ".schema.yaml")
    with open(schema, encoding="utf-8") as f:
        valid = f.read()

    seq = [0]

    def keys(h, text):
        out = ""
        for c in text:
            e.key(h, ord(c), 0)
            out += e.commit(h) or ""
        return out

    def reload():
        v = dict(e.settings)
        v["page_size"] = "1" if seq[0] % 2 else "9"
        seq[0] += 1
        kxcore.save(v, e.settings_path)
        return e.reload_if_changed()

    def fail():
        with open(schema, "w", encoding="utf-8") as f:
            f.write("schema: [broken\n")
        return reload()

    checks = []

    def check(ok, name, **detail):
        r = dict(case=name, **detail)
        r["pass"] = bool(ok)
        checks.append(r)

    try:
        if kind == "double-reload":
            h = e.session()
            e.lib.kx_set_option(e.native_session(h), b"full_shape", 0)
            text = keys(h, "60")
            check(text == "60" and e.property(h, "kinfx_digit_tail") == "1", "digit-setup", text=text)
            check(reload(), "first-reload")
            check(reload(), "second-reload")
            check(e.owns(h) and e.alive(h), "stable-owner-after-two-reloads")
            check(e.lib.kx_option(e.native_session(h), b"full_shape") == 0, "same-owner-width-after-two-idle-reloads",
                  actual=e.lib.kx_option(e.native_session(h), b"full_shape"))
            text += keys(h, "cm1")
            check(text == "60cm1", "same-owner-digit-after-two-idle-reloads", actual=text, expected="60cm1")
        elif kind == "failed-retry":
            h = e.session()
            e.lib.kx_set_option(e.native_session(h), b"full_shape", 0)
            text = keys(h, "60")
            check(not fail(), "failed-reload-truthful")
            check(e.owns(h) and not e.alive(h), "idle-reservation-survives-failure")
            with open(schema, "w", encoding="utf-8") as f:
                f.write(valid)
            check(reload(), "explicit-retry-applies")
            check(e.lib.kx_option(e.native_session(h), b"full_shape") == 0, "same-owner-width-after-failed-retry",
                  actual=e.lib.kx_option(e.native_session(h), b"full_shape"))
            text += keys(h, "cm1")
            check(text == "60cm1", "same-owner-digit-after-failed-retry", actual=text, expected="60cm1")
        elif kind == "pending-defer":
            hel = e.session()
            keys(hel, "hel")
            digit = e.session()
            keys(digit, "60")
            check(not reload(), "two-owner-pending-defer")
            check(e.alive(hel) and e.view(hel)[0] == "hel", "pending-survives", preedit=e.view(hel)[0])
            e.key(hel, RET, 0)
            e.commit(hel)
            check(e.property(digit, "kinfx_digit_tail") == "1", "other-owner-digit-after-deferred-reload",
                  actual=e.property(digit, "kinfx_digit_tail"))
        elif kind == "failed-clear":
            h = e.session()
            text = keys(h, "hello")
            e.key(h, RET, 0)
            text += e.commit(h) or ""
            e.lib.kx_set_option(e.native_session(h), b"full_shape", 1)
            check(text == "hello" and e.property(h, "kinfx_punct_tail") == "latin", "latin-setup", actual=text)
            check(not fail(), "failed-reload-truthful")
            check(e.owns(h) and not e.alive(h), "idle-reservation-survives-failure")
            e.clear(h)  # same-owner explicit finalize inside the failed gap
            with open(schema, "w", encoding="utf-8") as f:
                f.write(valid)
            check(reload(), "explicit-retry-applies")
            check(e.owns(h) and e.lib.kx_option(e.native_session(h), b"full_shape") == 1, "clear-preserves-owner-width")
            text += keys(h, ".")
            check(text == "hello\u3002", "same-owner-clear-revokes-Latin-routing", actual=text, expected="hello\u3002")
        elif kind == "failed-implicit-retry":
            h = e.session()
            text = keys(h, "hello")
            e.key(h, RET, 0)
            text += e.commit(h) or ""
            e.lib.kx_set_option(e.native_session(h), b"full_shape", 1)
            check(text == "hello" and e.property(h, "kinfx_punct_tail") == "latin", "latin-setup", actual=text)
            check(not fail(), "failed-reload-truthful")
            check(e.owns(h) and not e.alive(h), "idle-reservation-survives-failure")
            with open(schema, "w", encoding="utf-8") as f:
                f.write(valid)
            e.commit(h)  # queue read, NOT an explicit retry -> must stay latched
            check(e.owns(h) and not e.alive(h) and e.native_rebuild_failed, "no-implicit-native-retry-on-commit",
                  alive=e.alive(h), rebuild_failed=e.native_rebuild_failed)
            check(reload(), "explicit-retry-applies")
            check(e.alive(h) and not e.native_rebuild_failed, "explicit-retry-clears-latch")
        elif kind == "destroy-reservation":
            h = e.session()
            keys(h, "60")
            check(not fail(), "failed-reload-truthful")
            check(e.owns(h) and not e.alive(h), "idle-reservation-survives-failure")
            e.destroy(h)
            check(not e.owns(h) and h not in e.sessions and h not in e.retry_runtime,
                  "destroy-unregisters-both-reservations")
        elif kind == "reset-clear-slash":
            h = e.session()
            e.lib.kx_set_option(e.native_session(h), b"full_shape", 1)
            text = keys(h, "ofc1")
            check(text == "人類" and e.property(h, "kinfx_punct_tail") == "other",
                  "cjk-commit-sets-other-tail", text=text,
                  tail=e.property(h, "kinfx_punct_tail"))
            e.clear(h)  # same path as do_reset / do_focus_out / do_disable
            check(e.property(h, "kinfx_punct_tail") == "", "explicit-clear-resets-tail",
                  tail=e.property(h, "kinfx_punct_tail"))
            text += keys(h, "/")
            check(text == "人類/", "slash-half-width-after-clear", actual=text, expected="人類/")
        elif kind == "reset-clear-slash-preserve":
            h = e.session()
            e.lib.kx_set_option(e.native_session(h), b"full_shape", 1)
            text = keys(h, "vd1/")
            check(text == "好／", "slash-full-width-after-cjk", actual=text, expected="好／")
            text = keys(h, "/init ")
            check(text == "/init ", "leading-slash-command", actual=text, expected="/init ")
        else:
            raise ValueError(kind)
    finally:
        for x in set(e.sessions) | set(e.retry_runtime):
            e.destroy(x)
        shutil.rmtree(root, ignore_errors=True)
    return checks


class Lifecycle(unittest.TestCase):
    def _run(self, kind):
        return subprocess.run(
            [sys.executable, os.path.abspath(__file__), kind],
            capture_output=True, text=True, env=dict(os.environ))

    def _assert_green(self, kind):
        p = self._run(kind)
        self.assertEqual(p.returncode, 0, "%s failed:\n%s%s" % (kind, p.stdout, p.stderr))

    def test_double_reload_preserves_digit_tail(self):
        self._assert_green("double-reload")

    def test_failed_retry_preserves_digit_tail(self):
        self._assert_green("failed-retry")

    def test_pending_owner_defers_reload(self):
        self._assert_green("pending-defer")

    def test_failed_gap_same_owner_clear_revokes_latin_routing(self):
        self._assert_green("failed-clear")

    def test_commit_does_not_implicitly_rebuild_failed_latch(self):
        self._assert_green("failed-implicit-retry")

    def test_destroy_unregisters_both_reservations(self):
        self._assert_green("destroy-reservation")

    def test_explicit_clear_resets_tail_and_slash_half_width(self):
        self._assert_green("reset-clear-slash")

    def test_clear_absent_slash_still_follows_full_shape(self):
        self._assert_green("reset-clear-slash-preserve")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Child process: run one scenario, print its rows, exit 0 only if all green.
        rows = _run_scenario(sys.argv[1])
        for r in rows:
            print(json.dumps(r, ensure_ascii=False), flush=True)
        sys.exit(0 if all(r["pass"] for r in rows) else 1)
    unittest.main(verbosity=2)
