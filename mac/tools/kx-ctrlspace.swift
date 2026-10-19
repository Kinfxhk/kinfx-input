import CoreGraphics
import Foundation
// Post Control+Space (macOS "select previous input source") as real HID-level events.
let src = CGEventSource(stateID: .hidSystemState)
func post(_ k: CGKeyCode, _ down: Bool, _ f: CGEventFlags) {
  let e = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: down)!
  e.flags = f
  e.post(tap: .cghidEventTap)
  usleep(30000)
}
post(59, true, .maskControl); post(49, true, .maskControl); post(49, false, .maskControl); post(59, false, [])
