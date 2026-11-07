#!/usr/bin/env python3
"""Native session lifecycle regressions; run with --lib --data --work.

Each test delegates to the real library. Observer cleanup occurs only after
recording leaks, so a missing worker cleanup fails without crashing unittest.
"""
import argparse
import contextlib
import ctypes as C
import io
from pathlib import Path
import resource
import runpy
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class Function:
    def __init__(self, native, call):
        object.__setattr__(self, 'native', native)
        object.__setattr__(self, 'call', call)

    def __getattr__(self, name):
        return getattr(self.native, name)

    def __setattr__(self, name, value):
        setattr(self.native, name, value)

    def __call__(self, *args):
        return self.call(*args)


class Lifecycle(unittest.TestCase):
    def exercise(self, case, mode='commit', exception=False, acquire=False):
        if not OPTIONS.probe:
            args = [sys.executable, '-B', __file__, '--lib', str(OPTIONS.lib),
                    '--data', str(OPTIONS.data), '--work', str(OPTIONS.work),
                    '--runner', str(OPTIONS.runner), '--probe',
                    'Lifecycle.' + self._testMethodName]
            result = subprocess.run(args, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return
        module = runpy.run_path(str(OPTIONS.runner))
        real_cdll = C.CDLL
        native = real_cdll(str(OPTIONS.lib))
        native.kx_alive.argtypes = [C.c_size_t]
        native.kx_alive.restype = C.c_int
        native.kx_destroy.argtypes = [C.c_size_t]
        native.kx_destroy.restype = None
        sessions, destroyed, transitions = [], [], []
        observed = {}

        def session(schema):
            if acquire:
                return 0
            value = native.kx_session(schema)
            self.assertNotEqual(value, 0, 'real session acquisition failed')
            self.assertEqual(native.kx_alive(value), 1)
            sessions.append(value)
            return value

        def destroy(value):
            self.assertEqual(native.kx_destroy.argtypes, [C.c_size_t])
            self.assertIsNone(native.kx_destroy.restype)
            before = native.kx_alive(value)
            native.kx_destroy(value)
            transitions.append((before, native.kx_alive(value)))
            destroyed.append(value)

        class Library:
            kx_session = Function(native.kx_session, session)
            kx_destroy = Function(native.kx_destroy, destroy)

            def __getattr__(self, name):
                return getattr(native, name)

        class Output:
            def write_text(self, text):
                observed['output_reached'] = True
                if exception:
                    raise OSError('lifecycle output write failure')
                return output.write_text(text)

        def load(path):
            return Library() if path == str(OPTIONS.lib) else real_cdll(path)

        work = OPTIONS.work / self._testMethodName
        output = OPTIONS.work / (self._testMethodName + '.json')
        args = SimpleNamespace(work=work, data=OPTIONS.data, lib=OPTIONS.lib,
                               short_blur=mode, width='full', case=case,
                               output=Output())
        stdout = io.StringIO()
        try:
            with patch.object(C, 'CDLL', side_effect=load), contextlib.redirect_stdout(stdout):
                if exception:
                    # An unrelated error, or no error, must fail this test.
                    with self.assertRaisesRegex(OSError, '^lifecycle output write failure$'):
                        module['worker'](args)
                elif acquire:
                    with self.assertRaises(AssertionError) as error:
                        module['worker'](args)
                    self.assertEqual(str(error.exception), '')
                else:
                    observed['exit'] = module['worker'](args)
        finally:
            # Preserve the worker's state BEFORE observer-only orphan cleanup.
            observed['alive_after_worker'] = [native.kx_alive(s) for s in sessions]
            for s in sessions:
                if native.kx_alive(s):
                    native.kx_destroy(s)
        if acquire:
            self.assertEqual(sessions, [])
            self.assertEqual(destroyed, [])
            self.assertNotIn('output_reached', observed)
        else:
            self.assertEqual(len(sessions), 1)
            self.assertEqual(observed['alive_after_worker'], [0], 'worker leaked native session')
            self.assertEqual(destroyed, sessions, 'destroy exactly once for acquired session')
            self.assertEqual(transitions, [(1, 0)])
            self.assertTrue(observed.get('output_reached'), 'output exception seam not reached')
            if not exception:
                expected_exit = 1 if mode == 'letters' and case == 'cursor-candidate' else 0
                self.assertEqual(observed['exit'], expected_exit)
                self.assertTrue(output.is_file())
                self.assertTrue(stdout.getvalue())

    def test_normal_pass_releases_session(self):
        self.exercise('native-wide')

    def test_oracle_failure_releases_session(self):
        self.exercise('cursor-candidate', mode='letters')

    def test_output_exception_releases_session(self):
        self.exercise('native-wide', exception=True)

    def test_no_session_acquired_does_not_destroy(self):
        self.exercise('native-wide', acquire=True)


if __name__ == '__main__':
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lib', 'data', 'work'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--runner', type=Path,
                        default=Path(__file__).with_name('test-blur-finalization.py'))
    parser.add_argument('--probe', action='store_true', help=argparse.SUPPRESS)
    OPTIONS, remaining = parser.parse_known_args()
    remaining = [a for a in remaining if a != '--probe']
    if not OPTIONS.probe:
        OPTIONS.work.mkdir(parents=True, exist_ok=False)
    unittest.main(argv=[__file__] + remaining)
