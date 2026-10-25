# Install the built 0.1.8 exe (silent, admin) and swap the loaded TIP DLL without a reboot:
# stop ctfmon (it holds the TIP) + explorer, copy, re-register, redeploy. Writes inst\kx-install8.txt.
$ErrorActionPreference = 'Continue'
$inst = 'C:\Users\KinTest\inst'
New-Item -ItemType Directory -Force $inst | Out-Null
$r = New-Object Collections.ArrayList
$src = 'C:\Users\KinTest\kx\out'
$dst = 'C:\Program Files\KINFX Input'
$exe = "$src\KINFX-Input-0.1.8-Windows-x64.exe"
[void]$r.Add('exe=' + (Test-Path $exe) + ' size=' + (Get-Item $exe).Length + ' sha=' + (Get-FileHash $exe).Hash)
$p = Start-Process $exe -ArgumentList '/SILENT', '/NORESTART', "/LOG=$inst\install-0.1.8.log" -Wait -PassThru
[void]$r.Add('installer exit=' + $p.ExitCode)
[void]$r.Add('pending=' + ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations -join '|'))
$srcHash = (Get-FileHash "$src\KINFXInput.dll").Hash
[void]$r.Add("after-install dll-match=" + ((Get-FileHash "$dst\KINFXInput.dll").Hash -eq $srcHash))
for ($i = 0; $i -lt 12; $i++) {
  if ((Get-FileHash "$dst\KINFXInput.dll" -ErrorAction SilentlyContinue).Hash -eq $srcHash) { break }
  Stop-Process -Name ctfmon -Force -ErrorAction SilentlyContinue
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 600
  try {
    Copy-Item "$src\KINFXInput.dll" "$dst\KINFXInput.dll" -Force -ErrorAction Stop
    [void]$r.Add("dll-copied try=$i")
    break
  } catch {
    [void]$r.Add("try=$i " + $_.Exception.Message.Split([char]10)[0])
    Start-Sleep -Milliseconds 500
  }
}
Copy-Item "$src\KINFXInput.dll" "$dst\KINFXInput.dll" -Force -ErrorAction SilentlyContinue
Copy-Item "$src\app-info.json" "$dst\app-info.json" -Force
Copy-Item "$src\settings-spec.json" "$dst\settings-spec.json" -Force
$reg = Start-Process regsvr32 -ArgumentList '/s', "`"$dst\KINFXInput.dll`"" -Wait -PassThru
[void]$r.Add('regsvr32 exit=' + $reg.ExitCode)
$fi = Get-Item "$dst\KINFXInput.dll"
[void]$r.Add('installed dll=' + $fi.LastWriteTime.ToString('s') + ' size=' + $fi.Length + ' ver=' + $fi.VersionInfo.FileVersion + ' hash=' + (Get-FileHash $fi.FullName).Hash)
[void]$r.Add('src-hash=' + $srcHash)
[void]$r.Add('exe ver=' + (Get-Item "$dst\KINFXSettings.exe").VersionInfo.FileVersion)
[void]$r.Add('data punct=' + ((Get-FileHash "$dst\data\build\punctuation.yaml" -ErrorAction SilentlyContinue).Hash) + ' schema=' + ((Get-FileHash "$dst\data\build\kinfx_quick.schema.yaml" -ErrorAction SilentlyContinue).Hash))
$d = Start-Process "$dst\KINFXSettings.exe" -ArgumentList '--deploy' -Wait -PassThru
[void]$r.Add('deploy exit=' + $d.ExitCode)
$hk = 'HKCU:\Control Panel\Input Method\Hot Keys\00000010'
$tg = 'HKCU:\Keyboard Layout\Toggle'
function V($p, $n) {
  $v = (Get-ItemProperty -Path $p -Name $n -ErrorAction SilentlyContinue).$n
  if ($null -eq $v) { 'absent' } elseif ($v -is [byte[]]) { [BitConverter]::ToUInt32($v, 0) } else { $v }
}
[void]$r.Add('hotkeys mod=' + (V $hk 'Key Modifiers') + ' vk=' + (V $hk 'Virtual Key') + ' lang=' + (V $tg 'Language Hotkey') + ' layout=' + (V $tg 'Layout Hotkey'))
[void]$r.Add('explorer=' + @(Get-Process explorer -ErrorAction SilentlyContinue).Count + ' ctfmon=' + @(Get-Process ctfmon -ErrorAction SilentlyContinue).Count)
[IO.File]::WriteAllLines("$inst\kx-install8.txt", [string[]]$r.ToArray())
