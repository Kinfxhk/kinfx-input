#!/usr/bin/env python3
"""Newline-aware digit-tail revocation + ASCII letter classification.

Usage: python3 tools/test-digit-tail-newline.py --probe JSON_PROBE
  --data STAGED_SHARED_DATA --work EMPTY_SCRATCH --output results.json
The probe accepts shared-dir, isolated-user-dir and JSON keycode/mask pairs.
One process/user per case prevents history/options from contaminating vectors.

Oracle: a terminal Return/KP_Enter after a digit-led commit (60cm) revokes
kinfx_digit_tail, so the next line's lowercase letters are Sucheng codes again
(60cm CR vd1 -> 60cm CR 好). A confirm Return (hello/PS5) commits inside the
processor and keeps its Latin/digit semantics; a deferred dot/dash (hello. /
hello-) still commits and follows latin tail. Shift/release/shortcut/association/
navigation controls must not change.
"""
import argparse
import json
from pathlib import Path
import subprocess


RET = 0xff0d      # Return
KP = 0xff8d       # KP_Enter
SHIFT = 0xffe1    # Shift_L
LEFT = 0xff51     # Left arrow
RELEASE = 1 << 30
CTRL, ALT, SUPER, META = 1 << 2, 1 << 3, 1 << 26, 1 << 28


def keys(text):
    return [[ord(c), 1 if c.isupper() else 0] for c in text]


def cm6():
    return keys('60cm')


def cases():
    # Bug 1: digit-tail revoked across a genuine newline.
    yield 'return-revokes-digit-tail', cm6() + [[RET, 0]] + keys('vd1') + [[RET, 0]], '60cm好'
    yield 'kp-enter-revokes-digit-tail', cm6() + [[KP, 0]] + keys('vd1') + [[KP, 0]], '60cm好'
    # Confirm Return keeps Latin/digit semantics (accepted commit, not newline).
    yield 'hello-return-confirm', keys('hello') + [[RET, 0]], 'hello'
    yield 'ps5-return-confirm', keys('PS5') + [[RET, 0]], 'PS5'
    # Deferred dot/dash: same-key commit, latin tail correct, no digit tail.
    yield 'hello-dot-return', keys('hello.') + [[RET, 0]], 'hello.'
    yield 'hello-dash-return', keys('hello-') + [[RET, 0]], 'hello-'
    # Controls: no newline, digit tail stays literal.
    yield 'same-line-digit-tail', cm6() + keys('vd1'), '60cmvd1'
    # Shift+Return is kNoop but consumed downstream -> must NOT revoke.
    yield 'shift-return-preserved', cm6() + [[RET, SHIFT]] + keys('vd1'), '60cmvd1'
    yield 'shift-kp-enter-preserved', cm6() + [[KP, SHIFT]] + keys('vd1'), '60cmvd1'
    # Release only -> must NOT revoke.
    yield 'return-release-preserved', cm6() + [[RET, RELEASE]] + keys('vd1'), '60cmvd1'
    # Shortcut chords -> already cleared by the navigation/shortcut path.
    for name, mask in [('ctrl', CTRL), ('alt', ALT), ('super', SUPER), ('meta', META)]:
        yield name + '-return-clears', cm6() + [[RET, mask]] + keys('vd1'), '60cm好'
    # Existing boundary controls still clear the digit tail.
    yield 'backspace-clears', cm6() + [[0xff08, 0]] + keys('vd1'), '60cm好'
    yield 'escape-clears', cm6() + [[0xff1b, 0]] + keys('vd1'), '60cm好'
    yield 'navigation-clears', cm6() + [[LEFT, 0]] + keys('vd1'), '60cm好'
    # Association / Shift tap unchanged.
    yield 'association-pick', keys('vd1') + [[ord('1'), 1]], '好似'
    yield 'shift-tap-word', keys('hello') + [[SHIFT, 1], [SHIFT, RELEASE]], 'hello'


def run(args):
    rows = []
    for name, events, want in cases():
        user = args.work / name
        user.mkdir(parents=True, exist_ok=False)
        proc = subprocess.run([str(args.probe), str(args.data), str(user), json.dumps(events)],
                              capture_output=True, text=True, timeout=60)
        if proc.returncode:
            raise RuntimeError(proc.stderr)
        raw = json.loads(proc.stdout.strip().splitlines()[-1])
        row = dict(name=name, expected=want, got=raw['commit'],
                   pass_=raw['commit'] == want, steps=len(raw['steps']))
        rows.append(row)
        args.output.write_text(json.dumps(
            dict(mode='actual Engine/librime key replay; newline-aware digit-tail + ASCII classification',
                 rows=rows), ensure_ascii=False, indent=2))
        print(('PASS' if row['pass_'] else 'FAIL'), name, repr(row['got']),
              'want', repr(want), flush=True)
    failed = sum(not r['pass_'] for r in rows)
    print(json.dumps(dict(total=len(rows), passed=len(rows) - failed, failed=failed)))
    return bool(failed)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for flag in ('probe', 'data', 'work', 'output'):
        p.add_argument('--' + flag, required=True, type=Path)
    raise SystemExit(run(p.parse_args()))
