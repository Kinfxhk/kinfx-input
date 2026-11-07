#!/usr/bin/env python3
"""One-shot full_shape navigation regression through real librime (not GUI).

--data is an already staged shared data directory, including the Lua under test.
Each case runs in a fresh process/user directory; only multi-session deliberately
interleaves contexts in one process. No installed IME or user settings are used.
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

RELEASE = 1 << 30
P0 = ['似', '彩', '食', '奇', '的', '玩', '睇', '過', '了']
P1 = ['聽', '好', '人', '心', '在', '多', '靚', '痛', '快']
SAME = ['assoc', 'click', 'total', 'preedit', 'cursor', 'page_size',
        'page', 'highlighted', 'candidates', 'input', 'caret']


def chord(mask=RELEASE):
    return [['key', 0xffe1, 1], ['key', 32, 1],
            ['key', 32, RELEASE | 1], ['key', 0xffe1, mask]]


def pick(slot=1, mask=RELEASE, symbol=False):
    code = ord('!@#$%^&*('[slot - 1]) if symbol else 48 + slot
    return [['key', 0xffe1, 1], ['key', code, 1],
            ['key', code, RELEASE | 1], ['key', 0xffe1, mask]]


def cases():
    # First tracer bullet: literal expected text, not merely self-consistency.
    actions = [['type', 'vd1'], ['key', 32],
               ['check', dict(total='好', page=1, candidates=P1)], ['save', 'before']]
    actions += chord() + [['check', dict(full_shape=True)], ['same', 'before', SAME]]
    actions += chord() + [['check', dict(full_shape=False)], ['same', 'before', SAME]]
    actions += pick() + [['check', dict(total='好聽', assoc='', click='', candidates=[])],
                         ['clear'], ['check', dict(assoc='', candidates=[])]]
    out: list[dict] = [dict(name='assoc-page2-literal', actions=actions)]
    # Same mechanism, bounded representative states (not a word/code fuzz).
    for ps, page, literal in ((9, 0, P0), (9, 1, P1),
                              (5, 1, ['玩', '睇', '過', '了', '聽']),
                              (5, 2, ['好', '人', '心', '在', '多']),
                              (5, 7, ['象']),
                              (9, 3, ['嘢', '吧', '看', '意', '少', '幾', '比', '易', '象'])):
        for wide in (False, True):
            mask = RELEASE | 1 if wide else RELEASE
            a = chord(mask) if wide else []
            a += [['type', 'vd1']] + [['key', 32] for _ in range(page)]
            # Down gives a real nonzero highlight where the page permits it.
            highlight = min(2, len(literal) - 1)
            a += [['key', 0xff54] for _ in range(highlight)]
            a += [['check', dict(total='好', page=page, candidates=literal,
                                 highlighted=highlight, full_shape=wide)], ['save', 'before']]
            if page in (3, 7):
                a += [['check', dict(last=1)]]
            a += chord(mask) + [['check', dict(full_shape=not wide)], ['same', 'before', SAME]]
            a += [['click', len(literal) - 1],
                  ['check', dict(total='好' + literal[-1], assoc='', click='', candidates=[])],
                  ['clear'], ['check', dict(assoc='', candidates=[])], ['type', 'vd1'],
                  ['check', dict(total='好' + literal[-1] + '好', page=0,
                                 highlighted=0, candidates=P0[:ps])]]
            out.append(dict(name=f'assoc-size{ps}-page{page}-from-{wide}', page_size=ps, actions=a))
    for code, literal in (('v', ['女']),
                          ('vd', ['嫻', '槳', '樂', '繅', '孿', '姀', '孥', '姝', '婐'])):
        a = [['type', code]]
        if code == 'vd':
            a += [['key', 32], ['key', 0xff54], ['key', 0xff54]]
        a += [['check', dict(candidates=literal, preedit=code, cursor=len(code))], ['save', 'before']]
        a += chord(RELEASE | 1) + [['same', 'before', SAME], ['check', dict(full_shape=True)]]
        a += [['click', 0], ['check', dict(total=literal[0])]]
        out.append(dict(name='ordinary-' + code, actions=a))
    for symbol in (False, True):
        a = [['type', 'vd1'], ['key', 32]] + chord(RELEASE | 1)
        a += pick(2, RELEASE | 1, symbol) + [['check', dict(total='好好', assoc='', candidates=[])],
                                            ['clear'], ['check', dict(assoc='', candidates=[])]]
        out.append(dict(name=f'assoc-pick2-symbol-{symbol}', actions=a))
    for kc in (0x39, 0x28, 0xffb9):
        for wide in (False, True):
            # Independent starting width. Keyboard ninth remains punctuation;
            # displayed/native slot nine is covered by the page2 click above.
            a = chord() if not wide else []
            a += [['type', 'vd1'], ['key', 32]] + chord()
            a += [['check', dict(full_shape=wide)], ['key', kc, 1],
                  ['check', dict(total='好' + ('（' if wide else '('), assoc='', candidates=[])]]
            out.append(dict(name=f'shift9-{kc}-width-{wide}', actions=a))
    # Terminal states cannot lend the next composition an old checkpoint.
    for end, expected in ((['key', 0xff1b], '好'), (['key', 0xff08], '好'),
                          (['key', 0xff0d], '好'), (['key', 0xffe0], '好'),
                          (['type', 'v'], '好')):
        a = [['type', 'vd1'], ['key', 32]] + chord() + [end]
        a += [['clear'], ['check', dict(total=expected, assoc='', candidates=[])],
              ['type', 'vd1'], ['check', dict(page=0, highlighted=0, candidates=P0)]]
        out.append(dict(name='reset-' + str(end[-1]), actions=a))
    # All are negative controls for the transaction and full Shift lifecycle.
    for word in ('', 'hello', 'hello.', 'hello-', 'asxz'):
        fields = SAME if word not in ('hello.', 'hello-') else [f for f in SAME if f != 'candidates']
        a = [['type', word], ['save', 'before']] + chord(RELEASE | 1)
        a += [['same', 'before', fields], ['check', dict(full_shape=True)]]
        if word in ('hello.', 'hello-'):
            a += [['check', dict(candidates=['。' if word.endswith('.') else '－'])]]
        a += chord() + [['same', 'before', SAME], ['check', dict(full_shape=False)]]
        out.append(dict(name='unchanged-' + (word or 'idle'), actions=a))
    a = [['type', 'vd1'], ['key', 32], ['key', 0xff54], ['save', 'a'],
         ['session', 'b'], ['type', 'vd1'], ['key', 32], ['key', 32],
         ['key', 0xff54], ['key', 0xff54], ['save', 'b']]
    a += chord() + [['same', 'b', SAME], ['click', 1], ['check', dict(total='好感')],
                    ['session', 'a']] + chord(RELEASE | 1)
    a += [['same', 'a', SAME], ['click', 8], ['check', dict(total='好快')],
          ['clear'], ['recreate'], ['type', 'vd1'], ['check', dict(page=0, highlighted=0, candidates=P0)]]
    out.append(dict(name='multi-session-and-destroy', actions=a))
    a = [['type', 'vd1'], ['key', 32], ['save', 'before'],
         ['option', 'full_shape', True], ['same', 'before', SAME],
         ['option', 'full_shape', False], ['same', 'before', SAME],
         ['click', 8], ['check', dict(total='好快', assoc='', candidates=[])]]
    out.append(dict(name='direct-option-not-key', actions=a))
    # Native clear while ARMED deliberately rearms at index zero; it is not
    # cancel. A one-shot transaction must not resurrect the OLD page on update.
    a = [['type', 'vd1'], ['key', 32]] + chord() + [['clear'],
         ['check', dict(total='好', page=0, highlighted=0, candidates=P0, assoc='fjhn')]]
    a += chord() + [['check', dict(page=0, highlighted=0, candidates=P0)]]
    out.append(dict(name='armed-native-clear-new-menu', actions=a))
    a = [['type', 'vd1'], ['key', 32]] + chord() + [
        ['schema', 'kinfx_en'], ['schema', 'kinfx_quick'], ['type', 'vd1'],
        ['check', dict(page=0, highlighted=0, candidates=P0)]]
    out.append(dict(name='schema-switch', actions=a))
    a = [['type', 'vd'], ['caret', 1], ['save', 'before']] + chord()
    a += [['same', 'before', SAME], ['check', dict(full_shape=True)]]
    out.append(dict(name='ordinary-mid-caret', actions=a))
    # Explicitly labelled scratch schema fixture: native punctuation menus have
    # different identities across width. Never transplant the old highlight.
    a = [['type', '`'], ['key', 0xff54], ['key', 0xff54],
         ['check', dict(candidates=['甲', '乙', '丙'], highlighted=2)], ['save', 'before']]
    a += chord() + [['same', 'before', ['input', 'caret', 'total', 'preedit', 'cursor']],
                    ['check', dict(full_shape=True, candidates=['丁', '戊', '己'], highlighted=0)],
                    ['click', 0], ['check', dict(total='丁')]]
    out.append(dict(name='native-punctuation-identity-change', actions=a,
                    patch='  "punctuator/half_shape/`": [甲, 乙, 丙]\n'
                          '  "punctuator/full_shape/`": [丁, 戊, 己]\n'))
    # No checkpoint may survive a full_shape change with no menu in ascii mode.
    a = [['option', 'ascii_mode', True], ['save', 'before']] + chord()
    a += [['same', 'before', SAME], ['option', 'ascii_mode', False], ['type', 'vd1'],
          ['check', dict(page=0, highlighted=0, candidates=P0)]]
    out.append(dict(name='ascii-idle-to-new-association', actions=a))
    return out


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rime_api(lib):
    """Versioned public RimeApi ABI (1.0+ prefix, 1.17 tail), no QA overlay.

    Slots are pointer fields after data_size in rime_api.h. Check both the
    published byte size and non-null entry before binding optional tail APIs.
    """
    lib.rime_get_api.restype = C.c_void_p
    base = lib.rime_get_api()
    size = C.c_int.from_address(base).value
    offset = (C.sizeof(C.c_int) + C.sizeof(C.c_void_p) - 1) // C.sizeof(C.c_void_p) * C.sizeof(C.c_void_p)

    def bind(slot, restype, *argtypes):
        pos = offset + slot * C.sizeof(C.c_void_p)
        if pos + C.sizeof(C.c_void_p) > size + C.sizeof(C.c_int):
            raise RuntimeError('required RimeApi slot unavailable: ' + str(slot))
        address = C.c_void_p.from_address(base + pos).value
        if not address:
            raise RuntimeError('null RimeApi slot: ' + str(slot))
        return C.CFUNCTYPE(restype, *argtypes)(address)

    return dict(set_option=bind(27, None, C.c_size_t, C.c_char_p, C.c_int),
                select_schema=bind(34, C.c_int, C.c_size_t, C.c_char_p),
                get_input=bind(69, C.c_char_p, C.c_size_t),
                get_caret=bind(70, C.c_size_t, C.c_size_t),
                set_caret=bind(73, None, C.c_size_t, C.c_size_t))


def worker(a, case):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.work.mkdir(parents=True, exist_ok=False)
    (a.work / 'log').mkdir()
    for name in ('kinfx_capture.txt', 'kinfx_en_names.txt', 'kinfx_en_unsafe.txt'):
        shutil.copy2(a.data / name, a.work / name)
    (a.work / 'kinfx_quick.custom.yaml').write_text(
        'patch:\n  "english/blur_short": letters\n  "win_quick/hot_page": false\n'
        '  "menu/page_size": ' + str(case.get('page_size', 9)) + '\n' + case.get('patch', ''))
    lib = C.CDLL(str(a.lib))
    api = rime_api(lib)
    lib.kx_start.argtypes = [C.c_char_p] * 3 + [C.c_int]
    lib.kx_session.argtypes = [C.c_char_p]
    lib.kx_session.restype = C.c_size_t
    lib.kx_key.argtypes = [C.c_size_t, C.c_int, C.c_int]
    lib.kx_select_candidate_on_current_page.argtypes = [C.c_size_t, C.c_int]
    lib.kx_clear.argtypes = [C.c_size_t]
    lib.kx_destroy.argtypes = [C.c_size_t]
    lib.kx_property.argtypes = [C.c_size_t, C.c_char_p]
    lib.kx_property.restype = C.c_void_p
    lib.kxt_option.argtypes = [C.c_size_t, C.c_char_p]
    lib.kxt_option.restype = C.c_int
    lib.kxt_version.restype = C.c_char_p
    for name in ('kx_context', 'kx_take_commit'):
        getattr(lib, name).argtypes = [C.c_size_t]
        getattr(lib, name).restype = C.c_void_p
    free = C.CDLL(None).free
    free.argtypes = [C.c_void_p]

    def text(ptr):
        if not ptr:
            return ''
        result = C.string_at(ptr).decode()
        free(ptr)
        return result

    assert lib.kx_start(str(a.data).encode(), str(a.work).encode(),
                        str(a.work / 'log').encode(), 0)
    sessions = {'a': lib.kx_session(b'kinfx_quick')}
    assert sessions['a']
    current = 'a'
    totals, saved, errors = {}, {}, []

    def snapshot(action, handled=None):
        sid = sessions[current]
        fields = text(lib.kx_context(sid)).split('\x1f')
        commit = text(lib.kx_take_commit(sid))
        totals[current] = totals.get(current, '') + commit
        state = dict(session=current, action=action, handled=handled, commit=commit,
                     input=(api['get_input'](sid) or b'').decode(), caret=api['get_caret'](sid),
                     total=totals[current], preedit=fields[0], cursor=int(fields[1]),
                     page_size=int(fields[2]), page=int(fields[3]), last=int(fields[4]),
                     highlighted=int(fields[5]),
                     candidates=[x.split('\x1e')[0] for x in fields[6:]],
                     assoc=text(lib.kx_property(sid, b'kinfx_assoc_code')),
                     click=text(lib.kx_property(sid, b'kinfx_candidate_click')),
                     blur=text(lib.kx_property(sid, b'kinfx_blur')),
                     full_shape=bool(lib.kxt_option(sid, b'full_shape')))
        print(json.dumps(state, ensure_ascii=False), flush=True)
        return state

    state = snapshot('initial')
    try:
        for action in case['actions']:
            op = action[0]
            sid = sessions[current]
            if op == 'type':
                for ch in action[1]:
                    state = snapshot(['key', ord(ch), 0], lib.kx_key(sid, ord(ch), 0))
            elif op == 'key':
                state = snapshot(action, lib.kx_key(sid, action[1], action[2] if len(action) > 2 else 0))
            elif op == 'click':
                state = snapshot(action, lib.kx_select_candidate_on_current_page(sid, action[1]))
            elif op == 'clear':
                lib.kx_clear(sid)
                state = snapshot(action)
            elif op == 'option':
                api['set_option'](sid, action[1].encode(), int(action[2]))
                state = snapshot(action)
            elif op == 'caret':
                api['set_caret'](sid, action[1])
                state = snapshot(action)
            elif op == 'schema':
                assert api['select_schema'](sid, action[1].encode()), action
                state = snapshot(action)
            elif op == 'session':
                current = action[1]
                if current not in sessions:
                    sessions[current] = lib.kx_session(b'kinfx_quick')
                    assert sessions[current]
                state = snapshot(action)
            elif op == 'recreate':
                lib.kx_destroy(sid)
                sessions[current] = lib.kx_session(b'kinfx_quick')
                assert sessions[current]
                state = snapshot(action)
            elif op == 'save':
                saved[action[1]] = dict(state)
            elif op in ('check', 'same'):
                wants = action[1] if op == 'check' else {k: saved[action[1]][k] for k in action[2]}
                for field, want in wants.items():
                    if state[field] != want:
                        errors.append(dict(at=action, field=field, want=want, got=state[field]))
            else:
                raise ValueError(action)
    finally:
        for sid in sessions.values():
            lib.kx_destroy(sid)
    result = dict(name=case['name'], errors=errors, final=state,
                  version=lib.kxt_version().decode())
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    return int(bool(errors))


def main(a):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.work.mkdir(parents=True, exist_ok=False)
    selected = [c for c in cases() if not a.case or c['name'] == a.case]
    if not selected:
        raise ValueError('unknown --case: ' + str(a.case))
    identity = {n: sha(a.data / ('lua/' + n)) for n in ('english_mix.lua', 'assoc.lua')}
    lib_hash = sha(a.lib)
    results = []
    (a.work / 'cases.json').write_text(json.dumps(selected, ensure_ascii=False, indent=2))
    for case in selected:
        output = a.work / (case['name'] + '.json')
        command = [sys.executable, __file__, '--worker', json.dumps(case),
                   '--lib', str(a.lib), '--data', str(a.data),
                   '--work', str(a.work / (case['name'] + '-user')), '--output', str(output)]
        try:
            p = subprocess.run(command, capture_output=True, text=True, timeout=90,
                               env=dict(os.environ, TMPDIR=str(a.work), PYTHONDONTWRITEBYTECODE='1'))
            (a.work / (case['name'] + '.jsonl')).write_text(p.stdout)
            (a.work / (case['name'] + '.stderr.log')).write_text(p.stderr)
            result = json.loads(output.read_text()) if output.exists() else {}
            result.update(name=case['name'], exit=p.returncode, passed=p.returncode == 0 and bool(result))
            # A swallowed Lua exception must not turn into an accidental PASS.
            lua_error = any(token in p.stderr for token in ('Lua Compoment', 'error loading module',
                             'LuaProcessor::', 'LuaTranslation::', 'LuaSegmentor::', 'rime.lua error'))
            if lua_error:
                result.update(passed=False, fixture_or_runtime_error='see stderr.log')
        except subprocess.TimeoutExpired:
            result = dict(name=case['name'], passed=False, error='worker timeout')
        results.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
        a.output.write_text(json.dumps(dict(results=results), ensure_ascii=False, indent=2))
    unchanged = identity == {n: sha(a.data / ('lua/' + n)) for n in identity} and lib_hash == sha(a.lib)
    summary = dict(count=len(results), passed=sum(r['passed'] for r in results),
                   failed=sum(not r['passed'] for r in results), identity=identity,
                   lib_sha256=lib_hash, inputs_unchanged=unchanged,
                   scope='real-librime API replay; NOT GUI or physical keyboard', results=results)
    a.output.write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print(json.dumps({k: v for k, v in summary.items() if k != 'results'}, ensure_ascii=False))
    return int(not unchanged or any(not r['passed'] for r in results))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work', 'output'):
        parser.add_argument('--' + name, type=lambda s: Path(s).resolve(), required=True)
    parser.add_argument('--case')
    parser.add_argument('--worker', help=argparse.SUPPRESS)
    args = parser.parse_args()
    raise SystemExit(worker(args, json.loads(args.worker)) if args.worker else main(args))
