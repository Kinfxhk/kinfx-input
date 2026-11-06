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
  private(set) var settings = Settings.defaults()

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
    settings = Settings.load(settingsPath)
    try writeCustom(settings)
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
    do { try apply(Settings.load(settingsPath)) }
    catch { settingsState = .failed }
  }

  static let settingsStateChanged = Notification.Name("KINFXSettingsStateChanged")
  enum SettingsState: Equatable { case unchanged, applied, deferred, savedForActivation, failed }
  private(set) var settingsState: SettingsState = .unchanged {
    didSet { NotificationCenter.default.post(name: Self.settingsStateChanged, object: self) }
  }
  // Stable controller handles survive a native rebuild. No text is copied or
  // replayed: rebuilding is allowed only when EVERY live session is empty and
  // every possible native commit has been read by its controller.
  private var sessions: [UInt: UInt] = [:]
  private var nextSession: UInt = 0
  private var undrained = Set<UInt>()
  // A failed rebuild has no input session. Keep only the already-proven-idle
  // switches and script category under the original controller handle for retry.
  private struct IdleRuntime { let options: [Int32]; let tail: Int32; let digitTail: Int32 }
  private var retryRuntime: [UInt: IdleRuntime] = [:]
  // App-side fallback (the host app inserts an unhandled printable key literally,
  // e.g. the fallback2 '2'): per-owner marker so clear()/blur() of a failed owner
  // keeps its latin/digit tail (half-width punctuation) instead of revoking it.
  private var appFallback: [UInt: Bool] = [:]  // handle -> inserted character was an ASCII digit
  // UI failure also covers persistence I/O before native sessions are touched.
  // Only a failed rebuild blocks new owners, even when no old owners existed.
  private var nativeRebuildFailed = false
  private var reloadPending = false
  private static let switches = ["ascii_mode", "full_shape", "simplification", "ascii_punct"]
  // Engine handles are controller-owned, not raw RimeSessionIds. Native-only
  // QA probes must resolve them immediately before calling the C test API.
  func nativeSession(_ s: UInt) -> UInt { sessions[s] ?? 0 }
  private func native(_ s: UInt) -> UInt { nativeSession(s) }

  private func reloadWhenIdle() {
    guard started, reloadPending, settingsState != .failed else { return }
    for (handle, sid) in sessions where kx_alive(sid) == 0 {
      sessions.removeValue(forKey: handle); undrained.remove(handle)
    }
    guard undrained.isEmpty,
          sessions.values.allSatisfy({ kx_has_pending($0) == 0 }) else { return }
    var runtime = retryRuntime
    for (handle, sid) in sessions {
      let tail = kx_idle_punct_tail(sid)
      let digitTail = kx_idle_digit_tail(sid)
      guard tail >= 0, digitTail >= 0 else { return }
      runtime[handle] = IdleRuntime(options: Self.switches.map { kx_option(sid, $0) }, tail: tail, digitTail: digitTail)
    }
    // From here every owner is idle and drained. A failed deploy/reopen must not
    // manufacture an unknown session which would block its own explicit retry.
    retryRuntime = runtime
    sessions.removeAll()
    var restored: [UInt: UInt] = [:]
    var ok = kx_redeploy() != 0
    if ok {
      for (handle, saved) in runtime {
        let sid = UInt(kx_session(Self.schema))
        guard sid != 0 else { ok = false; break }
        restored[handle] = sid
        for (key, value) in zip(Self.switches, saved.options) { kx_set_option(sid, key, value) }
        if kx_restore_idle_punct_tail(sid, saved.tail) == 0 { ok = false; break }
        if kx_restore_idle_digit_tail(sid, saved.digitTail) == 0 { ok = false; break }
      }
    }
    if ok {
      sessions = restored
      retryRuntime.removeAll()
      appFallback.removeAll()
    } else {
      for sid in restored.values { kx_destroy(sid) }
    }
    reloadPending = !ok
    nativeRebuildFailed = !ok
    settingsState = ok ? .applied : .failed
  }

  func apply(_ s: [String: String]) throws {
    try FileManager.default.createDirectory(atPath: userDir, withIntermediateDirectories: true)
    try Settings.save(s, to: settingsPath)
    settings = Settings.load(settingsPath)
    // Normalize through the same validated settings used by the UI/runtime.
    try writeCustom(settings)
    settingsStamp = stamp()
    guard started else { settingsState = .savedForActivation; return }
    // Rime's mtime resolution is seconds, so force the requested rebuild.
    let built = userDir + "/build/\(Engine.schema).schema.yaml"
    if FileManager.default.fileExists(atPath: built) { try FileManager.default.removeItem(atPath: built) }
    reloadPending = true
    settingsState = .deferred
    reloadWhenIdle()
  }

  func newSession() -> UInt {
    reloadWhenIdle()
    guard started, !nativeRebuildFailed else { return 0 }
    let sid = UInt(kx_session(Self.schema))
    guard sid != 0 else { return 0 }
    nextSession += 1; sessions[nextSession] = sid
    return nextSession
  }
  func alive(_ s: UInt) -> Bool { kx_alive(native(s)) != 0 }
  // Ownership can outlive a failed native rebuild; it is not input readiness.
  func ownsSession(_ s: UInt) -> Bool { alive(s) || retryRuntime[s] != nil }
  func destroy(_ s: UInt) {
    kx_destroy(native(s)); sessions.removeValue(forKey: s); retryRuntime.removeValue(forKey: s)
    appFallback.removeValue(forKey: s)
    undrained.remove(s); reloadWhenIdle()
  }
  // Record that the host app inserted a literal character for an unhandled key
  // (fallback2 contract). The engine never saw that text, so a later clear/blur
  // must keep — not revoke — this owner's tail so a following period stays
  // half-width. `isAsciiDigit` marks a digit-led run (e.g. the '2' in "hello2").
  func noteAppFallback(_ s: UInt, isAsciiDigit: Bool) {
    appFallback[s] = isAsciiDigit
  }
  // Same-owner explicit finalization while the native runtime is unavailable:
  // empty only this owner's routing metadata (script tail + digit tail). The
  // logical owner and its four runtime switches stay, so a later explicit retry
  // still restores width under the same controller handle (C transition).
  private func revokeRouting(_ s: UInt) {
    guard let saved = retryRuntime[s] else { return }
    if let isDigit = appFallback[s] {
      // The app inserted text the engine never saw: keep the script tail so the
      // next punctuation stays half-width, and mark a digit-led run for a digit.
      retryRuntime[s] = IdleRuntime(options: saved.options, tail: saved.tail,
                                    digitTail: isDigit ? 1 : saved.digitTail)
      return
    }
    retryRuntime[s] = IdleRuntime(options: saved.options, tail: 0, digitTail: 0)
  }
  func clear(_ s: UInt) {
    guard alive(s) else { revokeRouting(s); return }
    // Clear notifiers can commit a held prefix; only takeCommit proves its queue drained.
    undrained.insert(s); kx_clear(native(s)); reloadWhenIdle()
  }
  func key(_ s: UInt, _ code: Int32, _ mask: Int32) -> Bool {
    guard alive(s) else { return false }
    undrained.insert(s)
    return kx_key(native(s), code, mask) != 0
  }
  // 0.1.4 focus left (click elsewhere, app switch): F35 makes english_mix.lua commit what was typed
  // (English letters as typed, Sucheng as Return gives), then Rime is cleared.
  func blur(_ s: UInt) -> String? {
    // A terminal commit while the native runtime is unavailable revokes that
    // owner's routing continuity the same way an explicit clear does.
    guard alive(s) else { revokeRouting(s); return nil }
    // Keep the terminal transaction under one native session. It has already
    // drained the F35 queue; do not reload between that drain and the final clear.
    _ = key(s, 0xffe0, 0)
    let p = kx_take_commit(native(s))
    let text = p.map { String(cString: $0) }
    if let p = p { free(p) }
    kx_clear(native(s))
    // Clear notifiers may enqueue retained prefixes. Read them before the barrier.
    let suffix = takeCommit(s)
    let combined = (text ?? "") + (suffix ?? "")
    return combined.isEmpty ? nil : combined
  }

  func takeCommit(_ s: UInt) -> String? {
    defer { undrained.remove(s); reloadWhenIdle() }
    guard let p = kx_take_commit(native(s)) else { return nil }
    defer { free(p) }
    return String(cString: p)
  }

  func view(_ s: UInt) -> RimeView {
    guard let p = kx_context(native(s)) else { return RimeView() }
    defer { free(p) }
    return RimeView(raw: String(cString: p))
  }
}
