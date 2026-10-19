import Foundation

// Debug trace to <user dir>/log/kx-trace.log, on only when that log dir holds a
// file named "trace-on". Unified logging redacts NSLog text from this process.
enum Trace {
  static var dir: String?
  static func log(_ s: @autoclosure () -> String) {
    guard let d = dir, FileManager.default.fileExists(atPath: d + "/trace-on") else { return }
    let line = "\(Date()) \(s())\n"
    let p = d + "/kx-trace.log"
    if let h = FileHandle(forWritingAtPath: p) {
      h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
      try? line.write(toFile: p, atomically: false, encoding: .utf8)
    }
  }
}
