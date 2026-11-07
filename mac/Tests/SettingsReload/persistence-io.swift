import Cocoa
import InputMethodKit
final class QuietPanel {
 func hide(owner:ObjectIdentifier){}
 func show(_ v:RimeView,below:NSRect,vertical:Bool,owner:ObjectIdentifier,refreshCaret:@escaping ()->NSRect?){}
}
final class AppDelegate:NSObject,NSApplicationDelegate {static var engine:Engine!;static let panel=QuietPanel();@objc func showSettings(){}}
let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
let root=CommandLine.arguments[1];AppDelegate.engine=Engine(sharedDir:root+"/data",userDir:root+"/controller-user")
let e=AppDelegate.engine!;try e.start();try e.apply(e.settings);var failures=0
func check(_ ok:Bool,_ name:String,_ detail:[String:Any]=[:]) {var r=detail;r["case"]=name;r["pass"]=ok;print(String(data:try! JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]),encoding:.utf8)!);if !ok{failures += 1}}
let codes:[Character:Int]=["v":9,"d":2,"h":4,"e":14,"l":37,"o":31,"1":18,".":47]
final class Fixture {
 let c=KINFXInputController(server:nil,delegate:nil,client:nil)!
 let t=QAClient(frame:NSRect(x:0,y:0,width:800,height:200))
 var sid:UInt {Mirror(reflecting:c).children.first{$0.label=="session"}!.value as! UInt}
 @discardableResult func type(_ text:String)->Bool {var all=true;for ch in text {let accepted=c.inputText(String(ch),key:codes[ch]!,modifiers:0,client:t);all = accepted && all};return all}
 func key(_ code:Int,_ text:String="",_ flags:NSEvent.ModifierFlags=[]){_ = c.inputText(text,key:code,modifiers:Int(flags.rawValue),client:t)}
 deinit {c.commitComposition(t)}
}
func children(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap(children)}
let w=SettingsWindow(engine:e);w.alphaValue=0
func change(){let p=children(w.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.identifier?.rawValue=="page_size"}!;p.selectItem(at:0);precondition(p.sendAction(p.action,to:p.target))}
func status()->String{((w.contentView as! NSStackView).views[1] as! NSTextField).stringValue}
func count(_ name:String)->Int{Mirror(reflecting:e).children.first{$0.label==name}.map{Mirror(reflecting:$0.value).children.count} ?? -1}
func prop(_ h:UInt,_ key:String)->String {guard let p=kx_property(e.nativeSession(h),key) else{return ""};defer{free(p)};return String(cString:p)}
let fm=FileManager.default,front=NSWorkspace.shared.frontmostApplication?.processIdentifier
let switches=["ascii_mode","full_shape","simplification","ascii_punct"]
// Actual outer controller + SettingsWindow + unmodified native shim. The private
// custom-path directory produces real write I/O failure before any redeploy.
for existing in [false,true] {
 do {let warm=Fixture();precondition(warm.type("vd1") && warm.t.string=="好");warm.key(53)}
 precondition(count("sessions")==0)
 var owners:[Fixture]=[]
 if existing {
  let a=Fixture(),b=Fixture();a.key(49," ",.shift);a.type("hello");a.key(36,"\r");b.type("vd1");b.key(53)
  precondition(a.t.string=="hello" && b.t.string=="好");owners=[a,b]
 }
 let handles=owners.map{$0.sid},native=owners.map{e.nativeSession($0.sid)}
 let runtime=owners.map{f in switches.map{kx_option(e.nativeSession(f.sid),$0)}}
 let tails=owners.map{prop($0.sid,"kinfx_punct_tail")}
 let prefix=existing ? "existing-owners" : "zero-owners"
 try fm.removeItem(atPath:e.customPath);try fm.createDirectory(atPath:e.customPath,withIntermediateDirectories:false)
 var isDirectory:ObjCBool=false
 check(fm.fileExists(atPath:e.customPath,isDirectory:&isDirectory) && isDirectory.boolValue,prefix+"-custom-path-directory-readback")
 let oldStamp=(try fm.attributesOfItem(atPath:e.settingsPath))[.modificationDate] as! Date
 var changed=Settings.load(e.settingsPath);changed["page_size"]="5";try Settings.save(changed,to:e.settingsPath)
 try fm.setAttributes([.modificationDate:oldStamp.addingTimeInterval(2)],ofItemAtPath:e.settingsPath)
 e.reloadIfSettingsChanged()
 check(Settings.load(e.settingsPath)["page_size"]=="5" && e.settingsState == .failed && status().contains("失敗"),prefix+"-external-settings-reload-truthful-failed-UI",["status":status()])
 let direct=kx_session(Engine.schema)
 check(e.started && direct != 0 && kx_alive(direct) != 0,prefix+"-native-requested-dictionary-still-available",["direct":direct]);kx_destroy(direct)
 check(owners.map{$0.sid}==handles && owners.map{e.nativeSession($0.sid)}==native && handles.allSatisfy{e.alive($0) && e.ownsSession($0)},prefix+"-original-owners-still-ready-same-native")
 let fresh=Fixture();let accepted=fresh.type("vd1")
 check(accepted && fresh.sid != 0 && fresh.t.string=="好",prefix+"-new-production-controller-converts",["text":fresh.t.string,"handled":accepted,"handle":fresh.sid])
 check(e.settingsState == .failed && status().contains("失敗"),prefix+"-typing-does-not-hide-persistence-failure",["status":status()])
 check(owners.map{f in switches.map{kx_option(e.nativeSession(f.sid),$0)}}==runtime && owners.map{prop($0.sid,"kinfx_punct_tail")}==tails,prefix+"-own-switches-and-tail-retained")
 if existing {
  owners[0].type(".");owners[0].type("vd1");owners[1].type("vd1")
  check(owners[0].t.string=="hello.好" && owners[1].t.string=="好好",prefix+"-original-production-controllers-keep-own-output",["A":owners[0].t.string,"B":owners[1].t.string])
 }
 fresh.key(53);for f in owners{f.key(53)}
 try fm.removeItem(atPath:e.customPath);change()
 check(e.settingsState == .applied && status()=="已套用。" && (try? String(contentsOfFile:e.customPath,encoding:.utf8))==Settings.rimeCustom(e.settings),prefix+"-explicit-popup-recovery-writes-custom-and-applies",["status":status()])
 let recovered=fresh.type("vd1")
 check(recovered && fresh.t.string=="好好" && owners.map{$0.sid}==handles,prefix+"-controller-still-converts-after-explicit-recovery",["text":fresh.t.string])
 fresh.key(53)
}
// No original owners means retryRuntime is empty even after a real failed
// rebuild. Availability must stay latched until an explicit settings action.
precondition(count("sessions")==0)
let schema=e.sharedDir+"/kinfx_quick.schema.yaml",valid=try String(contentsOfFile:e.sharedDir+"/kinfx_quick.schema.yaml",encoding:.utf8)
try "schema: [broken\n".write(toFile:schema,atomically:true,encoding:.utf8)
let brokenReadback=try String(contentsOfFile:schema,encoding:.utf8);precondition(brokenReadback=="schema: [broken\n")
change()
check(e.settingsState == .failed && status().contains("失敗") && count("retryRuntime")==0,"real-failed-rebuild-with-zero-original-owners",["status":status(),"snapshots":count("retryRuntime")])
check(e.newSession()==0,"zero-owner-failed-rebuild-newSession-refused")
try valid.write(toFile:schema,atomically:true,encoding:.utf8)
// A native-only repair proves the guard is not accidentally relying on an
// empty retry map or on kx_session returning zero for malformed schema.
precondition(kx_redeploy() != 0)
let repaired=kx_session(Engine.schema);precondition(repaired != 0);kx_destroy(repaired)
let refused=Fixture();let accepted=refused.type("v")
check(!accepted && refused.sid==0 && e.newSession()==0 && status().contains("失敗"),"zero-owner-native-repair-does-not-implicitly-retry-controller",["handled":accepted,"handle":refused.sid,"status":status()])
change();refused.type("vd1")
check(status()=="已套用。" && refused.t.string=="好","zero-owner-explicit-popup-retry-restores-input",["text":refused.t.string,"status":status()]);refused.key(53)
check(NSWorkspace.shared.frontmostApplication?.processIdentifier==front,"no-frontmost-change")
w.close();exit(failures==0 ? 0:1)
