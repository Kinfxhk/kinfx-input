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
check("no numeric tunables exposed", String(Settings.specs.contains { $0.rimeKey.contains("min") }), "false")
try? FileManager.default.removeItem(atPath: tmp)

// Key mapping.
func km(_ r: (Int32, Int32)?) -> String { r.map { String(format: "%x/%x", $0.0, $0.1) } ?? "nil" }
check("letter", km(RimeKeys.keyDown(keyCode: 9, chars: "v", bare: "v", mods: [])), "76/0")
check("shift+4", km(RimeKeys.keyDown(keyCode: 21, chars: "$", bare: "4", mods: .shift)), "24/1")
check("ctrl+v", km(RimeKeys.keyDown(keyCode: 9, chars: "\u{16}", bare: "v", mods: .control)), "76/4")
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

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
