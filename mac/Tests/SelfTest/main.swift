import Foundation

// Command-line self-test: same Engine, Settings and key mapping as the input method,
// against the bundled data in a throwaway user dir.
// usage: kinfx-selftest <shared_dir> <scratch_user_dir>
var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
  let ok = got == want
  if !ok { failures += 1 }
  print("\(ok ? "PASS" : "FAIL") \(name): got [\(got)] want [\(want)]")
}

// Settings: defaults, bad input, round trip, Rime patch.
let tmp = NSTemporaryDirectory() + "kx-settings-\(getpid()).json"
try "{\"page_size\": 7, \"association\": false, \"bogus\": 1, \"preedit\": \"radicals\"}".write(toFile: tmp, atomically: true, encoding: .utf8)
var s = Settings.load(tmp)
check("bad page_size falls back", s["page_size"]!, "9")
check("bool read", s["association"]!, "false")
check("string read", s["preedit"]!, "radicals")
s["page_size"] = "5"
try Settings.save(s, to: tmp)
check("round trip", Settings.load(tmp)["page_size"]!, "5")
let saved = try String(contentsOfFile: tmp, encoding: .utf8)
check("json keeps types", String(saved.contains("\"page_size\" : 5") && saved.contains("\"association\" : false")), "true")
check("capture off maps to none", String(Settings.rimeCustom(["phrase_capture": "off"]).contains("\"phrase_mix/capture\": none")), "true")
check("no numeric tunables exposed", String(Settings.specs.contains { $0.rimeKey?.contains("min") == true }), "false")
check("candidate layout default vertical", Settings.defaults()["candidate_layout"]!, "vertical")
check("layout not sent to rime", String(Settings.rimeCustom(Settings.defaults()).contains("layout")), "false")
try? FileManager.default.removeItem(atPath: tmp)

// Key mapping.
func km(_ r: (Int32, Int32)?) -> String { r.map { String(format: "%x/%x", $0.0, $0.1) } ?? "nil" }
check("letter", km(RimeKeys.keyDown(keyCode: 9, chars: "v", bare: "v", mods: [])), "76/0")
check("shift+4", km(RimeKeys.keyDown(keyCode: 21, chars: "$", bare: "4", mods: .shift)), "24/1")
check("ctrl+v", km(RimeKeys.keyDown(keyCode: 9, chars: "\u{16}", bare: "v", mods: .control)), "76/4")
check("ctrl+v from inputText (control char as bare)", km(RimeKeys.keyDown(keyCode: 9, chars: "\u{16}", bare: "\u{16}", mods: .control)), "76/4")
check("space", km(RimeKeys.keyDown(keyCode: 49, chars: " ", bare: " ", mods: [])), "20/0")
check("left shift down", km(RimeKeys.flagsChanged(keyCode: 56, mods: .shift)), "ffe1/1")
check("left shift up", km(RimeKeys.flagsChanged(keyCode: 56, mods: [])), "ffe1/40000000")

// Engine.
let args = CommandLine.arguments
guard args.count == 3 else { print("usage: kinfx-selftest <shared_dir> <scratch_user_dir>"); exit(2) }
let engine = Engine(sharedDir: args[1], userDir: args[2])
try? FileManager.default.removeItem(atPath: engine.settingsPath)
try engine.start()
check("engine started", String(engine.started), "true")

func type(_ keys: String) -> (commit: String, view: RimeView) {
  let sess = engine.newSession()
  defer { engine.destroy(sess) }
  var out = ""
  for ch in keys.unicodeScalars {
    _ = engine.key(sess, Int32(ch.value), 0)
    if let c = engine.takeCommit(sess) { out += c }
  }
  return (out, engine.view(sess))
}

check("vd1", type("vd1").commit, "好")
check("vd1 Return reaches app (assoc closes, not eaten)", { () -> String in
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  for k: Int32 in [0x76, 0x64, 0x31] { _ = engine.key(sess, k, 0) }
  _ = engine.takeCommit(sess)
  return String(engine.key(sess, 0xff0d, 0)) + "/" + String(engine.view(sess).candidates.isEmpty)
}(), "false/true")
let v9 = type("vd").view
check("default page_size", String(v9.pageSize), "9")
check("default first page count", String(v9.candidates.count), "9")
check("vd first page", v9.candidates.map(\.text).joined(), "好她妹紆巢媒彙綑綵")

