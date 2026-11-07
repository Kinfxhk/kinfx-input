import Cocoa
import InputMethodKit

// Execute the production controller and trace with real NSEvents. No window,
// keyboard injection, registered input source, client text or daily data is used.
guard CommandLine.arguments.count == 2 else { fatalError("expected private output directory") }
let root = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
Trace.dir = root
let enabled = root + "/trace-on"
try Data().write(to: URL(fileURLWithPath: enabled))
guard let controller = KINFXInputController(server: nil, delegate: nil, client: nil) else {
  fatalError("required controller fixture was not constructed")
}
for type in [NSEvent.EventType.flagsChanged, .keyDown, .keyUp] {
  guard let event = NSEvent.keyEvent(with: type, location: .zero,
    modifierFlags: .shift, timestamp: 0, windowNumber: 0, context: nil,
    characters: "A", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 56) else {
    fatalError("required real NSEvent fixture was not constructed")
  }
  precondition(!controller.handle(event, client: nil), "nil client must not handle input")
}
precondition(!controller.handle(nil, client: nil), "nil event must not handle input")
let trace = try String(contentsOfFile: root + "/kx-trace.log", encoding: .utf8)
let lines = trace.components(separatedBy: "\n").filter { $0.contains("handle type=") }
precondition(lines.count == 4, "every supplied event must be traced")
precondition(lines.contains { $0.contains("type=12 key=56 chars= flags=20000") },
  "modifier trace must retain key/type/flags without reading characters")
precondition(lines.contains { $0.contains("type=10 key=56 chars=A flags=20000") })
precondition(lines.contains { $0.contains("type=11 key=56 chars=A flags=20000") })
precondition(lines.contains { $0.contains("type=0 key=0 chars= flags=0") })
try FileManager.default.removeItem(atPath: enabled)
let bytesBefore = try Data(contentsOf: URL(fileURLWithPath: root + "/kx-trace.log"))
guard let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero,
  modifierFlags: .shift, timestamp: 0, windowNumber: 0, context: nil,
  characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56) else {
  fatalError("required trace-off event fixture was not constructed")
}
precondition(!controller.handle(event, client: nil))
let bytesAfter = try Data(contentsOf: URL(fileURLWithPath: root + "/kx-trace.log"))
precondition(bytesBefore == bytesAfter, "disabled trace must not write")
print("TRACE PASS: flagsChanged/keyDown/keyUp/nil, trace-on and trace-off; not system IMK acceptance")
