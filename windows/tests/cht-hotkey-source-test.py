"""Ctrl+Space must reach the key sink: the CHT IME/non-IME toggle (0x70) is taken over and restored."""
from pathlib import Path
import unittest

CORE = (Path(__file__).resolve().parents[1] / 'tip' / 'core.cpp').read_text(encoding='utf-8')


class ChtHotkey(unittest.TestCase):
    def test_takeover_clears_0x70_live(self):
        body = CORE.split('void TakeOverHotkeys() {', 1)[1].split('\nbool RestoreHotkeys', 1)[0]
        self.assertIn('kChtToggle = 0x70', CORE)
        self.assertIn('ImmSetHotKey', CORE)
        self.assertIn('ChtSet(0, 0)', body)

    def test_backup_written_once(self):
        body = CORE.split('void TakeOverHotkeys() {', 1)[1].split('\nbool RestoreHotkeys', 1)[0]
        self.assertIn('hotkeys-backup-cht.json', CORE)
        self.assertIn('GetFileAttributesW(cb.c_str()) == INVALID_FILE_ATTRIBUTES', body)

    def test_restore_puts_original_back(self):
        body = CORE.split('bool RestoreHotkeys() {', 1)[1]
        self.assertIn('ChtSet((UINT)std::stoul(a[1]), (UINT)std::stoul(b[1]))', body)
        self.assertIn('DeleteFileW(ChtHotkeyBackup().c_str())', body)


if __name__ == '__main__':
    unittest.main(verbosity=2)