var five = Settings.load(engine.settingsPath)
five["page_size"] = "5"
try engine.apply(five)
let v5 = type("vd").view
check("page_size after apply 5", String(v5.pageSize), "5")
check("first page count after apply 5", String(v5.candidates.count), "5")
check("vd1 still 好 at 5", type("vd1").commit, "好")
check("vd space 1 at 5 (page 2)", { () -> String in
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  for k: Int32 in [0x76, 0x64, 0x20, 0x31] { _ = engine.key(sess, k, 0) }
  return engine.takeCommit(sess) ?? ""
}(), "媒")

five["page_size"] = "9"
try engine.apply(five)
check("page_size back to 9", String(type("vd").view.pageSize), "9")
check("english word", type("iPhone ").commit, "iPhone ")

// 0.1.1 English fixes (engine/rime/lua/english_mix.lua).
func typeKeys(_ keys: [Int32]) -> String {
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  var out = ""
  for k in keys { _ = engine.key(sess, k, 0); if let c = engine.takeCommit(sess) { out += c } }
  return out
}
let ret: Int32 = 0xff0d
// 0.1.9 made half-width punctuation the default; linux/selftest.py already expects
// "hello." / "thanks?", so these two mac expectations were the stale side of that change.
check("word . chinese", type("hello.vd1").commit, "hello.\u{597D}")
check("domain stays latin", type("openai.com ").commit, "openai.com ")
check("file name stays latin", type("llama.cpp ").commit, "llama.cpp ")
check("5-letter prefix + space stays chinese", type("fogge 1").commit, "\u{708A}\u{572D}\u{6C34}")
check("word Enter", typeKeys([0x68, 0x65, 0x6c, 0x6c, 0x6f, ret]), "hello")
check("chinese Enter unchanged", typeKeys([0x76, 0x64, ret]), "\u{597D}")
check("word ?", type("thanks?").commit, "thanks?")
check("contraction", type("don't ").commit, "don't ")
check("gg space", type("gg ").commit, "gg ")
check("gg1 still chinese", type("gg1").commit, "\u{572D}")
check("ez space still pages", type("ez ").commit, "")
check("/init space", type("/init ").commit, "/init ")

// 0.1.2: paste mid-composition keeps the held top-outs (Windows model), drops the letters.
check("held top-outs flush before Ctrl+V", { () -> String in
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  var out = ""
  for k: Int32 in [0x76, 0x64, 0x68, 0x65, 0x6c] { _ = engine.key(sess, k, 0); if let c = engine.takeCommit(sess) { out += c } }
  _ = engine.key(sess, 0x76, 1 << 2)
  if let c = engine.takeCommit(sess) { out += c }
  return out
}(), "\u{597D}\u{53CD}")
check("plain code drops before Ctrl+V", { () -> String in
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  var out = ""
  for k: Int32 in [0x76, 0x64] { _ = engine.key(sess, k, 0); if let c = engine.takeCommit(sess) { out += c } }
  _ = engine.key(sess, 0x76, 1 << 2)
  if let c = engine.takeCommit(sess) { out += c }
  return out
}(), "")
check("ofc1", type("ofc1").commit, "\u{4EBA}\u{985E}")

// 0.1.4: focus left (F35) keeps what was typed, then vd1 still types.
// v0.1.11: a 1–2 letter run keeps its letters on blur (english/blur_short=letters);
// the earlier Windows behaviour commits the first candidate and is still available
// by setting english/blur_short: commit.
for (keys, want) in [("hel", "hel"), ("vdhel", "vdhel"), ("vd", "vd"), ("vd1hel", "\u{597D}hel"),
                     ("ofca", "ofca"), ("he", "he"), ("as", "as"), ("a", "a")] {
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  var out = ""
  for ch in keys.unicodeScalars { _ = engine.key(sess, Int32(ch.value), 0); if let c = engine.takeCommit(sess) { out += c } }
  out += engine.blur(sess) ?? ""
  for k: Int32 in [0x76, 0x64, 0x31] { _ = engine.key(sess, k, 0); if let c = engine.takeCommit(sess) { out += c } }
  check("\(keys) blur keeps text", out, want + "\u{597D}")
}


