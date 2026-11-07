#!/usr/bin/env python3
"""Expected-value blur finalization vectors using real librime, no OS GUI.

Each child is isolated so a native abort is a failed row, never a green skip.
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

CASES = {
    'native-wide': ('zzzz', [], False, 'ｚｚｚｚ'),
    'deferred-dot': ('openai.c', [0xff08], False, 'openai.'),
    'cursor-suffix': ('asxzq', [0xff51], False, 'ｘｚｑ'),
    'cursor-candidate': ('xz', [0xff51], False, '難ｚ'),
    'selected-suffix': ('xz', [0xff51, 0xff0d], False, '難ｚ'),
    'selected-native-suffix': ('xz', [0xff51, 'click0'], False, '難ｚ'),
    'selected-second-suffix': ('xz', [0xff51, 0xff54, 0xff0d], False, '的ｚ'),
    'selected-second-native-suffix': ('xz', [0xff51, 'click1'], False, '的ｚ'),
}


def worker(a):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.work.mkdir(parents=True, exist_ok=False)
    (a.work / 'log').mkdir()
    for name in ('kinfx_capture.txt', 'kinfx_en_names.txt', 'kinfx_en_unsafe.txt'):
        shutil.copy2(a.data / name, a.work / name)
    (a.work / 'kinfx_quick.custom.yaml').write_text(
        'patch:\n  "english/blur_short": ' + a.short_blur + '\n  "win_quick/hot_page": false\n')
    lib = C.CDLL(str(a.lib))
    lib.kx_start.argtypes = [C.c_char_p] * 3 + [C.c_int]
    lib.kx_session.argtypes = [C.c_char_p]
    lib.kx_session.restype = C.c_size_t
    lib.kx_destroy.argtypes = [C.c_size_t]
    lib.kx_destroy.restype = None
    lib.kx_key.argtypes = [C.c_size_t, C.c_int, C.c_int]
    lib.kx_select_candidate_on_current_page.argtypes = [C.c_size_t, C.c_int]
    lib.kx_property.argtypes = [C.c_size_t, C.c_char_p]
    lib.kx_property.restype = C.c_void_p
    lib.kxt_option.argtypes = [C.c_size_t, C.c_char_p]
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
    s = lib.kx_session(b'kinfx_quick')
    try:
        assert s
        steps = []

        def key(code, mask=0):
            handled = (lib.kx_select_candidate_on_current_page(s, int(code[-1]))
                       if isinstance(code, str) and code.startswith('click')
                       else lib.kx_key(s, code, mask))
            context = text(lib.kx_context(s)).split('\x1f')
            step = dict(key=code, mask=mask, handled=handled,
                        commit=text(lib.kx_take_commit(s)), preedit=context[0],
                        preview=text(lib.kx_property(s, b'kinfx_blur')),
                        assoc=text(lib.kx_property(s, b'kinfx_assoc_code')))
            steps.append(step)
            return step

        width_keys = ([(0xffe1, 1), (32, 1), (32, (1 << 30) | 1),
                       (0xffe1, 1 << 30)] if a.width == 'full' else [])
        for code, mask in width_keys:
            key(code, mask)
        word, edits, _, expected = CASES[a.case]
        if a.width == 'half':
            expected = ''.join(chr(ord(c) - 0xfee0) if '\uff01' <= c <= '\uff5e' else c
                               for c in expected)
        for char in word:
            key(ord(char))
        for code in edits:
            key(code)
        before = steps[-1]['preview']
        selected_preedit = steps[-1]['preedit']
        final = key(0xffe0)
        checks = dict(preview_exact=before == expected,
                      commit_exact=final['commit'] == expected,
                      preview_commit_equal=before == final['commit'],
                      cleared=not final['preedit'] and not final['preview'] and not final['assoc'],
                      width_preserved=lib.kxt_option(s, b'full_shape') == int(a.width == 'full'))
        if a.case.startswith('selected-'):
            checks['selection_precondition'] = selected_preedit == expected.replace('ｚ', 'z')
        following = ''.join(str(key(ord(c))['commit']) for c in 'vd1')
        checks['next_field_clean'] = following == '好'
        result = dict(case=a.case, short_blur=a.short_blur, width=a.width,
                      expected=expected, before=before,
                      final=final, following=following, checks=checks, steps=steps)
        a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
        print(json.dumps(result, ensure_ascii=False), flush=True)
        return int(not all(checks.values()))
    finally:
        if s:
            lib.kx_destroy(s)


def main(a):
    a.work.mkdir(parents=True, exist_ok=False)
    rows = []
    for name in CASES:
        if a.selected_only and not name.startswith('selected-'):
            continue
        out = a.work / (name + '.json')
        p = subprocess.run([sys.executable, __file__, '--case', name,
                            '--lib', str(a.lib), '--data', str(a.data),
                            '--work', str(a.work / name), '--output', str(out),
                            '--short-blur', a.short_blur, '--width', a.width],
                           capture_output=True, text=True, timeout=60,
                           env=dict(os.environ, TMPDIR=str(a.work),
                                    PYTHONDONTWRITEBYTECODE='1'))
        (a.work / (name + '.stdout')).write_text(p.stdout)
        (a.work / (name + '.stderr')).write_text(p.stderr)
        row = dict(case=name, exit=p.returncode, passed=p.returncode == 0)
        if out.exists():
            detail = json.loads(out.read_text())
            row.update({k: detail[k] for k in ('expected', 'before', 'final', 'checks')})
        rows.append(row)
    result = dict(scope='real-librime replay; NOT OS GUI',
                  english_sha=hashlib.sha256((a.data / 'lua/english_mix.lua').read_bytes()).hexdigest(),
                  assoc_sha=hashlib.sha256((a.data / 'lua/assoc.lua').read_bytes()).hexdigest(),
                  rows=rows, passed=all(row['passed'] for row in rows))
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return int(not result['passed'])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--case', choices=CASES)
    p.add_argument('--short-blur', choices=('letters', 'commit'), default='commit')
    p.add_argument('--width', choices=('half', 'full'), default='full')
    p.add_argument('--selected-only', action='store_true')
    args = p.parse_args()
    raise SystemExit(worker(args) if args.case else main(args))
