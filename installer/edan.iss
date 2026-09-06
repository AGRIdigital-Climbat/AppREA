; Script Inno Setup para EDAN - Evaluación de Daños y Necesidades
; Genera Instalador_EDAN.exe a partir de build\windows\x64\runner\Release\
; Última compilación: flutter build windows --release

#define MyAppName "EDAN"
#define MyAppVersion "1.0.7"
#define MyAppPublisher "net.climbat"
#define MyAppExeName "EDAN.exe"

[Setup]
AppId={{4E3D1F2A-8B7C-4A9E-9D1B-2C3D4E5F6A7B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\EDAN
DefaultGroupName=EDAN
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Instalador_EDAN
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=admin
AppPublisherURL=https://climbat.net
UsePreviousAppDir=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\net.climbat\EDAN\"
Type: filesandordirs; Name: "{userappdata}\com.climbat.rea\"