// Shift + letter on a short composition (ShiftEnglish). A bare Shift tap never
// reaches the controller on current macOS (0 flagsChanged events), so this is the
// gesture the controller can actually see.
for (pre, mods, key, want) in [
  ("a", RimeKeys.Mods.shift, "x", true),
  ("as", RimeKeys.Mods.shift, "x", true),
  ("as", RimeKeys.Mods.shift, "1", true),
  ("asd", RimeKeys.Mods.shift, "x", false),
  ("as", [], "x", false),
  ("as", [.shift, .command], "x", false),
  ("", RimeKeys.Mods.shift, "x", false),
  ("as", RimeKeys.Mods.shift, "\u{4E2D}", false),
] {
  let got = ShiftEnglish.shouldCommit(preedit: pre, mods: mods, chars: key)
  check("shift-english preedit=\(pre) key=\(key)", got ? "true" : "false", want ? "true" : "false")
}

// The commit the controller triggers: press+release Left Shift through the engine.
func shiftTap(_ sess: UInt) -> String {
  _ = engine.key(sess, 0xffe1, 1)
  _ = engine.key(sess, 0xffe1, 0x40000000)
  return engine.takeCommit(sess) ?? ""
}
for (keys, want) in [("a", "a"), ("as", "as"), ("abc", "abc"), ("abcd", "abcd"), ("abcde", "abcde")] {
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  for ch in keys.unicodeScalars { _ = engine.key(sess, Int32(ch.value), 0); _ = engine.takeCommit(sess) }
  check("\(keys) + shift tap stays literal", shiftTap(sess), want)
}


// A shifted run after the commit: further keys are typed literally, with the case
// the OS produced (Caps Lock on/off is handled by the OS, not by us).
for (chars, mods, cont, want) in [
  ("B", RimeKeys.Mods.shift, true, true),
  ("b", RimeKeys.Mods.shift, true, true),
  (";", RimeKeys.Mods.shift, true, true),
  (" ", RimeKeys.Mods.shift, true, false),
  ("b", [], true, false),
  ("b", RimeKeys.Mods.shift, false, false),
  ("b", [.shift, .command], true, false),
] {
  let got = ShiftEnglish.shouldTypeDirectly(chars: chars, mods: mods, continuing: cont)
  check("shift-run chars=\(chars) cont=\(cont)", got ? "true" : "false", want ? "true" : "false")
}

// Shift+Space is reserved for Rime's full_shape toggle: shouldCommit must never
// fire for a space, so the width command reaches the engine unchanged. Other
// printable ASCII keys (! 1 …) keep the existing short-code English gesture.
for (preedit, chars, mods, expected) in [
  ("of", " ", RimeKeys.Mods.shift, false),
  ("of", "!", RimeKeys.Mods.shift, true),
  ("of", "1", RimeKeys.Mods.shift, true),
  ("hel", " ", RimeKeys.Mods.shift, false),
  ("", " ", RimeKeys.Mods.shift, false),
  ("of", " ", [.shift, .command], false),
  ("人火", " ", RimeKeys.Mods.shift, false),
] {
  check("legacy Shift collision preedit=\(preedit) chars=\(String(reflecting: chars)) mods=\(mods.rawValue)",
        String(ShiftEnglish.shouldCommit(preedit: preedit, mods: mods, chars: chars)), String(expected))
}
check("ShiftSpace mapping reaches engine unchanged when not intercepted", km(RimeKeys.keyDown(keyCode: 49, chars: " ", bare: " ", mods: .shift)), "20/1")
check("Right remains Rime candidate paging key", km(RimeKeys.keyDown(keyCode: 124, chars: nil, bare: nil, mods: [])), "ff53/0")
check("Left remains Rime candidate paging key", km(RimeKeys.keyDown(keyCode: 123, chars: nil, bare: nil, mods: [])), "ff51/0")


