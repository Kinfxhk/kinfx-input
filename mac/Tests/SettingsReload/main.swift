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
 func half(){if sid==0 {_ = c.inputText("",key:53,modifiers:0,client:t)};kx_set_option(e.nativeSession(sid),"full_shape",0)}
 var shadow:String {Mirror(reflecting:c).children.first{$0.label=="pendingLetters"}!.value as! String}
 func type(_ text:String){for ch in text {_ = c.inputText(String(ch),key:codes[ch]!,modifiers:0,client:t)}}
 func key(_ code:Int,_ text:String="",_ flags:NSEvent.ModifierFlags=[]){_ = c.inputText(text,key:code,modifiers:Int(flags.rawValue),client:t)}
 deinit {c.commitComposition(t)}
}
func children(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap(children)}
let w=SettingsWindow(engine:e);w.alphaValue=0
func change(_ key:String,_ index:Int){let p=children(w.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.identifier?.rawValue==key}!;p.selectItem(at:index);precondition(p.sendAction(p.action,to:p.target))}
func status()->String{((w.contentView as! NSStackView).views[1] as! NSTextField).stringValue}
func raw(_ h:UInt)->UInt {guard let m=Mirror(reflecting:e).children.first{$0.label=="sessions"}?.value as? [UInt:UInt] else{return h};return m[h] ?? 0}
func prop(_ h:UInt,_ key:String)->String {guard let p=kx_property(raw(h),key) else{return ""};defer{free(p)};return String(cString:p)}
let front=NSWorkspace.shared.frontmostApplication?.processIdentifier
let schema=e.sharedDir+"/kinfx_quick.schema.yaml", valid=try String(contentsOfFile:e.sharedDir+"/kinfx_quick.schema.yaml",encoding:.utf8)
func breakSchema() throws {try "schema: [broken\n".write(toFile:schema,atomically:true,encoding:.utf8);let readback=try String(contentsOfFile:schema,encoding:.utf8);precondition(readback=="schema: [broken\n")}
func restoreSchema() throws {try valid.write(toFile:schema,atomically:true,encoding:.utf8)}
// Hosted full production controller, real SettingsWindow popup sendAction and native Rime.
// No system IMK, no OS-key dispatch. Keep one owner across failure AND retry.
do {
 let f=Fixture();f.half();f.key(49," ",.shift);f.type("hello");f.key(36,"\r")
 precondition(f.t.string=="hello" && kx_option(raw(f.sid),"full_shape")==1 && prop(f.sid,"kinfx_punct_tail")=="latin")
 let handle=f.sid
 try breakSchema();change("page_size",1)
 check(status().contains("失敗"),"actual-popup-failure-truthful",["status":status()])
 check(!e.alive(handle),"failed-transaction-no-alive-schema-less-session",["alive":e.alive(handle),"owner":prop(handle,"kinfx_english_state")])
 let rejected=kx_session("kinfx_quick");check(rejected==0,"malformed-requested-schema-native-session-rejected",["session":rejected]);kx_destroy(rejected)
 try restoreSchema();change("page_size",0)
 check(status()=="已套用。","same-owner-explicit-popup-retry-applies",["status":status()])
 check(f.sid==handle && kx_option(raw(handle),"full_shape")==1 && prop(handle,"kinfx_punct_tail")=="latin","same-owner-width-tail-preserved",["handle":f.sid,"native":raw(handle),"width":kx_option(raw(handle),"full_shape"),"tail":prop(handle,"kinfx_punct_tail")])
 f.type(".")
 check(f.t.string=="hello.","period-before-Chinese-after-retry",["text":f.t.string])
 f.type("vd1")
 check(f.t.string=="hello.好","same-full-controller-retry-next-Chinese-pick",["text":f.t.string,"preedit":e.view(f.sid).preedit])
 f.key(53)
}

