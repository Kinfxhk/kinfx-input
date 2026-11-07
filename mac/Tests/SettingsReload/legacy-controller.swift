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
do {let a=Fixture(),b=Fixture();a.type("asxe");b.type("abxx");precondition(a.t.string=="昨xe" && b.t.string=="明xx");change("page_size",1);a.c.commitComposition(a.t);b.c.commitComposition(b.t);check(a.t.string=="昨xe" && b.t.string=="明xx","full-controller-two-client-text-survives",["A":a.t.string,"B":b.t.string]);a.type("vd1");b.type("vd1");check(a.t.string=="昨xe好" && b.t.string=="明xx好","full-controller-same-session-next-input",["A":a.t.string,"B":b.t.string])}
do {let f=Fixture();f.type("hello");change("page_size",0);f.key(36,"\r");check(f.t.string=="hello" && status()=="已套用。","full-controller-normal-Return-completes-reload",["text":f.t.string,"status":status()]);f.type("vd");check(e.view(f.sid).pageSize==9,"full-controller-next-menu-new-settings")}
do {let f=Fixture();f.type("hello");change("page_size",1);f.type(" ");f.type(".");check(f.t.string=="hello .","reload-preserves-idle-Latin-punctuation-context",["text":f.t.string])}
for (end,code,text) in [("Escape",53,""),("Return",36,"\r"),("digit-pick",18,"1")] {
 do {let f=Fixture();f.type("vd");precondition(f.shadow=="vd");f.key(code,text);let before=f.t.string;let sh=f.shadow;f.c.commitComposition(f.t);check(sh.isEmpty && f.t.string==before,"production-update-invalidates-shadow-"+end,["shadow":sh,"before":before,"after":f.t.string])}
}
do {let f=Fixture();f.half();f.type("vd");f.key(49," ",.control);let before=f.t.string;f.c.commitComposition(f.t);check(f.t.string==before && f.shadow.isEmpty,"production-mode-toggle-no-stale-replay",["before":before,"after":f.t.string])}
// Focus-style native disappearance, unlike a normal controller key/update:
// existing October safeguard must stay. This is injection, not OS IMK proof.
do {let f=Fixture();f.type("vd");precondition(f.shadow=="vd");e.clear(f.sid);precondition(e.view(f.sid).preedit.isEmpty);f.c.commitComposition(f.t);check(f.t.string=="vd" && f.shadow.isEmpty,"known-focus-empty-keeps-unfinished-letters",["text":f.t.string])}
for mode in ["letters","commit"] { for wide in [false,true] {
 change("short_blur",mode=="letters" ? 0:1)
 do {let f=Fixture();f.half();if wide {f.key(49," ",.shift)};f.type("vd");precondition(!e.view(f.sid).preedit.isEmpty);change("page_size",0);f.c.commitComposition(f.t);check(f.t.string==(mode=="letters" ? "vd":"好"),"settings-short-"+mode+"-full="+String(wide),["text":f.t.string])}
 do {let f=Fixture();f.half();if wide {f.key(49," ",.shift)};f.type("xz");f.key(123);f.key(36,"\r");precondition(e.view(f.sid).preedit=="難z");change("page_size",1);f.c.commitComposition(f.t);check(f.t.string==(wide ? "難ｚ":"難z"),"settings-selected-prefix-"+mode+"-full="+String(wide),["text":f.t.string])}
}}
change("short_blur",0)
// Parent: prove actual runtime width and idle script context through a real settings action.
for reload in [false,true] {
 do {let f=Fixture();f.half();f.key(49," ",.shift);f.type("hello");f.key(36,"\r");precondition(f.t.string=="hello");let beforeWidth=kx_option(e.nativeSession(f.sid),"full_shape");if reload {change("page_size",0)};let afterWidth=kx_option(e.nativeSession(f.sid),"full_shape");check(beforeWidth==1 && afterWidth==1,"parent-native-full-shape-proof-"+String(reload),["before":beforeWidth,"after":afterWidth]);f.type(".");check(f.t.string=="hello.","parent-idle-Latin-punctuation-reload-"+String(reload),["text":f.t.string]);f.key(53)}
}
// Parent matrix: three idle states, both widths, real settings action, same handles.
for wide in [false,true] { for reload in [false,true] {
 do {let a=Fixture(),b=Fixture(),cleared=Fixture();a.half();b.half();cleared.half();if wide {a.key(49," ",.shift);b.key(49," ",.shift);cleared.key(49," ",.shift)};a.type("hello");a.key(36,"\r");b.type("vd1");b.key(49," ",.control);b.key(49," ",.control);cleared.type("hello");cleared.key(36,"\r");cleared.key(53);precondition(a.t.string=="hello" && b.t.string=="好" && cleared.t.string=="hello");let old=[a.sid,b.sid,cleared.sid];if reload {change("page_size",1)};let widths=[a,b,cleared].map{kx_option(e.nativeSession($0.sid),"full_shape")};check(widths.allSatisfy{$0==(wide ? 1:0)},"matrix-runtime-width-full-"+String(wide)+"-reload-"+String(reload),["widths":widths]);a.type(".");b.type(".");cleared.type(".");check(a.t.string=="hello.","matrix-Latin-full-"+String(wide)+"-reload-"+String(reload),["text":a.t.string]);check(b.t.string==(wide ? "好。":"好."),"matrix-Chinese-full-"+String(wide)+"-reload-"+String(reload),["text":b.t.string]);check(cleared.t.string==(wide ? "hello。":"hello."),"matrix-clear-full-"+String(wide)+"-reload-"+String(reload),["text":cleared.t.string]);check(old==[a.sid,b.sid,cleared.sid],"matrix-stable-three-owners-full-"+String(wide)+"-reload-"+String(reload));a.key(53);b.key(53);cleared.key(53)}
}}
weak var gone:SettingsWindow?
autoreleasepool {var z:SettingsWindow?=SettingsWindow(engine:e);gone=z;z?.close();z=nil}
check(gone==nil,"full-appkit-settings-window-released")
w.close();exit(failures==0 ? 0:1)
