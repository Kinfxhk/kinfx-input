import Cocoa
import InputMethodKit

// Input method entry. The process is launched by the system when the user picks
// KINFX Input; started by hand with --settings it opens only the settings window.
final class AppDelegate: NSObject, NSApplicationDelegate {
  static var engine: Engine!
  static var server: IMKServer?
  static let panel = CandidatePanel()
  var settingsWindow: SettingsWindow?

  func applicationDidFinishLaunching(_ n: Notification) {
    let fm = FileManager.default
    let shared = Bundle.main.resourcePath! + "/data"
    // Sandboxed: this resolves inside the app container. Direct build: ~/Library/Application Support.
    let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("KINFX Input").path
    AppDelegate.engine = Engine(sharedDir: shared, userDir: support)
    Trace.dir = support + "/log"
    Trace.log("launch args=\(CommandLine.arguments) support=\(support)")

    if CommandLine.arguments.contains("--settings") || anotherInstanceRunning() {
      // Settings only: write settings.json; the running input method rebuilds on its
      // next activation. Never run a second librime on the same user dir.
      showSettings()
      return
    }
    do { try AppDelegate.engine.start() } catch { NSLog("KINFX Input: engine start failed: \(error)") }
    let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String ?? ""
    AppDelegate.server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
    Trace.log("server \(name) -> \(AppDelegate.server == nil ? "FAILED" : "ok"), engine started=\(AppDelegate.engine.started)")
  }

  private func anotherInstanceRunning() -> Bool {
    let me = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
      .contains { $0.processIdentifier != me }
  }

  @objc func showSettings() {
    if settingsWindow == nil { settingsWindow = SettingsWindow(engine: AppDelegate.engine) }
    NSApp.setActivationPolicy(.accessory)
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
    AppDelegate.server == nil
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
