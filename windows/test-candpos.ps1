# Candidate / association window position check. For each app: type vd (preedit list), then vd1
# (association list after the pick); record the KINFX candidate window rect (class KINFXInputCand)
# and the screenshot crop. Output: C:\Users\KinTest\inst\kx-pos-<app>.txt + kx-pos-<app>-<n>.png
param([string]$App = 'notepad')
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class KP {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
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
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
  public static string Cand() {
    IntPtr h = FindWindow("KINFXInputCand", null);
    if (h == IntPtr.Zero) return "none";
    RECT r; GetWindowRect(h, out r);
    return (IsWindowVisible(h) ? "shown " : "hidden ") + r.l + "," + r.t + "," + r.r + "," + r.b;
  }
  public static string C = "42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3", P = "35BE04B0-E9E0-4E06-8438-10BFDCAE9E41";
  public static int Use() { var m = (IKpMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED"))); Guid c = new Guid(C), p = new Guid(P); return m.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x20000000); }
}
[ComImport, Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKpMgr { [PreserveSig] int ActivateProfile(uint type, ushort lang, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags); }
'@
[void][KP]::SetProcessDPIAware()
$log = New-Object Collections.ArrayList
$ud = Join-Path $env:APPDATA 'KINFX Input'
New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null
Remove-Item (Join-Path $ud 'log\kx-trace.log') -EA SilentlyContinue
$root = [Windows.Automation.AutomationElement]::RootElement
function Find($cond) { for ($i = 0; $i -lt 15; $i++) { $e = $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $cond); if ($e) { return $e }; Start-Sleep 1 }; return $null }
if ($App -like 'edge*') {} elseif ($App -ne 'notepad') {
  $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $f = New-Object Windows.Forms.Form; $f.Text = 'kx-edge'; $f.StartPosition = 'Manual'; $f.FormBorderStyle = 'None'; $f.TopMost = $true
  if ($App -eq 'bottom') { $f.SetBounds($wa.Left + 300, $wa.Bottom - 90, 700, 90) } else { $f.SetBounds($wa.Right - 260, $wa.Top + 300, 260, 300) }
  $tb = New-Object Windows.Forms.TextBox; $tb.Multiline = $true; $tb.Dock = 'Fill'; $tb.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 14); $tb.AccessibleName = 'boxa'; $f.Controls.Add($tb)
  $f.Show(); [void][KP]::ShowWindow($f.Handle, 5); [Windows.Forms.Application]::DoEvents(); Start-Sleep 1
  [void][KP]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$tb.Focus()
  $box = [Windows.Automation.AutomationElement]::FromHandle($tb.Handle)
  [void]$log.Add('workarea=' + $wa + ' form=' + $f.Bounds)
} elseif ($App -eq 'notepad') {
  Get-Process notepad -EA SilentlyContinue | Stop-Process -Force; Start-Sleep 1
  Start-Process notepad; Start-Sleep 4
  $box = Find (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ClassNameProperty, 'RichEditD2DPT'))
}
if ($App -like 'edge*') {
  $html = "$inst\kx-pos.html"
  Set-Content $html '<html><body style="margin:80px"><textarea aria-label="boxa" style="width:700px;height:300px;font-size:20px"></textarea></body></html>' -Encoding UTF8
  Get-Process msedge -EA SilentlyContinue | Stop-Process -Force; Start-Sleep 2
  Start-Process msedge -ArgumentList '--new-window', '--no-first-run', ('file:///' + ($html -replace '\\', '/')); Start-Sleep 6
  $box = Find (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, 'boxa'))
}
[void]$log.Add('box=' + ($box -ne $null))
$r = $box.Current.BoundingRectangle
[KP]::Click([int]($r.Left + 60), [int]($r.Top + 30)); Start-Sleep -Milliseconds 400
[KP]::Key(0x41, 0x11); [KP]::Key(0x2E, 0); Start-Sleep -Milliseconds 200
# three lines of text so the caret is well inside the field
foreach ($ln in 1..3) { foreach ($c in 'iPhone '.ToCharArray()) { if ($c -eq ' ') { [KP]::Key(0x20, 0) } elseif ($c -cmatch '[A-Z]') { [KP]::Key([uint16][int]$c, 0x10) } else { [KP]::Key([uint16][int][char]([string]$c).ToUpper(), 0) }; Start-Sleep -Milliseconds 60 }; [KP]::Key(0x0D, 0); Start-Sleep -Milliseconds 100 }
foreach ($c in 'iPhone '.ToCharArray()) { if ($c -eq ' ') { [KP]::Key(0x20, 0) } elseif ($c -cmatch '[A-Z]') { [KP]::Key([uint16][int]$c, 0x10) } else { [KP]::Key([uint16][int][char]([string]$c).ToUpper(), 0) }; Start-Sleep -Milliseconds 60 }
$hr = [KP]::Use(); Start-Sleep -Milliseconds 300
[void]$log.Add('use hr=' + $hr)
$pump = { for ($i = 0; $i -lt 30; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 15 } }
$shot = { param($n) $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height; $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size); $bmp.Save("$inst\kx-pos-$App-$n.png") }
[KP]::Key(0x56, 0); & $pump; [KP]::Key(0x44, 0); & $pump; & $pump
[void]$log.Add('after vd: ' + [KP]::Cand()); & $shot 1
[KP]::Key(0x31, 0); & $pump; & $pump
[void]$log.Add('after vd1: ' + [KP]::Cand()); & $shot 2
[KP]::Key(0x20, 0); & $pump
[void]$log.Add('after vd1 Space: ' + [KP]::Cand())
[KP]::Key(0x1B, 0); Start-Sleep -Milliseconds 200
$tr = Join-Path $ud 'log\kx-trace.log'
if (Test-Path $tr) { foreach ($l in (Get-Content $tr -Encoding UTF8)) { if ($l -match '^cand at') { [void]$log.Add('trace ' + $l) } } ; Remove-Item $tr }
Remove-Item (Join-Path $ud 'trace-on') -EA SilentlyContinue
[KP]::Key(0x41, 0x11); [KP]::Key(0x2E, 0)
if ($App -eq 'notepad') { Get-Process notepad -EA SilentlyContinue | Stop-Process -Force } elseif ($App -like 'edge*') { Get-Process msedge -EA SilentlyContinue | Stop-Process -Force } else { $f.Close() }
[IO.File]::WriteAllLines("$inst\kx-pos-$App.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
