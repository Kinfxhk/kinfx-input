import Cocoa
// Print the HID modifier state (cmd/shift/ctrl/alt held?) as the system sees it.
let f = CGEventSource.flagsState(.hidSystemState)
var held: [String] = []
if f.contains(.maskCommand) { held.append("cmd") }
if f.contains(.maskShift) { held.append("shift") }
if f.contains(.maskControl) { held.append("ctrl") }
if f.contains(.maskAlternate) { held.append("alt") }
if f.contains(.maskAlphaShift) { held.append("caps") }
print("HID flags 0x\(String(f.rawValue, radix: 16)) held=\(held)")
