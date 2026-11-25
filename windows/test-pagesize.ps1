param([string]$Size = '5')
# Set page size the way the settings window does (settings.json + KINFXSettings --deploy), then run the real-key test.
$ud = Join-Path $env:APPDATA 'KINFX Input'
$p = Join-Path $ud 'settings.json'
$j = if (Test-Path $p) { Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } else { New-Object psobject }
$j | Add-Member -NotePropertyName page_size -NotePropertyValue ([int]$Size) -Force
[IO.File]::WriteAllText($p, ($j | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$d = Start-Process 'C:\Program Files\KINFX Input\KINFXSettings.exe' -ArgumentList '--deploy' -Wait -PassThru
$inst = Join-Path $env:USERPROFILE 'inst'
Add-Content (Join-Path $inst 'kx-step.txt') ("deploy exit=" + $d.ExitCode + " size=" + $Size)
& (Join-Path $inst 'test-notepad.ps1')
Copy-Item (Join-Path $inst 'kx-real.txt') (Join-Path $inst "kx-real-$Size.txt") -Force
