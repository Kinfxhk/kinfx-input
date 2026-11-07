import Cocoa

// Real CandidatePanel.show and real AppKit text measurement; no IMK registration,
// key injection, activation, or installed-user data. All test windows stay invisible.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
let panel = CandidatePanel()
for window in app.windows { window.alphaValue = 0; window.ignoresMouseEvents = true }
guard let screen = NSScreen.main else { fatalError("A desktop session is required") }
let visible = screen.visibleFrame
let caret = NSRect(x: visible.midX, y: visible.midY, width: 0, height: 22)
var checks = 0, failures = 0
func check(_ condition: Bool, _ name: String) {
  checks += 1
  if !condition { failures += 1 }
  print("\(condition ? "PASS" : "FAIL") \(name)")
}
func rect(_ r: NSRect) -> [String: Double] {
  ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
}
func show(_ texts: [String], vertical: Bool, at anchor: NSRect? = nil) -> NSWindow? {
  var view = RimeView()
  view.candidates = texts.map { ($0, "") }; view.pageSize = 9
  panel.show(view, below: anchor ?? caret, vertical: vertical)
  return app.windows.first { $0.isVisible }
}
let ordinary = ["好", "她", "妹", "紆", "巢", "媒", "彙", "綑", "綵"]
if let window = show(ordinary, vertical: true) {
  check(visible.contains(window.frame), "ordinary is within visible screen")
  check(!window.frame.intersects(caret.insetBy(dx: -1, dy: -4)), "ordinary excludes caret plus gap")
} else { check(false, "ordinary visible") }
if let window = show(Array(repeating: String(repeating: "超長候選文字", count: 12), count: 9), vertical: false) {
  print("GEOMETRY " + String(data: try JSONSerialization.data(withJSONObject: ["panel": rect(window.frame), "screen": rect(visible)], options: [.sortedKeys]), encoding: .utf8)!)
  check(visible.contains(window.frame), "long horizontal stays within visible screen")
  check(!window.frame.intersects(caret.insetBy(dx: -1, dy: -4)), "long horizontal excludes caret plus gap")
} else { check(false, "long horizontal visible") }
panel.hide()
if let window = show(ordinary, vertical: true) {
  check(window.level == .popUpMenu, "uses popup level, not global shielding")
  check(!window.canBecomeKey && !window.canBecomeMain, "panel cannot take keyboard focus")
  check(window.ignoresMouseEvents, "keyboard-only panel passes unrelated mouse clicks through")
  NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
  check(!window.isVisible, "app activation dismisses panel even without IMK deactivation")
} else { check(false, "lifecycle fixture visible") }
if let window = show(ordinary, vertical: true) {
  NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
  check(!window.isVisible, "inactive login session dismisses panel")
} else { check(false, "inactive-session fixture visible") }
for (name, notification) in [("sleep", NSWorkspace.willSleepNotification)] {
  if let window = show(ordinary, vertical: true) {
    NSWorkspace.shared.notificationCenter.post(name: notification, object: nil)
    check(!window.isVisible, "\(name) dismisses panel")
  } else { check(false, "\(name) fixture visible") }
}
if let window = show(ordinary, vertical: true) {
  NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
  check(!window.isVisible, "display topology change dismisses panel")
} else { check(false, "display-topology fixture visible") }
for count in [5, 9] {
  for vertical in [false, true] {
    if let window = show(Array(ordinary.prefix(count)), vertical: vertical) {
      let labels = window.contentView!.subviews.compactMap { $0 as? NSTextField }
      check(labels.filter { $0.stringValue.hasSuffix(".") }.map(\.stringValue) == (1...count).map { "\($0)." }, "\(count) candidates preserve shortcut labels vertical=\(vertical)")
      check(visible.contains(window.frame), "\(count) candidate layout bounded vertical=\(vertical)")
    } else { check(false, "\(count) candidate layout visible vertical=\(vertical)") }
  }
}
check(CandidatePanelGeometry.frame(caret: NSRect(x: 10, y: 10, width: 0, height: 22),
                                  size: NSSize(width: 600, height: 280),
                                  screen: NSRect(x: 0, y: 0, width: 100, height: 100)) == nil, "unplaceable panel hides instead of clipping shortcut labels")
