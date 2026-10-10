; Uban Windows 安裝程式（Inno Setup 6）
; 編譯前需先由 build_installer.ps1 準備 payload\（Uban.apk 與 platform-tools）
#define MyAppName "Uban"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "國立臺北商業大學 資訊管理系 第115207組"

[Setup]
AppId={{B7D3E4A1-5C2F-4E8B-9A61-3F0D8C27E5B4}
AppName={#MyAppName}
AppVerName=Uban AI 跨世代感知照護系統 {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\Uban
DefaultGroupName=Uban
SetupIconFile=uban.ico
UninstallDisplayIcon={app}\uban.ico
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir=Output
OutputBaseFilename=Uban_Setup_{#MyAppVersion}
ArchitecturesInstallIn64BitMode=x64compatible
InfoBeforeFile=安裝說明.txt

[Languages]
Name: "chinesetraditional"; MessagesFile: "ChineseTraditional.isl"

[Tasks]
Name: "desktopicon"; Description: "建立桌面捷徑"; GroupDescription: "額外工作:"

[Files]
Source: "payload\Uban.apk"; DestDir: "{app}"; Flags: ignoreversion
Source: "payload\platform-tools\*"; DestDir: "{app}\platform-tools"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "install_app.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uban.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "安裝說明.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\安裝 Uban 到手機"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install_app.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\uban.ico"
Name: "{group}\Uban 安裝檔資料夾"; Filename: "{app}"
Name: "{group}\安裝說明"; Filename: "{app}\安裝說明.txt"
Name: "{group}\解除安裝 Uban"; Filename: "{uninstallexe}"
Name: "{autodesktop}\安裝 Uban 到手機"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install_app.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\uban.ico"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install_app.ps1"""; WorkingDir: "{app}"; Description: "立即將 Uban 安裝到手機"; Flags: postinstall skipifsilent
Filename: "{app}\安裝說明.txt"; Description: "開啟安裝說明"; Flags: postinstall shellexec unchecked skipifsilent

[UninstallRun]
Filename: "{app}\platform-tools\adb.exe"; Parameters: "kill-server"; Flags: runhidden; RunOnceId: "AdbKillServer"
