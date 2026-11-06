"""Candidate placement must go through the tested pure geometry, not ad-hoc clamping."""
from pathlib import Path
import unittest

SRC = (Path(__file__).parents[1] / 'tip' / 'tip.cpp').read_text(encoding='utf-8')
HDR = (Path(__file__).parents[1] / 'tip' / 'cand-place.h').read_text(encoding='utf-8')

class CandidatePlacement(unittest.TestCase):
    def test_header_is_included(self):
        self.assertIn('#include "cand-place.h"', SRC)

    def test_show_uses_place_candidate(self):
        self.assertIn('kx::PlaceCandidate(caretLine, ww, wh, area, 2,', SRC)
        self.assertIn('vertical_ && items_.size() >= 5', SRC)

    def test_tall_list_prefers_above(self):
        # >= 5 rows must ask for the space above; short lists keep the familiar below.
        self.assertIn('if (aboveFits && preferAbove)', HDR)
        self.assertIn('if (belowFits)', HDR)

    def test_panel_never_intersects_caret_line(self):
        # Space arithmetic keeps every candidate clear of the caret line, and every return path
        # is clamped into the work area.
        self.assertIn('const int belowSpace = area.bottom - (caret.bottom + gap);', HDR)
        self.assertIn('const int aboveSpace = (caret.top - gap) - area.top;', HDR)
        self.assertEqual(HDR.count('return FitInside('), 7)
        self.assertNotIn('return below;', HDR)
        self.assertNotIn('return above;', HDR)

    def test_old_ad_hoc_clamp_removed(self):
        self.assertNotIn('at.y = max(wa.top, above)', SRC)
        self.assertNotIn('if (vertical_ && items_.size() > 1 && above >= wa.top) at.y = above;', SRC)

    def test_mouse_selection_kept(self):
        self.assertIn('HitItem(pt) >= 0 ? HTCLIENT : HTTRANSPARENT', SRC)


if __name__ == '__main__':
    unittest.main()
