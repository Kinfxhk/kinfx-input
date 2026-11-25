param([string]$Script, [string]$Level = 'Limited')
$name = 'KinfxX' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$inst = Join-Path $env:USERPROFILE 'inst'
$act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "' + (Join-Path $inst 'hidden.vbs') + '" "' + (Join-Path $inst $Script) + '"')
$pr = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel $Level
Register-ScheduledTask -TaskName $name -Action $act -Principal $pr -Force | Out-Null
Start-ScheduledTask -TaskName $name
'started ' + $name
