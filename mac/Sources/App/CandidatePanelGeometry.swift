import Foundation

/// AppKit screen coordinates (including negative display origins). No fallback to
/// the main screen: an off-desktop or malformed client rectangle must not leave
/// candidates at an unrelated application's origin.
enum CandidatePanelGeometry {
  static let gap: CGFloat = 4

  static func screen(for caret: CGRect, in screens: [CGRect]) -> CGRect? {
    guard finite(caret), caret.size.width >= 0, caret.size.height > 0 else { return nil }
    let line = CGRect(x: caret.minX, y: caret.minY, width: max(1, caret.width), height: caret.height)
    var best: CGRect?
    var area: CGFloat = 0
    for screen in screens where finite(screen) && screen.width > 0 && screen.height > 0 {
      let overlap = screen.intersection(line)
      let candidateArea = overlap.isNull ? 0 : overlap.width * overlap.height
      if candidateArea > area { best = screen; area = candidateArea }
    }
    return best
  }

  static func frame(caret: CGRect, size: CGSize, screen: CGRect) -> CGRect? {
    guard finite(caret), finite(screen), size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0,
          size.width <= screen.width, size.height <= screen.height else { return nil }
    let x = min(max(caret.minX, screen.minX), screen.maxX - size.width)
    let y = min(max(caret.minY, screen.minY), screen.maxY - size.height)
    // Prefer below then above, without ever clamping a window back onto the line.
    let origins = [CGPoint(x: x, y: floor(caret.minY - gap) - size.height),
                   CGPoint(x: x, y: ceil(caret.maxY + gap)),
                   CGPoint(x: ceil(caret.maxX + gap), y: y),
                   CGPoint(x: floor(caret.minX - gap) - size.width, y: y)]
    let exclusion = caret.insetBy(dx: -gap, dy: -gap)
    // Strict separation avoids treating floating-point edge contact as overlap.
    return origins.map { CGRect(origin: $0, size: size) }.first { panel in
      screen.contains(panel) && (panel.maxY <= caret.minY - gap || panel.minY >= caret.maxY + gap ||
        panel.maxX <= exclusion.minX || panel.minX >= exclusion.maxX)
    }
  }

  private static func finite(_ r: CGRect) -> Bool {
    [r.origin.x, r.origin.y, r.size.width, r.size.height, r.maxX, r.maxY].allSatisfy { $0.isFinite }
  }
}
