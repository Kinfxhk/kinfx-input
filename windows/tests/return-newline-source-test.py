"""Windows TIP source contracts; NOT native TSF/GUI acceptance.

Run with Python only; never starts the engine, changes registry or sends input.

Contract (shared tools/test-digit-tail-newline.py, hello-dot-return / hello-dash-return):
a Return that Rime does NOT handle while a preedit is open (deferred "hello." / "hello-")
is a genuine newline: the held text is committed AND the app receives the newline.

Windows RED (VM 2026-11-07, DLL 16086DE2, nl-result-ee51e5e-red3.json): with the
composition still open, the unhandled Return went to the app, which used it to end the
composition instead of inserting CR LF ("hello.," instead of "hello.\r\n,").

Design (r3, after Mac review CHANGES on 41f3901 and VM RED of r2 3d8dcb6):
the commit happens in the TEST path (OnTestKeyDown -> FinishNewline -> Update), the way
Tail() commits a Ctrl+Space switch, and the Return is reported NOT eaten, so TSF hands
that same physical key to the app after the text. r2 (claim in test, commit + pass in
OnKeyDown) gave no newline on VM WinForms (nl-result-3d8dcb6-nl1.json N01/N02/N11/N12).
No SendInput: a synthetic Return could overtake a queued async commit, re-enter, or be
lost when SendInput fails (Mac mock-TSF repros). If the sync lock was refused (our
composition still open after Update) the Return is swallowed: text kept, one newline
lost, never newline-before-text.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
PROCESS = SOURCE.split("  bool Process(", 1)[1].split("  bool ToggleAscii(", 1)[0]
HANDLE = SOURCE.split("  bool Handle(ITfContext *c, WPARAM w, LPARAM l, bool up) {", 1)[1].split("  void Update(ITfContext *c) {", 1)[0]
RESET = SOURCE.split("  void ResetInput() {", 1)[1].split("}", 1)[0]
BLOCK = SOURCE.split("  bool FinishNewline(ITfContext *c) {", 1)[1].split("  bool Handle(", 1)[0]
TEST_DOWN = SOURCE.split("STDMETHODIMP OnTestKeyDown(", 1)[1].split("STDMETHODIMP OnTestKeyUp(", 1)[0]


class ReturnNewlineSourceTests(unittest.TestCase):
    def test_unhandled_return_with_open_composition_is_claimed(self):
        self.assertIn("newline_ = sym == 0xff0d && !up && !eaten && comp_ != nullptr;", PROCESS)
        self.assertNotIn("if (newline_) eaten = true;", PROCESS)  # r2 claim removed
        self.assertLess(PROCESS.index("eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;"),
                        PROCESS.index("newline_ = sym == 0xff0d"))

    def test_test_path_commits_then_passes_the_same_key(self):
        self.assertIn("if (FinishNewline(c)) { *eaten = TRUE; pendEaten_ = true; }", TEST_DOWN)
        self.assertLess(TEST_DOWN.index("*eaten = Process(w, l, false);"), TEST_DOWN.index("FinishNewline(c)"))
        self.assertIn("newline_ = false;", BLOCK)
        self.assertLess(BLOCK.index("newline_ = false;"), BLOCK.index("Update(c);"))
        self.assertIn("return false;", BLOCK)
        self.assertIn("if (FinishNewline(c)) return true;", HANDLE)  # OnKeyDown without a test call

    def test_no_synthetic_return(self):
        # Mac review: re-sent input can overtake an async commit, self-reinject, or be lost.
        self.assertNotIn("SendInput", BLOCK)
        self.assertNotIn("VK_RETURN; in[", HANDLE)

    def test_refused_sync_commit_swallows_instead_of_newline_first(self):
        self.assertIn('if (comp_) { Trace("newline: commit queued, Return swallowed"); return true; }', BLOCK)
        self.assertLess(BLOCK.index("if (comp_)"), BLOCK.rindex("return false;"))

    def test_test_path_reports_eaten_so_on_keydown_runs(self):
        test_down = SOURCE.split("STDMETHODIMP OnTestKeyDown(", 1)[1].split("STDMETHODIMP OnTestKeyUp(", 1)[0]
        self.assertIn("*eaten = Process(w, l, false);", test_down)
        on_down = SOURCE.split("STDMETHODIMP OnKeyDown(", 1)[1].split("\n", 1)[0]
        self.assertIn("*eaten = Handle(c, w, l, false);", on_down)

    def test_flag_is_reset_and_declared(self):
        self.assertLess(PROCESS.index("if (same) return pendEaten_;"), PROCESS.index("newline_ = false;"))
        self.assertLess(PROCESS.index("newline_ = false;"), PROCESS.index("int sym = KeySym(w, l)"))
        self.assertIn("newline_", RESET)
        self.assertIn("bool newline_ = false;", SOURCE)
        self.assertNotIn("newlineExt_", SOURCE)

    def test_confirm_return_and_idle_return_unchanged(self):
        self.assertIn("comp_ != nullptr", PROCESS)
        self.assertIn("case VK_RETURN: return 0xff0d;", SOURCE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
