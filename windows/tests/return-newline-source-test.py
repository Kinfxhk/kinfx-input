"""Windows TIP source contracts; NOT native TSF/GUI acceptance.

Run with Python only; never starts the engine, changes registry or sends input.

Contract (shared tools/test-digit-tail-newline.py, hello-dot-return / hello-dash-return):
a Return that Rime does NOT handle while a preedit is open (deferred "hello." / "hello-")
is a genuine newline: the held text is committed AND the app receives the newline.

Windows RED (VM 2026-11-07, DLL 16086DE2, nl-result-ee51e5e-red3.json): with the
composition still open, the unhandled Return went to the app, which used it to end the
composition instead of inserting CR LF ("hello.," instead of "hello.\\r\\n,").
Fix: the shell eats that Return, commits synchronously (Update ends the composition),
then re-sends one Return the same way the held-text paste re-sends Ctrl+V.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
PROCESS = SOURCE.split("  bool Process(", 1)[1].split("  bool ToggleAscii(", 1)[0]
HANDLE = SOURCE.split("  bool Handle(ITfContext *c, WPARAM w, LPARAM l, bool up) {", 1)[1].split("  void Update(ITfContext *c) {", 1)[0]
RESET = SOURCE.split("  void ResetInput() {", 1)[1].split("}", 1)[0]


class ReturnNewlineSourceTests(unittest.TestCase):
    def test_unhandled_return_with_open_composition_is_claimed(self):
        self.assertIn("newline_ = sym == 0xff0d && !up && !eaten && comp_ != nullptr;", PROCESS)
        self.assertIn("if (newline_) eaten = true;", PROCESS)
        # decided after Rime saw the key, inside the normal Rime branch
        self.assertLess(PROCESS.index("eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;"),
                        PROCESS.index("newline_ = sym == 0xff0d"))

    def test_handle_commits_then_resends_one_return(self):
        self.assertIn("const bool newline = newline_ && !up && w == VK_RETURN;", HANDLE)
        self.assertIn("newline_ = false;", HANDLE)
        block = HANDLE.split("if (newline) {", 1)[1].split("return true;", 1)[0]
        self.assertIn("VK_RETURN", block)
        self.assertIn("KEYEVENTF_EXTENDEDKEY", block)  # keypad Enter keeps its identity
        self.assertIn("SendInput(", block)
        # the commit (Update) runs before the re-send, so the app sees text then newline
        self.assertLess(HANDLE.index("Update(c);"), HANDLE.index("if (newline) {"))

    def test_test_path_reports_eaten_so_app_never_sees_the_original(self):
        test_down = SOURCE.split("STDMETHODIMP OnTestKeyDown(", 1)[1].split("STDMETHODIMP OnTestKeyUp(", 1)[0]
        self.assertIn("*eaten = Process(w, l, false);", test_down)

    def test_flag_is_reset_and_declared(self):
        # a stale flag from a Return whose OnKeyDown never came must not leak into the next key
        self.assertLess(PROCESS.index("if (same) return pendEaten_;"), PROCESS.index("newline_ = false;"))
        self.assertLess(PROCESS.index("newline_ = false;"), PROCESS.index("int sym = KeySym(w, l)"))
        self.assertIn("newline_", RESET)
        self.assertIn("bool newline_ = false, newlineExt_ = false;", SOURCE)

    def test_confirm_return_and_idle_return_unchanged(self):
        # Rime-handled Return (vd -> 好, hello confirm) keeps eaten=true from kx_key; idle Return
        # (no composition) keeps eaten=false, so neither path is re-sent.
        self.assertIn("comp_ != nullptr", PROCESS)
        self.assertIn("case VK_RETURN: return 0xff0d;", SOURCE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
