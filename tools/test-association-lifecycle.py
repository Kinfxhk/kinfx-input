#!/usr/bin/env python3
"""Real-librime association lifecycle regression; isolated child per vector.

Requires the prebuilt product data and production shim. This is engine replay,
not an installed input-method or native GUI acceptance test.
"""
import argparse
import ctypes as C
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
    s = lib.kx_session(b'kinfx_quick')
    assert s
    steps = []
    for code in (ord('x'), ord('z'), 0xff51, 0xff0d):
        handled = lib.kx_key(s, code, 0)
        context = text(lib.kx_context(s)).split('\x1f')
        step = dict(key=code, handled=handled,
                    commit=text(lib.kx_take_commit(s)), preedit=context[0],
                    assoc=text(lib.kx_property(s, b'kinfx_assoc_code')))
        steps.append(step)
        print(json.dumps(step, ensure_ascii=False), flush=True)
    final = steps[-1]
    assert final['commit'] == '', final
    assert final['preedit'] == '難z', final
    assert final['assoc'] == '', final
    return 0


def main(a):
    a.work.mkdir(parents=True, exist_ok=False)
    p = subprocess.run([sys.executable, __file__, '--worker', '--lib', str(a.lib),
                        '--data', str(a.data), '--work', str(a.work / 'user'),
                        '--output', str(a.output)], capture_output=True, text=True,
                       timeout=60, env=dict(os.environ, TMPDIR=str(a.work),
                                           PYTHONDONTWRITEBYTECODE='1'))
    (a.work / 'raw.jsonl').write_text(p.stdout)
    (a.work / 'stderr.log').write_text(p.stderr)
    result = dict(case='partial-selection-keeps-suffix-without-association',
                  exit=p.returncode, passed=p.returncode == 0,
                  scope='real-librime replay, NOT OS GUI',
                  steps=[json.loads(line) for line in p.stdout.splitlines()
                         if line.startswith('{')], stderr_tail=p.stderr[-300:])
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return int(not result['passed'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--worker', action='store_true')
    args = parser.parse_args()
    raise SystemExit(worker(args) if args.worker else main(args))
