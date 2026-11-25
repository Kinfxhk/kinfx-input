$ErrorActionPreference = 'Continue'
$o = Join-Path $env:USERPROFILE 'inst\kx-install.txt'
$r = New-Object Collections.ArrayList
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
[void]$r.Add("admin=$isAdmin")
$setup = Join-Path $env:USERPROFILE 'kx\stage\out\KINFX-Input-0.1.5-Windows-x64.exe'
$setupLog = Join-Path $env:USERPROFILE 'inst\kx-setup.log'
$p = Start-Process $setup -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=$setupLog" -Wait -PassThru
[void]$r.Add("setup exit=" + $p.ExitCode)
[void]$r.Add("files=" + ((Get-ChildItem 'C:\Program Files\KINFX Input' -Name) -join ','))
[void]$r.Add("clsid=" + (Test-Path 'Registry::HKEY_CLASSES_ROOT\CLSID\{42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3}\InprocServer32'))
[void]$r.Add("tip=" + (Test-Path 'HKLM:\SOFTWARE\Microsoft\CTF\TIP\{42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3}'))
[void]$r.Add("userdir=" + ((Get-ChildItem "$env:APPDATA\KINFX Input" -Name -ErrorAction SilentlyContinue) -join ','))
[void]$r.Add("langs=" + (((Get-WinUserLanguageList) | ForEach-Object { $_.LanguageTag + ':' + ($_.InputMethodTips -join ',') }) -join ' | '))
[IO.File]::WriteAllLines($o, [string[]]$r.ToArray())
