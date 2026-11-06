"""Ctrl+Space must reach the key sink: the CHT IME/non-IME toggle (0x70) is taken over and restored."""
from pathlib import Path
import unittest

CORE = (Path(__file__).resolve().parents[1] / 'tip' / 'core.cpp').read_text(encoding='utf-8')


class ChtHotkey(unittest.TestCase):
    def test_takeover_clears_0x70_live(self):
        body = CORE.split('void TakeOverHotkeys() {', 1)[1].split('\nbool RestoreHotkeys', 1)[0]
        self.assertIn('kChtToggle = 0x70', CORE)
        self.assertIn('ImmSetHotKey', CORE)
        self.assertIn('if (set && ChtBackupValid(cb)) ChtSet(0, 0);', body)

    def test_backup_written_once(self):
        body = CORE.split('void TakeOverHotkeys() {', 1)[1].split('\nbool RestoreHotkeys', 1)[0]
        self.assertIn('hotkeys-backup-cht.json', CORE)
        # Mac review P1: the binding is cleared only after the backup reads back valid.
        self.assertIn('if (set && !ChtBackupValid(cb))', body)
        self.assertLess(body.index('WriteIfChanged(cb, json)'), body.index('ChtSet(0, 0)'))
        self.assertIn('if (!HotkeyBackupValid(b)) return;', body)

    def test_restore_puts_original_back(self):
        body = CORE.split('bool RestoreHotkeys() {', 1)[1]
        self.assertIn('ChtSet(wm, wv);', body)
        # A backup is deleted only after the live values read back equal to it.
        self.assertIn('if (ChtGet(&lm, &lv) && lm == wm && lv == wv) DeleteFileW(cb.c_str());', body)
        self.assertIn('if (live) DeleteFileW(hb.c_str());', body)
        # Mac re-review P2: a malformed backup fails closed (returns false, file kept).
        self.assertIn('if (!ParseCht(ReadAll(cb), &wm, &wv)) ok = false;', body)
        self.assertIn('if (!ParseHotkeys(ReadAll(hb), &v)) return false;', body)
        self.assertIn('return any && ok;', body)

    def test_selftest_never_takes_over_from_start(self):
        self.assertEqual(CORE.count('if (!SelfTest()) TakeOverHotkeys();'), 2)


if __name__ == '__main__':
    unittest.main(verbosity=2)
