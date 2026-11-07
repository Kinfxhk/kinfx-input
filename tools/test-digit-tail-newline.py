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
locale is passed to the probe child via env (LC_CTYPE=loc, LC_ALL removed), and
the probe PROCESS itself calls setlocale(LC_CTYPE, getenv("LC_CTYPE")) then
reports its own start/end effective locale plus a ctype positive control
(isalpha(0xba): 0 under C, 1 under a UTF-8 locale on macOS). No Python sidecar
ever stands in for the probe's locale state — env-only propagation never changes
libc ctype, so the probe must call setlocale itself and attest its own state.

Verification model (fail-closed): the matrix is VERIFIED only when BOTH the C
locale (isalpha(0xba)=0) and at least one genuinely distinct UTF-8 locale
(isalpha(0xba)=1) ran natively in the probe. A label whose setlocale silently
no-ops (native effective stays C) is SKIPped explicitly; a matrix that cannot
establish that C vs UTF-8 actually differ inside the probe is reported
NOTVERIFIED and exits non-zero, never "all skipped = full matrix".
"""
import argparse
import json
import os
from pathlib import Path
import subprocess


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
    attest = []
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
        # The probe attests its OWN locale state at start and end of each run.
        attest.append(dict(start=raw.get("localeStart", {}),
                           end=raw.get("localeEnd", {})))
    return rows, attest


def child_env(loc):
    # The locale must reach the probe CHILD via its environment, not a
    # parent-only setlocale (which mutates Python's C state but never writes
    # os.environ). LC_ALL would override LC_CTYPE, so drop it.
    env = dict(os.environ)
    env.pop("LC_ALL", None)
    env["LC_CTYPE"] = loc
    return env


def classify_locale(requested, attest):
    # Summarize the probe's own start/end locale attestation into a native
    # ctype class. This is the probe's state, never a Python sidecar's.
    effs, isas = set(), set()
    for a in attest:
        for k in ("start", "end"):
            effs.add(a[k].get("effective"))
            isas.add(a[k].get("isalphaBA"))
    eff = effs.pop() if len(effs) == 1 else None
    isa = isas.pop() if len(isas) == 1 else None
    if eff is None or isa is None:
        return dict(status="NOTVERIFIED", effective=None, isalphaBA=None, ctype=None,
                    reason="inconsistent probe attestation "
                           f"(effective={sorted(effs)}, isalphaBA={sorted(isas)})")
    if eff == "C":
        ctype = "C" if isa == 0 else "other"
    else:
        ctype = "UTF-8" if isa == 1 else "other"
    if requested != "C" and eff == "C":
        # setlocale silently no-op'd: requested a non-C label but the probe's
        # libc ctype never left C. That label is unsupported -> explicit SKIP.
        return dict(status="SKIP", effective=eff, isalphaBA=isa, ctype=ctype,
                    reason=f"setlocale no-op: requested {requested} but native "
                           f"effective stays C (isalpha(0xba)={isa})")
    if ctype == "other":
        # Native locale changed name but the ctype positive control did not flip:
        # we cannot prove C vs this locale are genuinely distinct.
        return dict(status="NOTVERIFIED", effective=eff, isalphaBA=isa, ctype=ctype,
                    reason=f"native ctype not distinct: effective={eff}, "
                           f"isalpha(0xba)={isa}")
    return dict(status="OK", effective=eff, isalphaBA=isa, ctype=ctype, reason=None)


def run(args):
    locales = args.locales.split(",")
    per_locale = {}
    native = {}
    skipped = {}
    ran = []
    for i, loc in enumerate(locales):
        env = child_env(loc)
        work_root = args.work / str(i)
        try:
            rows, attest = run_once(args, work_root, loc, env)
        except RuntimeError as exc:
            print(f"ERROR locale {loc}: probe failed: {exc}", flush=True)
            skipped[loc] = "probe-crash"
            continue
        summ = classify_locale(loc, attest)
        native[loc] = summ
        if summ["status"] != "OK":
            print(f"{summ['status']} locale {loc}: {summ['reason']}", flush=True)
            skipped[loc] = summ["reason"]
            continue
        ran.append(loc)
        per_locale[loc] = rows
        print(f"locale {loc} -> native effective {summ['effective']} "
              f"isalpha(0xba)={summ['isalphaBA']} [{summ['ctype']}]", flush=True)
    # Fail-closed: a real locale matrix needs BOTH the C ctype (isalpha(0xba)=0)
    # and a genuinely distinct UTF-8 ctype (isalpha(0xba)=1) to have run natively.
    ctypes_ran = {native[loc]["ctype"] for loc in ran}
    positive_control = "C" in ctypes_ran and "UTF-8" in ctypes_ran
    if not ran or not positive_control:
        matrix_status = "NOTVERIFIED"
        fail_closed = True
        print("ERROR: native locale matrix NOTVERIFIED — need C (isalpha=0) AND "
              "a distinct UTF-8 (isalpha=1) to run inside the probe; "
              f"ran={ran} ctypes={sorted(ctypes_ran)} skipped={skipped}", flush=True)
    else:
        matrix_status = "VERIFIED"
        fail_closed = False
    failed = 0
    for loc, r in per_locale.items():
        for row in r:
            if not row["pass_"]:
                failed += 1
            print(("PASS" if row["pass_"] else "FAIL"),
                  f"[{loc}]", row["name"], "commit", repr(row["got"]),
                  "want", repr(row["expected"]),
                  "handled", row["handled"], "want_handled", row["want_handled"], flush=True)
    base_loc = ran[0] if ran else None
    rows = per_locale[base_loc] if base_loc else []
    args.output.write_text(json.dumps(
        dict(mode="actual Engine/librime key replay; newline tail revocation (digit+punct), handled+commit+locale+width",
             locales=locales, ran_locales=ran, skipped_locales=skipped,
             native_locales={loc: native[loc] for loc in ran},
             locale_matrix_status=matrix_status,
             rows=rows, per_locale=per_locale,
             locale_stable=bool(base_loc and all(per_locale[base_loc] == per_locale[loc] for loc in ran)),
             locale_distinct=len({native[loc]["effective"] for loc in ran}) == len(ran)),
        ensure_ascii=False, indent=2))
    total = len(rows) * len(per_locale)
    print(json.dumps(dict(total=total, passed=total - failed, failed=failed,
                          locale_matrix_status=matrix_status)))
    return bool(failed) or fail_closed


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for flag in ("probe", "data", "work", "output"):
        p.add_argument("--" + flag, required=True, type=Path)
    p.add_argument("--locales", default="C,zh_CN.UTF-8,zh_HK.UTF-8")
    raise SystemExit(run(p.parse_args()))
