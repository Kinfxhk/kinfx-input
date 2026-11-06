#!/usr/bin/env python3
"""Strict native inline ASCII punctuation; real librime, NOT GUI acceptance.

Every literal is fixed before execution. App-model is append-only commits plus
rejected printable keys; preedit, routing, commit and pass-through stay separate.
Native commit uses the real production shim, not a synthetic Return.
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import resource
import runpy
import shutil

base = runpy.run_path(str(Path(__file__).with_name('test-ascii-punctuation.py')))
keys, chord, REL = base['keys'], base['chord'], base['REL']


def shaped(text, width):
    return ''.join(chr(0x3000 if c == ' ' else ord(c) + 0xfee0)
                   if width == 'full' and (c.isalnum() or c == ' ') else c for c in text)


def live_keys(text):
    # Each printable payload key remains native composition: no early commit,
    # no app passthrough. The final check separately verifies raw/preedit text.
    for action in keys(text):
        yield action
        yield ['check', dict(handled=1, commit='', passthrough='')]


def cases():
    # Exact original reviewer literals: action arrays and want fields unchanged.
    # Frozen v7 is RED on these three; do not weaken their final text oracle.
    start = chord('width') + keys('vd1') + chord('ascii') + keys('hello,.()')
    noearly = ['check', dict(app='好', commits='好', preedit='hello,.()',
                            input='hello,.()', ascii_mode=True, literal_tail=False)]
    yield dict(name='strict-inline-full-f35', actions=start + [noearly,
        ['check', dict(blur='ｈｅｌｌｏ,.()')], ['key', 0xffe0],
        ['check', dict(app='好ｈｅｌｌｏ,.()', commits='好ｈｅｌｌｏ,.()',
                       preedit='', input='', blur='', assoc='', full_shape=True)]])
    yield dict(name='strict-inline-full-return', actions=start + [noearly,
        ['key', 0xff0d], ['check', dict(app='好ｈｅｌｌｏ,.()', preedit='',
                                     input='', full_shape=True)]])
    yield dict(name='strict-inline-width-toggle-f35', actions=keys('vd1') +
        chord('ascii') + keys('hello,.()') + [noearly] + chord('width', REL | 1) +
        [noearly, ['check', dict(full_shape=True, blur='ｈｅｌｌｏ,.()')],
         ['key', 0xffe0], ['check', dict(app='好ｈｅｌｌｏ,.()', preedit='',
                                       input='', assoc='', full_shape=True)]])
    ends = {'f35': [['key', 0xffe0]], 'return': [['key', 0xff0d]], 'native': [['native']],
            'shift': [['key', 0xffe1, 1], ['key', 0xffe1, REL]],
            'modeoff-f35': chord('ascii') + [['key', 0xffe0]],
            'modeoff-return': chord('ascii') + [['key', 0xff0d]]}
    for width in ('half', 'full'):
        start = (chord('width') if width == 'full' else []) + keys('vd1') + chord('ascii')
        for display in ('letters', 'radicals'):
            for short in ('letters', 'commit'):
                for end in ('f35', 'return', 'native'):
                    want = shaped('hello', width) + ',.();'
                    yield dict(name=f'inline-{width}-{display}-{short}-{end}',
                        preedit=display, short_blur=short,
                        actions=start + list(live_keys('hello,.();')) +
                        [['check', dict(app='好', commits='好', preedit='hello,.();',
                                        input='hello,.();', blur=want, literal_tail=False,
                                        ascii_mode=True)]] + ends[end] +
                        [['check', dict(app='好' + want, commit=want, passthrough='',
                                        input='', preedit='', blur='', assoc='', tail='',
                                        full_shape=width == 'full')]] +
                        chord('ascii') + keys('vd1') +
                        [['check', dict(app='好' + want + '好')]])
        for word in ('a', 'NVDA', 'iPhone', 'a2 ', 'hello'):
            want = shaped(word, width) + ',.();'
            yield dict(name=f'word-{width}-{word.strip()}', actions=start + keys(word + ',.();') +
                [['check', dict(app='好', commits='好', preedit=word + ',.();', blur=want)],
                 ['key', 0xffe0], ['check', dict(app='好' + want, commit=want, preedit='')]])
        for end in ('shift', 'modeoff-f35', 'modeoff-return'):
            # Existing Shift confirm commits raw halfwidth letters, unlike
            # native Return/F35. Preserve that established letter-width policy.
            want = ('hello' if end == 'shift' else shaped('hello', width)) + ',.()'
            yield dict(name=f'terminal-{width}-{end}', actions=start + keys('hello,.()') +
                [['check', dict(app='好', commits='好', preedit='hello,.()',
                                 blur=shaped('hello', width) + ',.()')]] +
                ends[end] + [['check', dict(app='好' + want, commit=want,
                    input='', preedit='', blur='', full_shape=width == 'full')]])
        for word, want in [(',.;()2', '，．；（）２' if width == 'full' else ',.;()2'),
                           (',a2 ,.();', '，ａ２　,.();' if width == 'full' else ',a2 ,.();')]:
            # Initial punctuation closes the association before ascii_composer;
            # it is native idle output, not a live raw/no-early-commit oracle.
            yield dict(name=f'initial-{width}-{ord(word[1])}', actions=start + keys(word) +
                [['check', dict(app='好' + want, preedit='', blur='')], ['native'],
                 ['check', dict(app='好' + want, input='', preedit='')]])
        for cancel in ('escape', 'clear'):
            yield dict(name=f'cancel-{width}-{cancel}', actions=start + keys('hello,.()') +
                ([['clear']] if cancel == 'clear' else [['key', 0xff1b]]) +
                [['check', dict(app='好', commits='好', input='', preedit='', blur='', tail='')]] +
                chord('ascii') + keys('vd1') + [['check', dict(app='好好')]])
    for release in (REL, REL | 1):
        yield dict(name=f'width-inline-{release}', actions=keys('vd1') + chord('ascii') + keys('hello,.()') +
            chord('width', release) + [['check', dict(app='好', commits='好', input='hello,.()',
                preedit='hello,.()', full_shape=True, blur='ｈｅｌｌｏ,.()', literal_tail=False)],
                ['key', 0xffe0], ['check', dict(app='好ｈｅｌｌｏ,.()', preedit='')]])
    for offset in (1, 2):
        for end in ('f35', 'return', 'native'):
            yield dict(name=f'inline-caret-{offset}-{end}', actions=chord('width') + keys('vd1') +
                chord('ascii') + keys('hello,.()') + [['key', 0xff51]] * offset +
                [['check', dict(app='好', commits='好', preedit='hello,.()',
                                 cursor=9-offset, blur='ｈｅｌｌｏ,.()')]] + ends[end] +
                [['check', dict(app='好ｈｅｌｌｏ,.()', commit='ｈｅｌｌｏ,.()', input='', preedit='')]])
    yield dict(name='selected-prefix-not-inline', actions=chord('width') + keys('xz') +
        [['key', 0xff51], ['key', 0xff0d], ['check', dict(preedit='難z')],
         ['key', 0xffe0], ['check', dict(commit='難ｚ', preedit='', blur='')]])


def worker(a, case):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.work.mkdir(parents=True, exist_ok=False)
    (a.work / 'log').mkdir()
    for name in ('kinfx_capture.txt', 'kinfx_en_names.txt', 'kinfx_en_unsafe.txt'):
        shutil.copy2(a.data / name, a.work / name)
    (a.work / 'kinfx_quick.custom.yaml').write_text(
        'patch:\n  "english/blur_short": ' + case.get('short_blur', 'letters') +
        '\n  "english/preedit": ' + case.get('preedit', 'letters') +
        '\n  "win_quick/hot_page": false\n')
    lib = C.CDLL(str(a.lib))
    lib.kx_start.argtypes = [C.c_char_p] * 3 + [C.c_int]
    lib.kx_session.argtypes = [C.c_char_p]
    lib.kx_session.restype = C.c_size_t
    lib.kx_key.argtypes = [C.c_size_t, C.c_int, C.c_int]
    for name in ('kx_clear', 'kx_destroy', 'kx_commit_composition'):
        getattr(lib, name).argtypes = [C.c_size_t]
    for name in ('kx_context', 'kx_take_commit'):
        getattr(lib, name).argtypes = [C.c_size_t]
        getattr(lib, name).restype = C.c_void_p
    lib.kx_property.argtypes = [C.c_size_t, C.c_char_p]
    lib.kx_property.restype = C.c_void_p
    lib.kxt_option.argtypes = [C.c_size_t, C.c_char_p]
    lib.kxt_set_property.argtypes = [C.c_size_t, C.c_char_p, C.c_char_p]
    lib.kx_select_candidate_on_current_page.argtypes = [C.c_size_t, C.c_int]
    lib.kxt_version.restype = C.c_char_p
    get_input = base['api_bind'](lib, 69, C.c_char_p, C.c_size_t)
    free = C.CDLL(None).free
    free.argtypes = [C.c_void_p]
    def text(ptr):
        if not ptr:
            return ''
        try:
            return C.string_at(ptr).decode()
        finally:
            free(ptr)
    assert lib.kx_start(str(a.data).encode(), str(a.work).encode(), str(a.work / 'log').encode(), 0)
    sessions, totals, steps, errors = {}, {}, [], []
    current = 'a'
    sessions[current] = lib.kx_session(b'kinfx_quick')
    assert sessions[current]
    def snapshot(action, handled=None, code=0, mask=0):
        sid = sessions[current]
        fields = text(lib.kx_context(sid)).split('\x1f')
        commit = text(lib.kx_take_commit(sid))
        passthrough = (chr(code) if handled == 0 and not mask &
                       (REL | 4 | 8 | (1 << 26) | (1 << 28)) and 32 <= code <= 126 else '')
        app, committed = totals.get(current, ('', ''))
        app, committed = app + commit + passthrough, committed + commit
        totals[current] = app, committed
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
            op, sid = action[0], sessions[current]
            if op == 'key':
                code, mask = action[1], action[2] if len(action) > 2 else 0
                state = snapshot(action, lib.kx_key(sid, code, mask), code, mask)
            elif op == 'native':
                state = snapshot(action, lib.kx_commit_composition(sid))
            elif op == 'select':
                state = snapshot(action, lib.kx_select_candidate_on_current_page(sid, action[1]))
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
                        errors.append(dict(at=len(steps)-1, field=field, want=want, got=got))
            else:
                raise ValueError(action)
    finally:
        for sid in sessions.values():
            lib.kx_destroy(sid)
    a.output.write_text(json.dumps(dict(name=case['name'], errors=errors, steps=steps,
        version=lib.kxt_version().decode(), rlimit_core=resource.getrlimit(resource.RLIMIT_CORE)),
        ensure_ascii=False, indent=2))
    return int(bool(errors))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work', 'output'):
        parser.add_argument('--' + name, required=True, type=lambda s: Path(s).resolve())
    parser.add_argument('--case')
    parser.add_argument('--worker', help=argparse.SUPPRESS)
    args = parser.parse_args()
    base['main'].__globals__.update(cases=cases, __file__=__file__)
    raise SystemExit(worker(args, json.loads(args.worker)) if args.worker else base['main'](args))
