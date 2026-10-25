# Bare-modifier chord probe (run via launch.ps1 as the logged-in user).
# Types vd1 (hao in Chinese, raw "vd1" in English) after each chord, so the mode is visible.
# Output: C:\Users\KinTest\inst\kx-chords.txt
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
function Step($m) { Add-Content "$inst\kx-chords-step.txt" ((Get-Date -f HH:mm:ss) + ' ' + $m) }
Step 'start'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class KI {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  public static void Send(int[] keys) {
    var l = new List<INPUT>();
    for (int i = 0; i < keys.Length; i += 2) { var x = new INPUT(); x.type = 1; x.ki.wVk = (ushort)keys[i]; x.ki.dwFlags = (uint)keys[i+1]; l.Add(x); }
    SendInput((uint)l.Count, l.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Key(ushort vk) { Send(new int[] { vk, 0, vk, 2 }); }
  public static void ClickAt(int x, int y) { SetCursorPos(x, y); mouse_event(0x02,0,0,0,IntPtr.Zero); mouse_event(0x04,0,0,0,IntPtr.Zero); }
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
Step 'types ok'
$ud = Join-Path $env:APPDATA 'KINFX Input'
New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null
Remove-Item (Join-Path $ud 'log\kx-trace.log') -ErrorAction SilentlyContinue
$log = New-Object Collections.ArrayList
$f = New-Object Windows.Forms.Form
$f.Text = 'kx-chords'; $f.Width = 520; $f.Height = 280; $f.TopMost = $true
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.Dock = 'Fill'; $t.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 14)
$f.Controls.Add($t)
$tm = New-Object Windows.Forms.Timer
$tm.Interval = 1500
function Pump($n) { for ($i = 0; $i -lt $n; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
$V = 0x56; $D = 0x44; $ONE = 0x31; $CTRL = 0x11; $SHIFT = 0x10; $ALT = 0x12
function TypeProbe { foreach ($k in @($V, $D, $ONE)) { [KI]::Key([uint16]$k); Pump 5 }; Pump 8 }
function Mark($name) { [void]$log.Add('STEP ' + $name + ' TEXT<' + ($t.Text -replace "`r`n", '\n') + '>'); [KI]::Key(0x1B); Pump 3; $t.Text = ''; Pump 2 }
function ChordCS { [KI]::Send(@($CTRL,0, $SHIFT,0, $SHIFT,2, $CTRL,2)); Pump 8 }
function ChordAS { [KI]::Send(@($ALT,0, $SHIFT,0, $SHIFT,2, $ALT,2)); Pump 8 }
$f.Add_Shown({
  Step 'shown'
  [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate hr=' + [KxTsf]::UseKinfx())
  $tm.Start()
})
$tm.Add_Tick({
  $tm.Stop(); Step 'typing'
  [KI]::Key(0x12); Pump 3
  [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  Pump 5
  [void]$log.Add('activate2 hr=' + [KxTsf]::UseKinfx())
  Pump 10
  [void]$log.Add('fg=' + ([KI]::GetForegroundWindow() -eq $f.Handle))
  TypeProbe; Mark 'z0-baseline'
  ChordCS; TypeProbe; Mark 'z1-cs-en'
  ChordCS; TypeProbe; Mark 'z2-cs-zh'
  ChordAS; TypeProbe; Mark 'z3-as-en'
  ChordAS; TypeProbe; Mark 'z4-as-zh'
  $tr = Join-Path $ud 'log\kx-trace.log'
  if (Test-Path $tr) { foreach ($l in (Get-Content $tr -Encoding UTF8 | Select-Object -Last 120)) { [void]$log.Add('trace ' + $l) } }
  Remove-Item (Join-Path $ud 'trace-on') -ErrorAction SilentlyContinue
  [IO.File]::WriteAllLines("$inst\kx-chords.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
  Step 'done'
  $f.Close()
})
[Windows.Forms.Application]::Run($f)
Step 'exit'
