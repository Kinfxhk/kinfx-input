import Foundation

struct RimeView {
  var preedit = ""
  var cursorBytes = 0
  var pageSize = 0
  var pageNo = 0
  var isLastPage = true
  var highlighted = 0
  var candidates: [(text: String, comment: String)] = []

  init() {}

  init(raw: String) {
    let f = raw.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 6 else { return }
    preedit = f[0]
    cursorBytes = Int(f[1]) ?? 0
    pageSize = Int(f[2]) ?? 0
    pageNo = Int(f[3]) ?? 0
    isLastPage = f[4] != "0"
    highlighted = Int(f[5]) ?? 0
    candidates = f.dropFirst(6).map { c in
      let p = c.split(separator: "\u{1e}", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
      return (p[0], p.count > 1 ? p[1] : "")
    }
  }

  // Rime reports the cursor in UTF-8 bytes; AppKit wants UTF-16 units.
  var cursorUTF16: Int {
    let bytes = Array(preedit.utf8)
    let n = min(max(cursorBytes, 0), bytes.count)
    return (String(decoding: bytes[0..<n], as: UTF8.self)).utf16.count
  }
}

final class Engine {
  static let schema = "kinfx_quick"
  static let bundledTextFiles = ["kinfx_capture.txt", "kinfx_en_unsafe.txt", "kinfx_en_names.txt"]

  let sharedDir: String
  let userDir: String
  private(set) var started = false

  init(sharedDir: String, userDir: String) {
    self.sharedDir = sharedDir
    self.userDir = userDir
  }

  var settingsPath: String { userDir + "/settings.json" }
  var customPath: String { userDir + "/\(Engine.schema).custom.yaml" }

  // The Lua scripts read their word lists from the user data dir; keep that copy
  // equal to the bundle, and keep the Rime patch equal to settings.json.
  func prepareUserDir() throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: userDir + "/log", withIntermediateDirectories: true)
    for name in Engine.bundledTextFiles {
      let src = sharedDir + "/" + name, dst = userDir + "/" + name
      if fm.contentsEqual(atPath: src, andPath: dst) { continue }
      try? fm.removeItem(atPath: dst)
      try fm.copyItem(atPath: src, toPath: dst)
    }
    try writeCustom(Settings.load(settingsPath))
  }

  private func writeCustom(_ s: [String: String]) throws {
    let text = Settings.rimeCustom(s)
    if (try? String(contentsOfFile: customPath, encoding: .utf8)) == text { return }
    try text.write(toFile: customPath, atomically: true, encoding: .utf8)
  }

  func start() throws {
    try prepareUserDir()
    started = kx_start(sharedDir, userDir, userDir + "/log", 0) != 0
    settingsStamp = stamp()
  }

  private var settingsStamp: Date?
  private func stamp() -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: settingsPath))?[.modificationDate] as? Date
  }

  // A settings window in another process (opened from Finder) only writes settings.json.
  func reloadIfSettingsChanged() {
    let now = stamp()
    guard started, now != settingsStamp else { return }
    try? apply(Settings.load(settingsPath))
  }

  // Settings window: save, regenerate the patch, rebuild. Old sessions end here;
  // controllers open a new one on their next key.
  func apply(_ s: [String: String]) throws {
    try FileManager.default.createDirectory(atPath: userDir, withIntermediateDirectories: true)
    try Settings.save(s, to: settingsPath)
    settingsStamp = stamp()
    try writeCustom(s)
    // Rime compares mtimes in whole seconds; drop the built schema so a change made
    // within the same second as the last build is still rebuilt.
    try? FileManager.default.removeItem(atPath: userDir + "/build/\(Engine.schema).schema.yaml")
    _ = kx_redeploy()
  }

  func newSession() -> UInt { UInt(kx_session(Engine.schema)) }
  func alive(_ s: UInt) -> Bool { kx_alive(UInt(s)) != 0 }
  func destroy(_ s: UInt) { kx_destroy(UInt(s)) }
  func clear(_ s: UInt) { kx_clear(UInt(s)) }
  func key(_ s: UInt, _ code: Int32, _ mask: Int32) -> Bool { kx_key(UInt(s), code, mask) != 0 }
  func commitComposition(_ s: UInt) { _ = kx_commit_composition(UInt(s)) }

  func takeCommit(_ s: UInt) -> String? {
    guard let p = kx_take_commit(UInt(s)) else { return nil }
    defer { free(p) }
    return String(cString: p)
  }

  func view(_ s: UInt) -> RimeView {
    guard let p = kx_context(UInt(s)) else { return RimeView() }
    defer { free(p) }
    return RimeView(raw: String(cString: p))
  }
}
