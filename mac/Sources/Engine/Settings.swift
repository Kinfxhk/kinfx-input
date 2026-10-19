import Foundation

// The only user settings. Every shell (macOS now; iPad / Android / Windows later)
// reads and writes the same settings.json keys and values.
struct SettingSpec {
  let key: String
  let label: String
  let options: [(value: String, label: String)]  // options[0] is the default
  let rimeKey: String?  // nil = shell-only setting (not passed to Rime)
}

enum Settings {
  static let specs: [SettingSpec] = [
    SettingSpec(key: "page_size", label: "每頁候選數",
                options: [("9", "9 個"), ("5", "5 個")], rimeKey: "menu/page_size"),
    SettingSpec(key: "english_space", label: "英文詞後按空白",
                options: [("safe", "安全詞上屏"), ("long", "只限長詞"), ("off", "關閉")], rimeKey: "english/space"),
    SettingSpec(key: "association", label: "聯想詞",
                options: [("true", "開啟"), ("false", "關閉")], rimeKey: "association/enable"),
    SettingSpec(key: "space_after_pick", label: "選字後按空白",
                options: [("type", "輸入空格"), ("page", "翻頁")], rimeKey: "association/space"),
    SettingSpec(key: "phrase_capture", label: "常用詞前綴",
                options: [("hot", "熱門"), ("all", "全部"), ("off", "關閉")], rimeKey: "phrase_mix/capture"),
    SettingSpec(key: "empty_shift", label: "未輸入時按左 Shift",
                options: [("noop", "不動作"), ("ascii", "臨時英文")], rimeKey: "english/empty_shift"),
    SettingSpec(key: "preedit", label: "預編輯顯示",
                options: [("letters", "字母"), ("radicals", "字根")], rimeKey: "english/preedit"),
    SettingSpec(key: "candidate_layout", label: "選字表",
                options: [("vertical", "直排"), ("horizontal", "橫排")], rimeKey: nil),
  ]

  static func defaults() -> [String: String] {
    Dictionary(uniqueKeysWithValues: specs.map { ($0.key, $0.options[0].value) })
  }

  // settings.json is a trust boundary: unknown keys are dropped, bad values fall back to the default.
  static func load(_ path: String) -> [String: String] {
    var s = defaults()
    guard let data = FileManager.default.contents(atPath: path),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return s }
    for spec in specs {
      guard let raw = obj[spec.key] else { continue }
      let v: String
      if let b = raw as? Bool, CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID() { v = b ? "true" : "false" }
      else if let n = raw as? NSNumber { v = n.stringValue }
      else if let str = raw as? String { v = str }
      else { continue }
      if spec.options.contains(where: { $0.value == v }) { s[spec.key] = v }
    }
    return s
  }

  static func save(_ s: [String: String], to path: String) throws {
    var obj: [String: Any] = [:]
    for spec in specs {
      let v = s[spec.key] ?? spec.options[0].value
      switch spec.key {
      case "page_size": obj[spec.key] = Int(v) ?? 9
      case "association": obj[spec.key] = (v == "true")
      default: obj[spec.key] = v
      }
    }
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  // Rime patch generated from the settings; the user never sees it.
  static func rimeCustom(_ s: [String: String]) -> String {
    var out = "# 由 KINFX Input 設定視窗產生，請勿手動修改。\npatch:\n"
    for spec in specs {
      guard let rimeKey = spec.rimeKey else { continue }
      var v = s[spec.key] ?? spec.options[0].value
      if spec.key == "phrase_capture" && v == "off" { v = "none" }
      out += "  \"\(rimeKey)\": \(v)\n"
    }
    return out
  }
}
