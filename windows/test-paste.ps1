# Real-key 0.1.2 check on the VM desktop (run via vm/launch.ps1 as the logged-in user).
# Clipboard = PASTE, then for each case: Esc, clear the box, type keys through KINFX (TSF + SendInput),
# record the text box raw, Esc again and record what stayed committed.
# Tokens: {SP} {ENTER} {ESC} {CV}=Ctrl+V {S1}=Shift+1; other chars typed literally.
# Output: C:\Users\KinTest\inst\kx-paste.txt (+ kx-paste-trace.txt), progress in kx-step.txt
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
function Step($m) { Add-Content "$inst\kx-step.txt" ((Get-Date -f HH:mm:ss) + ' ' + $m) }
Step 'paste start'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KI {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  public static void Key(ushort vk, ushort mod) {
    var l = new System.Collections.Generic.List<INPUT>();
    Action<ushort,uint> add = (v, f) => { var x = new INPUT(); x.type = 1; x.ki.wVk = v; x.ki.dwFlags = f; l.Add(x); };
    if (mod != 0) add(mod, 0);
    add(vk, 0); add(vk, 2);
    if (mod != 0) add(mod, 2);
    SendInput((uint)l.Count, l.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
}
[ComImport, Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKxProfileMgr {
  [PreserveSig] int ActivateProfile(uint type, ushort lang, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags);
}
public static class KxTsf {
  public static int UseKinfx() {
    var mgr = (IKxProfileMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));
    Guid c = new Guid("42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3"), p = new Guid("35BE04B0-E9E0-4E06-8438-10BFDCAE9E41");
    return mgr.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x10000000);
  }
}
'@
$cases = @(
  'vd{CV}', 'vdhel{CV}', 'vd1{CV}', 'vd1{CV}{S1}', 'vd{SP}{CV}', 'hello{CV}', 'ofc{CV}', '{CV}',
  'vd1', 'iPhone{SP}',
  'hello.vd1', 'openai.com{SP}', 'fogge{SP}1', "don't{SP}", 'gg{SP}', 'hello{ENTER}', 'thanks?', 'ofc1'
)
function Keys($s) {
  $out = New-Object Collections.ArrayList
  $m = [regex]::Matches($s, '\{[A-Z0-9]+\}|.')
  foreach ($x in $m) {
    $v = $x.Value
    switch -CaseSensitive ($v) {
      '{SP}' { [void]$out.Add(@(0x20, 0)); continue }
      '{ENTER}' { [void]$out.Add(@(0x0D, 0)); continue }
      '{ESC}' { [void]$out.Add(@(0x1B, 0)); continue }
      '{CV}' { [void]$out.Add(@(0x56, 0x11)); continue }
      '{S1}' { [void]$out.Add(@(0x31, 0x10)); continue }
      '.' { [void]$out.Add(@(0xBE, 0)); continue }
      "'" { [void]$out.Add(@(0xDE, 0)); continue }
      '?' { [void]$out.Add(@(0xBF, 0x10)); continue }
      default {
        $c = [char]$v
        if ($c -cmatch '[A-Z]') { [void]$out.Add(@([int]$c, 0x10)) }
        elseif ($c -cmatch '[a-z]') { [void]$out.Add(@([int][char]$v.ToUpper(), 0)) }
        else { [void]$out.Add(@([int]$c, 0)) }
      }
    }
  }
  return ,$out
}
function Pump($n) { for ($i = 0; $i -lt $n; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 } }
$ud = Join-Path $env:APPDATA 'KINFX Input'
New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null
Remove-Item (Join-Path $ud 'log\kx-trace.log') -ErrorAction SilentlyContinue
$log = New-Object Collections.ArrayList
$f = New-Object Windows.Forms.Form
$f.Text = 'kx-paste'; $f.Width = 600; $f.Height = 300; $f.TopMost = $true
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.Dock = 'Fill'; $t.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 14)
$f.Controls.Add($t)
$tm = New-Object Windows.Forms.Timer
$tm.Interval = 1500
$f.Add_Shown({
  [void][KI]::ShowWindow($f.Handle, 5)  # hidden.vbs launches with SW_HIDE
  [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate hr=' + [KxTsf]::UseKinfx())
  $tm.Start()
})
$tm.Add_Tick({
  $tm.Stop(); Step 'paste typing'
  [Windows.Forms.Clipboard]::SetText('PASTE')
  [KI]::Key(0x12, 0); [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate2 hr=' + [KxTsf]::UseKinfx())
  Pump 50
  [void]$log.Add('fg=' + ([KI]::GetForegroundWindow() -eq $f.Handle) + ' clip=' + [Windows.Forms.Clipboard]::GetText())
  foreach ($cs in $cases) {
    [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus(); Pump 10
    $fg = [KI]::GetForegroundWindow() -eq $f.Handle
    [KI]::Key(0x1B, 0); Pump 15; $t.Text = ''; Pump 10
    foreach ($k in (Keys $cs)) { [KI]::Key([uint16]$k[0], [uint16]$k[1]); Pump 25 }
    Pump 30
    $raw = $t.Text -replace "`r`n", '\n'
    [KI]::Key(0x1B, 0); Pump 20
    $kept = $t.Text -replace "`r`n", '\n'
    [void]$log.Add('CASE ' + $cs + ' fg=' + $fg + ' RAW<' + $raw + '> AFTERESC<' + $kept + '>')
  }
  [void]$log.Add('fg_end=' + ([KI]::GetForegroundWindow() -eq $f.Handle) + ' clip=' + [Windows.Forms.Clipboard]::GetText())
  $tr = Join-Path $ud 'log\kx-trace.log'
  if (Test-Path $tr) { Copy-Item $tr "$inst\kx-paste-trace.txt" -Force; Remove-Item $tr -ErrorAction SilentlyContinue }
  Remove-Item (Join-Path $ud 'trace-on') -ErrorAction SilentlyContinue
  [IO.File]::WriteAllLines("$inst\kx-paste.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
  Step 'paste done'
  $f.Close()
})
[Windows.Forms.Application]::Run($f)
Step 'paste exit'
