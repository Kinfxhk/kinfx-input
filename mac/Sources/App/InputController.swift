import Cocoa
import InputMethodKit

@objc(KINFXInputController)
final class KINFXInputController: IMKInputController {
  private var session: UInt = 0
  private var lastMods: RimeKeys.Mods = []

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

  private func keyDown(_ keyCode: UInt16, _ chars: String?, _ bare: String?, _ mods: RimeKeys.Mods, _ sender: Any!) -> Bool {
    guard let client = sender as? IMKTextInput, ensureSession(),
          let (k, m) = RimeKeys.keyDown(keyCode: keyCode, chars: chars, bare: bare, mods: mods) else { return false }
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
    engine.commitComposition(session)
    update(client)
  }

  override func activateServer(_ sender: Any!) {
    Trace.log("activateServer \(String(describing: sender))")
    super.activateServer(sender)
    engine.reloadIfSettingsChanged()
  }

  override func deactivateServer(_ sender: Any!) {
    if session != 0, let client = sender as? IMKTextInput {
      engine.commitComposition(session)
      update(client)
      engine.clear(session)
    }
    AppDelegate.panel.hide()
    super.deactivateServer(sender)
  }

  override func menu() -> NSMenu! {
    let m = NSMenu()
    for (title, sel) in [("KINFX Input 設定…", #selector(openSettings(_:))), ("說明", #selector(openHelp(_:))),
                         ("關於 KINFX Input", #selector(openAbout(_:))), ("捐款…", #selector(openDonate(_:)))] {
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
