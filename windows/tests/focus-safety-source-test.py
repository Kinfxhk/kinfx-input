"""Source-contract checks only; not a TSF runtime or mouse-focus acceptance test."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")

def method(name, next_name):
    return SOURCE.split(name, 1)[1].split(next_name, 1)[0]

class FocusSafetySourceTests(unittest.TestCase):
    def test_blur_defers_only_for_end_edit_and_preserves_empty_commit(self):
        # Contract change (Mac review P1, 2026-11-06): OnEndEdit holds the app's lock, so a
        # synchronous blur there is refused. Only that caller may defer; the deferred write is
        # bound to its generation so a later focus change cancels it. Focus changes stay sync.
        blur = method("  void Blur(", "  void TrackContext(")
        self.assertIn("(deferred ? TF_ES_ASYNC : TF_ES_SYNC) | TF_ES_READWRITE", blur)
        finish = blur.split("auto finish =", 1)[1].split("};", 1)[0]
        self.assertTrue(finish.lstrip().split("\n", 1)[1].strip().startswith("if (generation != generation_) return;"))
        self.assertIn("lifetime", finish.split("\n", 1)[0])
        self.assertEqual(SOURCE.count(", true);  // deferred") + SOURCE.count("Blur(false, 0, true)"), 1)
        end_edit = method("  STDMETHODIMP OnEndEdit(", "\n private:")
        self.assertIn("Blur(false, 0, true)", end_edit)
        self.assertIn("!commit.empty()", blur)
        self.assertIn("generation != generation_", blur)
        finish = blur.split("auto finish =", 1)[1]
        self.assertNotIn("kx_clear", finish)
        self.assertNotIn("SetSelection", blur)

    def test_ensure_does_not_publish_after_reentrant_blur(self):
        ensure = method("  void EnsureContext(", "  void RefreshFocus(")
        after_blur = ensure.split("if (changed) Blur(false, 0, fromEndEdit);", 1)[1]
        before_track = after_blur.split("TrackContext(c);", 1)[0]
        self.assertIn("generation_ !=", before_track)
        self.assertIn("view->Release()", before_track)

    def test_end_edit_abandons_changed_generation_and_old_composition(self):
        end_edit = method("  STDMETHODIMP OnEndEdit(", "\n private:")
        after_ensure = end_edit.split("EnsureContext(c, true);", 1)[1]
        self.assertIn("generation != generation_", after_ensure.split("BOOL changed", 1)[0])
        self.assertIn("Same(composition.get(), comp_)", end_edit)

    def test_every_end_edit_path_is_async(self):
        # Mac review P1 (2026-11-06): OnEndEdit -> EnsureContext -> Blur must not request TF_ES_SYNC.
        end_edit = method("  STDMETHODIMP OnEndEdit(", "\n private:")
        self.assertNotIn("EnsureContext(c);", end_edit)
        self.assertIn("EnsureContext(c, true);", end_edit)
        ensure = method("  void EnsureContext(", "  void RefreshFocus(")
        self.assertIn("bool fromEndEdit = false", ensure)
        self.assertNotIn("Blur();", ensure)

    def test_track_context_detaches_before_unadvise(self):
        track = method("  void TrackContext(", "  void EnsureContext(")
        self.assertLess(track.index("focus_ = nullptr"), track.index("source->UnadviseSink(oldCookie)"))

    def test_rejected_sync_write_keeps_commit(self):
        # Mac review P1: a mouse pick has already taken the commit from the engine; a refused
        # sync lock must queue the same write async instead of only hiding the window.
        update = method("  void Update(", "  void PickCandidate(")
        refused = update.split("if (FAILED(request) || FAILED(hr)) {", 1)[1].split("cand_.Hide(true);", 1)[0]
        self.assertIn("!commit.empty()", refused)
        self.assertIn("TF_ES_ASYNC | TF_ES_READWRITE", refused)
        self.assertIn("generation != generation_", refused)

    def test_shown_preedit_only_after_settext_succeeds(self):
        write = SOURCE.split("  void Write(", 1)[1]
        self.assertIn("if (SUCCEEDED(set)) shownPre_ = pre;", write)
        self.assertNotIn("shownPre_ = pre;\n    if (generation", write)

if __name__ == "__main__":
    unittest.main()
