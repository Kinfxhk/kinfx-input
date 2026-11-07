import Foundation

// Dedicated contract regression. No IMK registration, input-source selection,
// live settings, or keyboard events. --start/--continuing/--wiring are TDD slices.
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "--start"
var checks = 0, failures = 0
func check(_ condition: Bool, _ name: String) {
  checks += 1
  if !condition { failures += 1 }
  print("\(condition ? "PASS" : "FAIL") \(name)")
}

if mode == "--start" || mode == "--all" {
  for preedit in ["a", "of", "hello", "", "人火"] {
    for mods: RimeKeys.Mods in [.shift, [.shift, .capsLock]] {
      check(!ShiftEnglish.shouldCommit(preedit: preedit, mods: mods, chars: " "),
            "ShiftSpace never starts English commit preedit=\(preedit) mods=\(mods.rawValue)")
    }
  }
  check(ShiftEnglish.shouldCommit(preedit: "of", mods: .shift, chars: "A"), "Shift+letter retains existing short-code gesture")
  for symbol in ["!", "$", "1", ";"] {
    check(ShiftEnglish.shouldCommit(preedit: "of", mods: .shift, chars: symbol), "non-space printable \(symbol) is not narrowed")
  }
  for mods: RimeKeys.Mods in [[], .control, .command, [.shift, .control], [.shift, .option], [.shift, .command]] {
    check(!ShiftEnglish.shouldCommit(preedit: "of", mods: mods, chars: " "), "Space/chords do not start English mods=\(mods.rawValue)")
  }
  let mapped = RimeKeys.keyDown(keyCode: 49, chars: " ", bare: " ", mods: .shift)
  check(mapped?.0 == 0x20 && mapped?.1 == RimeKeys.shift, "physical ShiftSpace maps to Rime space/shift")
}

if mode == "--continuing" || mode == "--all" {
  for continuing in [false, true] {
    for mods: RimeKeys.Mods in [.shift, [.shift, .capsLock]] {
      check(!ShiftEnglish.shouldTypeDirectly(chars: " ", mods: mods, continuing: continuing),
            "ShiftSpace never becomes literal space continuing=\(continuing) mods=\(mods.rawValue)")
    }
  }
  for text in ["A", "a", "!", "1", ";"] {
    check(ShiftEnglish.shouldTypeDirectly(chars: text, mods: .shift, continuing: true), "existing shifted literal \(text) retained")
    check(!ShiftEnglish.shouldTypeDirectly(chars: text, mods: .shift, continuing: false), "idle shifted \(text) still reaches engine")
  }
  check(!ShiftEnglish.shouldTypeDirectly(chars: " ", mods: [], continuing: true), "ordinary Space remains engine-routed")
  check(!ShiftEnglish.shouldTypeDirectly(chars: "\r", mods: .shift, continuing: true), "Enter remains engine-routed")
}

if mode == "--wiring" || mode == "--all" {
  guard args.count > 2 else { fatalError("--wiring/--all requires repository root") }
  let root = args[2]
  let source = try String(contentsOfFile: root + "/mac/Sources/App/InputController.swift", encoding: .utf8)
  // Verify the real controller terminates stale Shift state before its early return.
  // This is a source-wiring assertion, NOT an IMK/OS-event integration claim.
  let reset = source.range(of: "if !mods.contains(.shift) || k == 0x20 { shiftRun = false }")
  let direct = source.range(of: "if ShiftEnglish.shouldTypeDirectly(")
  check(reset != nil && direct != nil && reset!.lowerBound < direct!.lowerBound,
        "actual controller ends shiftRun on width command before direct-insert branch")
  check(source.contains("let handled = engine.key(session, k, m)"), "actual controller retains original engine key/mask fallthrough")
  check(source.contains("RimeKeys.keyDown(keyCode: keyCode, chars: chars, bare: bare, mods: mods)"), "both IMK entry points retain production key mapping")
}

print("SHIFTSPACE checks=\(checks) failures=\(failures) mode=\(mode)")
exit(failures == 0 ? 0 : 1)
