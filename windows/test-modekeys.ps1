# Real-key test for the Chinese/English mode hotkeys (run via launch.ps1 as the logged-in user).
# One WinForms text box, KINFX Input activated for this process, SendInput only:
#   Ctrl+Space, bare Ctrl+Shift (both release orders), bare Alt+Shift, lone Ctrl,
#   Ctrl+Shift+P (must not toggle), Ctrl+C / Ctrl+V, and a switch while a preedit is open.
# Output: C:\Users\KinTest\inst\kx-mode.txt (progress in kx-mode-step.txt)
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
function Step($m) { Add-Content "$inst\kx-mode-step.txt" ((Get-Date -f HH:mm:ss) + ' ' + $m) }
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
$f.Text = 'kx-mode'; $f.Width = 520; $f.Height = 320; $f.TopMost = $true
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.Dock = 'Fill'; $t.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 14)
$f.Controls.Add($t)
$tm = New-Object Windows.Forms.Timer
$tm.Interval = 1500
function Pump($n) { for ($i = 0; $i -lt $n; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
$V = 0x56; $D = 0x44; $ONE = 0x31; $CTRL = 0x11; $SHIFT = 0x10; $ALT = 0x12; $SPACE = 0x20; $P = 0x50; $C = 0x43
function TypeProbe { foreach ($k in @($V, $D, $ONE)) { [KI]::Key([uint16]$k); Pump 5 }; Pump 8 }
function Mark($name) { [void]$log.Add('STEP ' + $name + ' TEXT<' + ($t.Text -replace "`r`n", '\n') + '>'); [KI]::Key(0x1B); Pump 3; $t.Text = ''; Pump 2 }
# hotkey shapes
function CtrlSpace { [KI]::Send(@($CTRL,0, $SPACE,0, $SPACE,2, $CTRL,2)); Pump 8 }
function ChordCS { [KI]::Send(@($CTRL,0, $SHIFT,0, $SHIFT,2, $CTRL,2)); Pump 8 }        # shift released first
function ChordCSr { [KI]::Send(@($CTRL,0, $SHIFT,0, $CTRL,2, $SHIFT,2)); Pump 8 }        # ctrl released first
function ChordAS { [KI]::Send(@($ALT,0, $SHIFT,0, $SHIFT,2, $ALT,2)); Pump 8 }
function ChordASr { [KI]::Send(@($ALT,0, $SHIFT,0, $ALT,2, $SHIFT,2)); Pump 8 }
function CtrlC { [KI]::Send(@($CTRL,0, $C,0, $C,2, $CTRL,2)); Pump 8 }
function CtrlV { [KI]::Send(@($CTRL,0, $V,0, $V,2, $CTRL,2)); Pump 8 }
function CtrlShiftP { [KI]::Send(@($CTRL,0, $SHIFT,0, $P,0, $P,2, $SHIFT,2, $CTRL,2)); Pump 8 }
$f.Add_Shown({
  Step 'shown'
  [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate hr=' + [KxTsf]::UseKinfx())
  $tm.Start()
})
$tm.Add_Tick({
  $tm.Stop(); Step 'typing'
  [KI]::Key(0x12); Pump 3   # a synthetic Alt tap: the process does not own the foreground yet
  [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  Pump 5
  [void]$log.Add('activate2 hr=' + [KxTsf]::UseKinfx())
  Pump 10
  for ($i = 0; $i -lt 12 -and ([KI]::GetForegroundWindow() -ne $f.Handle); $i++) { [KI]::ClickAt(($f.Left + 60), ($f.Top + 60)); Pump 10 }
  [void]$log.Add('fg=' + ([KI]::GetForegroundWindow() -eq $f.Handle))

  TypeProbe; Mark 'c0-baseline-zh'          # want: hao
  CtrlSpace; TypeProbe; Mark 'c1-ctrlspace-en'   # want: vd1
  CtrlSpace; TypeProbe; Mark 'c2-ctrlspace-zh'
  ChordCS;  TypeProbe; Mark 'c3-chord-cs-en'
  ChordCSr; TypeProbe; Mark 'c4-chord-cs-zh'
  ChordCS;  TypeProbe; Mark 'c5-chord-cs-en2'
  ChordCSr; TypeProbe; Mark 'c6-chord-cs-zh2'
  ChordAS;  TypeProbe; Mark 'c7-chord-as-en'
  ChordASr; TypeProbe; Mark 'c8-chord-as-zh'
  [KI]::Key($CTRL); Pump 8; TypeProbe; Mark 'c9-ctrl-alone-zh'
  CtrlShiftP; TypeProbe; Mark 'c10-ctrlshift-p-zh'
  # switch while a preedit is open: vd shows candidates, the mode key must commit it first
  [KI]::Key($V); Pump 5; [KI]::Key($D); Pump 8
  [void]$log.Add('pre-preedit TEXT<' + ($t.Text -replace "`r`n", '\n') + '>')
  CtrlSpace; Mark 'c11-preedit-commit'      # want: hao
  TypeProbe; Mark 'c12-after-preedit-en'    # want: vd1
  CtrlSpace; TypeProbe; Mark 'c13-back-zh'
  # app shortcuts still reach the app
  $t.Text = 'AB12'; $t.SelectAll(); Pump 4
  CtrlC; Pump 6
  $clip = ''
  try { $clip = [Windows.Forms.Clipboard]::GetText() } catch { $clip = 'ERR ' + $_.Exception.Message }
  [void]$log.Add('clip<' + $clip + '>')
  $t.Text = ''; $t.Select(0, 0); Pump 4
  CtrlV; Pump 10
  Mark 'c14-paste'                          # want: AB12
  TypeProbe; Mark 'c15-after-paste-zh'      # want: hao

  $tr = Join-Path $ud 'log\kx-trace.log'
  if (Test-Path $tr) { foreach ($l in (Get-Content $tr -Encoding UTF8 | Select-Object -Last 400)) { [void]$log.Add('trace ' + $l) } }
  Remove-Item (Join-Path $ud 'trace-on') -ErrorAction SilentlyContinue
  [IO.File]::WriteAllLines("$inst\kx-mode.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
  Step 'done'
  $f.Close()
})
[Windows.Forms.Application]::Run($f)
Step 'exit'
