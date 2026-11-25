$kx = Join-Path $env:USERPROFILE 'kx'
Remove-Item -Recurse -Force $kx -ErrorAction SilentlyContinue
Expand-Archive (Join-Path $env:USERPROFILE 'stage.zip') $kx -Force
cmd /c "chcp 65001 >nul & `"$kx\stage\build.cmd`"" 2>&1 | Select-Object -Last 40
"exit=$LASTEXITCODE"
