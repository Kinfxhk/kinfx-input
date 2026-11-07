from pathlib import Path
import unittest
s=(Path(__file__).resolve().parents[1]/'tip/tip.cpp').read_text(encoding='utf-8')
class OriginBridge(unittest.TestCase):
 def test_edit_only_context_checked_before_cached_origin(self):
  b=s.split('  void Below(',1)[1].split('  void Begin(',1)[0]
  self.assertIn('kx::PreferEditCaret(',b)
  self.assertIn('gi.hwndFocus == fw',b)
  self.assertIn('gi.hwndCaret == fw',b)
  self.assertIn('viewWindow == fw',b)
  self.assertIn('GetClassNameW(fw',b)
  self.assertIn('ClientToScreen(fw',b)
  self.assertLess(b.index('kx::PreferEditCaret('),b.index('last_ = *at'))
if __name__=='__main__':unittest.main(verbosity=2)
