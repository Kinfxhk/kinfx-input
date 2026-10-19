import Cocoa

// One borderless panel for the candidate list (no IMKCandidates).
final class CandidatePanel {
  private let window: NSPanel
  private let label: NSTextField

  init() {
    window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    window.hasShadow = true
    window.isOpaque = false
    window.backgroundColor = .windowBackgroundColor
    label = NSTextField(labelWithString: "")
    label.font = NSFont(name: "PingFang HK", size: 18) ?? .systemFont(ofSize: 18)
    label.textColor = .labelColor
    window.contentView?.addSubview(label)
  }

  // vertical (default): one candidate per line; horizontal: one row.
  func show(_ v: RimeView, below caret: NSRect, vertical: Bool) {
    let line = NSMutableAttributedString()
    for (i, c) in v.candidates.enumerated() {
      if vertical && i > 0 { line.append(NSAttributedString(string: "\n")) }
      let hi = i == v.highlighted
      line.append(NSAttributedString(string: "\(i + 1). ", attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                                                                       .font: label.font!]))
      line.append(NSAttributedString(string: c.text + c.comment + (vertical ? "" : "  "), attributes: [
        .foregroundColor: hi ? NSColor.controlAccentColor : NSColor.labelColor, .font: label.font!]))
    }
    label.attributedStringValue = line
    label.sizeToFit()
    let size = NSSize(width: label.frame.width + 16, height: label.frame.height + 10)
    label.frame.origin = NSPoint(x: 8, y: 5)
    var origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 4)
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(caret.origin) }) ?? NSScreen.main {
      let f = screen.visibleFrame
      if origin.y < f.minY { origin.y = caret.maxY + 4 }
      origin.x = min(max(origin.x, f.minX), f.maxX - size.width)
    }
    window.setFrame(NSRect(origin: origin, size: size), display: true)
    window.orderFrontRegardless()
  }

  func hide() { window.orderOut(nil) }
}
