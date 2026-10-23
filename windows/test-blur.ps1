# Real-key blur check on the VM desktop (run via vm/launch.ps1 as the logged-in user).
# For each case: clear box A, type keys through KINFX (TSF + SendInput), then a real mouse click
# moves focus (box B, or inside box A), and the text left in box A is recorded.
# Tokens: {SP} {ENTER}; other chars typed literally. Mode per case: B = click box B, A = click inside box A.
# Output: C:\Users\KinTest\inst\kx-blur.txt (+ kx-blur-trace.txt), progress in kx-step.txt
param([string]$Tip = 'kinfx')
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
function Step($m) { Add-Content "$inst\kx-step.txt" ((Get-Date -f HH:mm:ss) + ' ' + $m) }
Step 'blur start'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KI {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int x, y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out PT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(PT p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder b, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static string Info(IntPtr h) { var b = new System.Text.StringBuilder(256); GetClassName(h, b, 256); uint pid; GetWindowThreadProcessId(h, out pid); string n = ""; try { n = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {} return h + ":" + b + ":" + n; }
  [DllImport("imm32.dll")] public static extern IntPtr ImmGetContext(IntPtr h);
  [DllImport("imm32.dll")] public static extern bool ImmSetOpenStatus(IntPtr c, bool o);
  [DllImport("imm32.dll")] public static extern bool ImmSetConversionStatus(IntPtr c, uint conv, uint sent);
  [DllImport("imm32.dll")] public static extern bool ImmReleaseContext(IntPtr h, IntPtr c);
  public static void Native(IntPtr h) { var c = ImmGetContext(h); ImmSetOpenStatus(c, true); ImmSetConversionStatus(c, 1, 0); ImmReleaseContext(h, c); }
  public static string Where() { PT p; GetCursorPos(out p); return p.x + "," + p.y + " hwnd=" + WindowFromPoint(p); }
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
  public static void Key(ushort vk, ushort mod) {
    var l = new System.Collections.Generic.List<INPUT>();
    Action<ushort,uint> add = (v, f) => { var x = new INPUT(); x.type = 1; x.ki.wVk = v; x.ki.dwFlags = f; l.Add(x); };
    if (mod != 0) add(mod, 0);
    add(vk, 0); add(vk, 2);
    if (mod != 0) add(mod, 2);
    SendInput((uint)l.Count, l.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
}
[ComImport, Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKxProfileMgr {
  [PreserveSig] int ActivateProfile(uint type, ushort lang, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags);
}
public static class KxTsf {
  public static string C = "42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3", P = "35BE04B0-E9E0-4E06-8438-10BFDCAE9E41";
  public static int UseKinfx() {
    var mgr = (IKxProfileMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));
    Guid c = new Guid(C), p = new Guid(P);
    return mgr.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x10000000);
  }
}
'@
# Physical pixels for both the form layout and SetCursorPos (the VM runs at 150 %).
[void][KI]::SetProcessDPIAware()
# -Tip msquick: Microsoft Quick (速成) as the Windows reference.
if ($Tip -eq 'msquick') { [KxTsf]::C = '531FDEBF-9B4C-4A43-A2AA-960E8FCDC732'; [KxTsf]::P = '6024B45F-5C54-11D4-B921-0080C882687E' }
$out = if ($Tip -eq 'kinfx') { 'kx-blur' } else { 'kx-blur-' + $Tip }
$cases = @(
  'B:hel', 'B:hello', 'B:vdhel', 'B:vd', 'B:v', 'B:vd1', 'B:ofc', 'B:iPhone', 'B:openai.co', 'B:llama.c', 'B:hello{SP}vd',
  'A:hel', 'A:vdhel', 'A:vd', 'A:hello{SP}', 'B:vd1hel', 'W:hel', 'W:vdhel', 'W:vd'
)
function Keys($s) {
  $out = New-Object Collections.ArrayList
  foreach ($x in [regex]::Matches($s, '\{[A-Z0-9]+\}|.')) {
    $v = $x.Value
    switch -CaseSensitive ($v) {
      '{SP}' { [void]$out.Add(@(0x20, 0)); continue }
      '{ENTER}' { [void]$out.Add(@(0x0D, 0)); continue }
      '.' { [void]$out.Add(@(0xBE, 0)); continue }
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
function Mid($c) { $r = $c.RectangleToScreen($c.ClientRectangle); return @(($r.Right - 30), ($r.Top + [int]($r.Height / 2))) }
$ud = Join-Path $env:APPDATA 'KINFX Input'
New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null
Remove-Item (Join-Path $ud 'log\kx-trace.log') -ErrorAction SilentlyContinue
$log = New-Object Collections.ArrayList
$f = New-Object Windows.Forms.Form
$f.Text = 'kx-blur'; $f.Width = 600; $f.Height = 360; $f.TopMost = $true; $f.StartPosition = 'Manual'; $f.Left = 100; $f.Top = 100
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.Left = 10; $t.Top = 10; $t.Width = 560; $t.Height = 140; $t.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 14)
$t2 = New-Object Windows.Forms.TextBox
$t2.Multiline = $true; $t2.Left = 10; $t2.Top = 170; $t2.Width = 560; $t2.Height = 120; $t2.Font = $t.Font
$f.Controls.Add($t); $f.Controls.Add($t2)
# W cases click this second window (focus leaves the form).
$g = New-Object Windows.Forms.Form
$g.Text = 'kx-other'; $g.Width = 400; $g.Height = 200; $g.StartPosition = 'Manual'; $g.Left = 800; $g.Top = 100; $g.TopMost = $true
$g2 = New-Object Windows.Forms.TextBox; $g2.Dock = 'Fill'; $g2.Multiline = $true; $g.Controls.Add($g2)
$tm = New-Object Windows.Forms.Timer
$tm.Interval = 1500
$f.Add_Shown({
  # hidden.vbs starts powershell with SW_HIDE, which the first ShowWindow obeys: the form exists but is not on screen.
  [void][KI]::ShowWindow($f.Handle, 5)
  $g.Show(); [void][KI]::ShowWindow($g.Handle, 5)
  [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate hr=' + [KxTsf]::UseKinfx())
  $tm.Start()
})
$tm.Add_Tick({
  $tm.Stop(); Step 'blur typing'
  try {
  [KI]::Key(0x12, 0); [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('activate2 hr=' + [KxTsf]::UseKinfx())
  Pump 50
  [void]$log.Add('fg0=' + ([KI]::GetForegroundWindow() -eq $f.Handle) + ' screen=' + [Windows.Forms.Screen]::PrimaryScreen.Bounds + ' fb=' + $f.Bounds + ' tr=' + $t.RectangleToScreen($t.ClientRectangle) + ' under=' + [KI]::Info([KI]::WindowFromPoint((New-Object KI+PT -Property @{x=400;y=200}))))
  foreach ($cs in $cases) {
    $mode, $keys = $cs.Split(':', 2)
    # no Alt tap here: a second Alt opens the system menu loop and DoEvents never returns
    [void][KI]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus(); Pump 10
    $pa = Mid $t; [KI]::Click($pa[0], $pa[1]); Pump 15
    $hr = [KxTsf]::UseKinfx(); Pump 10
    if ($Tip -eq 'msquick') { [KI]::Native($t.Handle); Pump 5 }
    if ($cs -eq $cases[0]) { [void]$log.Add('click ' + ($pa -join ',') + ' at ' + [KI]::Where() + ' t=' + $t.Handle + ' f=' + $f.Handle + ' fg=' + [KI]::Info([KI]::GetForegroundWindow()) + ' under=' + [KI]::Info([KI]::WindowFromPoint((New-Object KI+PT -Property @{x=$pa[0];y=$pa[1]}))) + ' focused=' + $t.Focused) }
    [KI]::Key(0x1B, 0); Pump 15; $t.Text = ''; $t2.Text = ''; Pump 10
    $fg = [KI]::GetForegroundWindow() -eq $f.Handle
    foreach ($k in (Keys $keys)) { [KI]::Key([uint16]$k[0], [uint16]$k[1]); Pump 25 }
    Pump 20
    $before = $t.Text -replace "`r`n", '\n'
    if ($mode -eq 'B') { $p = Mid $t2 } elseif ($mode -eq 'W') { $p = Mid $g2 } else { $r = $t.RectangleToScreen($t.ClientRectangle); $p = @(($r.Left + 5), ($r.Bottom - 10)) }
    [KI]::Click($p[0], $p[1]); Pump 40
    $after = $t.Text -replace "`r`n", '\n'
    # Typing after the click shows whether a stale composition comes back.
    [KI]::Key(0x41, 0x10); Pump 20
    $next = ($t.Text -replace "`r`n", '\n') + '|' + ($t2.Text -replace "`r`n", '\n')
    Step ('case ' + $cs + ' fg=' + $fg + ' shown=' + $before + ' after=' + $after + ' pa=' + $pa + ' p=' + $p)
    [void]$log.Add('CASE ' + $cs + ' fg=' + $fg + ' hr=' + $hr + ' SHOWN<' + $before + '> AFTER<' + $after + '> NEXT<' + $next + '>')
  }
  } catch { [void]$log.Add('ERR ' + $_) ; Step ('ERR ' + $_) }
  $tr = Join-Path $ud 'log\kx-trace.log'
  if (Test-Path $tr) { Copy-Item $tr "$inst\$out-trace.txt" -Force; Remove-Item $tr -ErrorAction SilentlyContinue }
  Remove-Item (Join-Path $ud 'trace-on') -ErrorAction SilentlyContinue
  [IO.File]::WriteAllLines("$inst\$out.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
  Step 'blur done'
  $f.Close()
})
[Windows.Forms.Application]::Run($f)
Step 'blur exit'
