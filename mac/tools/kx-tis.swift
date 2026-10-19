import Carbon
import Foundation
// Register / enable / select / disable an input method bundle for the current user.
//   kx-tis register <app>   |   kx-tis enable <id>   |   kx-tis select <id>   |   kx-tis disable <id>   |   kx-tis current
func source(_ id: String) -> TISInputSource? {
  let f = [kTISPropertyInputSourceID as String: id] as CFDictionary
  return (TISCreateInputSourceList(f, true)?.takeRetainedValue() as? [TISInputSource])?.first
}
func prop(_ s: TISInputSource, _ k: CFString) -> Any? {
  guard let p = TISGetInputSourceProperty(s, k) else { return nil }
  return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
}
let a = CommandLine.arguments
guard a.count >= 2 else { exit(2) }
switch a[1] {
case "register":
  print("register", TISRegisterInputSource(URL(fileURLWithPath: a[2]) as CFURL))
case "enable":
  guard let s = source(a[2]) else { print("not found"); exit(1) }
  print("enable", TISEnableInputSource(s))
case "select":
  guard let s = source(a[2]) else { print("not found"); exit(1) }
  print("select", TISSelectInputSource(s))
case "disable":
  guard let s = source(a[2]) else { print("not found"); exit(1) }
  print("disable", TISDisableInputSource(s))
case "current":
  let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
  print(prop(s, kTISPropertyInputSourceID) ?? "?")
default:
  exit(2)
}
