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

// The whole candidate-panel geometry of CandWin::Show, pure so the production path is testable.
// 1. The natural layout (caller's orientation) wherever PlaceCandidate puts it unshrunk.
// 2. Otherwise a re-flow bounded on BOTH axes by the real room: for the preferred side of the caret
//    first, then the other, try rows wrapped to the area width and columns wrapped to the side's
//    height; the first layout whose width fits the area and whose height fits that side wins. Such
//    a panel always gets an unshrunk PlaceCandidate result, so no cell is clipped
//    (Mac review 2026-11-06 P2, second round: the old orientation fallback re-flowed rows against
//    the width only, and the second placement shrank the window again).
// 3. Defined fallback when nothing fits (room smaller than one row, or one item wider than the
//    screen): columns in the larger side, placed (and shrunk) by PlaceCandidate; every cell that is
//    not entirely inside the client area becomes an empty Rect, so it is neither painted nor
//    clickable. Keyboard selection still reaches it.
// inset: window border per side (client = window minus 2*inset). Returns the window rect;
// *cells: one cell per item in client coordinates (empty Rect = hidden); *visible: shown count.
struct CandGeom { int lineH, padX, padY, gapX, gap, inset; };
inline bool IsEmpty(const Rect &r) { return r.right <= r.left || r.bottom <= r.top; }
inline Rect FitCandidates(const std::vector<int> &widths, bool vertical, Rect caret, const Rect &area,
                          const CandGeom &g, std::vector<Rect> *cells, int *visible, int *how, bool *vertOut) {
  const int n = (int)widths.size();
  const bool preferAbove = vertical && n >= 5;
  const int big = 1 << 30;
  int W = 0, H = 0;
  bool vert = vertical;
  *cells = LayoutCells(widths, g.lineH, vert, big, big, g.padX, g.padY, g.gapX, &W, &H);
  const int e = 2 * g.inset;  // LayoutCells sizes the client; the window adds the border
  Rect placed = PlaceCandidate(caret, W + e, H + e, area, g.gap, preferAbove, how);
  // A vertical list that fits neither above nor below is re-flowed too (rows first: the familiar
  // single-row fallback), even when PlaceCandidate could hang it beside the caret.
  const bool tallMisfit = vertical && n > 1 && caret.top - g.gap - (H + e) < area.top &&
                          caret.bottom + g.gap + (H + e) > area.bottom;
  if (tallMisfit || placed.Width() < W + e || placed.Height() < H + e) {
    const int belowRoom = area.bottom - (caret.bottom + g.gap) - e;  // client room per side
    const int aboveRoom = (caret.top - g.gap) - area.top - e;
    const int roomW = area.Width() - e;
    const int rooms[2] = {preferAbove ? aboveRoom : belowRoom, preferAbove ? belowRoom : aboveRoom};
    bool found = false;
    for (int s = 0; s < 2 && !found; ++s) {
      const int room = rooms[s];
      for (int o = 0; o < 2 && !found; ++o) {
        const bool v = o == 1;  // rows first: a single row is the familiar fallback for a tall list
        int w = 0, h = 0;
        std::vector<Rect> c = LayoutCells(widths, g.lineH, v, v ? big : roomW, v ? room : big,
                                          g.padX, g.padY, g.gapX, &w, &h);
        if (w <= roomW && h <= room) { *cells = c; W = w; H = h; vert = v; found = true; }
      }
    }
    if (!found) {  // nothing fits: columns in the larger side, cells outside the client hidden below
      vert = true;
      *cells = LayoutCells(widths, g.lineH, true, big, aboveRoom > belowRoom ? aboveRoom : belowRoom,
                           g.padX, g.padY, g.gapX, &W, &H);
    }
    placed = PlaceCandidate(caret, W + e, H + e, area, g.gap, vert && n >= 5, how);
  }
  const int cw = placed.Width() - e, ch = placed.Height() - e;
  int shown = 0;
  for (auto &c : *cells) {
    // A row must be wholly visible. An item wider than the whole panel (only possible when it is
    // wider than the work area, or column cells widened by it) is cut at the client edge, so it
    // stays readable from its start and clickable; a cell that starts past the edge is hidden.
    if (c.right > cw && c.left < cw - g.padX) c.right = cw;
    if (c.left < 0 || c.top < 0 || c.right > cw || c.bottom > ch) c = Rect{0, 0, 0, 0};
    else ++shown;
  }
  if (visible) *visible = shown;
  if (vertOut) *vertOut = vert;
  return placed;
}

}  // namespace kx
#endif
