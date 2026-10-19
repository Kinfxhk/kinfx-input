$me = $PID
Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'wscript.exe') -and $_.ProcessId -ne $me } |
  ForEach-Object { "kill " + $_.ProcessId + " " + ($_.CommandLine -replace '.*\\inst\\', '') ; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-ScheduledTask KinfxX* -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
'clean'