// A dead native session outside the settings transaction is still replaceable.
do {let f=Fixture();f.type("hello");f.key(36,"\r");kx_destroy(raw(f.sid));f.type("vd1");check(f.t.string=="hello好","unrelated-dead-session-still-reopens",["text":f.t.string]);f.key(53)}
// Different document contexts and widths must not migrate between owners.
do {
 let a=Fixture(),b=Fixture(),cleared=Fixture();a.half();b.half();cleared.half()
 a.key(49," ",.shift);a.type("hello");a.key(36,"\r")
 b.type("vd1");b.key(49," ",.control);b.key(49," ",.control)
 cleared.key(49," ",.shift);cleared.type("hello");cleared.key(36,"\r");cleared.key(53)
 precondition(a.t.string=="hello" && b.t.string=="好" && cleared.t.string=="hello")
 let handles=[a.sid,b.sid,cleared.sid]
 let switches=["ascii_mode","full_shape","simplification","ascii_punct"]
 // Complementary values cover every schema switch in one transaction.
 for (i,k) in switches.enumerated() where k != "full_shape" {kx_set_option(raw(a.sid),k,Int32(i%2));kx_set_option(raw(b.sid),k,Int32((i+1)%2))}
 let expected=[a,b,cleared].map{f in switches.map{kx_option(raw(f.sid),$0)}}
 try breakSchema();change("page_size",1)
 check(handles.allSatisfy{!e.alive($0)},"three-owner-failure-no-live-replacements")
 // No dictionary is claimed, and neither existing nor new controllers can
 // enqueue stale commits. QA models the app's ordinary unhandled-key fallback.
 let handled=a.c.inputText("2",key:19,modifiers:0,client:a.t)
 if !handled {a.t.insertText("2",replacementRange:NSRange(location:NSNotFound,length:0))}
 check(!handled && a.t.string=="hello2" && a.sid==handles[0] && a.shadow.isEmpty,"failed-owner-literal-fallback-keeps-handle",["text":a.t.string,"handled":handled,"status":status()])
 let fresh=Fixture();let accepted=fresh.c.inputText("v",key:9,modifiers:0,client:fresh.t)
 if !accepted {fresh.t.insertText("v",replacementRange:NSRange(location:NSNotFound,length:0))}
 check(!accepted && fresh.t.string=="v" && fresh.sid==0 && status().contains("失敗"),"new-controller-during-failure-no-dictionary-claim",["text":fresh.t.string,"status":status()])
 check(e.newSession()==0,"failed-state-newSession-refused")
 a.c.commitComposition(a.t)
 check(a.t.string=="hello2" && status().contains("失敗"),"failed-blur-no-queued-text-or-auto-retry",["text":a.t.string,"status":status()])
 try restoreSchema()
 // Merely restoring the source, draining, clearing or requesting a new session
 // is not an explicit retry and must not turn the UI green.
 _ = e.takeCommit(a.sid);e.clear(a.sid)
 check(e.newSession()==0 && status().contains("失敗"),"failed-state-waits-for-explicit-settings-action")
 change("page_size",0)
 check(status()=="已套用。" && handles==[a.sid,b.sid,cleared.sid],"three-owner-explicit-retry-stable-handles")
 let actual=[a,b,cleared].map{f in switches.map{kx_option(raw(f.sid),$0)}}
 check(expected==actual,"three-owner-four-switch-snapshot-restored",["before":expected,"after":actual])
 // Restore the test's non-default modes before exercising Chinese-mode output;
 // width and script-category snapshots themselves stay under the same owner.
 for f in [a,b,cleared] {kx_set_option(raw(f.sid),"ascii_mode",0);kx_set_option(raw(f.sid),"simplification",0);kx_set_option(raw(f.sid),"ascii_punct",0)}
 a.type(".");b.type(".");cleared.type(".")
 check(a.t.string=="hello2.","wide-Latin-tail-after-failure-retry",["text":a.t.string])
 check(b.t.string=="好.","half-Chinese-tail-after-failure-retry",["text":b.t.string])
 check(cleared.t.string=="hello。","wide-cleared-tail-after-failure-retry",["text":cleared.t.string])
 a.type("vd1");b.type("vd1");cleared.type("vd1");fresh.type("vd1")
 check(a.t.string=="hello2.好" && b.t.string=="好.好" && cleared.t.string=="hello。好" && fresh.t.string=="v好","all-controllers-Chinese-after-retry",["A":a.t.string,"B":b.t.string,"clear":cleared.t.string,"fresh":fresh.t.string])
 for f in [a,b,cleared,fresh] {f.key(53)}
}
// Destroying a failed owner releases its snapshot; monotonic handles cannot
// resurrect it in a new controller on a later retry.
do {
 var gone:Fixture?=Fixture();gone!.half();gone!.key(49," ",.shift);gone!.type("hello");gone!.key(36,"\r")
 let old=gone!.sid
 try breakSchema();change("page_size",1);gone=nil
 let saved=Mirror(reflecting:e).children.first{$0.label=="retryRuntime"}.map{Mirror(reflecting:$0.value).children.count} ?? -1
 check(saved==0 && !e.alive(old),"destroy-failed-owner-releases-snapshot",["snapshots":saved])
 try restoreSchema();change("page_size",0)
 let f=Fixture();f.half();f.type("vd1")
 check(f.sid != old && f.t.string=="好" && kx_option(raw(f.sid),"full_shape")==0 && raw(old)==0,"destroyed-owner-never-resurrected",["old":old,"new":f.sid,"text":f.t.string]);f.key(53)
}
check(NSWorkspace.shared.frontmostApplication?.processIdentifier==front,"no-frontmost-change")
w.close();exit(failures==0 ? 0:1)
