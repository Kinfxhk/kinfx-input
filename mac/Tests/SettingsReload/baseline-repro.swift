import Cocoa
import InputMethodKit
final class QuietPanel {
 func hide(owner:ObjectIdentifier){}
 func show(_ v:RimeView,below:NSRect,vertical:Bool,owner:ObjectIdentifier,refreshCaret:@escaping ()->NSRect?){}
}
final class AppDelegate:NSObject,NSApplicationDelegate {static var engine:Engine!;static let panel=QuietPanel();@objc func showSettings(){}}
let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
let root=CommandLine.arguments[1];AppDelegate.engine=Engine(sharedDir:root+"/data",userDir:root+"/controller-user")
let e=AppDelegate.engine!;try e.start();var failures=0
func check(_ ok:Bool,_ name:String,_ detail:[String:Any]=[:]) {var r=detail;r["case"]=name;r["pass"]=ok;print(String(data:try! JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]),encoding:.utf8)!);if !ok{failures += 1}}
let codes:[Character:Int]=["v":9,"d":2,"a":0,"s":1,"x":7,"z":6,"e":14,"b":11,"h":4,"l":37,"o":31,"1":18,"2":19,".":47," ":49]
final class Fixture {
 let c=KINFXInputController(server:nil,delegate:nil,client:nil)!
 let t=QAClient(frame:NSRect(x:0,y:0,width:800,height:200))
 var sid:UInt {Mirror(reflecting:c).children.first{$0.label=="session"}!.value as! UInt}
 var shadow:String {Mirror(reflecting:c).children.first{$0.label=="pendingLetters"}!.value as! String}
 func type(_ text:String){for ch in text {_ = c.inputText(String(ch),key:codes[ch]!,modifiers:0,client:t)}}
 func key(_ code:Int,_ text:String="",_ flags:NSEvent.ModifierFlags=[]){_ = c.inputText(text,key:code,modifiers:Int(flags.rawValue),client:t)}
 deinit {c.commitComposition(t)}
}
func children(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap(children)}
let w=SettingsWindow(engine:e);w.alphaValue=0
func change(_ key:String,_ index:Int){let p=children(w.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.identifier?.rawValue==key}!;p.selectItem(at:index);precondition(p.sendAction(p.action,to:p.target))}
func status()->String{((w.contentView as! NSStackView).views[1] as! NSTextField).stringValue}
func raw(_ h:UInt)->UInt {if let m=Mirror(reflecting:e).children.first(where:{$0.label=="sessions"})?.value as? [UInt:UInt]{return m[h] ?? 0};return h}
func prop(_ h:UInt,_ key:String)->String {guard let p=kx_property(raw(h),key) else{return ""};defer{free(p)};return String(cString:p)}
let f=Fixture();f.key(49," ",.shift);f.type("hello");f.key(36,"\r");precondition(f.t.string=="hello")
let path=e.sharedDir+"/kinfx_quick.schema.yaml",valid=try String(contentsOfFile:e.sharedDir+"/kinfx_quick.schema.yaml",encoding:.utf8)
try "schema: [broken\n".write(toFile:path,atomically:true,encoding:.utf8)
change("page_size",1)
let failedStatus=status(),failedAlive=e.alive(f.sid),failedOwner=prop(f.sid,"kinfx_english_state")
try valid.write(toFile:path,atomically:true,encoding:.utf8)
change("page_size",0)
let retryStatus=status()
f.type("vd1")
check(f.t.string=="hello好","actual-controller-settings-failure-retry-preserves-Chinese",["text":f.t.string,"failedStatus":failedStatus,"retryStatus":retryStatus,"failedAlive":failedAlive,"failedOwner":failedOwner,"currentOwner":prop(f.sid,"kinfx_english_state"),"preedit":e.view(f.sid).preedit])
f.key(53);w.close();exit(failures==0 ? 0:1)
