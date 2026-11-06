import Cocoa

// Keyboard-only candidates: never take focus or intercept an unrelated click.
final class CandidatePanel {
  private let window: NSPanel
  private let font = NSFont(name: "PingFang HK", size: 18) ?? .systemFont(ofSize: 18)
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var refreshTimer: Timer?
  private var currentOwner: ObjectIdentifier?

  init() {
    window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    window.level = .popUpMenu
    window.ignoresMouseEvents = true
    window.hasShadow = true
    window.isOpaque = false
    window.backgroundColor = .windowBackgroundColor
    // IMK normally hides on deactivateServer. These process-wide safety nets
    // dismiss only the UI if an app/session transition arrives first; they must
    // never commit, clear or retarget the controller's composition.
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didActivateApplicationNotification,
                 NSWorkspace.sessionDidResignActiveNotification,
                 NSWorkspace.willSleepNotification] {
      observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.hide()
      }))
    }
    let center = NotificationCenter.default
    observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                object: nil, queue: .main) { [weak self] _ in self?.hide() }))
  }

  deinit {
    refreshTimer?.invalidate()
    for (center, token) in observers { center.removeObserver(token) }
  }

  // A long horizontal row falls back to vertical; each shortcut has its own
  // nontruncated label. Only candidate text is ellipsized, never its index.
  func show(_ v: RimeView, below caret: NSRect, vertical: Bool,
            owner: ObjectIdentifier? = nil, refreshCaret: (() -> NSRect?)? = nil) {
    guard !v.candidates.isEmpty,
          let screen = CandidatePanelGeometry.screen(for: caret, in: NSScreen.screens.map(\.visibleFrame)) else {
      hide(owner: owner); return
    }
    let texts = v.candidates.map { candidate in
      (candidate.text + candidate.comment).replacingOccurrences(of: "\r\n", with: "↵")
        .replacingOccurrences(of: "\n", with: "↵").replacingOccurrences(of: "\r", with: "↵")
        .replacingOccurrences(of: "\t", with: "⇥")
    }
    let rowHeight = ceil(font.ascender - font.descender + font.leading) + 4
    let indexWidth = ceil(("\(v.candidates.count). " as NSString).size(withAttributes: [.font: font]).width) + 4
    let widths = texts.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + indexWidth + 12 }
    let maxWidth = min(600, screen.width)
    let useVertical = vertical || widths.reduce(0, +) + 16 > maxWidth
    let size = NSSize(width: min(maxWidth, (useVertical ? (widths.max() ?? 0) : widths.reduce(0, +)) + 16),
                      height: (useVertical ? CGFloat(texts.count) : 1) * rowHeight + 10)
    guard size.width > indexWidth + 28,
          let frame = CandidatePanelGeometry.frame(caret: caret, size: size, screen: screen) else {
      hide(owner: owner); return
    }
    let content = NSView(frame: NSRect(origin: .zero, size: size))
    var x: CGFloat = 8
    for (i, text) in texts.enumerated() {
      let y = useVertical ? size.height - 5 - CGFloat(i + 1) * rowHeight : 5
      let width = useVertical ? size.width - 16 : widths[i]
      let index = NSTextField(labelWithString: "\(i + 1).")
      index.font = font
      index.textColor = .secondaryLabelColor
      index.frame = NSRect(x: x, y: y, width: indexWidth, height: rowHeight)
      let label = NSTextField(labelWithString: text)
      label.font = font
      label.textColor = i == v.highlighted ? .controlAccentColor : .labelColor
      label.lineBreakMode = .byTruncatingTail
      label.maximumNumberOfLines = 1
      label.toolTip = v.candidates[i].text + v.candidates[i].comment
      label.frame = NSRect(x: x + indexWidth, y: y, width: width - indexWidth, height: rowHeight)
      content.addSubview(index)
      content.addSubview(label)
      if !useVertical { x += width }
    }
    currentOwner = owner
    window.contentView = content
    window.setFrame(frame, display: true)
    window.orderFront(nil)
    refreshTimer?.invalidate()
    refreshTimer = nil
    if let refreshCaret = refreshCaret {
      var lastCaret = caret
      // Query only the same active IMK client while candidates are visible.
      // No global keyboard/mouse/clipboard monitor and no engine/marked-text work.
      let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
        guard let self = self, self.refreshTimer === timer else { return }
        let updated = refreshCaret()
        // The client query may reenter show/hide. A cancelled timer must not
        // apply its result to the replacement presentation, even for one owner.
        guard self.refreshTimer === timer else { return }
        guard self.window.isVisible, let updated = updated,
              let screen = CandidatePanelGeometry.screen(for: updated, in: NSScreen.screens.map(\.visibleFrame)),
              let frame = CandidatePanelGeometry.frame(caret: updated, size: self.window.frame.size, screen: screen) else {
          self.hide(); return
        }
        if updated != lastCaret {
          self.window.setFrame(frame, display: true)
          lastCaret = updated
        }
      }
      timer.tolerance = 0.025
      RunLoop.main.add(timer, forMode: .common)
      refreshTimer = timer
    }
  }

  // No owner means a process-wide dismissal (workspace/sleep/screen changes).
  // A controller may dismiss only the presentation it still owns.
  func hide(owner: ObjectIdentifier? = nil) {
    guard owner == nil || owner == currentOwner else { return }
    refreshTimer?.invalidate()
    refreshTimer = nil
    currentOwner = nil
    window.orderOut(nil)
  }
}
