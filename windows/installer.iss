; KINFX Input Windows installer (Inno Setup 6). Built by build.cmd from windows\build\stage.
#define Ver "0.1.2"
[Setup]
AppId={{D71D8CE6-CDFB-4F06-B416-5C60A93B7FE0}
AppName=KINFX Input
AppVersion={#Ver}
AppPublisher=KINFX
AppPublisherURL=https://buymeacoffee.com/kinfxhk
DefaultDirName={autopf}\KINFX Input
DefaultGroupName=KINFX Input
DisableProgramGroupPage=yes
DisableDirPage=yes
; TSF registration writes HKCR, so a per-machine install with admin rights.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=out
OutputBaseFilename=KINFX-Input-{#Ver}-Windows-x64
SetupIconFile=kinfx.ico
UninstallDisplayIcon={app}\KINFXSettings.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartIfNeededByRun=no

[Languages]
Name: "zh"; MessagesFile: "ChineseTraditional.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
; A loaded TIP DLL cannot be overwritten; restartreplace finishes it after reboot.
Source: "out\KINFXInput.dll"; DestDir: "{app}"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "out\rime.dll"; DestDir: "{app}"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "out\KINFXSettings.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "out\app-info.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "out\settings-spec.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "out\kinfx.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "out\enable.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "out\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\KINFX Input 設定"; Filename: "{app}\KINFXSettings.exe"

[Run]
Filename: "{sys}\regsvr32.exe"; Parameters: "/s ""{app}\KINFXInput.dll"""; Flags: runhidden waituntilterminated
; Per-user steps run as the user who started the installer: first build + add to 繁中 input methods.
Filename: "{app}\KINFXSettings.exe"; Parameters: "--deploy"; Flags: runasoriginaluser runhidden waituntilterminated
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\enable.ps1"""; Flags: runasoriginaluser runhidden waituntilterminated
Filename: "{app}\KINFXSettings.exe"; Description: "開啟 KINFX Input 設定"; Flags: postinstall nowait skipifsilent runasoriginaluser

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\enable.ps1"" -Remove"; Flags: runhidden waituntilterminated; RunOnceId: "kxdisable"
Filename: "{sys}\regsvr32.exe"; Parameters: "/s /u ""{app}\KINFXInput.dll"""; Flags: runhidden waituntilterminated; RunOnceId: "kxunreg"
