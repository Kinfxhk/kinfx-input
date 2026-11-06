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
  std::printf("%d FAIL\n", fails);
  return fails ? 1 : 0;
}
