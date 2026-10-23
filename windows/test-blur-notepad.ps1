# Blur check in Notepad: type through KINFX, then click (A) lower in the same document or (W) on the
# desktop, come back, read the document with Ctrl+A Ctrl+C. Output: C:\Users\KinTest\inst\kx-np-<ime>.txt
param([string]$Ime = 'kinfx')
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KN {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
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
  public static string C = "42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3", P = "35BE04B0-E9E0-4E06-8438-10BFDCAE9E41";
  // TF_IPPMF_FORSESSION: the focused app (notepad, not this script) gets the profile.
  public static int Use() {
    var mgr = (IKxMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));
    Guid c = new Guid(C), p = new Guid(P);
    return mgr.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x20000000);
  }
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
}
[ComImport, Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKxMgr {
  [PreserveSig] int ActivateProfile(uint type, ushort lang, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags);
}
'@
[void][KN]::SetProcessDPIAware()
$log = New-Object Collections.ArrayList
$ud = Join-Path $env:APPDATA 'KINFX Input'
if ($Ime -eq 'kinfx') { New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null; Remove-Item (Join-Path $ud 'log\kx-trace.log') -EA SilentlyContinue }
$kx = '0404:{42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3}{35BE04B0-E9E0-4E06-8438-10BFDCAE9E41}'
if ($Ime -eq 'weasel') { [KN]::C = 'A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A'; [KN]::P = '3D02CAB6-2B8E-4781-BA20-1C9267529467' }
if ($Ime -eq 'msquick') { [KN]::C = '531FDEBF-9B4C-4A43-A2AA-960E8FCDC732'; [KN]::P = '6024B45F-5C54-11D4-B921-0080C882687E' }
if ($Ime -eq 'weasel') { $kx = '0404:{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}{3D02CAB6-2B8E-4781-BA20-1C9267529467}' }
if ($Ime -eq 'msquick') { $kx = '0404:{531FDEBF-9B4C-4A43-A2AA-960E8FCDC732}{6024B45F-5C54-11D4-B921-0080C882687E}' }
$ul = Get-WinUserLanguageList; $saved = $ul[0].InputMethodTips | ForEach-Object { $_ }
$ul[0].InputMethodTips.Remove($kx) | Out-Null; $ul[0].InputMethodTips.Insert(0, $kx); Set-WinUserLanguageList $ul -Force
Get-Process notepad -EA SilentlyContinue | Stop-Process -Force; Start-Sleep 1
Start-Process notepad; Start-Sleep 4
$root = [Windows.Automation.AutomationElement]::RootElement
$np = $null
for ($i = 0; $i -lt 10 -and -not $np; $i++) {
  $w = $root.FindFirst([Windows.Automation.TreeScope]::Children, (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ClassNameProperty, 'Notepad')))
  if ($w) { $np = $w.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Document))) }
  if (-not $np -and $w) { $np = $w.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit))) }
  Start-Sleep 1
}
[void]$log.Add('found=' + ($np -ne $null) + ' class=' + $np.Current.ClassName)
$r = $np.Current.BoundingRectangle
$top = @([int]($r.Left + 40), [int]($r.Top + 20)); $low = @([int]($r.Left + 200), [int]($r.Bottom - 30))
$desk = @(([Windows.Forms.Screen]::PrimaryScreen.Bounds.Width - 40), 400)
function Read() {
  [System.Windows.Forms.Clipboard]::SetText('EMPTY')
  [KN]::Key(0x41, 0x11); Start-Sleep -Milliseconds 150; [KN]::Key(0x43, 0x11); Start-Sleep -Milliseconds 400
  $t = [System.Windows.Forms.Clipboard]::GetText(); [KN]::Key(0x23, 0x11)
  return ($t -replace "`r`n", '\n' -replace "`n", '\n')
}
$cases = 'A:hel', 'A:hel', 'A:vdhel', 'A:vd', 'A:ofc', 'A:hello', 'W:hel', 'W:vdhel', 'W:vd', 'W:hello', 'A:hel'
foreach ($cs in $cases) {
  $mode, $keys = $cs.Split(':', 2)
  [KN]::Click($top[0], $top[1]); Start-Sleep -Milliseconds 300; [KN]::Key(0x1B, 0); Start-Sleep -Milliseconds 100
  [KN]::Key(0x41, 0x11); [KN]::Key(0x2E, 0); Start-Sleep -Milliseconds 200
  [KN]::Key(0x0D, 0); [KN]::Key(0x0D, 0); [KN]::Key(0x0D, 0); [KN]::Key(0x24, 0x11); Start-Sleep -Milliseconds 200
  $hr = [KN]::Use(); Start-Sleep -Milliseconds 300
  foreach ($c in $keys.ToCharArray()) { [KN]::Key([uint16][int][char]([string]$c).ToUpper(), 0); Start-Sleep -Milliseconds 120 }
  Start-Sleep -Milliseconds 300
  if ($mode -eq 'A') { [KN]::Click($low[0], $low[1]) } else { [KN]::Click($desk[0], $desk[1]); Start-Sleep -Milliseconds 500; [KN]::Click($low[0], $low[1]) }
  Start-Sleep -Milliseconds 600
  [KN]::Key(0x1B, 0); Start-Sleep -Milliseconds 150
  [void]$log.Add('CASE ' + $cs + ' hr=' + $hr + ' DOC<' + (Read) + '>')
}
[KN]::Key(0x41, 0x11); [KN]::Key(0x2E, 0)
Get-Process notepad -EA SilentlyContinue | Stop-Process -Force
if ($Ime -eq 'kinfx') { Copy-Item (Join-Path $ud 'log\kx-trace.log') "$inst\kx-np-trace.txt" -Force -EA SilentlyContinue; Remove-Item (Join-Path $ud 'trace-on'), (Join-Path $ud 'log\kx-trace.log') -EA SilentlyContinue }
$ul = Get-WinUserLanguageList; $ul[0].InputMethodTips.Clear(); foreach ($x in $saved) { $ul[0].InputMethodTips.Add($x) }; Set-WinUserLanguageList $ul -Force
[IO.File]::WriteAllLines("$inst\kx-np-$Ime.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
