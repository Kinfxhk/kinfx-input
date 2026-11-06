// Candidate panel placement: pure geometry, no Win32 calls, unit-testable.
// Rule (minimal, per parent's B): never cover the caret's own line; prefer below the caret,
// then above, then to the right; always stay inside the work area.
#ifndef KX_CAND_PLACE_H
#define KX_CAND_PLACE_H

#include <vector>

namespace kx {

struct Rect {
  int left, top, right, bottom;
  int Width() const { return right - left; }
  int Height() const { return bottom - top; }
};

inline bool Intersects(const Rect &a, const Rect &b) {
  return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
}

inline Rect FitInside(Rect r, const Rect &area) {
  if (r.Width() > area.Width()) { r.left = area.left; r.right = area.right; }
  if (r.Height() > area.Height()) { r.top = area.top; r.bottom = area.bottom; }
  if (r.right > area.right) { const int d = r.right - area.right; r.left -= d; r.right -= d; }
  if (r.bottom > area.bottom) { const int d = r.bottom - area.bottom; r.top -= d; r.bottom -= d; }
  if (r.left < area.left) { const int d = area.left - r.left; r.left += d; r.right += d; }
  if (r.top < area.top) { const int d = area.top - r.top; r.top += d; r.bottom += d; }
  return r;
}

// caret: the text line the composition sits on (screen px). area: monitor work area.
// A panel must never cover the line being typed. Order: the preferred side when the whole panel
// fits, the other side when that fits, otherwise the larger side shrunk to the space it has, and
// only when neither side has room at all to the right of the caret.
// *how receives 0=below, 1=above, 2=right for the caller's trace.
inline Rect PlaceCandidate(Rect caret, int w, int h, const Rect &area, int gap, bool preferAbove, int *how) {
  const int belowSpace = area.bottom - (caret.bottom + gap);
  const int aboveSpace = (caret.top - gap) - area.top;
  Rect below{caret.left, caret.bottom + gap, caret.left + w, caret.bottom + gap + h};
  Rect above{caret.left, caret.top - gap - h, caret.left + w, caret.top - gap};
  const bool belowFits = h <= belowSpace;
  const bool aboveFits = h <= aboveSpace;
  Rect right{caret.right + gap, caret.top, caret.right + gap + w, caret.top + h};
  const bool rightFits = right.right <= area.right && right.bottom <= area.bottom;
  if (aboveFits && preferAbove) { if (how) *how = 1; return FitInside(above, area); }
  // A tall list that cannot go above must not hang over the rows below the caret either: the
  // next input of a Qt/Electron form lives there. Put it beside the caret instead.
  if (preferAbove && rightFits) { if (how) *how = 2; return FitInside(right, area); }
  if (belowFits) { if (how) *how = 0; return FitInside(below, area); }
  if (aboveFits) { if (how) *how = 1; return FitInside(above, area); }
  if (aboveSpace >= belowSpace && aboveSpace > 0) {
    if (how) *how = 1;
    return FitInside(Rect{caret.left, area.top, caret.left + w, caret.top - gap}, area);
  }
  if (belowSpace > 0) {
    if (how) *how = 0;
    return FitInside(Rect{caret.left, caret.bottom + gap, caret.left + w, area.bottom}, area);
  }
  if (how) *how = 2;
  return FitInside(right, area);
}

// Candidate cells in client coordinates. widths: each item's text width; lineH: row height.
// pad/gap mirror the painter (x pad, y pad, gap between horizontal items / columns). maxW/maxH:
// the room the panel has (pass a huge value for the natural size). A vertical list that does not
// fit in maxH wraps into further columns; a horizontal row that does not fit in maxW wraps into
// further rows, so every candidate stays visible and clickable when the panel is shrunk (Mac
// review 2026-11-06 P2: shrinking only the window clipped later choices). *outW/*outH: panel size.
inline std::vector<Rect> LayoutCells(const std::vector<int> &widths, int lineH, bool vertical, int maxW, int maxH,
                                     int padX, int padY, int gapX, int *outW, int *outH) {
  std::vector<Rect> cells;
  const int n = (int)widths.size();
  if (n == 0) { *outW = 2 * padX; *outH = 2 * padY; return cells; }
  if (vertical) {
    int maxw = 0;
    for (int w : widths) maxw = maxw > w ? maxw : w;
    int rows = n;
    if (2 * padY + rows * lineH > maxH) rows = (maxH - 2 * padY) / lineH;
    if (rows < 1) rows = 1;
    const int cols = (n + rows - 1) / rows;
    rows = (n + cols - 1) / cols;  // balance the columns
    for (int i = 0; i < n; ++i) {
      const int c = i / rows, r = i % rows;
      const int x = padX + c * (maxw + gapX), y = padY + r * lineH;
      cells.push_back(Rect{x, y, x + maxw, y + lineH});
    }
    *outW = 2 * padX + cols * maxw + (cols - 1) * gapX;
    *outH = 2 * padY + rows * lineH;
    return cells;
  }
  int x = padX, y = padY, right = padX;
  for (int i = 0; i < n; ++i) {
    const int w = widths[i] + gapX;
    if (x > padX && x + w + padX > maxW) { x = padX; y += lineH; }  // wrap, never an empty row
    cells.push_back(Rect{x, y, x + w, y + lineH});
    x += w;
    right = right > x ? right : x;
  }
  *outW = right + padX;
  *outH = y + lineH + padY;
  return cells;
}

}  // namespace kx
#endif