// Real rendering keeps all nine shortcuts distinct even for pathological text.
if let window = show(Array(repeating: String(repeating: "測試\n", count: 12), count: 9), vertical: true) {
  let labels = window.contentView!.subviews.compactMap { $0 as? NSTextField }
  check(visible.contains(window.frame), "embedded newlines cannot grow panel off screen")
  check(labels.filter { $0.stringValue.hasSuffix(".") }.map(\.stringValue) == (1...9).map { "\($0)." }, "nine shortcut labels remain present and unchanged")
  check(labels.count == 18 && labels.allSatisfy { window.contentView!.bounds.contains($0.frame) }, "each index and text field has bounded layout")
  check(labels.filter { !$0.stringValue.hasSuffix(".") }.allSatisfy { $0.maximumNumberOfLines == 1 && $0.lineBreakMode == .byTruncatingTail }, "only candidate text has explicit single-line ellipsis")
} else { check(false, "pathological-text fixture visible") }
for invalid in [NSRect.zero, NSRect(x: 1, y: 1, width: 0, height: -1),
                NSRect(x: CGFloat.nan, y: 1, width: 0, height: 22),
                NSRect(x: 1_000_000, y: 1_000_000, width: 0, height: 22)] {
  check(show(ordinary, vertical: true) != nil, "invalid-caret dismissal fixture visible \(invalid)")
  check(show(ordinary, vertical: true, at: invalid) == nil, "invalid/off-desktop caret hides stale panel \(invalid)")
}
check(show(ordinary, vertical: true) != nil, "empty-candidate dismissal fixture visible")
check(show([], vertical: true) == nil, "empty candidates hide stale panel")
let left = NSRect(x: -1920, y: -200, width: 1920, height: 1049)
let right = NSRect(x: 0, y: 0, width: 1920, height: 1049)
check(CandidatePanelGeometry.screen(for: NSRect(x: -500, y: 40, width: 0, height: 22), in: [right, left]) == left, "selects negative-origin display without main-screen fallback")
check(CandidatePanelGeometry.screen(for: NSRect(x: -3, y: 40, width: 20, height: 22), in: [left, right]) == right, "monitor seam chooses greatest caret intersection")
check(CandidatePanelGeometry.screen(for: NSRect(x: 0, y: 40, width: 0, height: 22), in: [left, right]) == right, "zero-width caret at monitor seam is valid")
var propertyCases = 0, propertyViolations = 0, propertyPlaced = 0
for screen in [left, right, NSRect(x: -900, y: -800, width: 800, height: 600)] {
  for col in 0...20 {
    for row in 0...20 {
      let anchor = NSRect(x: screen.minX + CGFloat(col) * (screen.width - 1) / 20,
                          y: screen.minY + CGFloat(row) * (screen.height - 22) / 20, width: 0, height: 22)
      for size in [NSSize(width: 100, height: 40), NSSize(width: 600, height: 280), NSSize(width: 600, height: 160)] {
        propertyCases += 1
        if let frame = CandidatePanelGeometry.frame(caret: anchor, size: size, screen: screen) {
          propertyPlaced += 1
          if !screen.contains(frame) || frame.intersects(anchor.insetBy(dx: -4, dy: -4)) {
            propertyViolations += 1
            if propertyViolations <= 5 { print("PROPERTY_VIOLATION screen=\(screen) caret=\(anchor) frame=\(frame) contained=\(screen.contains(frame)) overlap=\(frame.intersects(anchor.insetBy(dx: -4, dy: -4)))") }
          }
        } else {
          // These screens all have sufficient vertical room for these sizes.
          let fitsAboveOrBelow = anchor.minY - screen.minY >= size.height + 4 || screen.maxY - anchor.maxY >= size.height + 4
          if fitsAboveOrBelow {
            propertyViolations += 1
            if propertyViolations <= 5 { print("PROPERTY_MISSING screen=\(screen) caret=\(anchor) size=\(size)") }
          }
        }
      }
    }
  }
}
check(propertyViolations == 0, "\(propertyCases) deterministic geometry cases bounded/nonoverlapping/placed when possible (placed=\(propertyPlaced))")
var movingCaret = caret
var movingView = RimeView(); movingView.candidates = ordinary.map { ($0, "") }
panel.show(movingView, below: caret, vertical: true, refreshCaret: { movingCaret })
if let window = app.windows.first(where: { $0.isVisible }) {
  let original = window.frame
  movingCaret.origin.x += 60
  movingCaret.origin.y += 40
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
  check(window.frame != original, "visible panel refreshes caret geometry without a key")
  check(!window.frame.intersects(movingCaret.insetBy(dx: -4, dy: -4)), "refreshed panel excludes new caret")
  movingCaret = .zero
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
  check(!window.isVisible, "invalid refreshed caret dismisses panel")
  movingCaret = caret
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
  check(!window.isVisible, "cancelled refresh cannot resurrect hidden panel")
} else { check(false, "caret-refresh fixture visible") }
// The AppDelegate shares one panel across controller instances. A's late blur
// must not dismiss the candidates B has already shown.
let ownerA = NSObject(), ownerB = NSObject()
panel.show(movingView, below: caret, vertical: true, owner: ObjectIdentifier(ownerA))
check(app.windows.contains { $0.isVisible }, "owner A initial fixture visible")
panel.show(movingView, below: caret.offsetBy(dx: 30, dy: 0), vertical: true, owner: ObjectIdentifier(ownerB))
if let window = app.windows.first(where: { $0.isVisible }) {
  let frame = window.frame
  panel.hide(owner: ObjectIdentifier(ownerA))
  check(window.isVisible, "late owner A hide preserves owner B panel")
  check(window.frame == frame, "late owner A hide leaves owner B geometry unchanged")
  panel.show(movingView, below: .zero, vertical: true, owner: ObjectIdentifier(ownerA))
  check(window.isVisible && window.frame == frame, "invalid stale owner show cannot dismiss owner B")
  panel.show(RimeView(), below: caret, vertical: true, owner: ObjectIdentifier(ownerA))
  check(window.isVisible, "empty stale owner show cannot dismiss owner B")
  panel.hide(owner: ObjectIdentifier(ownerB))
  check(!window.isVisible, "current owner B can hide its panel")
  panel.hide(owner: ObjectIdentifier(ownerB))
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
  check(!window.isVisible, "double owner hide stays hidden")
} else { check(false, "shared-owner fixture visible") }
panel.hide()
// Replacing a repeating timer stops the old client query, but leaves B's alive.
var oldQueries = 0, newQueries = 0
panel.show(movingView, below: caret, vertical: true, owner: ObjectIdentifier(ownerA), refreshCaret: {
  oldQueries += 1
  return caret
})
check(app.windows.contains { $0.isVisible }, "old timer fixture visible")
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
check(oldQueries > 0, "old timer runs before replacement")
let oldQueriesAtReplacement = oldQueries
panel.show(movingView, below: caret, vertical: true, owner: ObjectIdentifier(ownerB), refreshCaret: {
  newQueries += 1
  return caret.offsetBy(dx: 40, dy: 0)
})
if let window = app.windows.first(where: { $0.isVisible }) {
  panel.hide(owner: ObjectIdentifier(ownerA))
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
  check(oldQueries == oldQueriesAtReplacement, "replacement cancels previous owner's repeating timer")
  check(newQueries > 0 && window.isVisible, "stale hide does not cancel current owner's refresh")
  panel.hide()
  panel.hide()
  let queriesAtHide = newQueries
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
  check(!window.isVisible && newQueries == queriesAtHide, "double global hide cancels timer without resurrection")
} else { check(false, "replacement timer fixture visible") }
// A refresh may finish after it has synchronously caused a newer presentation
// (for example through an IMK client's reentrant callback). Its nil result is stale.
var didReplaceDuringRefresh = false
panel.show(movingView, below: caret, vertical: true, owner: ObjectIdentifier(ownerA), refreshCaret: {
  if !didReplaceDuringRefresh {
    didReplaceDuringRefresh = true
    panel.show(movingView, below: caret.offsetBy(dx: 80, dy: 0), vertical: true, owner: ObjectIdentifier(ownerB))
  }
  return nil
})
if let window = app.windows.first(where: { $0.isVisible }) {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
  check(didReplaceDuringRefresh, "reentrant refresh fixture executes original callback")
  check(window.isVisible, "stale refresh result cannot hide a new owner presentation")
} else { check(false, "reentrant refresh fixture visible") }
panel.hide()
// The same stale-result guard must cover movement, including a new presentation
// by the same owner: owner equality alone is not a timer generation check.
var replacedFrame: NSRect?
panel.show(movingView, below: caret, vertical: true, owner: ObjectIdentifier(ownerA), refreshCaret: {
  panel.show(movingView, below: caret.offsetBy(dx: 90, dy: 0), vertical: true, owner: ObjectIdentifier(ownerA))
  replacedFrame = app.windows.first(where: { $0.isVisible })?.frame
  return caret.offsetBy(dx: -90, dy: 0)
})
if let window = app.windows.first(where: { $0.isVisible }) {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
  check(replacedFrame != nil, "same-owner reentrant movement fixture executes")
  check(window.isVisible && window.frame == replacedFrame, "stale valid refresh cannot move replacement presentation")
  NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
  check(!window.isVisible, "global workspace dismissal still hides owned presentation")
} else { check(false, "same-owner reentrant movement fixture visible") }
panel.show(movingView, below: caret, vertical: true, owner: ObjectIdentifier(ownerB))
if let window = app.windows.first(where: { $0.isVisible }) {
  panel.show(movingView, below: .zero, vertical: true, owner: ObjectIdentifier(ownerB))
  check(!window.isVisible, "invalid current-owner show hides its stale panel")
} else { check(false, "invalid current-owner fixture visible") }
panel.hide()
check(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore, "frontmost PID unchanged")
print("CANDIDATE_PANEL checks=\(checks) failures=\(failures)")
exit(failures == 0 ? 0 : 1)
