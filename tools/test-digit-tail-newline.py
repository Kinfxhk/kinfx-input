#!/usr/bin/env python3
"""Newline tail revocation: a genuine newline revokes digit-tail AND punct-tail.

Usage: python3 tools/test-digit-tail-newline.py --probe JSON_PROBE
  --data STAGED_SHARED_DATA --work EMPTY_SCRATCH --output results.json
  [--locales C,zh_CN.UTF-8,zh_HK.UTF-8]

The probe accepts shared-dir, isolated-user-dir and one JSON array of
[keycode, mask] key events; it prints a JSON object whose last stdout line is
{"commit": "...", "steps": [{"key", "mask", "handled", "commit", "preedit",
"candidates", "pageSize"}, ...]}. One Engine.key per event — there is no
auto-release, so a release is an explicit event with mask bit 1<<30 set.

Oracle: a genuine newline (plain Return, Shift+Return, association Return, or a
second Return after a confirm) revokes BOTH kinfx_digit_tail and
kinfx_punct_tail, so the next line resumes CJK: 60cm CR vd1 -> 60cm CR 好
(digit-tail), and punctuation follows the new CJK line. A confirm Return
(hello/PS5) commits inside the processor and keeps its Latin/digit semantics.
Shift+Return while the association list is open is swallowed downstream (the
selector consumes it), so that one must NOT revoke. `handled` is asserted per
Return/KP key-down: a genuine newline is handled=false (the app receives CR),
a confirm or the association swallow is handled=true.

Mask fix: Shift is modifier bit 0 (mask 1), never the Shift_L keycode 0xffe1
passed as a mask. The full Shift lifecycle is Shift_L down -> Enter(mask 1) ->
Enter release -> Shift_L release. This test asserts commit AND the per-key
handled flag AND the width/locale stability, not just the raw commit string.

Width (full_shape) coverage: the probe has no kx_set_option, so width is
toggled with Shift+Space (key_binder's `toggle: full_shape` binding). A
`wide_on()` prefix turns full_shape on for the rest of the session. Under
full_shape the tail state becomes observable in the commit text itself: a
preserved "other" tail makes a following / full-width ／, while a cleared tail
(genuine newline) makes it a half-width command slash /; a preserved "latin"
tail (confirm) keeps a following , half-width, while a cleared tail makes it
full-width ，. That is what makes the Shift+association exclusion and the
deferred-dot/dash genuine-newline falsifiable.

Locale matrix: every case re-runs under each --locales LC_CTYPE value. The
locale is passed to the probe child via env (LC_CTYPE=loc, LC_ALL removed),
not via a parent-only setlocale, and the child's *effective* locale is
reported so a label that silently aliases (macOS maps C -> C.UTF-8) is not
mistaken for a distinct locale.
"""
import argparse
import json
import locale
import os
from pathlib import Path
import subprocess
import sys


RET = 0xff0d        # Return
KP = 0xff8d         # KP_Enter
SHIFT_L = 0xffe1    # Shift_L keycode (only ever a keycode, never a mask)
SHIFT = 1           # Shift-only modifier mask (bit 0)
SPACE = 0x20        # space keycode (Shift+Space toggles full_shape)
RELEASE = 1 << 30
LEFT = 0xff51
CTRL, ALT, SUPER, META = 1 << 2, 1 << 3, 1 << 26, 1 << 28


def keys(text):
    return [[ord(c), SHIFT if c.isupper() else 0] for c in text]


def cm6():
    return keys("60cm")


def shift_return(k):
    # Shift_L down -> Enter (Shift mask) -> Enter release -> Shift_L release.
    return [[SHIFT_L, 0], [k, SHIFT], [k, RELEASE | SHIFT], [SHIFT_L, RELEASE]]


def wide_on():
    # Shift+Space toggles librime's full_shape switch (the probe has no
    # kx_set_option); key_binder owns the toggle and nothing is committed.
    return [[SPACE, SHIFT]]


