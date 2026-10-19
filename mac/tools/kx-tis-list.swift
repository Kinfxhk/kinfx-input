import Carbon
import Foundation
// List every input source whose id contains the argument, with its flags.
func prop(_ s: TISInputSource, _ k: CFString) -> Any? {
  guard let p = TISGetInputSourceProperty(s, k) else { return nil }
  return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
}
let needle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let all = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
for s in all {
  let id = prop(s, kTISPropertyInputSourceID) as? String ?? "?"
  guard needle.isEmpty || id.contains(needle) else { continue }
  print(id, "enabled=\(prop(s, kTISPropertyInputSourceIsEnabled) ?? "?")",
        "selectCapable=\(prop(s, kTISPropertyInputSourceIsSelectCapable) ?? "?")",
        "enableCapable=\(prop(s, kTISPropertyInputSourceIsEnableCapable) ?? "?")",
        "selected=\(prop(s, kTISPropertyInputSourceIsSelected) ?? "?")",
        "category=\(prop(s, kTISPropertyInputSourceCategory) ?? "?")",
        "type=\(prop(s, kTISPropertyInputSourceType) ?? "?")",
        "mode=\(prop(s, kTISPropertyInputModeID) ?? "-")")
}
