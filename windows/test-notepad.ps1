# Real-key test on the VM desktop (run via kxlaunch.ps1 as the logged-in user).
# Opens a text box window, switches this process to KINFX Input through TSF, types
# vd1 Return iPhone Space with SendInput, then saves the text box content and the TIP trace.
# Output: C:\Users\KinTest\inst\kx-real.txt (progress in kx-step.txt)
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
function Step($m) { Add-Content "$inst\kx-step.txt" ((Get-Date -f HH:mm:ss) + ' ' + $m) }
Step 'start'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KI {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Key(ushort vk, bool shift) {
    var l = new System.Collections.Generic.List<INPUT>();
    Action<ushort,uint> add = (v, f) => { var x = new INPUT(); x.type = 1; x.ki.wVk = v; x.ki.dwFlags = f; l.Add(x); };
    if (shift) add(0x10, 0);
    add(vk, 0); add(vk, 2);
    if (shift) add(0x10, 2);
    SendInput((uint)l.Count, l.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
}
[ComImport, Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKxProfileMgr {
  [PreserveSig] int ActivateProfile(uint type, ushort lang, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags);
}
public static class KxTsf {
  // TF_PROFILETYPE_INPUTPROCESSOR, zh-TW, TF_IPPMF_FORPROCESS
  public static int UseKinfx() {
    var mgr = (IKxProfileMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));
    Guid c = new Guid("42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3"), p = new Guid("35BE04B0-E9E0-4E06-8438-10BFDCAE9E41");
    return mgr.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x10000000);
  }
}
'@
Step 'types ok'
$ud = Join-Path $env:APPDATA 'KINFX Input'
New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null
Remove-Item (Join-Path $ud 'log\kx-trace.log') -ErrorAction SilentlyContinue
$log = New-Object Collections.ArrayList
$f = New-Object Windows.Forms.Form
$f.Text = 'kx-real'; $f.Width = 500; $f.Height = 300; $f.TopMost = $true
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.Dock = 'Fill'; $t.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 14)
$f.Controls.Add($t)
$tm = New-Object Windows.Forms.Timer
$tm.Interval = 1500
$f.Add_Shown({
  Step 'shown'
  [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate hr=' + [KxTsf]::UseKinfx())
  $tm.Start()
})
$tm.Add_Tick({
  $tm.Stop(); Step 'typing'
  # A process launched from a task may not own the foreground; a synthetic Alt tap lifts the lock.
  [KI]::Key(0x12, $false); [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate2 hr=' + [KxTsf]::UseKinfx())
  for ($i = 0; $i -lt 50; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
  [void]$log.Add('fg=' + ([KI]::GetForegroundWindow() -eq $f.Handle))
  $keys = @(@(0x56,$false), @(0x44,$false), @(0x31,$false), @(0x0D,$false),
            @(0x49,$false), @(0x50,$true), @(0x48,$false), @(0x4F,$false), @(0x4E,$false), @(0x45,$false), @(0x20,$false))
  foreach ($k in $keys) { [KI]::Key([uint16]$k[0], $k[1]); for ($i = 0; $i -lt 15; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 } }
  [void]$log.Add('TEXT<' + ($t.Text -replace "`r`n", '\n') + '>')
  $tr = Join-Path $ud 'log\kx-trace.log'
  if (Test-Path $tr) { foreach ($l in (Get-Content $tr -Encoding UTF8)) { [void]$log.Add('trace ' + $l) } }
  Remove-Item (Join-Path $ud 'trace-on') -ErrorAction SilentlyContinue
  [IO.File]::WriteAllLines("$inst\kx-real.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
  Step 'done'
  $f.Close()
})
[Windows.Forms.Application]::Run($f)
Step 'exit'
