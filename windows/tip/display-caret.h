#pragma once
#include <windows.h>
#include <string>
#include <climits>
namespace kx {
// The shared shim reports validated UTF-8 byte offsets, TSF ranges count UTF-16 units.
inline LONG DisplayCaretUtf16(const std::string &text, const std::string &offset) {
 const int whole = text.empty() ? 0 : MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), (int)text.size(), nullptr, 0);
 const LONG fallback = whole > 0 ? whole : 0;
 if (offset.empty() || text.size() > INT_MAX) return fallback;
 size_t bytes = 0;
 for (unsigned char c : offset) {
  if (c < '0' || c > '9' || bytes > text.size()/10 || bytes*10+(c-'0') > text.size()) return fallback;
  bytes = bytes*10+(c-'0');
 }
 if (!bytes) return 0;
 if (bytes < text.size() && ((unsigned char)text[bytes] & 0xc0) == 0x80) return fallback;
 int units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), (int)bytes, nullptr, 0);
 return units > 0 ? units : fallback;
}
}
