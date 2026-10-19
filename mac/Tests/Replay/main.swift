import Foundation
// Replays the exact (keycode, mask) pairs KINFXInputController sends for a macOS
// key sequence, through the same Engine, and prints commit + preedit per key.
//   kx-replay <shared> <user> <seq>   seq tokens: letters/digits, SP, SHIFT_DOWN, SHIFT_UP, ^X (shift+X)
let a = CommandLine.arguments
let e = Engine(sharedDir: a[1], userDir: a[2])
try e.start()
let s = e.newSession()
var out = ""
var mods: RimeKeys.Mods = []
func send(_ r: (Int32, Int32)?, _ label: String) {
  guard let (k, m) = r else { print(label, "-> unmapped"); return }
  let eaten = e.key(s, k, m)
  let c = e.takeCommit(s) ?? ""
  out += c
  let v = e.view(s)
  print(String(format: "%-10@ k=%x m=%x eaten=%d commit=[%@] preedit=[%@] cand1=[%@]", label, k, m, eaten ? 1 : 0, c, v.preedit, v.candidates.first?.text ?? ""))
}
let vk: [Character: UInt16] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
for t in a[3].split(separator: " ").map(String.init) {
  switch t {
  case "SP": send(RimeKeys.keyDown(keyCode: 49, chars: " ", bare: " ", mods: mods), t)
  case "SHIFT_DOWN": mods.insert(.shift); send(RimeKeys.flagsChanged(keyCode: 56, mods: mods), t)
  case "SHIFT_UP": mods.remove(.shift); send(RimeKeys.flagsChanged(keyCode: 56, mods: mods), t)
  case "SHIFT_ON": mods.insert(.shift)   // shift held, but no flagsChanged delivered
  case "SHIFT_OFF": mods.remove(.shift)
  case "RSHIFT_DOWN": mods.insert(.shift); send(RimeKeys.flagsChanged(keyCode: 60, mods: mods), t)
  case "RSHIFT_UP": mods.remove(.shift); send(RimeKeys.flagsChanged(keyCode: 60, mods: mods), t)
  case _ where t.hasPrefix("K:"):  // raw rime key: K:<keycode hex>:<mask hex>
    let p = t.split(separator: ":")
    send((Int32(p[1], radix: 16)!, Int32(p[2], radix: 16)!), t)
  default:
    for ch in t {
      let low = Character(ch.lowercased())
      send(RimeKeys.keyDown(keyCode: vk[low] ?? 0, chars: String(ch), bare: String(low), mods: mods), String(ch))
    }
  }
}
print("APP TEXT [\(out)]")
