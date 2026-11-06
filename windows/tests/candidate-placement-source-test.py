import unittest
from pathlib import Path


class CandidatePlacement(unittest.TestCase):
    """x46/x47: a tall vertical list below the caret covered the next Qt/Electron field and ate its click."""

    def setUp(self):
        self.src = (Path(__file__).resolve().parents[1] / 'tip' / 'tip.cpp').read_text(encoding='utf-8')
        start = self.src.index('void Show(const std::vector<std::wstring> &items')
        self.show = self.src[start:self.src.index('void Hide(bool force', start)]

    def test_vertical_list_prefers_space_above_text_line(self):
        self.assertIn('const int above = at.y - lineAbove - 4 - wh;', self.show)
        self.assertIn('if (vertical_ && items_.size() > 1 && above >= wa.top) at.y = above;', self.show)

    def test_no_room_above_uses_single_row_below_caret(self):
        cond = 'if (vertical_ && items_.size() > 1 && at.y - lineAbove - 4 - wh < wa.top) {'
        self.assertIn(cond, self.show)
        i = self.show.index(cond)
        self.assertIn('vertical_ = false;', self.show[i:i + 160])
        self.assertIn('measure();', self.show[i:i + 200])
        # the switch happens before the above/below decision uses the measured height
        self.assertLess(i, self.show.index('const int above = at.y - lineAbove - 4 - wh;'))

    def test_falls_back_below_and_stays_on_screen(self):
        self.assertIn('if (at.y + wh > wa.bottom) at.y = max(wa.top, above);', self.show)
        self.assertIn('if (at.x + ww > wa.right) at.x = max(wa.left, wa.right - ww);', self.show)
        self.assertLess(self.show.index('above >= wa.top) at.y = above;'), self.show.index('if (at.y + wh > wa.bottom)'))

    def test_mouse_selection_kept(self):
        self.assertIn('HitItem(pt) >= 0 ? HTCLIENT : HTTRANSPARENT', self.src)


if __name__ == '__main__':
    unittest.main()
