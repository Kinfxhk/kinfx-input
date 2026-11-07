import Foundation

// Headless production Engine/RimeKeys replay, not OS/IMK event delivery.
let args = CommandLine.arguments
 guard args.count == 4 else { fatalError("engine-tests shared scratch results.json") }
let engine = Engine(sharedDir: args[1], userDir: args[2])
try engine.start()
var checks = 0, failures = 0
var rows: [[String: Any]] = []
func check(_ condition: Bool, _ name: String) {
  checks += 1
  if !condition { failures += 1 }
  print("\(condition ? "PASS" : "FAIL") \(name)")
}
func raw(_ session: UInt) -> String {
  guard let p = test_raw_input(engine.nativeSession(session)) else { return "" }
  defer { free(p) }
  return String(cString: p)
}
func snapshot(_ session: UInt, _ label: String, _ output: String, _ handled: Bool? = nil) -> [String: Any] {
  let view = engine.view(session)
  var result: [String: Any] = ["step": label, "full_shape": test_full_shape(engine.nativeSession(session)) != 0,
    "commit": output, "preedit": view.preedit, "raw_input": raw(session),
    "candidates": view.candidates.map(\.text), "page": view.pageNo]
  if let handled = handled { result["handled"] = handled }
  return result
}
func seed(_ text: String, _ session: UInt) -> String {
  var out = ""
  for c in text.unicodeScalars {
    _ = engine.key(session, Int32(c.value), CharacterSet.uppercaseLetters.contains(c) ? 1 : 0)
    out += engine.takeCommit(session) ?? ""
  }
  return out
}
check(engine.started, "real engine starts in scratch")
for display in ["letters", "radicals"] {
  var settings = Settings.defaults(); settings["preedit"] = display
  try engine.apply(settings)
  for releaseMask: Int32 in [1 << 30, (1 << 30) | 1] {
    for (state, keys) in [("Idle", ""), ("Short", "vd"), ("Long", "hello"),
                          ("Domain", "openai.com"), ("Dot", "hello."),
                          ("Dash", "hello-"), ("Rescue", "asxz"), ("Unknown", "abcd"),
                          ("Associating", "vd1"),
                          ("LiteralEnglish", "hello")] {
      let session = engine.newSession()
      check(session != 0, "\(display)/\(state) session created")
      test_set_full_shape(engine.nativeSession(session), 0)
      var out = ""
      if state == "LiteralEnglish" {
        check(engine.key(session, 0x20, RimeKeys.control), "\(display) Control+Space enters literal English")
        check(!engine.key(session, 0x68, 0), "\(display) English letter passes through to app")
        out += engine.takeCommit(session) ?? ""
        out += seed("ello", session)
        check(out.isEmpty && raw(session).isEmpty, "\(display) literal English creates no Rime composition/commit")
      } else {
        out = seed(keys, session)
      }
      let before = engine.view(session)
      let originalOutput = out, originalRaw = raw(session)
      let originalCandidates = before.candidates.map(\.text)
      if state == "Associating" { check(!originalCandidates.isEmpty && out == "好", "\(display) starts in real association state") }
      if state == "Short" || state == "Long" { check(!before.preedit.isEmpty, "\(display)/\(state) starts composing") }
      var steps = [snapshot(session, "before", out)]
      for (index, expected) in [true, false].enumerated() {
        let name = "\(display)/\(state)/\(releaseMask)/\(index+1)"
        var widthApplied = index == 1
        let mapping = RimeKeys.keyDown(keyCode: 49, chars: " ", bare: " ", mods: .shift)!
        check(!ShiftEnglish.shouldCommit(preedit: before.preedit, mods: .shift, chars: " "), "\(name) avoids English-start route")
        check(!ShiftEnglish.shouldTypeDirectly(chars: " ", mods: .shift, continuing: true), "\(name) avoids continuing-literal route")
        for (label, code, mask) in [("Shift-down", Int32(0xffe1), RimeKeys.shift),
                                    ("Space-down", mapping.0, mapping.1),
                                    ("Space-up", Int32(0x20), releaseMask | 1),
                                    ("Shift-up", Int32(0xffe1), releaseMask)] {
          let handled = engine.key(session, code, mask)
          out += engine.takeCommit(session) ?? ""
          steps.append(snapshot(session, "\(label)-\(index+1)", out, handled))
          if label == "Space-down" {
            check(handled, "\(name) chord reaches key_binder")
            widthApplied = expected
          }
          // Deferred punctuation is a native punctuation candidate: the
          // width option legitimately retranslates its glyph, never the word.
          let punctuation = state == "Dot" ? "." : state == "Dash" ? "-" : nil
          let widePunctuation = state == "Dot" ? "。" : "－"
          let wantCandidates = punctuation != nil && widthApplied ? [widePunctuation] : originalCandidates
          let wantPreedit = punctuation != nil && widthApplied && display == "radicals"
            ? "hello" + widePunctuation : before.preedit
          check(out == originalOutput, "\(name)/\(label) never commits")
          check(raw(session) == originalRaw, "\(name)/\(label) preserves raw input")
          check(engine.view(session).preedit == wantPreedit, "\(name)/\(label) preserves preedit except requested punctuation width")
          check(engine.view(session).candidates.map(\.text) == wantCandidates, "\(name)/\(label) preserves menu/order except requested punctuation width")
        }
        check((test_full_shape(engine.nativeSession(session)) != 0) == expected, "\(name) width -> \(expected)")
      }
      rows.append(["display": display, "state": state, "keys": keys, "releaseMask": releaseMask, "steps": steps])
      if state == "Associating" {
        _ = engine.key(session, 0x31, RimeKeys.shift)
        out += engine.takeCommit(session) ?? ""
        check(out == "好似", "\(display) Shift+1 still selects after width round-trip")
      } else if state != "Idle" && state != "LiteralEnglish" {
        check(engine.blur(session) == keys, "\(display)/\(state) full run survives width round-trip until blur")
      }
      engine.destroy(session)
    }
  }
  // Control paths use exact outputs, not vacuous 'must not equal' assertions.
  for (label, initial, events, want) in [
    ("Space", "vd", [(Int32(0x20), Int32(0)), (0x31, 0)], "嫻"),
    ("Enter", "vd", [(Int32(0xff0d), Int32(0))], "好"),
    ("Shift9", "vd1", [(Int32(0xffe1), Int32(1)), (0x39, 1), (0xffe1, 1 << 30)], "好(")
  ] {
    let session = engine.newSession()
    test_set_full_shape(engine.nativeSession(session), 0)
    var out = seed(initial, session)
    for (code, mask) in events { _ = engine.key(session, code, mask); out += engine.takeCommit(session) ?? "" }
    check(test_full_shape(engine.nativeSession(session)) == 0, "\(display) ordinary \(label) never toggles width")
    check(out == want, "\(display) ordinary \(label) retains Sucheng output: \(String(reflecting: out))")
    rows.append(["display": display, "state": "Normal-\(label)", "steps": [snapshot(session, label, out)]])
    engine.destroy(session)
  }
}
let result: [String: Any] = ["method": "headless real librime production Engine/RimeKeys; complete synthesized Shift/Space press-release lifecycle, no OS delivery", "checks": checks, "failures": failures, "rows": rows]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
print("ENGINE SHIFTSPACE checks=\(checks) failures=\(failures)")
exit(failures == 0 ? 0 : 1)