def cases():
    # Genuine newline revokes digit-tail (and punct-tail): next line is CJK.
    yield "return-revokes-digit-tail", cm6() + [[RET, 0]] + keys("vd1"), "60cm好", [False]
    yield "kp-enter-revokes-digit-tail", cm6() + [[KP, 0]] + keys("vd1"), "60cm好", [False]
    # Shift+Return idle is a real CR too (handled false), so it revokes as well.
    yield "shift-return-revokes-digit-tail", cm6() + shift_return(RET) + keys("vd1"), "60cm好", [False]
    yield "shift-kp-enter-revokes-digit-tail", cm6() + shift_return(KP) + keys("vd1"), "60cm好", [False]
    # Association Return is a genuine newline (handled false): punct-tail revoked.
    yield "association-newline", keys("vd1") + [[RET, 0]] + [[ord("/"), 0]], "好/", [False]
    # Confirm Return keeps Latin/digit (handled true, committed inside processor).
    yield "hello-return-confirm", keys("hello") + [[RET, 0]], "hello", [True]
    yield "ps5-return-confirm", keys("PS5") + [[RET, 0]], "PS5", [True]
    # First Return confirms hello, second is a real newline that revokes punct-tail.
    yield "second-real-newline", keys("hello") + [[RET, 0], [RET, 0]] + [[ord(","), 0]], "hello,", [True, False]
    # Deferred dot/dash: same key commits the token AND falls through as CR.
    yield "hello-dot-return", keys("hello.") + [[RET, 0]], "hello.", [False]
    yield "hello-dash-return", keys("hello-") + [[RET, 0]], "hello-", [False]
    # Shift+Return while the association list is open is swallowed: NOT revoked.
    yield "shift-association-swallowed", keys("vd1") + shift_return(RET) + [[ord("/"), 0]], "好/", [True]
    # Controls: no newline, digit tail stays literal.
    yield "same-line-digit-tail", cm6() + keys("vd1"), "60cmvd1", None
    # Release only -> must NOT revoke.
    yield "return-release-preserved", cm6() + [[RET, RELEASE]] + keys("vd1"), "60cmvd1", None
    # Shortcut chords -> cleared by the navigation/shortcut path (no CR).
    for name, mask in [("ctrl", CTRL), ("alt", ALT), ("super", SUPER), ("meta", META)]:
        yield name + "-return-clears", cm6() + [[RET, mask]] + keys("vd1"), "60cm好", None
    # Existing boundary controls still clear the digit tail.
    yield "backspace-clears", cm6() + [[0xff08, 0]] + keys("vd1"), "60cm好", None
    yield "escape-clears", cm6() + [[0xff1b, 0]] + keys("vd1"), "60cm好", None
    yield "navigation-clears", cm6() + [[LEFT, 0]] + keys("vd1"), "60cm好", None
    # Association pick / Shift tap unchanged.
    yield "association-pick", keys("vd1") + [[ord("1"), SHIFT]], "好似", None
    yield "shift-tap-word", keys("hello") + [[SHIFT_L, SHIFT], [SHIFT_L, RELEASE]], "hello", None
    # ---- full_shape (wide) oracles: the tail state is visible in the commit ----
    # Return/KP_Enter revoke the digit tail at BOTH widths (commit is
    # width-independent, so this guards against a width flip regressing it).
    yield "return-revokes-digit-tail-wide", wide_on() + cm6() + [[RET, 0]] + keys("vd1"), "60cm好", [False]
    yield "kp-enter-revokes-digit-tail-wide", wide_on() + cm6() + [[KP, 0]] + keys("vd1"), "60cm好", [False]
    # Association Return clears the tail: a following / is the half-width
    # command slash (好/), even under full_shape — the genuine-newline oracle.
    yield "association-newline-wide", keys("vd1") + wide_on() + [[RET, 0]] + [[ord("/"), 0]], "好/", [False]
    # Shift+Return with the association open is swallowed AND preserves the
    # "other" tail: the / comes out full-width ／ (好／). If the exclusion were
    # removed (wrong clear), this would be 好/ — this is the falsifying oracle.
    yield "shift-association-swallowed-wide", keys("vd1") + wide_on() + shift_return(RET) + [[ord("/"), 0]], "好／", [True]
    # Deferred dot/dash Return is a genuine newline (not a same-key commit): the
    # tail is cleared, so the next , is full-width ，. A wrong "same-key commit"
    # (latin kept) would give a half-width , instead.
    yield "hello-dot-return-wide", keys("hello.") + wide_on() + [[RET, 0]] + [[ord(","), 0]], "hello.，", [False]
    yield "hello-dash-return-wide", keys("hello-") + wide_on() + [[RET, 0]] + [[ord(","), 0]], "hello-，", [False]
    # Confirm Return keeps the latin tail: the next , stays half-width even
    # under full_shape. A wrong clear here would give a full-width ，.
    yield "hello-return-confirm-wide", keys("hello") + wide_on() + [[RET, 0]] + [[ord(","), 0]], "hello,", [True]
    yield "ps5-return-confirm-wide", keys("PS5") + wide_on() + [[RET, 0]] + [[ord(","), 0]], "PS5,", [True]


