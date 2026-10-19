Remove-Item -Recurse -Force C:\Users\KinTest\kx -ErrorAction SilentlyContinue
Expand-Archive C:\Users\KinTest\stage.zip C:\Users\KinTest\kx -Force
cmd /c "chcp 65001 >nul & C:\Users\KinTest\kx\stage\build.cmd" 2>&1 | Select-Object -Last 40
"exit=$LASTEXITCODE"
