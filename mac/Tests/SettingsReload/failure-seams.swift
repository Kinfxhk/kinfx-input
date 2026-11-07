import Cocoa
let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
let root=CommandLine.arguments[1],e=Engine(sharedDir:CommandLine.arguments[1]+"/data",userDir:CommandLine.arguments[1]+"/user")
try e.start();var failures=0
func check(_ ok:Bool,_ name:String,_ details:[String:Any]=[:]){var r=details;r["case"]=name;r["pass"]=ok;print(String(data:try! JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]),encoding:.utf8)!);if !ok{failures += 1}}
func raw(_ h:UInt)->UInt {let m=Mirror(reflecting:e).children.first{$0.label=="sessions"}?.value as? [UInt:UInt];return m?[h] ?? 0}
func text(_ p:UnsafeMutablePointer<CChar>?)->String {guard let p=p else{return ""};defer{free(p)};return String(cString:p)}
func count(_ name:String)->Int {Mirror(reflecting:e).children.first{$0.label==name}.map{Mirror(reflecting:$0.value).children.count} ?? -1}
func key(_ h:UInt,_ k:Int32,_ m:Int32=0)->String {_ = e.key(h,k,m);return e.takeCommit(h) ?? ""}
let w=SettingsWindow(engine:e);w.alphaValue=0
func children(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap(children)}
func change(){let p=children(w.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.identifier?.rawValue=="page_size"}!;p.selectItem(at:p.indexOfSelectedItem==0 ? 1:0);precondition(p.sendAction(p.action,to:p.target))}
func status()->String {((w.contentView as! NSStackView).views[1] as! NSTextField).stringValue}
let h=e.newSession()
check(text(qat_schema(raw(h)))=="kinfx_quick","native-selected-schema-identity",["schema":text(qat_schema(raw(h)))])
e.destroy(h)
precondition(qat_deploy(e.sharedDir+"/qa_other_schema.schema.yaml") != 0)
let other=kx_session("qa_other_schema")
precondition(other != 0 && text(qat_schema(other))=="qa_other_schema");kx_destroy(other)
for selectionReportsSuccess in [false,true] {
 let s=qat_bad_selection(selectionReportsSuccess ? 1:0)
 let defaultSchema=String(cString:qat_last_default_schema())
 let rejected=s==0 && qat_last_created_alive()==0 && defaultSchema=="kinfx_quick"
 check(rejected,"native-rejects-and-destroys-wrong-default-select-success-"+String(selectionReportsSuccess),["session":s,"lastAlive":qat_last_created_alive(),"defaultSchema":defaultSchema,"actualSchema":text(qat_schema(s))])
 kx_destroy(s)
}
// Real selection failure with a valid default dictionary, not only no-schema.
let bad=kx_session("qa_missing_schema")
check(bad==0,"native-missing-schema-never-returns-default",["session":bad,"actualSchema":text(qat_schema(bad))]);kx_destroy(bad)
for seam in ["create","restore"] {
 let a=e.newSession(),b=e.newSession()
 kx_set_option(raw(a),"full_shape",0);kx_set_option(raw(b),"full_shape",0)
 _ = key(a,0x20,RimeKeys.shift)
 var out="";for c in "hello".utf8 {out += key(a,Int32(c))};out += key(a,0xff0d);precondition(out=="hello")
 if seam=="create" {qat_fail_session(1)} else {qat_fail_restore(1)}
 change()
 check(status().contains("失敗") && !e.alive(a) && !e.alive(b) && count("retryRuntime")==2 && count("sessions")==0,"reopen-"+seam+"-failure-atomic-truthful",["status":status(),"snapshots":count("retryRuntime"),"sessions":count("sessions")])
 // Removing an owner while failed must release only its metadata.
 e.destroy(b)
 check(count("retryRuntime")==1,"reopen-"+seam+"-destroy-releases-one-snapshot")
 qat_fail_session(0);qat_fail_restore(0)
 _ = e.takeCommit(a)
 check(status().contains("失敗"),"reopen-"+seam+"-no-implicit-retry")
 change()
 check(status()=="已套用。" && e.alive(a) && raw(b)==0 && count("retryRuntime")==0 && count("sessions")==1,"reopen-"+seam+"-explicit-retry-restores-only-survivor",["status":status(),"snapshots":count("retryRuntime"),"sessions":count("sessions")])
 check(kx_option(raw(a),"full_shape")==1 && text(kx_property(raw(a),"kinfx_punct_tail"))=="latin" && key(a,0x2e)==".","reopen-"+seam+"-retry-retains-width-tail")
 e.destroy(a)
}
w.close();exit(failures==0 ? 0:1)
