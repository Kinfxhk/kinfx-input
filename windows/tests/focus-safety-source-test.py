"""Source-contract checks only; not a TSF runtime or mouse-focus acceptance test."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")

def method(name, next_name):
    return SOURCE.split(name, 1)[1].split(next_name, 1)[0]

class FocusSafetySourceTests(unittest.TestCase):
    def test_blur_has_no_deferred_write_and_preserves_empty_commit(self):
        blur = method("  void Blur(", "  void TrackContext(")
        self.assertNotIn("TF_ES_ASYNC", blur)
        self.assertIn("!commit.empty()", blur)
        self.assertIn("generation != generation_", blur)
        finish = blur.split("auto finish =", 1)[1]
        self.assertNotIn("kx_clear", finish)
        self.assertNotIn("SetSelection", blur)

    def test_ensure_does_not_publish_after_reentrant_blur(self):
        ensure = method("  void EnsureContext(", "  void RefreshFocus(")
        after_blur = ensure.split("if (changed) Blur();", 1)[1]
        before_track = after_blur.split("TrackContext(c);", 1)[0]
        self.assertIn("generation_ !=", before_track)
        self.assertIn("view->Release()", before_track)

    def test_end_edit_abandons_changed_generation_and_old_composition(self):
        end_edit = method("  STDMETHODIMP OnEndEdit(", "\n private:")
        after_ensure = end_edit.split("EnsureContext(c);", 1)[1]
        self.assertIn("generation != generation_", after_ensure.split("BOOL changed", 1)[0])
        self.assertIn("Same(composition.get(), comp_)", end_edit)

if __name__ == "__main__":
    unittest.main()
