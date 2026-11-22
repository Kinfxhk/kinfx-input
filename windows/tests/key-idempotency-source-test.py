"""Source contract for idempotent OnTestKeyDown/OnKeyDown pairing (prevents double-input bug)."""
from pathlib import Path
import unittest

SRC = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
TEST_DOWN = SRC.split("STDMETHODIMP OnTestKeyDown(", 1)[1].split("STDMETHODIMP OnTestKeyUp(", 1)[0]
TEST_UP = SRC.split("STDMETHODIMP OnTestKeyUp(", 1)[1].split("STDMETHODIMP OnKeyDown(", 1)[0]
KEY_DOWN = SRC.split("STDMETHODIMP OnKeyDown(", 1)[1].split("STDMETHODIMP OnKeyUp(", 1)[0]
PROCESS = SRC.split("  bool Process(", 1)[1].split("  bool ToggleAscii(", 1)[0]
TAIL = SRC.split("  void Tail(", 1)[1].split("  bool Process(", 1)[0]


class KeyIdempotencyTests(unittest.TestCase):
    def test_test_paths_pass_is_test_true_while_real_paths_consume(self):
        self.assertIn("Process(w, l, false, true)", TEST_DOWN)
        self.assertIn("Process(w, l, true, true)", TEST_UP)
        self.assertNotIn("true)", KEY_DOWN.split("Handle(", 1)[1])

    def test_repeat_test_key_does_not_clear_pending_within_window(self):
        self.assertIn("bool same = pendW_ == w && pendUp_ == up && (!isTest || msgTime - pendTime_ <= 50);", PROCESS)
        self.assertIn("if (!same || !isTest) pending_ = false;", PROCESS)
        self.assertIn("if (same) return pendEaten_;", PROCESS)

    def test_unclaimed_key_does_not_poison_pending_and_flushes_in_tail(self):
        self.assertIn("if (isTest && (eaten || paste_)) { pending_ = true;", PROCESS)
        self.assertIn("unclaimedFlush_ = true;", PROCESS)
        self.assertIn("if (!switch_ && !unclaimedFlush_) return;", TAIL)


if __name__ == "__main__":
    unittest.main(verbosity=2)
