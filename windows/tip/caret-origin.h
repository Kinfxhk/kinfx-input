#pragma once
namespace kx {
inline bool PreferEditCaret(bool editHost, bool sameFocus, bool sameCaret, bool sameView,
                           bool validCaret, int extentX, int caretX, int tolerance) {
  const long long delta = static_cast<long long>(extentX) - caretX;
  return editHost && sameFocus && sameCaret && sameView && validCaret && tolerance > 0 &&
         (delta > tolerance || delta < -static_cast<long long>(tolerance));
}
}
