import Foundation

// macOS key event -> Rime keycode (X11 keysym) and mask. Pure, so the self-test covers it.
enum RimeKeys {
  static let shift: Int32 = 1 << 0
  static let lock: Int32 = 1 << 1
  static let control: Int32 = 1 << 2
  static let alt: Int32 = 1 << 3
  static let superMask: Int32 = 1 << 26
  static let release: Int32 = 1 << 30

  struct Mods: OptionSet {
    let rawValue: Int
    static let shift = Mods(rawValue: 1)
    static let control = Mods(rawValue: 2)
    static let option = Mods(rawValue: 4)
    static let command = Mods(rawValue: 8)
    static let capsLock = Mods(rawValue: 16)
  }

  static func mask(_ m: Mods) -> Int32 {
    var r: Int32 = 0
    if m.contains(.shift) { r |= shift }
    if m.contains(.capsLock) { r |= lock }
    if m.contains(.control) { r |= control }
    if m.contains(.option) { r |= alt }
    if m.contains(.command) { r |= superMask }
    return r
  }

  // kVK_* virtual key codes that are not characters.
  static let special: [UInt16: Int32] = [
    36: 0xff0d, 76: 0xff0d, 48: 0xff09, 49: 0x20, 51: 0xff08, 117: 0xffff, 53: 0xff1b,
    123: 0xff51, 124: 0xff53, 125: 0xff54, 126: 0xff52,
    115: 0xff50, 119: 0xff57, 116: 0xff55, 121: 0xff56,
  ]

  static let modifierKeys: [UInt16: (Int32, Mods)] = [
    56: (0xffe1, .shift), 60: (0xffe2, .shift),
    59: (0xffe3, .control), 62: (0xffe4, .control),
    58: (0xffe9, .option), 61: (0xffea, .option),
    55: (0xffeb, .command), 54: (0xffec, .command),
  ]

  // keyDown: `chars` is event.characters, `bare` is charactersIgnoringModifiers.
  static func keyDown(keyCode: UInt16, chars: String?, bare: String?, mods: Mods) -> (Int32, Int32)? {
    if let k = special[keyCode] { return (k, mask(mods)) }
    // Control / Option / Command change `characters`; Rime wants the base key.
    var text = mods.intersection([.control, .option, .command]).isEmpty ? chars : bare?.lowercased()
    // inputText(_:key:modifiers:) hands over the control character itself (Ctrl+V = U+0016): use its letter.
    if mods.contains(.control), let u = text?.unicodeScalars.first, text?.unicodeScalars.count == 1,
       (1...26).contains(u.value) { text = String(UnicodeScalar(u.value + 0x60)!) }
    guard let t = text, t.unicodeScalars.count == 1, let u = t.unicodeScalars.first,
          u.value >= 0x20, u.value < 0x7f else { return nil }
    return (Int32(u.value), mask(mods))
  }

  // flagsChanged: a modifier went down (it is in `mods` now) or up.
  static func flagsChanged(keyCode: UInt16, mods: Mods) -> (Int32, Int32)? {
    guard let (k, flag) = modifierKeys[keyCode] else { return nil }
    if mods.contains(flag) { return (k, mask(mods)) }
    return (k, mask(mods) | release)
  }
}
