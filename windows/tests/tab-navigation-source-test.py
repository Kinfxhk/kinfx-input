"""Windows TIP source contracts; NOT native TSF/GUI acceptance.

Run with Python only; never starts the engine, changes registry or sends input.
The real GUI RED is recorded separately in the VM completion evidence.
"""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
PROCESS = SOURCE.split("  bool Process(", 1)[1].split("  bool ToggleAscii(", 1)[0]


class TabNavigationSourceTests(unittest.TestCase):
    def test_plain_and_shift_tab_blur_before_rime_and_are_not_eaten(self):
        # Tab is host navigation even with pending preedit. It must never reach
        # Rime's Tab candidate binding; use existing raw-preserving Blur policy.
        branch = re.search(
            r"if\s*\(sym == 0xff09 && !\(mask & \(kControl \| kAlt\)\)\)\s*\{(?P<body>.*?)\n    \}",
            PROCESS, re.S,
        )
        self.assertIsNotNone(branch, "Tab/Shift+Tab must bypass Rime using the existing blur policy")
        body = branch.group("body")
        self.assertRegex(body, r"if\s*\(!up\)\s*Blur\(\);")
        self.assertRegex(body, r"return false;")
        self.assertNotIn("kx_key", body)
        self.assertLess(branch.start(), PROCESS.index("Session()"))
        self.assertLess(branch.start(), PROCESS.index("chord_.Event"))
        # No Shift exclusion: Shift+Tab navigates backwards using the same path.
        self.assertNotIn("kShift", body)

    def test_existing_key_mapping_and_blur_policy_stay_intact(self):
        self.assertIn("case VK_TAB: return 0xff09;", SOURCE)
        self.assertIn("kx_key(sess_, 0xffe0, 0);", SOURCE)
        self.assertIn("eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;", PROCESS)
        self.assertIn("sym && (paste || !(mask & (kControl | kAlt)))", PROCESS)
        blur = SOURCE.split("  void Blur(", 1)[1].split("  void TrackContext(", 1)[0]
        self.assertIn("TF_ES_SYNC | TF_ES_READWRITE", blur)
        self.assertNotIn("TF_ES_ASYNC", blur)


if __name__ == "__main__":
    unittest.main(verbosity=2)
