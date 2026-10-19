import Cocoa
// Renders the menu-bar icon (a 速 glyph) to a TIFF: make-icon.swift <out.tiff>
let size = NSSize(width: 16, height: 16)
let img = NSImage(size: size)
img.lockFocus()
let font = NSFont(name: "PingFang HK", size: 14) ?? .systemFont(ofSize: 14)
let s = NSAttributedString(string: "速", attributes: [.font: font, .foregroundColor: NSColor.black])
let b = s.size()
s.draw(at: NSPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2))
img.unlockFocus()
img.isTemplate = true
try! img.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
