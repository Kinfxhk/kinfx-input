# Blur check in Edge: two textareas in a local page, keys through KINFX, mouse click into the
# second textarea, values read through UIA. Output: C:\Users\KinTest\inst\kx-edge.txt
param([string]$Ime = 'kinfx')
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
function Step($m) { Add-Content "$inst\kx-step.txt" ((Get-Date -f HH:mm:ss) + ' edge ' + $m) }
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KE {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
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
'@
[void][KE]::SetProcessDPIAware()
$log = New-Object Collections.ArrayList
$ud = Join-Path $env:APPDATA 'KINFX Input'
New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null
Remove-Item (Join-Path $ud 'log\kx-trace.log') -EA SilentlyContinue
$html = "$inst\kx-edge.html"
Set-Content $html '<html><body><textarea id="a" title="boxa" aria-label="boxa" style="width:600px;height:150px;font-size:24px"></textarea><br><textarea id="b" title="boxb" aria-label="boxb" style="width:600px;height:150px"></textarea></body></html>' -Encoding UTF8
Get-Process msedge -EA SilentlyContinue | Stop-Process -Force; Start-Sleep 2
$tip = '0404:{42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3}{35BE04B0-E9E0-4E06-8438-10BFDCAE9E41}'
if ($Ime -eq 'weasel') { $tip = '0404:{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}{3D02CAB6-2B8E-4781-BA20-1C9267529467}' }
if ($Ime -eq 'msquick') { $tip = '0404:{531FDEBF-9B4C-4A43-A2AA-960E8FCDC732}{6024B45F-5C54-11D4-B921-0080C882687E}' }
$out = if ($Ime -eq 'kinfx') { 'kx-edge' } else { 'kx-edge-' + $Ime }
$ul = Get-WinUserLanguageList; $saved = $ul[0].InputMethodTips | ForEach-Object { $_ }
# KINFX first in the list so a new window starts on it; restored at the end.
$ul[0].InputMethodTips.Remove($tip) | Out-Null; $ul[0].InputMethodTips.Insert(0, $tip); Set-WinUserLanguageList $ul -Force
Start-Process msedge -ArgumentList '--new-window', '--no-first-run', ('file:///' + ($html -replace '\\', '/'))
Start-Sleep 6
$root = [Windows.Automation.AutomationElement]::RootElement
function Box($n) { $root.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, $n))) }
function Val($e) { try { return $e.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { return '?' } }
function Ctr($e) { $r = $e.Current.BoundingRectangle; return @([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2)) }
for ($i = 0; $i -lt 10 -and -not ($a -and $b); $i++) { $a = Box 'boxa'; $b = Box 'boxb'; Start-Sleep 1 }
[void]$log.Add('found a=' + ($a -ne $null) + ' b=' + ($b -ne $null))
$cases = 'hel', 'vdhel', 'vd', 'ofc', 'vd1hel', 'hello'
foreach ($cs in $cases) {
  if (-not $a) { break }
  $pa = Ctr $a; [KE]::Click($pa[0], $pa[1]); Start-Sleep -Milliseconds 300
  [KE]::Key(0x1B, 0); Start-Sleep -Milliseconds 150
  $a.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue(''); $b.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('')
  [KE]::Click($pa[0], $pa[1]); Start-Sleep -Milliseconds 300
  foreach ($c in $cs.ToCharArray()) { [KE]::Key([uint16][int][char]([string]$c).ToUpper(), 0); Start-Sleep -Milliseconds 120 }
  Start-Sleep -Milliseconds 300
  $shown = Val $a
  $pb = Ctr $b; [KE]::Click($pb[0], $pb[1]); Start-Sleep -Milliseconds 600
  $after = Val $a
  # UIA Value in Edge can be stale; the page's own text is read back with Ctrl+A Ctrl+C (Esc first, KINFX idle).
  [System.Windows.Forms.Clipboard]::SetText('EMPTY')
  [KE]::Click($pa[0], $pa[1]); Start-Sleep -Milliseconds 300; [KE]::Key(0x1B, 0); Start-Sleep -Milliseconds 150
  [KE]::Key(0x41, 0x11); Start-Sleep -Milliseconds 150; [KE]::Key(0x43, 0x11); Start-Sleep -Milliseconds 400
  $clip = [System.Windows.Forms.Clipboard]::GetText()
  [void]$log.Add('CASE ' + $cs + ' SHOWN<' + $shown + '> UIA_AFTER<' + $after + '> PAGE_A<' + $clip + '>')
  [KE]::Key(0x1B, 0)
}
$tr = Join-Path $ud 'log\kx-trace.log'
if (Test-Path $tr) { Copy-Item $tr "$inst\$out-trace.txt" -Force; Remove-Item $tr }
Remove-Item (Join-Path $ud 'trace-on') -EA SilentlyContinue
Get-Process msedge -EA SilentlyContinue | Stop-Process -Force
$ul = Get-WinUserLanguageList; $ul[0].InputMethodTips.Clear(); foreach ($x in $saved) { $ul[0].InputMethodTips.Add($x) }; Set-WinUserLanguageList $ul -Force
[IO.File]::WriteAllLines("$inst\$out.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
Step 'done'
