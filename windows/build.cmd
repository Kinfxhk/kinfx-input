@echo off
rem Build KINFX Input for Windows inside windows\build\stage (made by gen.py). Needs MSVC x64 + Inno Setup 6.
setlocal
cd /d "%~dp0"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
if exist out rmdir /s /q out
mkdir out obj
set CF=/nologo /O2 /MT /EHsc /utf-8 /W3 /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS /D_CRT_NONSTDC_NO_DEPRECATE /Irime /I. /Itip
cl %CF% /c rime\kx_shim.c tip\core.cpp tip\tip.cpp tip\selftest.cpp /Foobj\ || exit /b 1
rc /nologo /fo obj\kx.res kx.rc || exit /b 1
rem rime.dll is delay-loaded: the host app's search path does not include our folder (core.cpp loads it by full path).
link /nologo /DLL /DEF:tip\tip.def /OUT:out\KINFXInput.dll obj\kx_shim.obj obj\core.obj obj\tip.obj obj\kx.res rime\rime.lib ^
  delayimp.lib /DELAYLOAD:rime.dll ole32.lib oleaut32.lib uuid.lib user32.lib gdi32.lib advapi32.lib shell32.lib || exit /b 1
link /nologo /OUT:out\kx-selftest.exe obj\kx_shim.obj obj\core.obj obj\selftest.obj rime\rime.lib ^
  delayimp.lib /DELAYLOAD:rime.dll user32.lib shell32.lib ole32.lib advapi32.lib || exit /b 1
%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /platform:x64 /codepage:65001 /win32icon:kinfx.ico ^
  /r:System.Web.Extensions.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:out\KINFXSettings.exe settings\Settings.cs || exit /b 1
copy /y rime\rime.dll out\ >nul
xcopy /e /i /q /y data out\data >nul
copy /y app-info.json out\ >nul
copy /y settings-spec.json out\ >nul
copy /y kinfx.ico out\ >nul
copy /y enable.ps1 out\ >nul
rem self-test in a throwaway user dir
set KX_USER=%TEMP%\kx-selftest-%RANDOM%
mkdir "%KX_USER%"
out\kx-selftest.exe || exit /b 1
set KX_USER=
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /Q installer.iss || exit /b 1
dir /b out\*.exe
