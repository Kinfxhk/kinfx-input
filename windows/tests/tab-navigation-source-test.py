"""Windows TIP source contracts; NOT native TSF/GUI acceptance.

Run with Python only; never starts the engine, changes registry or sends input.

Contract (handoff 2026-11-06, same as Linux/macOS): Tab = expand. With an open
composition Tab reaches Rime (win_quick toggles the multi-column list, the text
stays in preedit, focus stays). With nothing composing Tab is not eaten, so the
host keeps its Tab/Shift+Tab focus navigation.
"""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
PROCESS = SOURCE.split("  bool Process(", 1)[1].split("  bool ToggleAscii(", 1)[0]


class TabExpandSourceTests(unittest.TestCase):
    def test_idle_tab_passes_to_host_before_rime(self):
        m = re.search(r"if\s*\(sym == 0xff09 && !comp_ && !\(mask & \(kControl \| kAlt\)\)\)\s*return false;", PROCESS)
        self.assertIsNotNone(m, "idle Tab must go straight to the host for focus navigation")
        self.assertLess(m.start(), PROCESS.index("Session()"))
        self.assertLess(m.start(), PROCESS.index("chord_.Event"))

    def test_composing_tab_is_not_blurred_by_the_shell(self):
        # The old shell branch committed raw code and let focus move ("vd" Tab -> "vd").
        tab = PROCESS.split("sym == 0xff09", 1)[1].split("bool modKey", 1)[0]
        self.assertNotIn("Blur()", tab)
        self.assertNotIn("kx_key", tab)

    def test_existing_key_mapping_and_blur_policy_stay_intact(self):
        self.assertIn("case VK_TAB: return 0xff09;", SOURCE)
        self.assertIn("kx_key(sess_, 0xffe0, 0);", SOURCE)
        self.assertIn("eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;", PROCESS)
        self.assertIn("sym && (paste || !(mask & (kControl | kAlt)))", PROCESS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
