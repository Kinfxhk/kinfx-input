// Native contract for kx::PlaceCandidate (no GUI, no TSF).
#include "cand-place.h"
#include <cstdio>
#include <cstdlib>

static int fails = 0;
static void Check(const char *name, bool ok) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", name);
  if (!ok) ++fails;
}
int main() {
  using namespace kx;
  const Rect area{0, 0, 1920, 1040};
  const Rect caret{100, 100, 400, 130};  // single-line edit, caret line 30 px tall
  int how = -1;

  // 1. Room below: below the caret, never overlapping it.
  Rect r = PlaceCandidate(caret, 120, 300, area, 2, false, &how);
  Check("below: sits under the caret", r.top >= caret.bottom && how == 0 && !Intersects(r, caret));
  Check("below: x follows caret", r.left == caret.left && r.right == caret.left + 120);

  // 2. No room below (caret at the bottom edge): goes above, still clear of the caret.
  const Rect lowCaret{100, 980, 400, 1010};
  r = PlaceCandidate(lowCaret, 120, 300, area, 2, false, &how);
  Check("bottom edge: above", how == 1 && r.bottom <= lowCaret.top && !Intersects(r, lowCaret));
  Check("bottom edge: inside work area", r.top >= area.top && r.bottom <= area.bottom);

  // 3. Neither side holds the full panel: it shrinks into the larger side, still inside the area.
  const Rect small{0, 0, 640, 300};
  const Rect mid{40, 120, 200, 150};
  r = PlaceCandidate(mid, 200, 280, small, 2, false, &how);
  Check("tiny area: shrinks below", how == 0 && r.Height() < 280);
  Check("tiny area: inside", r.left >= small.left && r.right <= small.right && r.top >= small.top && r.bottom <= small.bottom);
  Check("tiny area: does not cover caret line", !Intersects(r, mid));

  // 4. Never cover the caret line even when clamped.
  const Rect edge{0, 0, 300, 300};
  const Rect c2{260, 140, 300, 170};
  r = PlaceCandidate(c2, 180, 200, edge, 2, false, &how);
  Check("edge clamp: stays inside", r.left >= edge.left && r.right <= edge.right && r.top >= edge.top && r.bottom <= edge.bottom);
  Check("edge clamp: caret still visible", !Intersects(r, c2));

  // 5. Taller-than-area panel is shrunk into the area rather than spilling out.
  r = PlaceCandidate(caret, 120, 5000, area, 2, false, &how);
  Check("oversized: clamped to area height", r.Height() <= area.Height());


  // 6. A tall list prefers the space above the text line (keeps the next field clickable).
  const Rect lowerCaret{100, 500, 400, 530};
  r = PlaceCandidate(lowerCaret, 120, 300, area, 2, true, &how);
  Check("tall list: above when it fits", how == 1 && r.bottom <= lowerCaret.top && !Intersects(r, lowerCaret));
  // 7. Short lists keep the familiar below placement.
  r = PlaceCandidate(caret, 120, 30, area, 2, false, &how);
  Check("short list: below", how == 0 && r.top >= caret.bottom);
  // 8. Tall list with no room above and no room beside: falls back below, clear of the caret line.
  const Rect topCaret{100, 4, 400, 34};
  r = PlaceCandidate(topCaret, 1600, 300, area, 2, true, &how);
  Check("tall list, no room above or beside: below", how == 0 && r.top >= topCaret.bottom && !Intersects(r, topCaret));
  // 9. Tall list with no room above goes beside the caret, not over the row below it.
  const Rect highCaret{100, 40, 400, 70};
  r = PlaceCandidate(highCaret, 120, 300, area, 2, true, &how);
  Check("tall list, no room above: right of caret", how == 2 && r.left >= highCaret.right && !Intersects(r, highCaret));
  Check("tall list, no room above: inside area", r.right <= area.right && r.bottom <= area.bottom);
  // 10. LayoutCells: natural vertical list is one column; every cell inside the panel.
  {
    std::vector<int> w9(9, 60);
    int W = 0, H = 0;
    auto c = LayoutCells(w9, 30, true, 1 << 30, 1 << 30, 14, 6, 20, &W, &H);
    Check("layout natural: one column, 9 rows", c.size() == 9 && H == 12 + 9 * 30 && W == 28 + 60 && c[8].top == 6 + 8 * 30);
    // 11. Shrunk to 150 px: wraps into columns, every cell fully inside the shrunk panel.
    c = LayoutCells(w9, 30, true, 1 << 30, 150, 14, 6, 20, &W, &H);
    bool inside = true, distinct = true;
    for (size_t i = 0; i < c.size(); ++i) {
      if (c[i].left < 0 || c[i].top < 0 || c[i].right > W || c[i].bottom > H) inside = false;
      for (size_t j = 0; j < i; ++j) if (Intersects(c[i], c[j])) distinct = false;
    }
    Check("layout shrunk vertical: fits height", H <= 150 && c.size() == 9);
    Check("layout shrunk vertical: all cells visible and disjoint", inside && distinct);
    Check("layout shrunk vertical: wrapped into columns", c[8].left > c[0].left);
    // 12. Horizontal row shrunk in width wraps into rows, still all inside.
    std::vector<int> w6(6, 80);
    c = LayoutCells(w6, 30, false, 300, 1 << 30, 14, 6, 20, &W, &H);
    inside = true;
    for (auto &r : c) if (r.right > W || r.bottom > H || r.right > 300) inside = false;
    Check("layout shrunk row: wraps, fits width", W <= 300 && H > 12 + 30 && inside);
    // 13. Too small for even one row: still one row (never zero), no crash.
    c = LayoutCells(w9, 30, true, 1 << 30, 10, 14, 6, 20, &W, &H);
    Check("layout degenerate: one row of columns", c.size() == 9 && c[1].left > c[0].left);
    // 14. Shrink + placement end to end: re-flowed panel fits the room and leaves the caret line clear.
    const Rect tiny{0, 0, 1920, 300};
    const Rect midCaret{100, 120, 400, 150};
    c = LayoutCells(w9, 30, true, 1 << 30, 1 << 30, 14, 6, 20, &W, &H);
    Rect p = PlaceCandidate(midCaret, W, H, tiny, 2, true, &how);
    if (p.Height() < H) {
      c = LayoutCells(w9, 30, true, tiny.Width(), p.Height(), 14, 6, 20, &W, &H);
      p = PlaceCandidate(midCaret, W, H, tiny, 2, true, &how);
    }
    Check("relayout: placed panel holds the re-flowed size", p.Width() == W && p.Height() == H);
    Check("relayout: caret line clear and inside area", !Intersects(p, midCaret) && p.top >= tiny.top && p.bottom <= tiny.bottom);
  }
  std::printf("%d FAIL\n", fails);
  return fails ? 1 : 0;
}
