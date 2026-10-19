param([string]$Script, [string]$Level = 'Limited')
$name = 'KinfxX' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "C:\Users\KinTest\inst\hidden.vbs" "C:\Users\KinTest\inst\' + $Script + '"')
$pr = New-ScheduledTaskPrincipal -UserId 'kinai\kintest' -LogonType Interactive -RunLevel $Level
Register-ScheduledTask -TaskName $name -Action $act -Principal $pr -Force | Out-Null
Start-ScheduledTask -TaskName $name
'started ' + $name
