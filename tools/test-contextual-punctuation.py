#!/usr/bin/env python3
"""Actual Engine/librime punctuation replay; no GUI delivery is implied.

Usage: python3 tools/test-contextual-punctuation.py --probe JSON_PROBE
  --data STAGED_SHARED_DATA --work EMPTY_SCRATCH --output results.json
The probe accepts shared-dir, isolated-user-dir and JSON keycode/mask pairs.
One process/user per case prevents history/options from contaminating vectors.
"""
import argparse
import json
from pathlib import Path
import subprocess


def keys(text):
    return [[ord(c), 1 if c.isupper() or c in '?!)@#$%^&*(:"<>_+{}|~' else 0] for c in text]


def shiftspace(release_mask=1 << 30):
    return [[0xffe1, 1], [32, 1], [32, (1 << 30) | 1], [0xffe1, release_mask]]


def cases():
    yield 'active-word-comma', keys('hello,'), 'hello,'
    yield 'active-word-question', keys('thanks?'), 'thanks?'
    yield 'held-dot-before-chinese', keys('hello.vd1'), 'hello.好'
    yield 'domain', keys('openai.com '), 'openai.com '
    yield 'file', keys('llama.cpp '), 'llama.cpp '
    for end, events, tail in [('space', [[32, 0]], ' '), ('enter', [[0xff0d, 0]], ''),
                              ('shift', [[0xffe1, 1], [0xffe1, 1 << 30]], '')]:
        yield 'committed-word-' + end, keys('hello') + events + keys(',?!'), 'hello' + tail + ',?!'
    yield 'acronym', keys('BTCUSDT,'), 'BTCUSDT,'
    yield 'capitalized', keys('iPhone,?!'), 'iPhone,?!'
    yield 'capitalized-dot', keys('iPhone. '), 'iPhone. '
    yield 'capitalized-enter', keys('iPhone') + [[0xff0d, 0]] + keys(',?!'), 'iPhone,?!'
    yield 'capitalized-shift', keys('iPhone') + [[0xffe1, 1], [0xffe1, 1 << 30]] + keys(',?!'), 'iPhone,?!'
    for symbol in ('/', '\\', '[', '{', '"', '<', '>', '+', '=', '~', '^', '&', '*', '|', '`', '_'):
        yield 'active-symbol-' + str(ord(symbol)), keys('hello' + symbol), 'hello' + symbol
        continuation = ' ' if symbol in ('+', '_') else ''
        yield 'capitalized-symbol-' + str(ord(symbol)), keys('iPhone' + symbol + continuation), 'iPhone' + symbol + continuation
    yield 'committed-all-symbols', keys('hello ,?!:;()[]{}<>/\\\'"-_=+~@#$%^&*|`'), 'hello ,?!:;()[]{}<>/\\\'"-_=+~@#$%^&*|`'
    yield 'domain-trailing', keys('openai.com,?!'), 'openai.com,?!'
    yield 'email-trailing', keys('me@example.com ,?!'), 'me@example.com ,?!'
    yield 'chinese-english', keys('vd1hello,?!'), '好hello,?!'
    yield 'english-chinese', keys('hello vd1,.'), {'half': 'hello 好,.', 'full': 'hello 好，。'}
    yield 'chinese-repeated', keys('vd1,.'), {'half': '好,.', 'full': '好，。'}
    yield 'chinese-unpicked', keys('vd,.'), {'half': '好,.', 'full': '好，。'}
    yield 'contraction', keys("don't "), "don't "
    yield 'two-code-digit', keys('gg1'), '圭'
    yield 'two-code-pages', keys('ez '), ''
    yield 'phrase', keys('ofc1'), '人類'
    yield 'short-chinese-page', keys('vd 1'), '嫻'
    yield 'right-chinese-page', keys('vd') + [[0xff53, 0]] + keys('1'), '嫻'
    yield 'association-pick', keys('vd1') + [[ord('1'), 1]], '好似'


def shiftspace_cases():
    """Shift+Space is the full_shape toggle and nothing else. Each case starts
    from the default half_shape state and toggles full_shape mid-vector where a
    user would; the chord must reach key_binder (toggle), never commit English,
    never commit Chinese, and never close an association list early."""
    for mask in (1 << 30, (1 << 30) | 1):
        chord = shiftspace(mask)
        for name, before, after, expected in [
            ('idle-chinese-punct', '', 'vd1,', '好，'),
            ('pending-english', 'hello', ',', 'hello,'),
            ('composing-chinese', 'vd', '1,', '好，'),
            ('associating', 'vd1', ',', '好，'),
            ('association-pick', 'vd1', '', '好似'),
            ('dot-then-chinese', 'hello.', 'vd1', 'hello.好'),
            ('dash-then-word', 'hello-', 'world ', 'hello-world '),
            ('domain', 'openai.com', ' ', 'openai.com '),
        ]:
            events = keys(before) + chord + keys(after)
            if name == 'association-pick':
                events += [[0xffe1, 1], [ord('1'), 1], [0xffe1, mask]]
            yield 'ss-' + name + '-' + str(mask), events, expected


def run(args):
    rows = []
    for mode in ('half', 'full'):
        for name, events, want in cases():
            user = args.work / mode / name
            user.mkdir(parents=True, exist_ok=False)
            if mode == 'full':
                events = shiftspace() + events  # complete width-toggle lifecycle
            proc = subprocess.run([str(args.probe), str(args.data), str(user), json.dumps(events)],
                                  capture_output=True, text=True, timeout=60)
            if proc.returncode:
                raise RuntimeError(proc.stderr)
            raw = json.loads(proc.stdout)
            expected = want[mode] if isinstance(want, dict) else want
            row = dict(name=name, mode=mode, expected=expected, got=raw['commit'],
                       pass_=raw['commit'] == expected, steps=raw['steps'])
            rows.append(row)
            args.output.write_text(json.dumps(dict(mode='actual Engine/librime key replay; Shift tap synthesized',
                                                   rows=rows), ensure_ascii=False, indent=2))
            print(('PASS' if row['pass_'] else 'FAIL'), mode, name, repr(row['got']), 'want', repr(expected), flush=True)
    for name, events, want in shiftspace_cases():
        user = args.work / 'shiftspace' / name
        user.mkdir(parents=True, exist_ok=False)
        proc = subprocess.run([str(args.probe), str(args.data), str(user), json.dumps(events)],
                              capture_output=True, text=True, timeout=60)
        if proc.returncode:
            raise RuntimeError(proc.stderr)
        raw = json.loads(proc.stdout)
        row = dict(name=name, mode='shiftspace', expected=want, got=raw['commit'],
                   pass_=raw['commit'] == want, steps=raw['steps'])
        rows.append(row)
        args.output.write_text(json.dumps(dict(mode='actual Engine/librime key replay; Shift tap synthesized',
                                               rows=rows), ensure_ascii=False, indent=2))
        print(('PASS' if row['pass_'] else 'FAIL'), 'shiftspace', name, repr(row['got']), 'want', repr(want), flush=True)
    failed = sum(not r['pass_'] for r in rows)
    print(json.dumps(dict(total=len(rows), passed=len(rows)-failed, failed=failed)))
    return bool(failed)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for flag in ('probe', 'data', 'work', 'output'):
        p.add_argument('--' + flag, required=True, type=Path)
    raise SystemExit(run(p.parse_args()))
