#!/usr/bin/env python3
"""Pure-English punctuation contract via real librime; NOT GUI acceptance.

--data is staged shared data with the Lua under test. Every case gets a fresh
process/user and disables core dumps before loading librime. App-model text is
engine commits plus rejected printable key-downs, never visible preedit.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys

REL = 1 << 30
SHIFTED = '?!)@#$%^&*(:"<>_+{}|~'


def keys(text):
    return [['key', ord(c), int(c.isupper() or c in SHIFTED)] for c in text]


def chord(kind, release=REL):
    kc, mask = (0xffe1, 1) if kind == 'width' else (0xffe3, 4)
    return [['key', kc, mask], ['key', 32, mask],
            ['key', 32, REL | mask], ['key', kc, release]]


def cases():
    for release in (REL, REL | 1):
        yield dict(name='exact-lifecycle-' + str(release), actions=
                   chord('ascii') + keys('hello') +
                   [['check', dict(app='hello', commits='', preedit='', ascii_mode=True)]] +
                   chord('width', release) +
                   [['check', dict(app='hello', commits='', preedit='', full_shape=True)]] +
                   keys(',') + [['check', dict(app='hello,', commits=',', preedit='',
                                             full_shape=True, ascii_mode=True, handled=1)]])
    # Second tracer bullet: command preservation must end before external clear.
    yield dict(name='clear-after-mode-command', actions=chord('ascii') + keys('hello') +
               chord('width') + [['clear'], ['check', dict(tail='', full_shape=True)]] +
               keys(',') + [['check', dict(app='hello，', commit='，')]])
    yield dict(name='space-keeps-latin-context', actions=chord('ascii') + chord('width') +
               keys('hello ,?!') + [['check', dict(app='ｈｅｌｌｏ　,?!', tail='latin',
                                                  full_shape=True, preedit='')]] +
               chord('ascii') + keys('vd1,.') +
               [['check', dict(app='ｈｅｌｌｏ　,?!好，。', full_shape=True)]])
    for width in ('half', 'full'):
        setup = chord('ascii') + (chord('width') if width == 'full' else [])
        letters = 'ｈｅｌｌｏ' if width == 'full' else 'hello'
        for label, value in [('comma', ','), ('period', '.'), ('parentheses', '()'),
                             ('broad-symbols', ',.?!:;()[]{}<>/\\\'"-_=+~@#$%^&*|`')]:
            yield dict(name=f'ascii-{width}-{label}', actions=setup + keys('hello' + value) +
                       [['check', dict(app=letters + value, preedit='', full_shape=width == 'full')]])
        yield dict(name=f'initial-symbols-{width}', actions=setup + keys(',.()') +
                   [['check', dict(app='，．（）' if width == 'full' else ',.()', tail='')]])
        yield dict(name=f'digit-control-{width}', actions=setup + keys('2') +
                   [['check', dict(app='２' if width == 'full' else '2', tail='')]])
        base = (chord('width') if width == 'full' else []) + keys('vd1')
        yield dict(name=f'chinese-ascii-closed-{width}', actions=base + [['key', 0xff1b]] +
                   chord('ascii') + keys('hello,.()') +
                   [['check', dict(app='好' + letters + ',.()', preedit='')]])
        yield dict(name=f'chinese-ascii-inline-{width}', actions=base + chord('ascii') + keys('hello,.()') +
                   [['check', dict(app='好', preedit='hello,.()', literal_tail=False)], ['key', 0xffe0],
                    # Strict English-after-Latin punctuation supersedes the
                    # old wide-punctuation oracle (frozen v7 reproduces RED).
                    # Native letter width and live no-early-commit stay intact.
                    ['check', dict(app='好' + ('ｈｅｌｌｏ,.()' if width == 'full' else 'hello,.()'),
                                   preedit='', blur='', tail='')]])
        yield dict(name=f'ascii-off-chinese-{width}', actions=setup + keys('hello,') +
                   chord('ascii') + keys('vd1,.()') +
                   [['check', dict(app=letters + ',' + ('好，。（）' if width == 'full' else '好,.()'))]])
        yield dict(name=f'mixed-control-{width}', actions=(chord('width') if width == 'full' else []) +
                   keys('hello,') + [['check', dict(app='hello,', preedit='')]])
    yield dict(name='tail-after-mode-off', actions=chord('ascii') + keys('hello') + chord('ascii') +
               chord('width') + keys(',') + [['check', dict(app='hello,', full_shape=True, ascii_mode=False)]])
    yield dict(name='full-width-before-ascii', actions=chord('width') + chord('ascii') + keys('hello,.()') +
               [['check', dict(app='ｈｅｌｌｏ,.()', full_shape=True)]])
    yield dict(name='full-ascii-width-off', actions=chord('ascii') + chord('width') + chord('width') +
               keys('hello,.()') + [['check', dict(app='hello,.()', full_shape=False)]])
    for label, events in (
            ('paste', [['key', 0xffe3, 4], ['key', ord('v'), 4], ['key', 0xffe3, REL | 4]]),
            ('cut', [['key', 0xffe3, 4], ['key', ord('x'), 4], ['key', 0xffe3, REL]]),
            ('shortcut', [['key', 0xffe3, 4], ['key', ord('s'), 4], ['key', 0xffe3, REL]]),
            ('super', [['key', ord('a'), 1 << 26]]),
            ('meta', [['key', ord('a'), 1 << 28]]),
            ('alt', [['key', ord('a'), 8]]),
            ('backspace', [['key', 0xff08]]), ('delete', [['key', 0xffff]]),
            ('left', [['key', 0xff51]]), ('home', [['key', 0xff50]]),
            ('blur', [['key', 0xffe0]]), ('clear', [['clear']]),
            ('focus-property', [['property', 'kinfx_punct_tail', '']])):
        yield dict(name='invalidate-' + label, actions=chord('ascii') + chord('width') + keys('hello') +
                   events + [['check', dict(tail='')]] + keys(',') +
                   [['check', dict(commit='，', full_shape=True, preedit='')]])
    for release in (REL, REL | 4):
        yield dict(name='bare-ctrl-lifecycle-' + str(release), actions=chord('ascii') + keys('hello') +
                   [['key', 0xffe3, 4], ['check', dict(tail='latin')], ['key', 0xffe3, release],
                    ['check', dict(tail='latin')]] + chord('width') + keys(',') +
                   [['check', dict(app='hello,')]])
    yield dict(name='literal-release-not-a-letter', actions=chord('ascii') + chord('width') +
               [['key', ord('h'), REL], ['check', dict(tail='')]] + keys(',') +
               [['check', dict(app='，')]])
    yield dict(name='two-session-isolation', actions=chord('ascii') + keys('hello') +
               [['session', 'b']] + chord('ascii') + chord('width') + keys(',') +
               [['check', dict(app='，', tail='')], ['session', 'a'], ['check', dict(tail='latin')]] +
               chord('width') + keys(',') + [['check', dict(app='hello,')], ['session', 'b']] +
               keys('hello,.') + [['check', dict(app='，ｈｅｌｌｏ,.')]])



def api_bind(lib, slot, restype, *args):
    lib.rime_get_api.restype = C.c_void_p
    base = lib.rime_get_api()
    offset = C.sizeof(C.c_void_p)
    size = C.c_int.from_address(base).value
    pos = offset + slot * C.sizeof(C.c_void_p)
    assert pos + C.sizeof(C.c_void_p) <= size + C.sizeof(C.c_int)
    address = C.c_void_p.from_address(base + pos).value
    assert address
    return C.CFUNCTYPE(restype, *args)(address)


def worker(a, case):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.work.mkdir(parents=True, exist_ok=False)
    (a.work / 'log').mkdir()
    for name in ('kinfx_capture.txt', 'kinfx_en_names.txt', 'kinfx_en_unsafe.txt'):
        shutil.copy2(a.data / name, a.work / name)
    (a.work / 'kinfx_quick.custom.yaml').write_text(
        'patch:\n  "english/blur_short": letters\n  "win_quick/hot_page": false\n')
    lib = C.CDLL(str(a.lib))
    lib.kx_start.argtypes = [C.c_char_p] * 3 + [C.c_int]
    lib.kx_session.argtypes = [C.c_char_p]
    lib.kx_session.restype = C.c_size_t
    lib.kx_key.argtypes = [C.c_size_t, C.c_int, C.c_int]
    for name in ('kx_clear', 'kx_destroy'):
        getattr(lib, name).argtypes = [C.c_size_t]
    for name in ('kx_context', 'kx_take_commit'):
        getattr(lib, name).argtypes = [C.c_size_t]
        getattr(lib, name).restype = C.c_void_p
    lib.kx_property.argtypes = [C.c_size_t, C.c_char_p]
    lib.kx_property.restype = C.c_void_p
    lib.kxt_set_property.argtypes = [C.c_size_t, C.c_char_p, C.c_char_p]
    lib.kxt_option.argtypes = [C.c_size_t, C.c_char_p]
    lib.kxt_version.restype = C.c_char_p
    get_input = api_bind(lib, 69, C.c_char_p, C.c_size_t)
    free = C.CDLL(None).free
    free.argtypes = [C.c_void_p]

    def text(ptr):
        if not ptr:
            return ''
        try:
            return C.string_at(ptr).decode()
        finally:
            free(ptr)

    assert lib.kx_start(str(a.data).encode(), str(a.work).encode(),
                        str(a.work / 'log').encode(), 0)
    sessions = {'a': lib.kx_session(b'kinfx_quick')}
    assert sessions['a']
    current = 'a'
    totals, steps, errors = {}, [], []

    def snapshot(action, handled=None, code=0, mask=0):
        sid = sessions[current]
        fields = text(lib.kx_context(sid)).split('\x1f')
        commit = text(lib.kx_take_commit(sid))
        # Deliberately not a GUI/editor model: no clipboard, deletion, OS text
        # substitution or preedit replacement is simulated. Those actions only
        # test context invalidation/routing here, not final app editing.
        passthrough = (chr(code) if handled == 0 and
                       not mask & (REL | 4 | 8 | (1 << 26) | (1 << 28))
                       and 32 <= code <= 126 else '')
        app, committed = totals.get(current, ('', ''))
        app += commit + passthrough
        committed += commit
        totals[current] = (app, committed)
        state = dict(session=current, action=action, handled=handled, commit=commit,
                     passthrough=passthrough, app=app, commits=committed,
                     preedit=fields[0], input=(get_input(sid) or b'').decode(),
                     cursor=int(fields[1]), candidates=[x.split('\x1e')[0] for x in fields[6:]],
                     tail=text(lib.kx_property(sid, b'kinfx_punct_tail')),
                     blur=text(lib.kx_property(sid, b'kinfx_blur')),
                     assoc=text(lib.kx_property(sid, b'kinfx_assoc_code')),
                     full_shape=bool(lib.kxt_option(sid, b'full_shape')),
                     ascii_mode=bool(lib.kxt_option(sid, b'ascii_mode')))
        steps.append(state)
        print(json.dumps(state, ensure_ascii=False), flush=True)
        return state

    state = snapshot('initial')
    try:
        for action in case['actions']:
            op = action[0]
            sid = sessions[current]
            if op == 'key':
                code, mask = action[1], action[2] if len(action) > 2 else 0
                state = snapshot(action, lib.kx_key(sid, code, mask), code, mask)
            elif op == 'clear':
                lib.kx_clear(sid)
                state = snapshot(action)
            elif op == 'property':
                lib.kxt_set_property(sid, action[1].encode(), action[2].encode())
                state = snapshot(action)
            elif op == 'session':
                current = action[1]
                if current not in sessions:
                    sessions[current] = lib.kx_session(b'kinfx_quick')
                    assert sessions[current]
                state = snapshot(action)
            elif op == 'check':
                for field, want in action[1].items():
                    got = state['tail'] == 'latin' if field == 'literal_tail' else state[field]
                    if got != want:
                        errors.append(dict(at=len(steps) - 1, field=field, want=want, got=got))
            else:
                raise ValueError(action)
    finally:
        for sid in sessions.values():
            lib.kx_destroy(sid)
    result = dict(name=case['name'], errors=errors, steps=steps,
                  version=lib.kxt_version().decode(), rlimit_core=resource.getrlimit(resource.RLIMIT_CORE))
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    return int(bool(errors))


def main(a):
    a.work.mkdir(parents=True, exist_ok=False)
    selected = [c for c in cases() if not a.case or c['name'] == a.case]
    if not selected:
        raise ValueError('unknown --case: ' + str(a.case))
    def identities():
        paths = dict(lib=a.lib, english=a.data / 'lua/english_mix.lua', assoc=a.data / 'lua/assoc.lua')
        return {k: hashlib.sha256(p.read_bytes()).hexdigest() for k, p in paths.items()}
    identity = identities()
    rows = []
    (a.work / 'cases.json').write_text(json.dumps(selected, ensure_ascii=False, indent=2))
    for case in selected:
        name = str(case['name'])
        out = a.work / (name + '.json')
        cmd = [sys.executable, '-B', str(Path(__file__).resolve()), '--worker', json.dumps(case),
               '--lib', str(a.lib), '--data', str(a.data),
               '--work', str(a.work / (name + '-user')), '--output', str(out)]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=90,
                               env=dict(os.environ, TMPDIR=str(a.work), PYTHONDONTWRITEBYTECODE='1'))
            (a.work / (name + '.jsonl')).write_text(p.stdout)
            (a.work / (name + '.stderr.log')).write_text(p.stderr)
            row = json.loads(out.read_text()) if out.exists() else {}
            lua_error = any(t in p.stderr for t in ('Lua Compoment', 'error loading module',
                            'LuaProcessor::', 'LuaTranslation::', 'LuaSegmentor::', 'rime.lua error'))
            row.update(exit=p.returncode, passed=p.returncode == 0 and bool(row) and not lua_error)
        except subprocess.TimeoutExpired:
            row = dict(name=case['name'], passed=False, error='worker timeout')
        rows.append(row)
        print(json.dumps({k: v for k, v in row.items() if k != 'steps'}, ensure_ascii=False), flush=True)
        a.output.write_text(json.dumps(dict(rows=rows), ensure_ascii=False, indent=2))
    result = dict(count=len(rows), passed=sum(r['passed'] for r in rows),
                  failed=sum(not r['passed'] for r in rows), identity=identity,
                  inputs_unchanged=identity == identities(), scope='real librime + literal app-model; NOT GUI', rows=rows)
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != 'rows'}))
    return int(result['failed'] != 0 or not result['inputs_unchanged'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work', 'output'):
        parser.add_argument('--' + name, required=True, type=lambda s: Path(s).resolve())
    parser.add_argument('--case')
    parser.add_argument('--worker', help=argparse.SUPPRESS)
    args = parser.parse_args()
    raise SystemExit(worker(args, json.loads(args.worker)) if args.worker else main(args))
