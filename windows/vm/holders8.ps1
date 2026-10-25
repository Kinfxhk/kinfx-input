$r = New-Object Collections.ArrayList
$dll = 'C:\Program Files\KINFX Input\KINFXInput.dll'
foreach ($p in Get-Process) {
  try {
    foreach ($m in $p.Modules) {
      if ($m.FileName -like '*KINFXInput.dll') { [void]$r.Add('holder pid=' + $p.Id + ' name=' + $p.ProcessName) ; break }
    }
  } catch {}
}
[void]$r.Add('done')
[IO.File]::WriteAllLines('C:\Users\KinTest\inst\kx-holders8.txt', [string[]]$r.ToArray())
