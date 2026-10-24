import Cocoa

// About / help / donate text comes from app-info.json (shared by every shell).
struct AppInfo {
  var version = "0.1.5"
  var about = ""
  var help: [String] = []
  var donateURL = ""   // legacy single link; unused when donate_links is set
  var donateLinks: [(label: String, url: URL)] = []
  var license = ""

  static func load(_ path: String) -> AppInfo {
    var i = AppInfo()
    guard let d = FileManager.default.contents(atPath: path),
          let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return i }
    i.version = o["version"] as? String ?? i.version
    i.about = o["about"] as? String ?? ""
    i.help = o["help"] as? [String] ?? []
    i.donateURL = (o["donate_url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    if let rows = o["donate_links"] as? [[String: Any]] {
      i.donateLinks = rows.compactMap { row in
        guard let label = row["label"] as? String,
              let raw = (row["url"] as? String)?.trimmingCharacters(in: .whitespaces),
              let u = URL(string: raw),
              ["https", "http"].contains(u.scheme?.lowercased() ?? "") else { return nil }
        return (label, u)
      }
    }
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
    let links = shared.donateLinks
    if links.isEmpty {
      if let u = shared.donateLink { NSWorkspace.shared.open(u); return }
      let a = NSAlert()
      a.messageText = "支持"
      a.informativeText = "支持連結尚未設定。"
      a.runModal()
      return
    }
    if links.count == 1 { NSWorkspace.shared.open(links[0].url); return }
    let a = NSAlert()
    a.messageText = "支持"
    a.informativeText = "揀一個："
    for l in links { a.addButton(withTitle: l.label) }
    a.addButton(withTitle: "取消")
    let i = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    if i >= 0 && i < links.count { NSWorkspace.shared.open(links[i].url) }
  }
}
