import Cocoa

// The only place a user changes anything. Each row is one entry of Settings.specs.
final class SettingsWindow: NSWindow {
  private let engine: Engine
  private var popups: [String: NSPopUpButton] = [:]
  private var settingsObserver: NSObjectProtocol?
  private let status = NSTextField(labelWithString: "")

  init(engine: Engine) {
    self.engine = engine
    super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 10),
               styleMask: [.titled, .closable], backing: .buffered, defer: false)
    title = "KINFX Input 設定"
    isReleasedWhenClosed = false

    let current = Settings.load(engine.settingsPath)
    let grid = NSGridView()
    for spec in Settings.specs {
      let label = NSTextField(labelWithString: spec.label)
      let popup = NSPopUpButton()
      popup.identifier = NSUserInterfaceItemIdentifier(spec.key)
      for o in spec.options { popup.addItem(withTitle: o.label) }
      let idx = spec.options.firstIndex { $0.value == current[spec.key] } ?? 0
      popup.selectItem(at: idx)
      popup.target = self
      popup.action = #selector(changed(_:))
      popup.setAccessibilityLabel(spec.label)
      popups[spec.key] = popup
      grid.addRow(with: [label, popup])
    }
    grid.column(at: 0).xPlacement = .trailing
    grid.rowSpacing = 10
    grid.columnSpacing = 12

    status.textColor = .secondaryLabelColor
    refreshStatus()
    settingsObserver = NotificationCenter.default.addObserver(
      forName: Engine.settingsStateChanged, object: nil, queue: nil) { [weak self] note in
      guard let self = self, (note.object as? Engine) === self.engine else { return }
      self.refreshStatus()
    }
    let buttons = NSStackView(views: [
      NSButton(title: "說明", target: self, action: #selector(help)),
      NSButton(title: "關於", target: self, action: #selector(about)),
      NSButton(title: "支持", target: self, action: #selector(donate)),
    ])
    buttons.spacing = 8
    let stack = NSStackView(views: [grid, status, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    contentView = stack
    setContentSize(stack.fittingSize)
    center()
  }

  deinit { if let observer = settingsObserver { NotificationCenter.default.removeObserver(observer) } }

  private func refreshStatus() {
    switch engine.settingsState {
    case .unchanged: status.stringValue = "變更會儲存；輸入中的文字完成後套用。"
    case .applied: status.stringValue = "已套用。"
    case .deferred: status.stringValue = "已儲存，等待輸入完成後套用。"
    case .savedForActivation: status.stringValue = "已儲存，下次啟用輸入法時套用。"
    case .failed: status.stringValue = "已儲存，但重載失敗；請重新選擇設定以重試。"
    }
  }

  @objc private func help() { AppInfo.showHelp() }
  @objc private func about() { AppInfo.showAbout() }
  @objc private func donate() { AppInfo.openDonate() }

  @objc private func changed(_ sender: NSPopUpButton) {
    var s: [String: String] = [:]
    for spec in Settings.specs {
      let i = popups[spec.key]?.indexOfSelectedItem ?? 0
      s[spec.key] = spec.options[max(0, min(i, spec.options.count - 1))].value
    }
    do {
      try engine.apply(s)
      refreshStatus()
    } catch {
      status.stringValue = "儲存失敗：\(error.localizedDescription)"
    }
  }
}
