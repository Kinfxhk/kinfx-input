#!/usr/bin/env python3
"""Production kx_context preedit contract, real librime, no GUI/install.

Build mac/Sources/Shim/kx_shim.c with tools/rime-test-api.c first.
All writable paths are caller supplied; fresh user directory required.
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import resource
import shutil
from typing import Any


def run(a):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.work.mkdir(parents=True, exist_ok=False)
    (a.work / 'log').mkdir()
    for name in ('kinfx_capture.txt', 'kinfx_en_names.txt', 'kinfx_en_unsafe.txt'):
        shutil.copy2(a.data / name, a.work / name)
    (a.work / 'kinfx_quick.custom.yaml').write_text(
        'patch:\n  "english/blur_short": ' + a.short_blur +
        '\n  "english/preedit": ' + a.preedit + '\n  "win_quick/hot_page": false\n')
    lib = C.CDLL(str(a.lib))
    lib.kx_start.argtypes = [C.c_char_p] * 3 + [C.c_int]
    lib.kx_session.argtypes = [C.c_char_p]
    lib.kx_session.restype = C.c_size_t
    lib.kx_key.argtypes = [C.c_size_t, C.c_int, C.c_int]
    lib.kx_destroy.argtypes = [C.c_size_t]
    lib.kx_clear.argtypes = [C.c_size_t]
    for name in ('kx_context', 'kx_take_commit'):
        getattr(lib, name).argtypes = [C.c_size_t]
        getattr(lib, name).restype = C.c_void_p
    lib.kx_property.argtypes = [C.c_size_t, C.c_char_p]
    lib.kx_property.restype = C.c_void_p
    lib.kxt_option.argtypes = [C.c_size_t, C.c_char_p]
    lib.kxt_set_property.argtypes = [C.c_size_t, C.c_char_p, C.c_char_p]
    lib.kx_select_candidate_on_current_page.argtypes = [C.c_size_t, C.c_int]
    free = C.CDLL(None).free
    free.argtypes = [C.c_void_p]

    def text(ptr):
        if not ptr:
            return ''
        out = C.string_at(ptr).decode()
        free(ptr)
        return out

    rows, steps = [], []
    def check(name, got, want):
        rows.append(dict(name=name, got=got, want=want, passed=got == want))
    def prop(s, key):
        return text(lib.kx_property(s, key.encode()))
    def snapshot(s) -> dict[str, Any]:
        fields = text(lib.kx_context(s)).split('\x1f')
        return dict(preedit=fields[0], cursor=int(fields[1]), candidates=fields[6:],
                    display=prop(s, 'kinfx_display'), blur=prop(s, 'kinfx_blur'))
    def key(s, code, mask=0):
        handled = lib.kx_key(s, code, mask)
        commit = text(lib.kx_take_commit(s))
        state = snapshot(s)
        # Decoding both slices proves the byte cursor never splits UTF-8.
        b = state['preedit'].encode()
        valid = 0 <= state['cursor'] <= len(b)
        if valid:
            try:
                b[:state['cursor']].decode(); b[state['cursor']:].decode()
            except UnicodeDecodeError:
                valid = False
        check('UTF8 cursor boundary', valid, True)
        steps.append(dict(session=s, key=code, mask=mask, handled=handled, commit=commit, **state))
        return commit
    def type_(s, word):
        return ''.join(key(s, ord(c), int(c.isupper())) for c in word)
    def session():
        s = lib.kx_session(b'kinfx_quick')
        assert s
        if a.width == 'full':
            for code, mask in ((0xffe1, 1), (32, 1), (32, (1 << 30) | 1), (0xffe1, 1 << 30)):
                key(s, code, mask)
        return s

    assert lib.kx_start(str(a.data).encode(), str(a.work).encode(), str(a.work / 'log').encode(), 0)
    for word, expected in [('asxz', 'asxz'), ('asxe', '昨xe'), ('abxx', '明xx')]:
        s = session()
        check('no early commit ' + word, type_(s, word), '')
        before = snapshot(s)
        inline = expected if a.preedit == 'letters' else {
            'asxz': '昨xz', 'asxe': '昨難水', 'abxx': '明難難'}[word]
        check('complete inline ' + word, before['preedit'], inline)
        check('cursor at complete inline end ' + word, before['cursor'], len(inline.encode()))
        if word == 'asxz':
            check('no-candidate precondition', before['candidates'], [])
        check('literal blur ' + word, before['blur'], expected)
        check('F35 ' + word, key(s, 0xffe0), expected)
        check('display cleared', prop(s, 'kinfx_display'), '')
        check('Chinese recovery', type_(s, 'vd1'), '好')
        lib.kx_destroy(s)
    # Real-key lifecycle and neighbour semantics; no test-only observer Lua.
    if a.core_only:
        result = dict(scope='production C bridge core RED/GREEN; NOT OS/GUI',
                      rows=rows, steps=steps, failed=sum(not r['passed'] for r in rows))
        a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
        print(json.dumps(dict(total=len(rows), failed=result['failed'])))
        return int(result['failed'] != 0)
    for word, want in [('hello', 'hello'), ('asxz', 'asxz'), ('asxe', '昨xe'),
                       ('hello.', 'hello.'), ('hello-', 'hello-')]:
        for release in (1 << 30, (1 << 30) | 1):
            s = session()
            type_(s, word)
            before = snapshot(s)
            candidates = before['candidates']
            width = lib.kxt_option(s, b'full_shape')
            out = ''.join(key(s, c, m) for c, m in
                          ((0xffe1, 1), (32, 1), (32, (1 << 30) | 1), (0xffe1, release)))
            after = snapshot(s)
            check('ShiftSpace no commit ' + word, out, '')
            if a.preedit == 'radicals' and word in ('hello.', 'hello-'):
                glyph = ('.' if word.endswith('.') else '-') if width else (
                    '。' if word.endswith('.') else '－')
                check('ShiftSpace native punctuation preedit ' + word,
                      after['preedit'], 'hello' + glyph)
            else:
                check('ShiftSpace preview stable ' + word, after['preedit'], before['preedit'])
            if word not in ('hello.', 'hello-'):
                check('ShiftSpace menu stable ' + word, after['candidates'], candidates)
            else:
                # Native punctuation glyph/comment legitimately follows width.
                check('ShiftSpace native punctuation menu retained ' + word,
                      len(after['candidates']), len(candidates))
            check('ShiftSpace width toggled ' + word, lib.kxt_option(s, b'full_shape'), 1 - width)
            check('ShiftSpace F35 ' + word, key(s, 0xffe0), want)
            lib.kx_destroy(s)
    for word, inline, blur in [('vd', 'vd', '好' if a.short_blur == 'commit' else 'vd'),
                               ('iPhone', 'iPhone', 'iPhone'), ('BTCUSDT', 'BTCUSDT', 'BTCUSDT'),
                               ('me@example.com', 'me@example.com', 'me@example.com'),
                               ('https://x.com', 'https://x.com', 'https://x.com')]:
        s = session()
        type_(s, word)
        if a.preedit == 'radicals' and word == 'vd':
            inline = '女木'
        check('native/short inline ' + word, snapshot(s)['preedit'], inline)
        check('native/short blur ' + word, key(s, 0xffe0), blur)
        lib.kx_destroy(s)
    for word, edits in [('hello', [0xff08]), ('asxz', [0xff08]),
                        ('asxe', [0xff1b]), ('asxz', [0xff51]),
                        ('xz', [0xff51, 0xff0d]), ('xz', [0xff51, 0xff54, 0xff0d])]:
        s = session()
        type_(s, word)
        for c in edits:
            key(s, c)
        if word == 'hello':
            check('backspace kept held run', snapshot(s)['preedit'],
                  'hell' if a.preedit == 'letters' else '反中中')
            check('backspace blur', key(s, 0xffe0), 'hell')
        if edits[-1] == 0xff0d:
            expected_prefix = '的' if 0xff54 in edits else '難'
            check('explicit selected prefix stays', snapshot(s)['preedit'], expected_prefix + 'z')
            check('selected prefix no display override', prop(s, 'kinfx_display'), '')
        lib.kx_clear(s)
        check('external clear invalidates display', prop(s, 'kinfx_display'), '')
        check('no state leak after clear', type_(s, 'vd1'), '好')
        lib.kx_destroy(s)
    # Reselection, rescue navigation and cancel retain literal baseline behavior.
    for word, actions, expected_commit, expected_inline in [
        ('asxz', [('key', 0xff08)], '昨', 'x'),
        ('asxz', [('key', 0xff1b)], '昨', ''),
        ('asxz', [('key', 0xff51)], '昨', 'xz'),
        ('asxe', [('key', 0xff0d)], '昨氵', ''),
        ('asxe', [('click', 1)], '昨氺', ''),
        ('abxx', [('click', 1)], '明飕', ''),
    ]:
        s = session(); type_(s, word)
        commits = ''
        for kind, code in actions:
            if kind == 'key':
                commits += key(s, code)
            else:
                lib.kx_select_candidate_on_current_page(s, code)
                commits += text(lib.kx_take_commit(s))
        check('editing commit contract ' + word + repr(actions), commits, expected_commit)
        if a.preedit == 'letters':
            check('editing inline contract ' + word + repr(actions), snapshot(s)['preedit'], expected_inline)
        lib.kx_clear(s); lib.kx_destroy(s)
    for word in ('iPhone', 'me@example.com'):
        for offset in (1, 2):
            s = session(); type_(s, word)
            for _ in range(offset):
                check('native caret no premature commit', key(s, 0xff51), '')
            check('native middle caret text ' + word, snapshot(s)['preedit'], word)
            check('native middle caret exact ' + word, snapshot(s)['cursor'], len(word) - offset)
            check('native middle caret no override', prop(s, 'kinfx_display'), '')
            check('native middle caret F35', key(s, 0xffe0), word)
            lib.kx_destroy(s)
    s, t = session(), session()
    type_(s, 'asxz'); type_(t, 'asxe')
    expected_s = 'asxz' if a.preedit == 'letters' else '昨xz'
    expected_t = '昨xe' if a.preedit == 'letters' else '昨難水'
    check('context A independent', snapshot(s)['preedit'], expected_s)
    check('context B independent', snapshot(t)['preedit'], expected_t)
    check('interleaved A F35', key(s, 0xffe0), 'asxz')
    check('context B survives A blur', snapshot(t)['preedit'], expected_t)
    check('interleaved B F35', key(t, 0xffe0), '昨xe')
    lib.kx_destroy(s); lib.kx_destroy(t)

    # Defensive transport tests are explicit property injection, NOT natural
    # typing/invalid-native-range claims. Never read huge values via kx_property.
    s = session(); type_(s, 'asxe')
    record = prop(s, 'kinfx_display')
    fields = record.split('\n')
    lib.kxt_set_property(s, b'kinfx_display', b'')
    fallback = text(lib.kx_context(s))
    def wire(overrides):
        f = fields.copy()
        for i, value in overrides.items():
            f[i] = value
        return '\n'.join(f).encode()
    invalids = [('missing', b''), ('oversized property', b'x' * 9000),
                ('unsupported version', wire({0: '2'})), ('wrong owner', wire({1: '99999'})),
                ('wrong input', wire({2: 'zz'})), ('wrong raw caret', wire({3: '0'})),
                ('oversized display', wire({4: '2049', 5: 'a' * 2049})),
                ('split UTF8 cursor', wire({4: '1', 5: '昨xe'})),
                ('cursor past end', wire({4: '999'})),
                ('wire separator', wire({4: '1', 5: '\x1fx'})),
                ('malformed UTF8', wire({4: '1', 5: 'x'}).replace(b'\nx', b'\n\xff'))]
    for n in (4095, 4096, 8191, 8192):
        invalids.append(('oversized property boundary ' + str(n), b'x' * n))
    for name, value in invalids:
        lib.kxt_set_property(s, b'kinfx_display', value)
        check('reject injected ' + name, text(lib.kx_context(s)), fallback)
    lib.kxt_set_property(s, b'kinfx_display', wire({4: '2048', 5: 'a' * 2048}))
    maximum = text(lib.kx_context(s)).split('\x1f')
    check('accept bounded maximum display exactly', maximum[:2], ['a' * 2048, '2048'])
    lib.kxt_set_property(s, b'kinfx_display', record.encode())
    check('valid record restores full display', snapshot(s)['preedit'], expected_t)
    # A legal native-tail byte maps after the virtual, read-only prefix.
    mapped = wire({4: '3', 5: '昨xe'})
    lib.kxt_set_property(s, b'kinfx_display', mapped)
    mapped_fields = text(lib.kx_context(s)).split('\x1f')
    check('UTF8 prefix mapping transport', mapped_fields[:2], ['昨xe', '3'])
    lib.kx_clear(s); lib.kx_destroy(s)
    result = dict(scope='real librime production C bridge; NOT OS/GUI',
                  short_blur=a.short_blur, width=a.width, preedit=a.preedit,
                  rows=rows, steps=steps, failed=sum(not r['passed'] for r in rows))
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps(dict(total=len(rows), failed=result['failed']), ensure_ascii=False))
    for row in rows:
        if not row['passed']:
            print(json.dumps(row, ensure_ascii=False))
    return int(result['failed'] != 0)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--core-only', action='store_true')
    p.add_argument('--short-blur', choices=('letters', 'commit'), default='letters')
    p.add_argument('--width', choices=('half', 'full'), default='half')
    p.add_argument('--preedit', choices=('letters', 'radicals'), default='letters')
    raise SystemExit(run(p.parse_args()))
