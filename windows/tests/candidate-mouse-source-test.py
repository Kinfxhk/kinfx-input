"""Source safety contract only; actual mouse GUI test required."""
from pathlib import Path
import unittest
s=(Path(__file__).resolve().parents[1]/'tip/tip.cpp').read_text(encoding='utf-8')
class MouseContract(unittest.TestCase):
 def test_item_hit_testing_preserves_padding_passthrough_and_noactivate(self):
  self.assertIn('int HitItem(POINT pt)',s)
  self.assertIn('return self && self->HitItem(pt) >= 0 ? HTCLIENT : HTTRANSPARENT;',s)
  self.assertIn('if (m == WM_MOUSEACTIVATE) return MA_NOACTIVATE;',s)
  self.assertIn('if (m == WM_LBUTTONUP)',s)
 def test_callback_rechecks_context_menu_and_generation(self):
  b=s.split('  void PickCandidate(',1)[1].split('  // Commit text',1)[0]
  for x in ['EnsureContext(c);','generation != generation_','GetFocus() != hwnd','Same(c, focus_)','menu != current','kx_select_candidate_on_current_page(sess_', 'Update(c);']:
   self.assertIn(x,b)
  self.assertNotIn('SendInput',b)
if __name__=='__main__':unittest.main(verbosity=2)
