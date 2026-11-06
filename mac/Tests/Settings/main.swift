import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: settings-test <repo-root> <scratch>") }
let root = args[1], scratch = args[2]
var checks = 0, failures = 0
func check(_ condition: Bool, _ name: String) {
  checks += 1; if !condition { failures += 1 }
  print("\(condition ? "PASS" : "FAIL") \(name)")
}
let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: root + "/settings-spec.json"))) as! [String: Any]
let shared = object["settings"] as! [[String: Any]]
check(Set(Settings.specs.map(\.key)) == Set(shared.map { $0["key"] as! String }), "Swift exposes exactly the shared setting keys")
for entry in shared {
  let key = entry["key"] as! String
  let spec = Settings.specs.first { $0.key == key }
  let options = entry["options"] as! [[String]]
  check(spec?.options.map(\.value) == options.map { $0[0] }, "\(key) options/default match shared spec")
  check(spec?.rimeKey == entry["rime_key"] as? String, "\(key) Rime key matches shared spec")
}
let defaultsFile = root + "/settings.default.json"
check(Settings.load(defaultsFile)["short_blur"] == "letters", "letters is short blur default")
let path = scratch + "/settings-roundtrip.json"
var values = Settings.defaults(); values["short_blur"] = "commit"
try Settings.save(values, to: path)
check(Settings.load(path)["short_blur"] == "commit", "explicit commit persists")
check(Settings.rimeCustom(Settings.load(path)).contains("\"english/blur_short\": commit"), "explicit commit reaches Rime patch")
try "{\"short_blur\":\"invalid\"}".write(toFile: path, atomically: true, encoding: .utf8)
check(Settings.load(path)["short_blur"] == "letters", "invalid short blur falls back to letters")
let engine = Engine(sharedDir: scratch + "/unused", userDir: scratch + "/settings-window")
try FileManager.default.createDirectory(atPath: engine.userDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(atPath: engine.settingsPath)
let window = SettingsWindow(engine: engine)
window.alphaValue = 0
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let controls = descendants(window.contentView!).compactMap { $0 as? NSPopUpButton }
check(controls.count == shared.count, "actual SettingsWindow renders one popup per shared setting")
let popup = controls.first { $0.identifier?.rawValue == "short_blur" }
check(popup?.itemTitles == ["保留英文字母", "上屏首選字"], "actual short blur popup offers both labels")
check(popup?.indexOfSelectedItem == 0, "actual short blur popup defaults to letters")
if let popup = popup {
  popup.selectItem(at: 1)
  check(popup.sendAction(popup.action, to: popup.target), "actual popup action dispatches")
  check(Settings.load(engine.settingsPath)["short_blur"] == "commit", "actual popup action saves commit")
  let patch = try String(contentsOfFile: engine.customPath, encoding: .utf8)
  check(patch.contains("\"english/blur_short\": commit"), "actual popup action generates commit patch")
  let reopened = SettingsWindow(engine: engine); reopened.alphaValue = 0
  let restored = descendants(reopened.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "short_blur" }
  check(restored?.indexOfSelectedItem == 1, "reopened actual SettingsWindow restores commit")
}
check(NSWorkspace.shared.frontmostApplication?.processIdentifier == front, "frontmost PID unchanged")
print("SETTINGS checks=\(checks) failures=\(failures)")
exit(failures == 0 ? 0 : 1)
