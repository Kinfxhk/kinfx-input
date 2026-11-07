#!/usr/bin/env python3
"""Test real librime via production C shim plus tools/rime-test-api.c.
Build libkxtest from those sources, pass --lib --data --work --output.
No settings/user install or GUI interaction. Data must be staged/prebuilt.
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import shutil


def run(a):
    a.work.mkdir(parents=True, exist_ok=False)
    (a.work / 'log').mkdir()
    for name in ('kinfx_capture.txt', 'kinfx_en_names.txt', 'kinfx_en_unsafe.txt'):
        shutil.copy2(a.data / name, a.work / name)
    (a.work / 'kinfx_quick.custom.yaml').write_text(
        'patch:\n  "english/blur_short": ' + a.short_blur + '\n')
    lib = C.CDLL(str(a.lib))
    lib.kx_start.argtypes = [C.c_char_p] * 3 + [C.c_int]
    lib.kx_session.argtypes = [C.c_char_p]
    lib.kx_session.restype = C.c_size_t
    for name in ('kx_clear', 'kx_destroy', 'kx_commit_composition'):
        getattr(lib, name).argtypes = [C.c_size_t]
    lib.kx_key.argtypes = [C.c_size_t, C.c_int, C.c_int]
    lib.kx_take_commit.argtypes = [C.c_size_t]
    lib.kx_take_commit.restype = C.c_void_p
    lib.kx_property.argtypes = [C.c_size_t, C.c_char_p]
    lib.kx_property.restype = C.c_void_p
    lib.kxt_set_property.argtypes = [C.c_size_t, C.c_char_p, C.c_char_p]
    lib.kxt_option.argtypes = [C.c_size_t, C.c_char_p]
    lib.kxt_version.restype = C.c_char_p
    libc = C.CDLL(None)
    libc.free.argtypes = [C.c_void_p]
    def text(ptr):
        if not ptr:
            return ''
        out = C.string_at(ptr).decode()
        libc.free(ptr)
        return out
    def prop(s, n):
        return text(lib.kx_property(s, n.encode()))
    def take(s):
        return text(lib.kx_take_commit(s))
    def type_(s, chars):
        out = ''
        for c in chars:
            lib.kx_key(s, ord(c), 1 if c.isupper() else 0)
            out += take(s)
        return out
    def check(name, got, want):
        rows.append(dict(name=name, got=got, want=want, pass_=got == want))
        print('PASS' if got == want else 'FAIL', name, repr(got), 'want', repr(want), flush=True)
        a.output.write_text(json.dumps(dict(version=lib.kxt_version().decode(),
            width=a.width, short_blur=a.short_blur, rows=rows), ensure_ascii=False, indent=2))
    assert lib.kx_start(str(a.data).encode(), str(a.work).encode(), str(a.work / 'log').encode(), 0)
    rows = []
    # Explicit text oracles catch equal-but-wrong property/commit output too.
    for word, expected in [('hel', 'hel'), ('vdhel', 'vdhel'), ('vd1hel', 'hel'),
                           ('hello', 'hello'), ('vd', 'vd'), ('he', 'he'),
                           ('openai.co', 'openai.co'), ('iPhone', 'iPhone'),
                           ('asxz', 'asxz'), ('abcd', 'abcd'),
                           # Rescue + a known short tail still commits the held
                           # Chinese prefix; the preview must not drop that prefix.
                           ('asxe', '昨xe'), ('asxl', '昨xl'), ('asxs', '昨xs'),
                           ('asxv', '昨xv'), ('asxx', '昨xx'), ('abxx', '明xx'),
                           ('hello.', 'hello.'), ('hello-', 'hello-'),
                           ('https://x.com', 'https://x.com'), ('BTCUSDT', 'BTCUSDT'),
                           ('me@example.com', 'me@example.com')]:
        s = lib.kx_session(b'kinfx_quick')
        if a.width == 'full':
            for key in [(0xffe1, 1), (32, 1), (32, (1 << 30) | 1), (0xffe1, 1 << 30)]:
                lib.kx_key(s, *key)
            check('full width enabled ' + word, lib.kxt_option(s, b'full_shape'), 1)
        if a.short_blur == 'commit' and word in ('vd', 'he'):
            expected = {'vd': '好', 'he': '反'}[word]
        type_(s, word)
        before = prop(s, 'kinfx_blur')
        lib.kx_key(s, 0xffe0, 0)
        after = take(s)
        check('blur property exact ' + word, before, expected)
        check('F35 exact ' + word, after, expected)
        check('blur property parity ' + word, before, after)
        check('property cleared after blur ' + word, prop(s, 'kinfx_blur'), '')
        check('width survives blur ' + word, lib.kxt_option(s, b'full_shape'), int(a.width == 'full'))
        check('Chinese pick after blur ' + word, type_(s, 'vd1'), '好')
        lib.kx_destroy(s)
    for action, key in [('clear', None), ('blur', (0xffe0, 0)), ('cursor-left', (0xff51, 0)),
                        ('backspace', (0xff08, 0)), ('paste', (ord('v'), 4))]:
        s = lib.kx_session(b'kinfx_quick')
        lib.kx_key(s, 32, 1)
        type_(s, 'hello ')
        if key:
            lib.kx_key(s, *key)
            take(s)
        else:
            lib.kx_clear(s)
        check('invalidate tail ' + action, prop(s, 'kinfx_punct_tail'), '')
        got = type_(s, ',')
        check('invalidate ' + action, got, '，')
        lib.kx_destroy(s)
    s = lib.kx_session(b'kinfx_quick')
    t = lib.kx_session(b'kinfx_quick')
    type_(s, 'hello ')
    check('other session tail starts empty', prop(t, 'kinfx_punct_tail'), '')
    type_(t, 'vd1')
    check('other session cannot inherit Latin tail', prop(t, 'kinfx_punct_tail') == 'latin', False)
    check('first session Latin tail survives', prop(s, 'kinfx_punct_tail'), 'latin')
    lib.kx_destroy(t)
    lib.kx_destroy(s)
    s = lib.kx_session(b'kinfx_quick')
    type_(s, 'hel')
    before = prop(s, 'kinfx_blur')
    t = lib.kx_session(b'kinfx_quick')
    type_(t, 'hello')
    lib.kx_key(s, 0xffe0, 0)
    check('interleaved session blur property parity', before, take(s))
    lib.kx_destroy(t)
    lib.kx_destroy(s)
    s = lib.kx_session(b'kinfx_quick')
    type_(s, 'asxz')
    t = lib.kx_session(b'kinfx_quick')
    type_(t, 'abcd')
    check('rescue property survives second context', prop(s, 'kinfx_blur'), 'asxz')
    check('lowercase property independent', prop(t, 'kinfx_blur'), 'abcd')
    lib.kx_destroy(t)
    check('rescue survives other context destruction', prop(s, 'kinfx_blur'), 'asxz')
    type_(s, 'q')
    check('continue rescue after context destruction', prop(s, 'kinfx_blur'), 'asxzq')
    lib.kx_key(s, 0xffe0, 0)
    check('interleaved continued rescue F35', take(s), 'asxzq')
    lib.kx_destroy(s)
    failed = sum(not r['pass_'] for r in rows)
    print(json.dumps(dict(total=len(rows), failed=failed)))
    return bool(failed)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for flag in ('lib', 'data', 'work', 'output'):
        p.add_argument('--' + flag, type=Path, required=True)
    p.add_argument('--width', choices=['half', 'full'], default='half')
    p.add_argument('--short-blur', choices=['letters', 'commit'], default='letters')
    raise SystemExit(run(p.parse_args()))
