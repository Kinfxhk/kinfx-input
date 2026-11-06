import Cocoa

// The trace regression passes a nil client, so no engine or UI method is called.
// Real Engine, Trace and InputController implementations are compiled unchanged.
final class AppDelegate: NSObject, NSApplicationDelegate {
  static var engine: Engine!
  static let panel = Panel()
  func showSettings() {}
}
final class Panel {
  func hide(owner: ObjectIdentifier) {}
  func show(_ view: RimeView, below: NSRect, vertical: Bool,
            owner: ObjectIdentifier, refreshCaret: @escaping () -> NSRect?) {}
}
enum AppInfo {
  static func showHelp() {}
  static func showAbout() {}
  static func openDonate() {}
}
