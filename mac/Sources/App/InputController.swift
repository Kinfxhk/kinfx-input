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
    Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
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
    Trace.log("handle type=\(event?.type.rawValue ?? 0) key=\(event?.keyCode ?? 0) chars=\(event?.characters ?? "")")
    guard let event = event, let client = sender as? IMKTextInput, ensureSession() else { return false }
    let mods = Self.mods(event.modifierFlags)
    var handled = false
    switch event.type {
    case .flagsChanged:
      defer { lastMods = mods }
      guard mods != lastMods, let (k, m) = RimeKeys.flagsChanged(keyCode: event.keyCode, mods: mods) else { return false }
      handled = engine.key(session, k, m)
    case .keyDown:
      guard let (k, m) = RimeKeys.keyDown(keyCode: event.keyCode, chars: event.characters,
                                          bare: event.charactersIgnoringModifiers, mods: mods) else { return false }
      handled = engine.key(session, k, m)
    default:
      return false
    }
    update(client)
    return handled
  }

  // Push commit text, preedit and candidates to the client after every key.
  private func update(_ client: IMKTextInput) {
    if let text = engine.takeCommit(session) {
      client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    let view = engine.view(session)
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText, at: NSRange(location: 0, length: 0)) as? [NSAttributedString.Key: Any] ?? [:]
    let pre = NSAttributedString(string: view.preedit, attributes: attrs)
    client.setMarkedText(pre, selectionRange: NSRange(location: view.cursorUTF16, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    if view.candidates.isEmpty {
      AppDelegate.panel.hide()
    } else {
      var rect = NSRect.zero
      client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
      AppDelegate.panel.show(view, below: rect)
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
    let item = NSMenuItem(title: "KINFX Input 設定…", action: #selector(openSettings(_:)), keyEquivalent: "")
    item.target = self
    m.addItem(item)
    return m
  }

  @objc func openSettings(_ sender: Any?) {
    (NSApp.delegate as? AppDelegate)?.showSettings()
  }

  deinit {
    if session != 0 { engine.destroy(session) }
  }
}
