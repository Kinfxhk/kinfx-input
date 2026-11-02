import Cocoa
import InputMethodKit

@objc(KINFXInputController)
final class KINFXInputController: IMKInputController {
  private var session: UInt = 0
  private var lastMods: RimeKeys.Mods = []
  /// What the preedit showed last. Used only when the engine has already lost the
  /// composition by the time focus leaves (macOS can clear the marked text first),
  /// so an unfinished English run is not silently dropped on blur.
  private var pendingLetters: String = ""
  /// True while a Shift run is being typed literally, so later letters keep the
  /// case the OS produced instead of becoming new composition codes.
  private var shiftRun = false

  private var engine: Engine { AppDelegate.engine }

  private func ensureSession() -> Bool {
    if session == 0 || !engine.alive(session) { session = engine.newSession() }
    return session != 0
  }

  @objc(recognizedEvents:)
  override func recognizedEvents(_ sender: Any!) -> Int {
    Trace.log("recognizedEvents")
    return Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
  }

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    super.init(server: server, delegate: delegate, client: inputClient)
    Trace.log("controller init client=\(String(describing: inputClient))")
  }

  // IMK prefers this over handleEvent:client: when both exist (real-key trace, 6ba4532),
  // so key downs come here; handleEvent still receives flagsChanged for Shift alone.
  override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
    Trace.log("inputText:key: [\(string ?? "")] key=\(keyCode) flags=\(String(flags, radix: 16))")
    let mods = Self.mods(NSEvent.ModifierFlags(rawValue: UInt(flags)))
    return keyDown(UInt16(keyCode), string, string, mods, sender)
  }

  private static func mods(_ f: NSEvent.ModifierFlags) -> RimeKeys.Mods {
    var m: RimeKeys.Mods = []
    if f.contains(.shift) { m.insert(.shift) }
    if f.contains(.control) { m.insert(.control) }
    if f.contains(.option) { m.insert(.option) }
    if f.contains(.command) { m.insert(.command) }
    if f.contains(.capsLock) { m.insert(.capsLock) }
    return m
  }

  @objc(handleEvent:client:)
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    Trace.log("handle type=\(event?.type.rawValue ?? 0) key=\(event?.keyCode ?? 0) chars=\(event?.characters ?? "") flags=\(String(event?.modifierFlags.rawValue ?? 0, radix: 16))")
    guard let event = event, let client = sender as? IMKTextInput, ensureSession() else { return false }
    let mods = Self.mods(event.modifierFlags)
    var handled = false
    switch event.type {
    case .flagsChanged:
      defer { lastMods = mods }
      guard mods != lastMods, let (k, m) = RimeKeys.flagsChanged(keyCode: event.keyCode, mods: mods) else { return false }
      Trace.log("  flags k=\(String(k, radix: 16)) m=\(String(m, radix: 16))")
      handled = engine.key(session, k, m)
    case .keyDown:
      return keyDown(event.keyCode, event.characters, event.charactersIgnoringModifiers, mods, sender)
    default:
      return false
    }
    update(client)
    Trace.log("  -> sent rime handled=\(handled)")
    return handled
  }

  /// Press then release Left Shift in the engine, which is the commit path
  /// `english_mix.lua` runs when a Shift tap ends a short composition.
  private func tapLeftShift() {
    if let (k, m) = RimeKeys.flagsChanged(keyCode: 56, mods: [.shift]) { _ = engine.key(session, k, m) }
    if let (k, m) = RimeKeys.flagsChanged(keyCode: 56, mods: []) { _ = engine.key(session, k, m) }
  }

  private func keyDown(_ keyCode: UInt16, _ chars: String?, _ bare: String?, _ mods: RimeKeys.Mods, _ sender: Any!) -> Bool {
    guard let client = sender as? IMKTextInput, ensureSession(),
          let (k, m) = RimeKeys.keyDown(keyCode: keyCode, chars: chars, bare: bare, mods: mods) else { return false }

    // Continuing a shifted run: type the key as-is (correct case with Caps Lock on
    // or off) instead of letting it start another composition.
    if ShiftEnglish.shouldTypeDirectly(chars: chars, mods: mods, continuing: shiftRun) {
      if let text = chars, !text.isEmpty {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        Trace.log("  shift-run insert [\(text)]")
      }
      update(client)
      return true
    }
    if !mods.contains(.shift) { shiftRun = false }

    // Shift + letter on a 1–2 code composition: commit the codes as English, then
    // type the letter. A bare Shift tap cannot be seen on this macOS (no
    // flagsChanged reaches the controller), so this is the reachable gesture.
    if ShiftEnglish.shouldCommit(preedit: engine.view(session).preedit, mods: mods, chars: chars) {
      tapLeftShift()
      if let text = engine.takeCommit(session) {
        Trace.log("  shift-english commit [\(text)]")
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        if let literal = chars, !literal.isEmpty {
          client.insertText(literal, replacementRange: NSRange(location: NSNotFound, length: 0))
          shiftRun = true
        }
        update(client)
        return true
      }
      // nothing was committed (empty or non-code composition): fall through
    }
    Trace.log("  key k=\(String(k, radix: 16)) m=\(String(m, radix: 16))")
    let handled = engine.key(session, k, m)
    update(client)
    Trace.log("  -> sent rime handled=\(handled)")
    return handled
  }

  // Push commit text, preedit and candidates to the client after every key.
  private func update(_ client: IMKTextInput) {
    if let text = engine.takeCommit(session) {
      Trace.log("  commit [\(text)]")
      client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    let view = engine.view(session)
    let letters = view.preedit.trimmingCharacters(in: .whitespaces)
    pendingLetters = (1...8).contains(letters.count) && letters.allSatisfy { $0.isASCII && $0.isLetter } ? letters : ""
    if !view.candidates.isEmpty { Trace.log("  view page=\(view.pageSize) n=\(view.candidates.count) layout=\(engine.settings["candidate_layout"] ?? "vertical")") }
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText, at: NSRange(location: 0, length: 0)) as? [NSAttributedString.Key: Any] ?? [:]
    let pre = NSAttributedString(string: view.preedit, attributes: attrs)
    client.setMarkedText(pre, selectionRange: NSRange(location: view.cursorUTF16, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    if view.candidates.isEmpty {
      AppDelegate.panel.hide()
    } else {
      var rect = NSRect.zero
      client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
      AppDelegate.panel.show(view, below: rect, vertical: engine.settings["candidate_layout"] != "horizontal")
    }
  }

  override func commitComposition(_ sender: Any!) {
    guard session != 0, let client = sender as? IMKTextInput else { return }
    blur(client)
  }

  private func blur(_ client: IMKTextInput) {
    let committed = engine.blur(session) ?? ""
    // The engine keeps the run normally; if focus loss already cleared it, fall back
    // to the letters the preedit showed so an unfinished English run survives.
    let text = committed.isEmpty ? pendingLetters : committed
    Trace.log("  blur commit [\(text)] engine=[\(committed)] shadow=[\(pendingLetters)]")
    pendingLetters = ""
    if !text.isEmpty {
      client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    AppDelegate.panel.hide()
  }

  override func activateServer(_ sender: Any!) {
    Trace.log("activateServer \(String(describing: sender))")
    super.activateServer(sender)
    engine.reloadIfSettingsChanged()
  }

  override func deactivateServer(_ sender: Any!) {
    if session != 0, let client = sender as? IMKTextInput { blur(client) }
    AppDelegate.panel.hide()
    super.deactivateServer(sender)
  }

  override func menu() -> NSMenu! {
    let m = NSMenu()
    for (title, sel) in [("KINFX Input 設定…", #selector(openSettings(_:))), ("說明", #selector(openHelp(_:))),
                         ("關於 KINFX Input", #selector(openAbout(_:))), ("支持…", #selector(openDonate(_:)))] {
      let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
      item.target = self
      m.addItem(item)
    }
    return m
  }

  @objc func openHelp(_ sender: Any?) { NSApp.activate(ignoringOtherApps: true); AppInfo.showHelp() }
  @objc func openAbout(_ sender: Any?) { NSApp.activate(ignoringOtherApps: true); AppInfo.showAbout() }
  @objc func openDonate(_ sender: Any?) { AppInfo.openDonate() }

  @objc func openSettings(_ sender: Any?) {
    (NSApp.delegate as? AppDelegate)?.showSettings()
  }

  deinit {
    if session != 0 { engine.destroy(session) }
  }
}
