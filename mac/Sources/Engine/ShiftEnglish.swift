import Foundation

/// Decides when a held Shift should turn a short Sucheng composition into English.
///
/// Why this exists: on current macOS the input method controller never receives
/// `flagsChanged`, so a bare Shift tap cannot be detected at all (measured: 0
/// events in kx-trace.log while typing). Shift is only visible as a modifier flag
/// on the next key down. So the reachable gesture is **Shift + letter**: when the
/// pending composition is one or two code letters, commit it as English and type
/// the letter instead of appending another code.
///
/// Deliberately narrow, so ordinary Sucheng input is untouched:
/// - only with Shift held (no Control/Option/Command),
/// - only while a composition of 1–2 ASCII letters is pending,
/// - only for a printable ASCII key (letters, digits, common punctuation).
enum ShiftEnglish {
  static func shouldCommit(preedit: String, mods: RimeKeys.Mods, chars: String?) -> Bool {
    guard mods.contains(.shift) else { return false }
    guard !mods.contains(.control), !mods.contains(.option), !mods.contains(.command) else { return false }
    guard let chars = chars, chars.count == 1, let scalar = chars.unicodeScalars.first else { return false }
    guard scalar.isASCII, scalar.value >= 0x20, scalar.value != 0x7f else { return false }
    let code = preedit.trimmingCharacters(in: .whitespaces)
    guard (1...2).contains(code.count) else { return false }
    return code.allSatisfy { $0.isASCII && $0.isLetter }
  }

  /// A shifted run continues after the first commit: every further Shift+key must be
  /// typed straight into the document, not appended to a new composition.
  /// Caps Lock is deliberately ignored here — the character the OS produced already
  /// carries the right case (Shift+A -> A, Caps Lock+Shift+A -> a, Caps Lock+A -> A).
  static func shouldTypeDirectly(chars: String?, mods: RimeKeys.Mods, continuing: Bool) -> Bool {
    guard mods.contains(.shift), !mods.contains(.control), !mods.contains(.option), !mods.contains(.command) else { return false }
    guard let chars = chars, chars.count == 1, let scalar = chars.unicodeScalars.first else { return false }
    guard scalar.isASCII, scalar.value >= 0x20, scalar.value != 0x7f else { return false }
    return continuing
  }
}
