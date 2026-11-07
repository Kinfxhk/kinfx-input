"""Windows TIP source contracts; NOT native TSF/GUI acceptance.

Run with Python only; never starts the engine, changes registry or sends input.

Contract (shared tools/test-digit-tail-newline.py, hello-dot-return / hello-dash-return):
a Return that Rime does NOT handle while a preedit is open (deferred "hello." / "hello-")
is a genuine newline: the held text is committed AND the app receives the newline.

Windows RED (VM 2026-11-07, DLL 16086DE2, nl-result-ee51e5e-red3.json): with the
composition still open, the unhandled Return went to the app, which used it to end the
composition instead of inserting CR LF ("hello.," instead of "hello.\r\n,").

Design (r2, after Mac review CHANGES on 41f3901): the shell claims that Return in the
test path only, so OnKeyDown runs; Handle commits (Update) and then returns NOT eaten,
so the SAME key reaches the app after the text. No SendInput: a synthetic Return could
overtake a queued async commit, re-enter this branch, or be lost when SendInput fails
(Mac mock-TSF repros: premature-Return, 4-hop self-reinjection, SendInput=0).
If the sync lock was refused (our composition still open after Update) the Return is
swallowed: text kept, one newline lost, never newline-before-text.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
PROCESS = SOURCE.split("  bool Process(", 1)[1].split("  bool ToggleAscii(", 1)[0]
HANDLE = SOURCE.split("  bool Handle(ITfContext *c, WPARAM w, LPARAM l, bool up) {", 1)[1].split("  void Update(ITfContext *c) {", 1)[0]
RESET = SOURCE.split("  void ResetInput() {", 1)[1].split("}", 1)[0]
BLOCK = HANDLE.split("if (newline) {", 1)[1].split("if (paste_ && !up) {", 1)[0]


class ReturnNewlineSourceTests(unittest.TestCase):
    def test_unhandled_return_with_open_composition_is_claimed(self):
        self.assertIn("newline_ = sym == 0xff0d && !up && !eaten && comp_ != nullptr;", PROCESS)
        self.assertIn("if (newline_) eaten = true;", PROCESS)
        self.assertLess(PROCESS.index("eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;"),
                        PROCESS.index("newline_ = sym == 0xff0d"))

    def test_handle_commits_then_passes_the_same_key(self):
        self.assertIn("const bool newline = newline_ && !up && w == VK_RETURN;", HANDLE)
        self.assertLess(HANDLE.index("Update(c);"), HANDLE.index("if (newline) {"))
        self.assertIn("return false;", BLOCK)

    def test_no_synthetic_return(self):
        # Mac review: re-sent input can overtake an async commit, self-reinject, or be lost.
        self.assertNotIn("SendInput", BLOCK)
        self.assertNotIn("VK_RETURN; in[", HANDLE)

    def test_refused_sync_commit_swallows_instead_of_newline_first(self):
        self.assertIn('if (comp_) { Trace("newline: commit queued, Return swallowed"); return true; }', BLOCK)
        self.assertLess(BLOCK.index("if (comp_)"), BLOCK.index("return false;"))

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
