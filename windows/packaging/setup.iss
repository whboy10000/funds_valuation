; Inno Setup script for Fund Valuation (Windows x64 installer).
; APP_VERSION is passed from CI via `ISCC /DAPP_VERSION=x.y.z`.
; Text kept in ASCII to avoid code-page issues on the compiler.

[Setup]
AppName=Fund Valuation
AppVersion={#APP_VERSION}
AppPublisher=whboy10000
DefaultDirName={autopf}\FundValuation
DefaultGroupName=Fund Valuation
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=fund-valuation-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\funds_valuation.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Fund Valuation"; Filename: "{app}\funds_valuation.exe"
Name: "{group}\{cm:UninstallProgram,Fund Valuation}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Fund Valuation"; Filename: "{app}\funds_valuation.exe"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\funds_valuation.exe"; \
    Description: "{cm:LaunchProgram,Fund Valuation}"; \
    Flags: nowait postinstall skipifsilent
