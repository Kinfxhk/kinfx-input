// Candidate panel placement: pure geometry, no Win32 calls, unit-testable.
// Rule (minimal, per parent's B): never cover the caret's own line; prefer below the caret,
// then above, then to the right; always stay inside the work area.
#ifndef KX_CAND_PLACE_H
#define KX_CAND_PLACE_H

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

}  // namespace kx
#endif
