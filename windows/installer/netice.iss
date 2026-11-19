; Netice Windows kurulum programı (Inno Setup 6)
#define AppName "Netice"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F2A1C3E-8B4D-4E7A-9C51-2D7E0B9A4F10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Netice
DefaultDirName={localappdata}\Programs\Netice
DefaultGroupName=Netice
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=Netice-Kurulum
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\netice.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Netice"; Filename: "{app}\netice.exe"
Name: "{autodesktop}\Netice"; Filename: "{app}\netice.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\netice.exe"; Description: "{cm:LaunchProgram,Netice}"; Flags: nowait postinstall skipifsilent
