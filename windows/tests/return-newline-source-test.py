"""Windows TIP source contracts; NOT native TSF/GUI acceptance.

Run with Python only; never starts the engine, changes registry or sends input.

Contract (shared tools/test-digit-tail-newline.py, hello-dot-return / hello-dash-return):
a Return that Rime does NOT handle while a preedit is open (deferred "hello." / "hello-")
is a genuine newline: the held text is committed AND the app receives the newline after it.

History (VM WinForms, real VK input):
- ee51e5e: unhandled Return passed with composition open -> app ended the composition, no
  CR LF ("hello.,"), nl-result-ee51e5e-red3.json N01/N02.
- 41f3901 (claim + always SendInput) passed on VM but Mac mock-TSF review (CHANGES) showed it
  re-sent before a refused-sync (async) commit, self-reinjected, ignored EndComposition failure
  and lost the Return when SendInput failed.
- 3d8dcb6 (claim in test, commit + pass in OnKeyDown): no newline at all (nl-...-3d8dcb6-nl1).
- fd02caa (commit in test path, pass the key): newline BEFORE the text (nl-...-fd02caa-nl1),
  because the IMM32/CUAS host applies the result after the key.

Design (r4): claim the Return; Handle runs Update (sync commit + EndComposition); only when
the commit is confirmed (our composition closed, EndComposition not refused) one Return is
re-sent, tagged in dwExtraInfo, queued behind the app's handling of the commit. The re-sent
Return arrives with no composition, so it can never be claimed again (and the tag excludes
it explicitly). Not confirmed -> Return swallowed: text kept, that newline lost, never
newline-before-text. SendInput failure is traced (newline lost, text kept).
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
PROCESS = SOURCE.split("  bool Process(", 1)[1].split("  bool ToggleAscii(", 1)[0]
HANDLE = SOURCE.split("  bool Handle(ITfContext *c, WPARAM w, LPARAM l, bool up) {", 1)[1].split("  void Update(ITfContext *c) {", 1)[0]
RESET = SOURCE.split("  void ResetInput() {", 1)[1].split("}", 1)[0]
FINISH = SOURCE.split("  bool FinishNewline() {", 1)[1].split("  bool Handle(", 1)[0]
END = SOURCE.split("  void End(TfEditCookie ec) {", 1)[1].split("\n  }", 1)[0]
TEST_DOWN = SOURCE.split("STDMETHODIMP OnTestKeyDown(", 1)[1].split("STDMETHODIMP OnTestKeyUp(", 1)[0]


class ReturnNewlineSourceTests(unittest.TestCase):
    def test_claim_only_untagged_unhandled_return_with_open_composition(self):
        self.assertIn("newline_ = sym == 0xff0d && !up && !eaten && comp_ != nullptr && GetMessageExtraInfo() != kNewlineTag;", PROCESS)
        self.assertIn("if (newline_) { eaten = true; endFailed_ = commitWritten_ = commitFailed_ = false; }", PROCESS)
        self.assertLess(PROCESS.index("eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;"),
                        PROCESS.index("newline_ = sym == 0xff0d"))

    def test_commit_runs_before_finish(self):
        self.assertLess(HANDLE.index("Update(c);"), HANDLE.index("if (!up && FinishNewline()) return true;"))
        self.assertNotIn("FinishNewline", TEST_DOWN)  # fd02caa design (commit in test path) removed

    def test_resend_only_after_confirmed_commit(self):
        guard = 'if (comp_ || endFailed_ || commitFailed_ || !commitWritten_) {'
        self.assertIn(guard, FINISH)
        self.assertLess(FINISH.index(guard), FINISH.index("SendInput("))
        self.assertLess(FINISH.index("newline_ = false;"), FINISH.index("SendInput("))

    def test_resend_is_tagged_one_pair_and_failure_traced(self):
        self.assertIn("in[i].ki.dwExtraInfo = (ULONG_PTR)kNewlineTag;", FINISH)
        self.assertIn("const UINT sent = SendInput(2, in, sizeof(INPUT));", FINISH)
        self.assertIn("SendInput failed, newline lost", FINISH)
        self.assertIn("KEYEVENTF_EXTENDEDKEY", FINISH)  # keypad Enter keeps its identity
        # partial insertion (Mac review P3): key-down in -> newline delivered, key-up retried alone
        self.assertIn("else if (sent == 1) {", FINISH)
        self.assertIn("const UINT up = SendInput(1, &in[1], sizeof(INPUT));", FINISH)
        self.assertEqual(FINISH.count("SendInput("), 2)

    def test_commit_write_result_is_recorded(self):
        # Mac review P2 on 606ee01: a refused GetRange/SetText must not count as a delivered commit.
        write = SOURCE.split("  void Write(TfEditCookie ec, ITfContext *c,", 1)[1].split("    if (pre.empty()) {", 1)[0]
        self.assertIn("if (SUCCEEDED(r->SetText(ec, 0, commit.c_str(), (LONG)commit.size()))) commitWritten_ = true;", write)
        self.assertIn("else commitFailed_ = true;", write)
        self.assertIn("if (!comp_) commitFailed_ = true;", write)  # Begin failed
        self.assertIn("} else {\n          commitFailed_ = true;", write.replace("\r\n", "\n"))  # GetRange failed
        self.assertIn("if (newline_) { eaten = true; endFailed_ = commitWritten_ = commitFailed_ = false; }", PROCESS)

    def test_end_composition_failure_is_recorded(self):
        self.assertIn("if (composition && FAILED(composition->EndComposition(ec))) endFailed_ = true;", END)

    def test_flags_reset_and_declared(self):
        self.assertLess(PROCESS.index("if (same) return pendEaten_;"), PROCESS.index("newline_ = false;"))
        self.assertLess(PROCESS.index("newline_ = false;"), PROCESS.index("int sym = KeySym(w, l)"))
        for f in ("newline_", "newlineExt_", "endFailed_", "commitWritten_", "commitFailed_"):
            self.assertIn(f, RESET)
        self.assertIn("static constexpr LPARAM kNewlineTag", SOURCE)

    def test_confirm_return_and_idle_return_unchanged(self):
        self.assertIn("case VK_RETURN: return 0xff0d;", SOURCE)
        self.assertIn("!eaten && comp_ != nullptr", PROCESS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