// Space is always half-width, independent of full_shape and the preceding
// script. full_shape reset:0 defaults to half-width and now governs punctuation
// only; Shift+Space toggles punctuation full-width and persists the choice
// across sessions (the engine restores it on each new context). One fresh
// session per check; the toggle checks net back to half-width.
func typeSeq(_ keys: [(Int32, Int32)]) -> String {
  let sess = engine.newSession(); defer { engine.destroy(sess) }
  var out = ""
  for (k, m) in keys { _ = engine.key(sess, k, m); if let c = engine.takeCommit(sess) { out += c } }
  return out
}
func letters(_ s: String) -> [(Int32, Int32)] { s.unicodeScalars.map { (Int32($0.value), 0) } }
let shiftSpace: [(Int32, Int32)] = [(0xffe1, 1), (0x20, 1), (0x20, (1 << 30) | 1), (0xffe1, 1 << 30)]
// Space is half-width everywhere, even after CJK or a bare digit run.
check("space hao half-width", typeSeq(letters("vd1") + [(0xff1b, 0), (0x20, 0)]), "好\u{0020}")
check("space hao two half-width", typeSeq(letters("vd1") + [(0xff1b, 0), (0x20, 0), (0x20, 0)]), "好\u{0020}\u{0020}")
check("space bare 60 two half-width", typeSeq(letters("60") + [(0x20, 0), (0x20, 0)]), "60\u{0020}\u{0020}")
check("space hello. half-width", typeSeq(letters("hello.") + [(0x20, 0)]), "hello. ")
check("space 60cm half-width", typeSeq(letters("60cm") + [(0x20, 0)]), "60cm ")
// Punctuation follows full_shape (default half-width).
check("comma hao half-width default", typeSeq(letters("vd1") + [(0x2c, 0)]), "好\u{002c}")
check("comma hello half-width", typeSeq(letters("hello") + [(0x2c, 0)]), "hello,")
// Shift+Space toggles punctuation full-width; space stays half-width.
check("toggle full comma full-width", typeSeq(shiftSpace + letters("vd1") + [(0x2c, 0)]), "好\u{ff0c}")
check("toggle full space still half-width", typeSeq(shiftSpace + letters("vd1") + [(0xff1b, 0), (0x20, 0)]), "好\u{0020}")
// full_shape + select-and-space: `abcd` splits to Sucheng pairs (明銖) and
// Space commits 明銖 + " " in ONE commit. That trailing space must stay U+0020
// under full_shape — Space is always half-width, width only affects punctuation.
// Ensure full_shape for these three, then net back to half so the width checks
// below still start from the default half-width.
do {
  let s0 = engine.newSession()
  if engine.globalFullShape == 0 { for (k, m) in shiftSpace { _ = engine.key(s0, k, m) }; _ = engine.takeCommit(s0) }
  engine.destroy(s0)
  check("toggle full abcd space half-width", typeSeq(letters("abcd") + [(0x20, 0)]), "明銖\u{0020}")
  check("toggle full vd space still pages", typeSeq(letters("vd") + [(0x20, 0)]), "")
  check("toggle full hello space half-width", typeSeq(letters("hello") + [(0x20, 0)]), "hello\u{0020}")
  let s1 = engine.newSession()
  if engine.globalFullShape == 1 { for (k, m) in shiftSpace { _ = engine.key(s1, k, m) }; _ = engine.takeCommit(s1) }
  engine.destroy(s1)
}

