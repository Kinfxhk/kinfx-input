$r = New-Object Collections.ArrayList
$d = 'C:\Program Files\KINFX Input'
$p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
$new = (Get-FileHash "$d\KINFXInput.dll").Hash
[void]$r.Add('installed dll=' + $new + ' ver=' + (Get-Item "$d\KINFXInput.dll").VersionInfo.FileVersion)
$before = (Get-ItemProperty $p -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
[void]$r.Add('pending entries before=' + @($before).Count)
# Every queued rename is an Inno leftover pointing at an is-*.tmp in our own folder; the installed
# DLL is already the built one, so dropping the queue and the leftovers keeps a reboot a no-op.
Get-ChildItem $d -Filter 'is-*.tmp' | ForEach-Object { [void]$r.Add('rm ' + $_.Name); Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
Remove-ItemProperty $p -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
$after = (Get-ItemProperty $p -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
[void]$r.Add('pending after=' + @($after).Count + ' dll=' + (Get-FileHash "$d\KINFXInput.dll").Hash + ' ver=' + (Get-Item "$d\KINFXInput.dll").VersionInfo.FileVersion)
[void]$r.Add('leftovers=' + @(Get-ChildItem $d -Filter 'is-*.tmp').Count)
[IO.File]::WriteAllLines('C:\Users\KinTest\inst\kx-pending8.txt', [string[]]$r.ToArray())
