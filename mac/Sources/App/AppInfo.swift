import Cocoa

// About / help / donate text comes from app-info.json (shared by every shell).
struct AppInfo {
  var version = "0.1.0"
  var about = ""
  var help: [String] = []
  var donateURL = ""   // empty until the maintainer sets one; never guess a URL
  var license = ""

  static func load(_ path: String) -> AppInfo {
    var i = AppInfo()
    guard let d = FileManager.default.contents(atPath: path),
          let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return i }
    i.version = o["version"] as? String ?? i.version
    i.about = o["about"] as? String ?? ""
    i.help = o["help"] as? [String] ?? []
    i.donateURL = (o["donate_url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    i.license = o["license"] as? String ?? ""
    return i
  }

  // Only http(s) URLs open; anything else counts as not set.
  var donateLink: URL? {
    guard let u = URL(string: donateURL), ["https", "http"].contains(u.scheme?.lowercased() ?? "") else { return nil }
    return u
  }

  static var shared = AppInfo.load(Bundle.main.resourcePath! + "/app-info.json")

  static func showAbout() {
    let a = NSAlert()
    a.messageText = "KINFX Input \(shared.version)"
    a.informativeText = shared.about + (shared.license.isEmpty ? "" : "\n\n授權：\(shared.license)")
    a.runModal()
  }

  static func showHelp() {
    let a = NSAlert()
    a.messageText = "KINFX Input 說明"
    a.informativeText = shared.help.map { "• " + $0 }.joined(separator: "\n")
    a.runModal()
  }

  static func openDonate() {
    if let u = shared.donateLink { NSWorkspace.shared.open(u); return }
    let a = NSAlert()
    a.messageText = "捐款"
    a.informativeText = "捐款連結尚未設定。"
    a.runModal()
  }
}