// full_shape global persistence: bidirectional broadcast to an already-typed
// existing owner, new-owner restore (destroy A / open B), and shortcut no-persist.
// These mirror linux/test-fullshape-global.py, which is the headless-verified side;
// the state-file fail-closed cases (invalid/unreadable/unwritable) live there too.
func toggleWidth(_ sess: UInt) {
  for (k, m) in shiftSpace { _ = engine.key(sess, k, m) }
  _ = engine.takeCommit(sess)
}
func width(_ sess: UInt) -> Int32 { kx_option(engine.nativeSession(sess), "full_shape") }
do {
  let a = engine.newSession(), b = engine.newSession()
  for k: Int32 in [0x76, 0x64, 0x31] { _ = engine.key(b, k, 0); _ = engine.takeCommit(b) }
  toggleWidth(a) // half -> full
  check("broadcast half->full follows typed B", String(width(b)), "1")
  toggleWidth(a) // full -> half
  check("broadcast full->half follows typed B", String(width(b)), "0")
  engine.destroy(a); engine.destroy(b)
}
do {
  let a = engine.newSession()
  toggleWidth(a) // half -> full (global = 1)
  engine.destroy(a)
  let b = engine.newSession()
  check("destroy A then new B restores global before first key", String(width(b)), "1")
  engine.destroy(b)
}
do {
  let s = engine.newSession()
  toggleWidth(s) // global -> full
  let before = width(s)
  _ = engine.key(s, 0x20, 1 << 2)         // Ctrl+Space (ascii_mode, not width)
  _ = engine.key(s, 0x20, 1 << 3)         // Alt+Space
  _ = engine.key(s, 0x20, 1 << 26)        // Super+Space
  _ = engine.key(s, 0x20, (1 << 30) | 1)  // Shift+Space release
  _ = engine.key(s, 0x20, (1 << 2) | 1)   // Ctrl+Shift+Space
  _ = engine.key(s, 0x20, (1 << 3) | 1)   // Alt+Shift+Space
  _ = engine.key(s, 0x20, (1 << 26) | 1)  // Super+Shift+Space
  _ = engine.takeCommit(s)
  check("shortcut chords never flip width", String(width(s)), String(before))
  let st = (try? String(contentsOfFile: engine.fullShapeStatePath, encoding: .ascii))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "<missing>"
  check("shift-combined chords never persist width", st, String(before))
  engine.destroy(s)
}

// The formatter's width_internal bypass (an English commit under full_shape
// briefly sets full_shape=false to render half-width, then restores it) is a
// temporary rendering switch, never a user toggle: it must not flip nor persist
// the global width.
do {
  let s = engine.newSession()
  if engine.globalFullShape == 0 { toggleWidth(s) } // ensure full (1) so the bypass triggers
  var out = ""
  for k: Int32 in [0x68, 0x65, 0x6c, 0x6c, 0x6f, 0xff0d] { // "hello" + Return
    _ = engine.key(s, k, 0); if let c = engine.takeCommit(s) { out += c }
  }
  check("english word stays half-width under full_shape", out, "hello")
  check("formatter bypass does not flip global width", String(engine.globalFullShape), "1")
  let st = (try? String(contentsOfFile: engine.fullShapeStatePath, encoding: .ascii))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "<missing>"
  check("formatter bypass does not persist width", st, "1")
  engine.destroy(s)
}

// A failed redeploy keeps the idle snapshot; after the schema is repaired, the
// explicit retry must restore the owner following the global width (full), not
// the schema default (half).
do {
  let s = engine.newSession()
  if engine.globalFullShape == 0 { toggleWidth(s) } // ensure global is full (1)
  let schemaPath = args[1] + "/kinfx_quick.schema.yaml"
  let valid = (try? String(contentsOfFile: schemaPath, encoding: .utf8)) ?? ""
  try? "schema: [broken\n".write(toFile: schemaPath, atomically: true, encoding: .utf8)
  var five = Settings.load(engine.settingsPath); five["page_size"] = "5"
  try engine.apply(five)   // explicit reload -> fails (broken schema)
  check("failed reload keeps owner reservation", String(engine.ownsSession(s)), "true")
  try? valid.write(toFile: schemaPath, atomically: true, encoding: .utf8)
  var nine = Settings.load(engine.settingsPath); nine["page_size"] = "9"
  try engine.apply(nine)   // explicit retry -> rebuilds
  check("failed-retry width follows global", String(width(s)), "1")
  engine.destroy(s)
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
