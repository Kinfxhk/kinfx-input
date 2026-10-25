$r = New-Object Collections.ArrayList
$dll = 'C:\Program Files\KINFX Input\KINFXInput.dll'
$src = 'C:\Users\KinTest\kx\out\KINFXInput.dll'
$srcHash = (Get-FileHash $src).Hash
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'")) {
  [void]$r.Add('ps pid=' + $p.ProcessId + ' start=' + $p.CreationDate + ' cmd=' + ($p.CommandLine -replace "`r?`n", ' '))
}
# Kill anything still holding the TIP, then swap the file (this is what a reboot would do).
foreach ($p in Get-Process powershell) {
  if ($p.Id -eq $PID) { continue }
  try {
    foreach ($m in $p.Modules) {
      if ($m.FileName -like '*KINFXInput.dll') { [void]$r.Add('killed holder pid=' + $p.Id); Stop-Process -Id $p.Id -Force; break }
    }
  } catch {}
}
Start-Sleep -Milliseconds 800
try {
  Copy-Item $src $dll -Force -ErrorAction Stop
  [void]$r.Add('copied=1')
} catch {
  [void]$r.Add('copy failed: ' + $_.Exception.Message.Split([char]10)[0])
}
$fi = Get-Item $dll
[void]$r.Add('dll ver=' + $fi.VersionInfo.FileVersion + ' size=' + $fi.Length + ' match=' + ((Get-FileHash $dll).Hash -eq $srcHash))
$reg = Start-Process regsvr32 -ArgumentList '/s', "`"$dll`"" -Wait -PassThru
[void]$r.Add('regsvr32 exit=' + $reg.ExitCode)
$d = Start-Process 'C:\Program Files\KINFX Input\KINFXSettings.exe' -ArgumentList '--deploy' -Wait -PassThru
[void]$r.Add('deploy exit=' + $d.ExitCode)
[void]$r.Add('data schema=' + (Get-FileHash 'C:\Program Files\KINFX Input\data\build\kinfx_quick.schema.yaml').Hash)
[IO.File]::WriteAllLines('C:\Users\KinTest\inst\kx-swap8.txt', [string[]]$r.ToArray())
