param([string]$Size = '5')
# Set page size the way the settings window does (settings.json + KINFXSettings --deploy), then run the real-key test.
$ud = Join-Path $env:APPDATA 'KINFX Input'
$p = Join-Path $ud 'settings.json'
$j = if (Test-Path $p) { Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } else { New-Object psobject }
$j | Add-Member -NotePropertyName page_size -NotePropertyValue ([int]$Size) -Force
[IO.File]::WriteAllText($p, ($j | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$d = Start-Process 'C:\Program Files\KINFX Input\KINFXSettings.exe' -ArgumentList '--deploy' -Wait -PassThru
Add-Content 'C:\Users\KinTest\inst\kx-step.txt' ("deploy exit=" + $d.ExitCode + " size=" + $Size)
& 'C:\Users\KinTest\inst\test-notepad.ps1'
Copy-Item 'C:\Users\KinTest\inst\kx-real.txt' ("C:\Users\KinTest\inst\kx-real-$Size.txt") -Force
