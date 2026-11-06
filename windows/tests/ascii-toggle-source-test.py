from pathlib import Path
import unittest
class AsciiToggle(unittest.TestCase):
 def test_no_synthetic_escape_before_shared_toggle(self):
  s=(Path(__file__).resolve().parents[1]/'tip'/'tip.cpp').read_text()
  body=s.split('bool ToggleAscii() {',1)[1].split('return eaten;',1)[0]
  self.assertNotIn('kx_key(sess_, 0xff1b, 0)',body,'Synthetic Escape destroys shared association inline state')
  self.assertIn('kx_key(sess_, 0x20, kControl)',body)
if __name__=='__main__':unittest.main(verbosity=2)
