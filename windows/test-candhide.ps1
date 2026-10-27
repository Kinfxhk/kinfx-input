# Candidate window cleanup on focus loss. Run via vm/launch.ps1 as the logged-in user.
# The candidate list must never stay on screen when the host stops being the foreground window or
# hides its window (reported 2026-10-27: a WebView2 panel / launcher host left the list floating).
# Steps use the association list (vd1, no composition) so a composition-terminated callback cannot
# be what hides the window; step 5 types again to prove the IME still shows the list afterwards.
# Output: C:\Users\KinTest\inst\kx-candhide.txt (one line per step, written as it happens)
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
$out = "$inst\kx-candhide.txt"
Set-Content -Path $out -Value '' -Encoding UTF8
function Step($m) { Add-Content "$inst\kx-step.txt" ((Get-Date -f HH:mm:ss) + ' candhide ' + $m) }
function Log($m) { Add-Content -Path $out -Value ((Get-Date -f HH:mm:ss) + ' ' + $m) -Encoding UTF8 }
Step 'start'; Log 'start'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class KH {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
  public static void Key(ushort vk, ushort mod) {
    var l = new List<INPUT>();
    Action<ushort,uint> add = (v, f) => { var x = new INPUT(); x.type = 1; x.ki.wVk = v; x.ki.dwFlags = f; l.Add(x); };
    if (mod != 0) add(mod, 0);
    add(vk, 0); add(vk, 2);
    if (mod != 0) add(mod, 2);
    SendInput((uint)l.Count, l.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder b, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static string Cands(uint only) {
    var o = new List<string>();
    EnumWindows((h,l) => {
      var b = new StringBuilder(256); GetClassName(h,b,256);
      if (b.ToString() == "KINFXInputCand") { uint pid; GetWindowThreadProcessId(h, out pid);
        if (pid == only) { RECT r; GetWindowRect(h, out r);
          o.Add("visible=" + IsWindowVisible(h) + " rect=" + r.L + "," + r.T + "," + r.R + "," + r.B); } }
      return true; }, IntPtr.Zero);
    return o.Count > 0 ? string.Join(" | ", o.ToArray()) : "none";
  }
  public static bool AnyVisible(uint only) {
    bool v = false;
    EnumWindows((h,l) => {
      var b = new StringBuilder(256); GetClassName(h,b,256);
      if (b.ToString() == "KINFXInputCand") { uint pid; GetWindowThreadProcessId(h, out pid);
        if (pid == only && IsWindowVisible(h)) v = true; }
      return true; }, IntPtr.Zero);
    return v;
  }
}
[ComImport, Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKhMgr { [PreserveSig] int ActivateProfile(uint type, ushort lang, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags); }
public static class KhTsf {
  public static int Use() {
    var m = (IKhMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));
    Guid c = new Guid("42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3"), p = new Guid("35BE04B0-E9E0-4E06-8438-10BFDCAE9E41");
    return m.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x10000000);
  }
}
'@
[void][KH]::SetProcessDPIAware()
function Pump($n) { for ($i = 0; $i -lt $n; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 } }
$script:ok = $true
function Check($tag, $wantShown) {
  $me = [uint32]$PID
  $shown = [KH]::AnyVisible($me)
  $pass = $false
  if ($wantShown) { $pass = $shown } else { $pass = -not $shown }
  $word = 'FAIL '
  if ($pass) { $word = 'PASS ' }
  $line = $word + $tag + ' shown=' + $shown + ' fg=' + [KH]::GetForegroundWindow() + ' cands=' + ([KH]::Cands($me))
  Log $line
  if (-not $pass) { $script:ok = $false }
}
$f = New-Object Windows.Forms.Form
$f.Text = 'kx-candhide'; $f.Width = 600; $f.Height = 300; $f.TopMost = $true; $f.StartPosition = 'Manual'; $f.Left = 200; $f.Top = 200
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.Left = 10; $t.Top = 10; $t.Width = 560; $t.Height = 200; $t.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 14)
$f.Controls.Add($t)
$g = New-Object Windows.Forms.Form
$g.Text = 'kx-other'; $g.Width = 400; $g.Height = 200; $g.TopMost = $true; $g.StartPosition = 'Manual'; $g.Left = 950; $g.Top = 200
$g2 = New-Object Windows.Forms.TextBox; $g2.Dock = 'Fill'; $g2.Multiline = $true; $g.Controls.Add($g2)
$tm = New-Object Windows.Forms.Timer
$tm.Interval = 900
$f.Add_Shown({
  [void][KH]::ShowWindow($f.Handle, 5); $g.Show(); [void][KH]::ShowWindow($g.Handle, 5)
  [KH]::Key(0x12, 0); [void][KH]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus()
  Log ('activate=' + [KhTsf]::Use())
  $tm.Start()
})
$tm.Add_Tick({
  $tm.Stop()
  try {
    Pump 30
    # 1. association list is on screen
    [void][KH]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus(); Pump 10
    [void][KhTsf]::Use(); Pump 10
    [KH]::Key(0x56, 0); Pump 3; [KH]::Key(0x44, 0); Pump 3; [KH]::Key(0x31, 0); Pump 70
    Check '1 assoc shown' $true
    # 2. click another window: the list must not stay
    [KH]::Click(1100, 300); Pump 90
    Check '2 click other hidden' $false
    # 3. the list comes back when typing again
    [void][KH]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus(); Pump 10
    [KH]::Key(0x1B, 0); Pump 10
    [void][KhTsf]::Use(); Pump 10
    [KH]::Key(0x56, 0); Pump 3; [KH]::Key(0x44, 0); Pump 3; [KH]::Key(0x31, 0); Pump 70
    Check '3 assoc again' $true
    # 4. the host hides its window (launcher / WebView2 panel): the list must not stay
    [void][KH]::ShowWindow($f.Handle, 0); Pump 90
    Check '4 host hidden' $false
    # 5. restore and type: the IME still works
    [void][KH]::ShowWindow($f.Handle, 5); Pump 10
    [void][KH]::SetForegroundWindow($f.Handle); $f.Activate(); [void]$t.Focus(); Pump 10
    [void][KhTsf]::Use(); Pump 10
    [KH]::Key(0x54, 0); Pump 3; [KH]::Key(0x55, 0); Pump 70
    Check '5 typing again' $true
  } catch { Log ('ERROR ' + $_) }
  $res = 'FAIL'
  if ($script:ok) { $res = 'PASS 5/5' }
  Log ('RESULT ' + $res)
  Step 'done'
  $f.Close()
})
[Windows.Forms.Application]::Run($f)
