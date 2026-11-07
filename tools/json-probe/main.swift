import Foundation

// Headless production Engine/RimeKeys key replay that emits one JSON object per
// invocation: {"commit","steps","localeStart","localeEnd"}. `steps` holds one
// entry per [keycode, mask] event; the last stdout line is the JSON object.
//
// Locale self-attestation (the fix): the harness must prove the probe PROCESS
// itself ran under the requested LC_CTYPE (C vs a UTF-8 locale), not a Python
// sidecar. We therefore call setlocale(LC_CTYPE, getenv("LC_CTYPE")) up front
// (env-only propagation never changes libc ctype state) and report, from this
// process, setlocale(LC_CTYPE, NULL) plus a ctype positive control at BOTH
// start and end of the run. isalpha(0xba) is 0 under C and 1 under a UTF-8
// locale on macOS, so localeStart/localeEnd let the harness verify that the
// locale held for the whole run and that C vs UTF-8 are genuinely distinct.
//
// Build (test-harness only; links the production Engine + librime, no product
// code change):
//   swiftc -O -swift-version 5 -sdk "$(xcrun --show-sdk-path)" \
//     -target "$(uname -m)-apple-macos13.0" \
//     -import-objc-header mac/Sources/Shim/kx_shim.h \
//     -I "$RIME_DIST/include" \
//     mac/Sources/Engine/*.swift tools/json-probe/main.swift \
//     kx_shim.o -L "$RIME_DIST/lib" -lrime \
//     -Xlinker -rpath -Xlinker "$RIME_DIST/lib" -o json-probe
func localeAttest() -> [String: Any] {
    let req = getenv("LC_CTYPE").map { String(cString: $0) } ?? ""
    let eff = setlocale(LC_CTYPE, nil).map { String(cString: $0) } ?? ""
    return ["requested": req, "effective": eff, "isalphaBA": isalpha(Int32(0xba)) != 0 ? 1 : 0]
}

let a = CommandLine.arguments
if let lc = getenv("LC_CTYPE") {
    setlocale(LC_CTYPE, lc)
}
let localeStart = localeAttest()
let e = Engine(sharedDir: a[1], userDir: a[2])
try e.start()
let s = e.newSession()
let ev = try JSONSerialization.jsonObject(with: Data(a[3].utf8)) as! [[Int]]
var out = ""
var steps: [[String: Any]] = []
for p in ev {
    let h = e.key(s, Int32(p[0]), Int32(p[1]))
    let c = e.takeCommit(s) ?? ""
    out += c
    let v = e.view(s)
    steps.append(["key": p[0], "mask": p[1], "handled": h, "commit": c,
                  "preedit": v.preedit, "pageSize": v.pageSize,
                  "candidates": v.candidates.map(\.text)])
}
e.destroy(s)
let localeEnd = localeAttest()
let d = try JSONSerialization.data(
    withJSONObject: ["commit": out, "steps": steps,
                     "localeStart": localeStart, "localeEnd": localeEnd],
    options: [.sortedKeys])
print(String(data: d, encoding: .utf8)!)