def return_down_handled(steps):
    # handled of each Return/KP key-DOWN (a release carries the 1<<30 bit).
    out = []
    for s in steps:
        if s.get("key") in (RET, KP) and not (s.get("mask", 0) & RELEASE):
            out.append(bool(s.get("handled")))
    return out


def run_once(args, work_root, locale_name, env):
    rows = []
    for name, events, want, want_handled in cases():
        user = work_root / (locale_name + "-" + name)
        user.mkdir(parents=True, exist_ok=False)
        proc = subprocess.run([str(args.probe), str(args.data), str(user), json.dumps(events)],
                              capture_output=True, text=True, timeout=60, env=env)
        if proc.returncode:
            raise RuntimeError(proc.stderr[-1200:])
        raw = json.loads(proc.stdout.strip().splitlines()[-1])
        got = raw.get("commit", "")
        handled = return_down_handled(raw.get("steps", []))
        ok = got == want
        if want_handled is not None:
            ok = ok and handled == want_handled
        rows.append(dict(name=name, expected=want, got=got,
                         handled=handled, want_handled=want_handled,
                         pass_=ok, steps=len(raw.get("steps", []))))
    return rows


def child_env(loc):
    # The locale must reach the probe CHILD via its environment, not a
    # parent-only setlocale (which mutates Python's C state but never writes
    # os.environ). LC_ALL would override LC_CTYPE, so drop it.
    env = dict(os.environ)
    env.pop("LC_ALL", None)
    env["LC_CTYPE"] = loc
    return env


def effective_locale(env):
    # Resolve what setlocale(LC_CTYPE, "") yields under this child environment,
    # so the matrix reports the *effective* locale the probe will run under,
    # not the requested label. Returns None when the locale cannot be set.
    code = ("import locale\n"
            "locale.setlocale(locale.LC_CTYPE, '')\n"
            "print(locale.setlocale(locale.LC_CTYPE, None))")
    try:
        r = subprocess.run([sys.executable, "-c", code],
                           capture_output=True, text=True, env=env, timeout=15)
    except Exception:
        return None
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return r.stdout.strip().splitlines()[-1]


def run(args):
    locales = args.locales.split(",")
    per_locale = {}
    effective = {}
    for i, loc in enumerate(locales):
        # Parent-side availability pre-check (locale.Error only fires on Linux
        # for an un-generated locale; macOS silently aliases, so effective_locale
        # below is what actually proves the child ran under a real locale).
        try:
            locale.setlocale(locale.LC_CTYPE, loc)
        except locale.Error:
            print(f"SKIP locale {loc} (unavailable in parent)", flush=True)
            effective[loc] = None
            continue
        env = child_env(loc)
        eff = effective_locale(env)
        if eff is None:
            print(f"SKIP locale {loc} (unresolvable in child)", flush=True)
            effective[loc] = None
            continue
        effective[loc] = eff
        work_root = args.work / str(i)
        per_locale[loc] = run_once(args, work_root, loc, env)
        print(f"locale {loc} -> effective {eff}", flush=True)
    if not per_locale:
        print("ERROR: no usable locale; nothing ran", flush=True)
        return True
    ran = list(per_locale)
    rows = per_locale[ran[0]]
    failed = 0
    for loc, r in per_locale.items():
        for row in r:
            if not row["pass_"]:
                failed += 1
            print(("PASS" if row["pass_"] else "FAIL"),
                  f"[{loc}]", row["name"], "commit", repr(row["got"]),
                  "want", repr(row["expected"]),
                  "handled", row["handled"], "want_handled", row["want_handled"], flush=True)
    args.output.write_text(json.dumps(
        dict(mode="actual Engine/librime key replay; newline tail revocation (digit+punct), handled+commit+locale+width",
             locales=locales, ran_locales=ran, effective_locales=effective,
             rows=rows, per_locale=per_locale,
             locale_stable=all(per_locale[ran[0]] == per_locale[loc] for loc in ran),
             locale_distinct=len({effective[loc] for loc in ran}) == len(ran)),
        ensure_ascii=False, indent=2))
    total = len(rows) * len(per_locale)
    print(json.dumps(dict(total=total, passed=total - failed, failed=failed)))
    return bool(failed)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for flag in ("probe", "data", "work", "output"):
        p.add_argument("--" + flag, required=True, type=Path)
    p.add_argument("--locales", default="C,zh_CN.UTF-8,zh_HK.UTF-8")
    raise SystemExit(run(p.parse_args()))
