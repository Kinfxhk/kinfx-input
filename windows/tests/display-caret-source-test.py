from pathlib import Path
import unittest
TIP=Path(__file__).resolve().parents[1]/'tip'/'tip.cpp'
class DisplayCaretContract(unittest.TestCase):
 def test_uses_shim_byte_caret_not_forced_end(self):
  s=TIP.read_text(encoding='utf-8')
  self.assertIn('kx::DisplayCaretUtf16(f[0], f[1])',s)
  self.assertIn('commit, pre, preCaret, &at',s)
  self.assertIn('caret->ShiftEnd(ec, preCaret, &shifted, nullptr)',s)
  self.assertIn('caret->Collapse(ec, TF_ANCHOR_END); SetSel(ec, c, caret)',s)
 def test_geometry_uses_current_selection(self):
  s=TIP.read_text(encoding='utf-8')
  self.assertIn('Below(ec, c, caret, at, lineH)',s)
if __name__=='__main__':unittest.main(verbosity=2)
