import CoreGraphics
// Modifier state as seen by HID vs. the combined session (what CGEvent(NULL source) inherits).
func names(_ f: CGEventFlags) -> [String] {
  var n: [String] = []
  if f.contains(.maskShift) { n.append("shift") }
  if f.contains(.maskControl) { n.append("ctrl") }
  if f.contains(.maskAlternate) { n.append("opt") }
  if f.contains(.maskCommand) { n.append("cmd") }
  if f.contains(.maskAlphaShift) { n.append("caps") }
  return n
}
let h = CGEventSource.flagsState(.hidSystemState)
let s = CGEventSource.flagsState(.combinedSessionState)
print("HID=\(names(h)) session=\(names(s))")
if let e = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true) { print("new event flags=\(names(e.flags)) raw=\(String(e.flags.rawValue, radix: 16))") }
