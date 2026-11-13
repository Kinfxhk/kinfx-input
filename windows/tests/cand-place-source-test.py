"""Candidate placement must go through the tested pure geometry, not ad-hoc clamping."""
from pathlib import Path
import unittest

SRC = (Path(__file__).parents[1] / 'tip' / 'tip.cpp').read_text(encoding='utf-8')
HDR = (Path(__file__).parents[1] / 'tip' / 'cand-place.h').read_text(encoding='utf-8')

class CandidatePlacement(unittest.TestCase):
    def test_header_is_included(self):
        self.assertIn('#include "cand-place.h"', SRC)

    def test_show_uses_place_candidate(self):
        # 2026-11-07: Show's placement moved into the pure kx::FitCandidates (re-flow before the
        # final size, Mac review P2 round 2); the >=5 tall-list rule moved with it.
        self.assertIn('kx::FitCandidates(widths, vertical_, caretLine, area, geom, &cells_,', SRC)
        self.assertIn('pageSize, stick ? stickyHow_ : -1)', SRC)
        self.assertIn('const bool preferAbove = vertical && pageSize >= 5;', HDR)
        self.assertIn('PlaceCandidate(caret, W + e, refH, area, g.gap, preferAbove, &refHow)', HDR)
        self.assertIn('PlaceCandidate(caret, W + e, H + e, area, g.gap, preferAbove, how, side)', HDR)
        self.assertIn('Show({s}, at, 20, true, 1)', SRC)
        self.assertIn('cand_.Show(cands, at, lineH, it == kx::Current().end() || it->second != "horizontal", pageSize,', SRC)
        self.assertIn('if (end != f[2].c_str() && v > 0) pageSize = (int)v;', SRC)
        self.assertIn('stickyHow_ = -1;', SRC)

    def test_hidden_cells_neither_painted_nor_hit(self):
        self.assertEqual(SRC.count('kx::IsEmpty('), 2)

    def test_show_uses_placed_size(self):
        # A shrunk placement must size the window too, not only move it.
        self.assertIn('ww = placed.Width();', SRC)
        self.assertIn('wh = placed.Height();', SRC)

    def test_tall_list_prefers_above(self):
        # Page capacity of 5 or more asks for the space above; a short page keeps below.
        # Side follows the configured page size, not the current item count (n >= 5 flipped the panel).
        self.assertNotIn('vertical && n >= 5', HDR)
        self.assertIn('if (aboveFits && preferAbove)', HDR)
        self.assertIn('if (belowFits)', HDR)

    def test_panel_never_intersects_caret_line(self):
        # Space arithmetic keeps every candidate clear of the caret line, and every return path
        # is clamped into the work area.
        self.assertIn('const int belowSpace = area.bottom - (caret.bottom + gap);', HDR)
        self.assertIn('const int aboveSpace = (caret.top - gap) - area.top;', HDR)
        # 7 original sides + 2 P3 no-room sides (right/left, d5e1863) + 3 sticky early returns
        # (below/above/right, cand-stable); each still FitInside.
        self.assertEqual(HDR.count('return FitInside('), 12)
        self.assertNotIn('return below;', HDR)
        self.assertNotIn('return above;', HDR)

    def test_old_ad_hoc_clamp_removed(self):
        self.assertNotIn('at.y = max(wa.top, above)', SRC)
        self.assertNotIn('if (vertical_ && items_.size() > 1 && above >= wa.top) at.y = above;', SRC)

    def test_mouse_selection_kept(self):
        self.assertIn('HitItem(pt) >= 0 ? HTCLIENT : HTTRANSPARENT', SRC)


if __name__ == '__main__':
    unittest.main()
