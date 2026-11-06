#!/usr/bin/env python3
"""Real-librime association commit lifecycle, not OS GUI acceptance."""
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


def worker(a):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.work.mkdir(parents=True, exist_ok=False)
    (a.work / 'log').mkdir()
    for name in ('kinfx_capture.txt', 'kinfx_en_names.txt', 'kinfx_en_unsafe.txt'):
        shutil.copy2(a.data / name, a.work / name)
    (a.work / 'kinfx_quick.custom.yaml').write_text(
        'patch:\n  "english/blur_short": commit\n  "win_quick/hot_page": false\n')
    lib = C.CDLL(str(a.lib))
    lib.kx_start.argtypes = [C.c_char_p] * 3 + [C.c_int]
    lib.kx_session.argtypes = [C.c_char_p]
    lib.kx_session.restype = C.c_size_t
    lib.kx_key.argtypes = [C.c_size_t, C.c_int, C.c_int]
    lib.kx_clear.argtypes = [C.c_size_t]
    lib.kx_property.argtypes = [C.c_size_t, C.c_char_p]
    lib.kx_property.restype = C.c_void_p
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
    sid = lib.kx_session(b'kinfx_quick')
    assert sid
    total = ''
    trace = []

    def snapshot():
        nonlocal total
        fields = text(lib.kx_context(sid)).split('\x1f')
        commit = text(lib.kx_take_commit(sid))
        total += commit
        state = dict(commit=commit, total=total, preedit=fields[0],
                     candidates=[x.split('\x1e')[0] for x in fields[6:]],
                     assoc=text(lib.kx_property(sid, b'kinfx_assoc_code')))
        trace.append(state)
        print(json.dumps(state, ensure_ascii=False), flush=True)
        return state

    def key(code, mask=0):
        lib.kx_key(sid, code, mask)
        return snapshot()

    for char in 'vd1':
        key(ord(char))
    for _ in range(a.page):
        key(32)
    before = snapshot()
    assert before['assoc'] and len(before['candidates']) >= a.slot
    expected = total + before['candidates'][a.slot - 1]
    if a.lifecycle:
        key(0xffe1, 1)
    final = key(ord('0') + a.slot, 1)
    if a.lifecycle:
        key(ord('0') + a.slot, (1 << 30) | 1)
        final = key(0xffe1, 1 << 30)
    lib.kx_clear(sid)
    cleared = snapshot()
    checks = dict(displayed_candidate=total == expected,
                  disarmed=final['assoc'] == '',
                  menu_closed=final['candidates'] == [],
                  no_resurrection=cleared['assoc'] == '' and cleared['candidates'] == [])
    result = dict(case=f'page{a.page}-rawshift{a.slot}-lifecycle{a.lifecycle}',
                  expected=expected, checks=checks, trace=trace)
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    return int(not all(checks.values()))


def main(a):
    a.work.mkdir(parents=True, exist_ok=False)
    out = a.work / 'worker.json'
    command = [sys.executable, __file__, '--worker', '--lib', str(a.lib),
               '--data', str(a.data), '--work', str(a.work / 'user'),
               '--output', str(out), '--slot', str(a.slot), '--page', str(a.page)]
    if a.lifecycle:
        command.append('--lifecycle')
    p = subprocess.run(command, capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, TMPDIR=str(a.work), PYTHONDONTWRITEBYTECODE='1'))
    (a.work / 'trace.jsonl').write_text(p.stdout)
    (a.work / 'stderr.log').write_text(p.stderr)
    result = json.loads(out.read_text()) if out.exists() else {}
    result.update(exit=p.returncode, passed=p.returncode == 0,
                  scope='real-librime replay; NOT physical keyboard or GUI',
                  assoc_sha256=hashlib.sha256((a.data / 'lua/assoc.lua').read_bytes()).hexdigest(),
                  english_sha256=hashlib.sha256((a.data / 'lua/english_mix.lua').read_bytes()).hexdigest())
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != 'trace'}, ensure_ascii=False))
    return int(not result['passed'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--slot', type=int, choices=range(1, 9), default=1)
    parser.add_argument('--page', type=int, choices=(0, 1), default=0)
    parser.add_argument('--lifecycle', action='store_true')
    parser.add_argument('--worker', action='store_true')
    args = parser.parse_args()
    raise SystemExit(worker(args) if args.worker else main(args))
