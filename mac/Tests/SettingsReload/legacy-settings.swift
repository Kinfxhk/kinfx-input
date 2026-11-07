import Cocoa
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
let root = CommandLine.arguments[1]
let e = Engine(sharedDir:root + "/data", userDir:root + "/user")
try e.start()
var failed = 0
func check(_ ok:Bool,_ name:String,_ details:[String:Any] = [:]) {
 var r=details; r["case"]=name;r["pass"]=ok
 print(String(data:try! JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]),encoding:.utf8)!)
 if !ok { failed += 1 }
}
func keys(_ s:UInt,_ text:String) {for c in text.utf8 {_ = e.key(s,Int32(c),0)}}
func descend(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap(descend)}
let w = SettingsWindow(engine:e); w.alphaValue=0
func status()->String {(w.contentView as! NSStackView).views[1].value(forKey:"stringValue") as! String}
func change(_ key:String,_ index:Int) {
 let p=descend(w.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.identifier?.rawValue==key}!
 p.selectItem(at:index);precondition(p.sendAction(p.action,to:p.target))
}
let a=e.newSession(),b=e.newSession(); keys(a,"asxe");keys(b,"abxx")
let beforeA=e.view(a).preedit,beforeB=e.view(b).preedit
precondition(beforeA=="昨xe" && beforeB=="明xx")
change("page_size",1)
check(e.alive(a) && e.alive(b) && e.view(a).preedit==beforeA && e.view(b).preedit==beforeB,"actual-action-retains-two-compositions",["A":e.view(a).preedit,"B":e.view(b).preedit])
check(status().contains("等待"),"actual-action-ui-deferred",["status":status()])
let outA=e.blur(a) ?? "";check(outA=="昨xe" && e.view(b).preedit==beforeB,"first-session-finish-retains-other",["text":outA])
let outB=e.blur(b) ?? "";check(outB=="明xx","last-session-finish-keeps-text",["text":outB])
check(status()=="已套用。","ui-updated-without-focus-cycle",["status":status()])
keys(a,"vd");check(e.view(a).pageSize==5,"same-controller-handle-new-config",["pageSize":e.view(a).pageSize]);e.clear(a);_ = e.takeCommit(a)
e.destroy(a);e.destroy(b)
// A normal Return ends composition but the native commit has NOT been read yet.
let q=e.newSession();keys(q,"hello");_=e.key(q,0xff0d,0)
precondition(e.view(q).preedit.isEmpty)
change("page_size",0)
check(status().contains("等待"),"undelivered-empty-native-queue-defers",["status":status()])
let queued=e.takeCommit(q) ?? ""
check(queued=="hello","normal-return-queue-is-not-cleared",["text":queued])
check(status()=="已套用。","normal-return-drain-applies-without-blur",["status":status()])
keys(q,"vd");check(e.view(q).pageSize==9,"same-session-after-normal-commit",["pageSize":e.view(q).pageSize]);e.clear(q);e.destroy(q)
// Every offered value goes through the real popup action, not Engine.apply alone.
for spec in Settings.specs { for (i,option) in spec.options.enumerated() {
 change(spec.key,i)
 check(Settings.load(e.settingsPath)[spec.key]==option.value && e.settings[spec.key]==option.value && status()=="已套用。","offered-value-"+spec.key+"="+option.value,["status":status()])
}}
// Explicitly saved-only mode never starts a second librime against the user's dir.
let writer=Engine(sharedDir:root+"/unused",userDir:root+"/writer")
let ww=SettingsWindow(engine:writer);ww.alphaValue=0
let wp=descend(ww.contentView!).compactMap{$0 as? NSPopUpButton}.first!
wp.selectItem(at:1);precondition(wp.sendAction(wp.action,to:wp.target))
let ws=(ww.contentView as! NSStackView).views[1].value(forKey:"stringValue") as! String
check(!writer.started && ws.contains("下次啟用"),"settings-only-process-truthful",["status":ws]);ww.close()
// Latest request wins while multiple ongoing sessions are untouched.
for spec in Settings.specs { change(spec.key,0) }
let x=e.newSession(),y=e.newSession();keys(x,"asxe");keys(y,"abxx")
change("page_size",1);change("page_size",0);change("page_size",1)
check(e.view(x).preedit=="昨xe" && e.view(y).preedit=="明xx","coalesced-changes-keep-two-sessions")
e.destroy(x)
check(status().contains("等待") && e.view(y).preedit=="明xx","destroy-one-does-not-clear-other")
let yt=e.blur(y) ?? "";check(yt=="明xx" && status()=="已套用。","destroyed-session-no-permanent-idle-block",["text":yt,"status":status()]);e.destroy(y)
// Private-prefix/truncation guard: injected only. Never count missing input as idle.
let guardSession=e.newSession();keys(guardSession,"asxe");_ = e.takeCommit(guardSession)
change("page_size",0)
check(status().contains("等待") && e.view(guardSession).preedit=="昨xe","private-prefix-strong-precondition-preserved")
e.clear(guardSession);_ = e.takeCommit(guardSession);e.destroy(guardSession)
let cleared=e.newSession();keys(cleared,"asxz");_ = e.takeCommit(cleared);change("page_size",1)
e.clear(cleared)
check(status().contains("等待"),"explicit-clear-requires-queue-drain")
_ = e.takeCommit(cleared)
check(status()=="已套用。","explicit-clear-drain-unblocks-reload");e.destroy(cleared)
let unknown=e.newSession();qat_property(raw(unknown),"kinfx_english_state","");change("page_size",1)
check(status().contains("等待"),"missing-lua-owner-is-not-idle");e.destroy(unknown)
check(status()=="已套用。","destroy-unknown-session-unblocks")
let truncated=e.newSession();qat_property(raw(truncated),"kinfx_blur",String(repeating:"x",count:5000));change("page_size",0)
check(status().contains("等待"),"truncated-plan-is-not-idle");e.destroy(truncated)
check(status()=="已套用。","destroy-truncated-session-unblocks")
#if CONTEXT_TAIL_API
// Narrow idle metadata API: never read/restore live composition or arbitrary strings.
let tailOwner=e.newSession()
check(kx_idle_punct_tail(raw(tailOwner))==0,"idle-context-empty-validated")
check(kx_restore_idle_punct_tail(raw(tailOwner),1)==1 && kx_idle_punct_tail(raw(tailOwner))==1,"idle-context-Latin-roundtrip")
check(kx_restore_idle_punct_tail(raw(tailOwner),2)==1 && kx_idle_punct_tail(raw(tailOwner))==2,"idle-context-other-roundtrip")
check(kx_restore_idle_punct_tail(raw(tailOwner),3)==0 && kx_idle_punct_tail(raw(tailOwner))==2,"idle-context-invalid-value-rejected")
qat_property(raw(tailOwner),"kinfx_punct_tail","unexpected")
change("page_size",1)
check(status().contains("等待") && e.alive(tailOwner),"idle-context-unknown-blocks-reload")
qat_property(raw(tailOwner),"kinfx_punct_tail",String(repeating:"x",count:50))
check(kx_idle_punct_tail(raw(tailOwner)) == -1,"idle-context-truncation-rejected")
check(kx_restore_idle_punct_tail(raw(tailOwner),0)==1,"idle-context-explicit-reset-validated")
_ = e.takeCommit(tailOwner)
check(status()=="已套用。","idle-context-validated-reset-unblocks-reload")
keys(tailOwner,"asxe");_ = e.takeCommit(tailOwner)
check(kx_idle_punct_tail(raw(tailOwner)) == -1 && kx_restore_idle_punct_tail(raw(tailOwner),1)==0 && e.view(tailOwner).preedit=="昨xe","idle-context-live-composition-rejected")
e.clear(tailOwner);_ = e.takeCommit(tailOwner);e.destroy(tailOwner)
#endif
// Runtime switches must survive for BOTH idle controllers, not reset to schema defaults.
func raw(_ h:UInt)->UInt {
 if let d=Mirror(reflecting:e).children.first(where:{$0.label=="sessions"})?.value as? [UInt:UInt] {return d[h]!}
 return h
}
let o1=e.newSession(),o2=e.newSession()
let names=["ascii_mode","full_shape","simplification","ascii_punct"]
for (i,n) in names.enumerated(){qat_option(raw(o1),n,Int32(i%2));qat_option(raw(o2),n,Int32((i+1)%2))}
change("page_size",0)
for (i,n) in names.enumerated(){check(qat_get_option(raw(o1),n)==Int32(i%2) && qat_get_option(raw(o2),n)==Int32((i+1)%2),"two-controller-option-preserved-"+n)}
e.destroy(o1);e.destroy(o2)
let stale=e.newSession();qat_destroy(raw(stale));change("page_size",1)
check(status()=="已套用。","dead-native-session-pruned-no-hang");e.destroy(stale)
qat_fail_reload(1);change("page_size",0)
check(status().contains("失敗") && !status().contains("已套用"),"reload-failure-never-says-applied",["status":status()])
qat_fail_reload(0);change("page_size",1)
check(status()=="已套用。","explicit-settings-action-retries-reload",["status":status()])
// A same-process reload from an external settings writer must expose I/O failure.
let customBackup=try String(contentsOfFile:e.customPath,encoding:.utf8)
try FileManager.default.removeItem(atPath:e.customPath)
try FileManager.default.createDirectory(atPath:e.customPath,withIntermediateDirectories:false)
var external=Settings.defaults();external["page_size"]="9";try Settings.save(external,to:e.settingsPath)
e.reloadIfSettingsChanged()
check(status().contains("失敗"),"external-reload-io-failure-visible",["status":status()])
try FileManager.default.removeItem(atPath:e.customPath)
try customBackup.write(toFile:e.customPath,atomically:true,encoding:.utf8)
change("page_size",1)
// Real schema task failure, not only injected return-code failure.
let schemaPath=e.sharedDir+"/kinfx_quick.schema.yaml"
let schemaBackup=try String(contentsOfFile:schemaPath,encoding:.utf8)
try "schema: [broken\n".write(toFile:schemaPath,atomically:true,encoding:.utf8)
change("page_size",0)
check(status().contains("失敗"),"real-schema-reload-failure-visible",["status":status()])
try schemaBackup.write(toFile:schemaPath,atomically:true,encoding:.utf8)
change("page_size",1)
check(status()=="已套用。","real-schema-failure-explicit-retry",["status":status()])
// No observer retain cycle; close/release while deferred must not keep a timer alive.
weak var gone:SettingsWindow?
autoreleasepool { var transient:SettingsWindow?=SettingsWindow(engine:e);gone=transient;transient?.close();transient=nil }
check(gone==nil,"settings-observer-does-not-retain-window")
check(NSWorkspace.shared.frontmostApplication?.processIdentifier==front,"no-frontmost-change")
w.close()
exit(failed==0 ? 0:1)
