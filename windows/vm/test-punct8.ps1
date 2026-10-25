# 0.1.8 real-key harness. ASCII-only source (expected glyphs are code points) because PowerShell 5.1
# on the zh-TW VM mis-parses this file when it carries UTF-8 non-ASCII text.
# Every punctuation key must commit exactly one glyph with NO candidate window (no full/half menu),
# Shift+Space toggles full shape, plus vd1 / Ctrl+Space / Ctrl+Shift / Ctrl+C+V and the mode badges.
# Output: C:\Users\KinTest\inst\kx-punct8.txt + kx-shot-*.png
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
function Step($m) { Add-Content "$inst\kx-step8.txt" ((Get-Date -f HH:mm:ss) + ' ' + $m) }
Step 'start'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KQ {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  static void Emit(ushort vk, uint f, System.Collections.Generic.List<INPUT> l) {
    var x = new INPUT(); x.type = 1; x.ki.wVk = vk; x.ki.dwFlags = f; l.Add(x);
  }
  public static void Key(ushort vk, ushort mod) {
    var l = new System.Collections.Generic.List<INPUT>();
    if (mod != 0) Emit(mod, 0, l);
    Emit(vk, 0, l); Emit(vk, 2, l);
    if (mod != 0) Emit(mod, 2, l);
    SendInput((uint)l.Count, l.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Chord() {
    var l = new System.Collections.Generic.List<INPUT>();
    Emit(0x11, 0, l); Emit(0x10, 0, l); Emit(0x10, 2, l); Emit(0x11, 2, l);
    SendInput((uint)l.Count, l.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
  public static string Cand() {
    IntPtr h = FindWindow("KINFXInputCand", null);
    if (h == IntPtr.Zero) return "none";
    RECT r; GetWindowRect(h, out r);
    return (IsWindowVisible(h) ? "shown" : "hidden") + ":" + (r.r - r.l) + "x" + (r.b - r.t);
  }
  public static string C = "42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3", P = "35BE04B0-E9E0-4E06-8438-10BFDCAE9E41";
  public static int Use() { var m = (IMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED"))); Guid c = new Guid(C), p = new Guid(P); return m.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x20000000); }
}
[ComImport, Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMgr { [PreserveSig] int ActivateProfile(uint type, ushort lang, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags); }
'@
[void][KQ]::SetProcessDPIAware()
$ud = Join-Path $env:APPDATA 'KINFX Input'
New-Item -ItemType File -Force (Join-Path $ud 'trace-on') | Out-Null
Remove-Item (Join-Path $ud 'log\kx-trace.log') -ErrorAction SilentlyContinue
$log = New-Object Collections.ArrayList
$b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
[void]$log.Add('screen=' + $b.Width + 'x' + $b.Height)
$f = New-Object Windows.Forms.Form
$f.Text = 'kx-punct8'; $f.StartPosition = 'Manual'; $f.SetBounds(80, 60, 720, 420); $f.TopMost = $true
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.Dock = 'Fill'; $t.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 16)
$f.Controls.Add($t)
$pump = { for ($i = 0; $i -lt 24; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 12 } }
$shotFull = {
  param($name)
  $bb = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object Drawing.Bitmap $bb.Width, $bb.Height
  $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($bb.Location, [Drawing.Point]::Empty, $bb.Size)
  $bmp.Save("$inst\$name.png"); $g.Dispose(); $bmp.Dispose()
}
# Crop a screen region and upscale 3x (nearest neighbour) so the tray / badge glyphs are readable.
$crop = {
  param($name, $x, $y, $w, $h)
  $bb = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $x = [int][Math]::Max(0, [Math]::Min($x, $bb.Width - 8)); $y = [int][Math]::Max(0, [Math]::Min($y, $bb.Height - 8))
  $w = [int][Math]::Min($w, $bb.Width - $x); $h = [int][Math]::Min($h, $bb.Height - $y)
  $src = New-Object Drawing.Bitmap $bb.Width, $bb.Height
  $g0 = [Drawing.Graphics]::FromImage($src); $g0.CopyFromScreen($bb.Location, [Drawing.Point]::Empty, $bb.Size)
  $small = New-Object Drawing.Bitmap $w, $h
  $g1 = [Drawing.Graphics]::FromImage($small)
  $g1.DrawImage($src, (New-Object Drawing.Rectangle 0, 0, $w, $h), (New-Object Drawing.Rectangle $x, $y, $w, $h), 'Pixel')
  $big = New-Object Drawing.Bitmap ($w * 3), ($h * 3)
  $g2 = [Drawing.Graphics]::FromImage($big)
  $g2.InterpolationMode = 'NearestNeighbor'
  $g2.DrawImage($small, 0, 0, ($w * 3), ($h * 3))
  $big.Save("$inst\$name.png")
  $g0.Dispose(); $g1.Dispose(); $g2.Dispose(); $src.Dispose(); $small.Dispose(); $big.Dispose()
}
$tm = New-Object Windows.Forms.Timer
$tm.Interval = 1200
$f.Add_Shown({
  Step 'shown'
  [void][KQ]::ShowWindow($f.Handle, 5)
  [void][KQ]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  $tm.Start()
})
$tm.Add_Tick({
  $tm.Stop(); Step 'typing'
  [KQ]::Key(0x12, 0); [void][KQ]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  [void]$log.Add('use hr=' + [KQ]::Use())
  & $pump
  [void]$log.Add('fg=' + ([KQ]::GetForegroundWindow() -eq $f.Handle))
  # label, vk, shift, expected code point
  $keys = @(
    @(',', 0xBC, 0, 0xFF0C), @('.', 0xBE, 0, 0x3002), @('?', 0xBF, 1, 0xFF1F), @('!', 0x31, 1, 0xFF01),
    @(';', 0xBA, 0, 0xFF1B), @(':', 0xBA, 1, 0xFF1A), @('(', 0x39, 1, 0xFF08), @(')', 0x30, 1, 0xFF09),
    @('[', 0xDB, 0, 0x300C), @(']', 0xDD, 0, 0x300D), @('{', 0xDB, 1, 0x300E), @('}', 0xDD, 1, 0x300F),
    @('<', 0xBC, 1, 0x300A), @('>', 0xBE, 1, 0x300B), @('\', 0xDC, 0, 0x3001), @("'", 0xDE, 0, 0x2018),
    @('"', 0xDE, 1, 0x201C), @('/', 0xBF, 0, 0x2F), @('-', 0xBD, 0, 0x2D), @('$', 0x34, 1, 0x24),
    @('%', 0x35, 1, 0x25), @('*', 0x38, 1, 0x2A), @('~', 0xC0, 1, 0x7E))
  [void]$log.Add('key' + "`t" + 'want' + "`t" + 'got-hex' + "`t" + 'cand' + "`t" + 'verdict')
  foreach ($k in $keys) {
    $before = $t.Text
    [KQ]::Key([uint16]$k[1], [uint16]($k[2] * 0x10))
    & $pump; & $pump
    $after = $t.Text
    $got = if ($after.Length -gt $before.Length) { $after.Substring($before.Length) } else { '' }
    $cand = [KQ]::Cand()
    $hex = (($got.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ',')
    $ok = if ($got -eq [string][char]$k[3] -and $cand -notlike 'shown*') { 'PASS' } else { 'FAIL' }
    [void]$log.Add($k[0] + "`t" + ('{0:X4}' -f $k[3]) + "`t" + $hex + "`t" + $cand + "`t" + $ok)
  }
  & $shotFull 'kx-shot-punct'
  & $crop 'kx-shot-tray' ($b.Width - 360) ($b.Height - 56) 360 56
  Step 'table-done'
  # Shift+Space -> full shape, then back to half shape.
  $t.Clear(); & $pump
  [KQ]::Key(0x20, 0x10); & $pump
  foreach ($k in @(@(',', 0xBC, 0, 0xFF0C), @('/', 0xBF, 0, 0xFF0F), @('*', 0x38, 1, 0xFF0A))) {
    $before = $t.Text
    [KQ]::Key([uint16]$k[1], [uint16]($k[2] * 0x10)); & $pump
    $got = if ($t.Text.Length -gt $before.Length) { $t.Text.Substring($before.Length) } else { '' }
    [void]$log.Add('full ' + $k[0] + "`t" + ('{0:X4}' -f $k[3]) + "`t" + ((($got.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ',')) + "`t" + [KQ]::Cand() + "`t" + $(if ($got -eq [string][char]$k[3]) { 'PASS' } else { 'FAIL' }))
  }
  [KQ]::Key(0x20, 0x10); & $pump
  foreach ($k in @(@('/', 0xBF, 0, 0x2F), @('*', 0x38, 1, 0x2A), @(',', 0xBC, 0, 0xFF0C))) {
    $before = $t.Text
    [KQ]::Key([uint16]$k[1], [uint16]($k[2] * 0x10)); & $pump
    $got = if ($t.Text.Length -gt $before.Length) { $t.Text.Substring($before.Length) } else { '' }
    [void]$log.Add('half ' + $k[0] + "`t" + ('{0:X4}' -f $k[3]) + "`t" + ((($got.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ',')) + "`t" + [KQ]::Cand() + "`t" + $(if ($got -eq [string][char]$k[3]) { 'PASS' } else { 'FAIL' }))
  }
  Step 'shape-done'
  # Regression: vd1 -> U+597D (hao)
  $hao = [string][char]0x597D
  $t.Clear(); & $pump
  foreach ($vk in @(0x56, 0x44, 0x31)) { [KQ]::Key([uint16]$vk, 0); & $pump }
  [KQ]::Key(0x0D, 0); & $pump
  [void]$log.Add('reg vd1' + "`t" + '597D' + "`t" + ((($t.Text.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ',')) + "`t" + $(if ($t.Text -eq $hao) { 'PASS' } else { 'FAIL' }))
  # Ctrl+Space -> EN: letters stay ASCII; back -> ZH: vd1 gives hao again.
  [KQ]::Key(0x20, 0x11); & $pump
  $t.Clear(); & $pump
  foreach ($vk in @(0x41, 0x42)) { [KQ]::Key([uint16]$vk, 0); & $pump }
  [void]$log.Add('reg ctrl+space en' + "`t" + 'ab' + "`t" + $t.Text + "`t" + $(if ($t.Text -eq 'ab') { 'PASS' } else { 'FAIL' }))
  [KQ]::Key(0x20, 0x11); & $pump
  $t.Clear(); & $pump
  foreach ($vk in @(0x56, 0x44, 0x31)) { [KQ]::Key([uint16]$vk, 0); & $pump }
  [KQ]::Key(0x0D, 0); & $pump
  [void]$log.Add('reg ctrl+space zh' + "`t" + '597D' + "`t" + ((($t.Text.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ',')) + "`t" + $(if ($t.Text -eq $hao) { 'PASS' } else { 'FAIL' }))
  # Bare Ctrl+Shift chord -> EN, letters ASCII, chord back.
  $t.Clear(); & $pump
  [KQ]::Chord(); & $pump; & $pump
  $t.Clear(); & $pump
  foreach ($vk in @(0x43, 0x44)) { [KQ]::Key([uint16]$vk, 0); & $pump }
  [void]$log.Add('reg ctrl+shift en' + "`t" + 'cd' + "`t" + $t.Text + "`t" + $(if ($t.Text -eq 'cd') { 'PASS' } else { 'FAIL' }))
  [KQ]::Chord(); & $pump; & $pump
  # Ctrl+C / Ctrl+V in the same box.
  $t.Clear(); & $pump
  foreach ($vk in @(0x56, 0x44, 0x31)) { [KQ]::Key([uint16]$vk, 0); & $pump }
  [KQ]::Key(0x0D, 0); & $pump
  [KQ]::Key(0x41, 0x11); & $pump
  [KQ]::Key(0x43, 0x11); & $pump
  [KQ]::Key(0x45, 0x11); & $pump
  [KQ]::Key(0x56, 0x11); & $pump; & $pump
  $dd = $hao + $hao
  [void]$log.Add('reg ctrl+c/v' + "`t" + '597D597D' + "`t" + ((($t.Text.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ',')) + "`t" + $(if ($t.Text -eq $dd) { 'PASS' } else { 'FAIL' }))
  Step 'reg-done'
  # Mode badge at the caret (400 ms 中/英 hint after each switch).
  $t.Clear(); & $pump
  $p0 = $t.PointToScreen((New-Object Drawing.Point 0, 0))
  [void]$log.Add('badge origin=' + $p0.X + ',' + $p0.Y)
  [KQ]::Key(0x20, 0x11)
  for ($i = 0; $i -lt 8; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 12 }
  & $crop 'kx-shot-badge-en' ($p0.X - 4) ($p0.Y - 4) 200 90
  [KQ]::Key(0x20, 0x11)
  for ($i = 0; $i -lt 8; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 12 }
  & $crop 'kx-shot-badge-zh' ($p0.X - 4) ($p0.Y - 4) 200 90
  Step 'badges-done'
  $tr = Join-Path $ud 'log\kx-trace.log'
  if (Test-Path $tr) { foreach ($l in (Get-Content $tr -Encoding UTF8)) { if ($l -match '^(commit|langbar|conversion|hint)') { [void]$log.Add('trace ' + $l) } } }
  Remove-Item (Join-Path $ud 'trace-on') -ErrorAction SilentlyContinue
  [IO.File]::WriteAllLines("$inst\kx-punct8.txt", [string[]]$log.ToArray(), (New-Object Text.UTF8Encoding($false)))
  Step 'done'
  $f.Close()
})
[Windows.Forms.Application]::Run($f)
Step 'exit'
