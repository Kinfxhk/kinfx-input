$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class QAKeys {
 [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT {public ushort vk,scan;public uint flags,time;public IntPtr extra;}
 [StructLayout(LayoutKind.Explicit,Size=40)] public struct INPUT {[FieldOffset(0)]public uint type;[FieldOffset(8)]public KEYBDINPUT ki;}
 [DllImport("user32.dll")]static extern uint SendInput(uint n,INPUT[] a,int cb);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint data,UIntPtr extra);
 public static void Key(ushort vk,bool shift=false,bool ctrl=false){
  var l=new System.Collections.Generic.List<INPUT>();
  Action<ushort,uint> add=(v,f)=>{var x=new INPUT();x.type=1;x.ki.vk=v;x.ki.flags=f;l.Add(x);};
  if(ctrl)add(0x11,0);if(shift)add(0x10,0);add(vk,0);add(vk,2);if(shift)add(0x10,2);if(ctrl)add(0x11,2);
  uint n=SendInput((uint)l.Count,l.ToArray(),40);if(n!=l.Count)throw new Exception("SendInput failed "+n);
 }
}
[ComImport,Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IProfileMgr {[PreserveSig]int ActivateProfile(uint type,ushort lang,ref Guid cls,ref Guid profile,IntPtr hkl,uint flags);}
public static class QATsf {
 public static int Activate(){var m=(IProfileMgr)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));Guid c=new Guid("42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3"),p=new Guid("35BE04B0-E9E0-4E06-8438-10BFDCAE9E41");return m.ActivateProfile(1,0x404,ref c,ref p,IntPtr.Zero,0x10000000);}
}
'@
function Pump([int]$ms=40){$sw=[Diagnostics.Stopwatch]::StartNew();do{[Windows.Forms.Application]::DoEvents();if($ms -gt 0){Start-Sleep -Milliseconds 2}}while($sw.ElapsedMilliseconds -lt $ms)}
function Key([int]$vk,[bool]$shift=$false,[bool]$ctrl=$false){[QAKeys]::Key([uint16]$vk,$shift,$ctrl);Pump 20}
function Type-Code([string]$s){foreach($ch in $s.ToCharArray()){if($ch -eq ' '){Key 32}elseif($ch -eq '.'){Key 190}else{Key ([int][char]::ToUpperInvariant($ch)) ([char]::IsUpper($ch))}}}
function Click-Control($control,[int]$delay=30){$pt=$control.PointToScreen((New-Object Drawing.Point(30,15)));[void][QAKeys]::SetCursorPos($pt.X,$pt.Y);[QAKeys]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[QAKeys]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Pump $delay}
$results=New-Object Collections.Generic.List[object]
$f=New-Object Windows.Forms.Form;$f.Text='IME QA two-context focus';$f.Size=New-Object Drawing.Size(620,380);$f.StartPosition='Manual';$f.Location=New-Object Drawing.Point(30,30)
$a=New-Object Windows.Forms.TextBox;$a.Multiline=$true;$a.Location=New-Object Drawing.Point(10,20);$a.Size=New-Object Drawing.Size(580,120)
$b=New-Object Windows.Forms.TextBox;$b.Multiline=$true;$b.Location=New-Object Drawing.Point(10,170);$b.Size=New-Object Drawing.Size(580,120)
$f.Controls.AddRange(@($a,$b))
$g=New-Object Windows.Forms.Form;$g.Text='IME QA second window';$g.Size=New-Object Drawing.Size(620,220);$g.StartPosition='Manual';$g.Location=New-Object Drawing.Point(30,430)
$c=New-Object Windows.Forms.TextBox;$c.Multiline=$true;$c.Dock='Fill';$g.Controls.Add($c)
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1800
$timer.Add_Tick({
 $timer.Stop()
 try{
  $g.Show();[void][QAKeys]::SetForegroundWindow($f.Handle);Click-Control $a 100
  $hr=[QATsf]::Activate();Pump 500
  $meta=@{activation_hr=$hr;version=(Get-Item 'C:\Program Files\KINFX Input\KINFXInput.dll').VersionInfo.FileVersion;started=(Get-Date).ToString('o')}
  Type-Code 'vd1';Pump 100
  $baseline=$a.Text
  $results.Add([pscustomobject]@{case='baseline';expected=[string][char]0x597D;actual=$baseline;pass=($baseline -eq [string][char]0x597D);foreground=([QAKeys]::GetForegroundWindow() -eq $f.Handle)})
  if($baseline -ne [string][char]0x597D){throw 'IME baseline failed; no false focus PASS results'}
  $index=0
  foreach($delay in @(0,50,250)){
   foreach($prefix in @('','v','vd','vdhel')){
    foreach($mode in @('same-window','cross-window')){
     for($rep=0;$rep -lt 10;$rep++){
      Key 27;Click-Control $a 40;Key 27;$a.Clear();$b.Clear();$c.Clear()
      if($prefix){Type-Code $prefix}
      $target=$b;if($mode -eq 'cross-window'){$target=$c}
      Click-Control $target $delay
      Type-Code 'vd1';Pump 80
      $actual=$target.Text;$want=[string][char]0x597D
      $results.Add([pscustomobject]@{case='focus';index=$index;delay_ms=$delay;prefix=$prefix;mode=$mode;rep=$rep;expected=$want;actual=$actual;source=$a.Text;pass=($actual -eq $want);foreground=([QAKeys]::GetForegroundWindow() -eq $target.FindForm().Handle)})
      $index++
      if(($index%20)-eq 0){$results|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 C:\QA\focus-results.json}
     }
    }
   }
  }
  foreach($item in @(@('vd1',[string][char]0x597D),@('iPhone ','iPhone '),@('hello.vd1',('hello'+[char]0x3002+[char]0x597D)),@('openai.com ','openai.com '),@('llama.cpp ','llama.cpp '))){
   Key 27;Click-Control $a 30;Key 27;$a.Clear();Type-Code $item[0];Pump 100
   $results.Add([pscustomobject]@{case='smoke';keys=$item[0];expected=$item[1];actual=$a.Text;pass=($a.Text -eq $item[1])})
  }
  [Windows.Forms.Clipboard]::SetText('PASTE')
  foreach($prefix in @('vd','vdhel')){
   Key 27;Click-Control $a 30;Key 27;$a.Clear();Type-Code $prefix;Key 86 $false $true;Pump 300
   $want='PASTE';if($prefix -eq 'vdhel'){$want=([string][char]0x597D)+[char]0x53CD+'PASTE'}
   $results.Add([pscustomobject]@{case='paste';prefix=$prefix;expected=$want;actual=$a.Text;pass=($a.Text -eq $want)})
  }
  $meta.finished=(Get-Date).ToString('o');$meta|ConvertTo-Json|Set-Content -Encoding UTF8 C:\QA\focus-meta.json
 }catch{$_|Out-String|Set-Content C:\QA\focus-error.txt}finally{
  $results|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 C:\QA\focus-results.json
  'DONE'|Set-Content C:\QA\focus-done.txt
  $g.Close();$f.Close()
 }
})
$f.Add_Shown({$timer.Start()})
[Windows.Forms.Application]::Run($f)
