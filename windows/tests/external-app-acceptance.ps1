$ProgressPreference='SilentlyContinue'
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing
. C:\QA\helpers.ps1
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class ExtTsf{public static int Activate(){var m=(IProfileMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));Guid c=new Guid("42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3"),p=new Guid("35BE04B0-E9E0-4E06-8438-10BFDCAE9E41");return m.ActivateProfile(1,0x404,ref c,ref p,IntPtr.Zero,0x20000000);}}
'@
$r=New-Object Collections.Generic.List[object]
try{
$edge='C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
Set-Content -Encoding ASCII C:\QA\external.html '<html><body><textarea aria-label="QA_OLD" style="width:600px;height:150px;font-size:24px"></textarea><br><textarea aria-label="QA_NEW" style="width:600px;height:150px;font-size:24px"></textarea></body></html>'
Start-Process $edge -ArgumentList '--no-first-run --force-renderer-accessibility --user-data-dir=C:\QA\edge-acceptance --new-window file:///C:/QA/external.html'
Start-Sleep 8
$root=[Windows.Automation.AutomationElement]::RootElement
function FindBox($name){$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,$name)))}
$a=FindBox 'QA_OLD';$b=FindBox 'QA_NEW'
if(!$a -or !$b){throw 'Edge UIA textareas unavailable (onboarding may block)'}
function ClickEl($e){$q=$e.Current.BoundingRectangle;[void][QAKeys]::SetCursorPos([int]($q.Left+30),[int]($q.Top+25));[QAKeys]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[QAKeys]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 200}
function V($e){$e.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value}
ClickEl $a;$hr=[ExtTsf]::Activate();Start-Sleep -Milliseconds 500
foreach($prefix in @('','vd','hel','vd1hel')){
ClickEl $a;Key 27;$a.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('');$b.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('');ClickEl $a
Type-Code $prefix;$before=V $a;ClickEl $b;Type-Code 'vd1';Start-Sleep -Milliseconds 250
$r.Add(@{app='Edge';prefix=$prefix;oldField=(V $a);newField=(V $b);before=$before;activationHr=$hr;expectedTarget=[string][char]0x597D;focus=[Windows.Automation.AutomationElement]::FocusedElement.Current.Name;preedit=$null;preeditUnavailable='UIA value includes composition; no TSF observer attached';selection=$null;panelRect=$null;panelUnavailable='Not instrumented in external process';dllHash=(Get-FileHash 'C:\Program Files\KINFX Input\KINFXInput.dll').Hash})
}
}catch{$r.Add(@{app='Edge';status='NOT_RUN';reason=$_.Exception.Message})}
$r|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 C:\QA\external-results.json
Invoke-WebRequest -UseBasicParsing -Method Post -InFile C:\QA\external-results.json http://192.168.174.1:18768/external-results.json
