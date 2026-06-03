#define MyAppName "CinePro Manager"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "CinePro Foundation"
#define MyAppPublisherUrl "https://github.com/cinepro-org"
#define MyAppSupportUrl "https://github.com/cinepro-org/core/issues"
#define MyAppUpdatesUrl "https://github.com/cinepro-org/core/releases"
#define MyAppExeName "cinepro_manager.exe"

[Setup]
; stable app id keeps upgrades attached to the same installed manager entry
AppId={{9FC6C6F8-9DE7-4E18-A1DA-CBE767A3E45A}
; visible app metadata used by setup, uninstall, shortcuts, and windows apps list
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; publisher link opens the cinepro foundation organization from windows app details
AppPublisherURL={#MyAppPublisherUrl}
; support link sends users to the core issue tracker for manager and setup bugs
AppSupportURL={#MyAppSupportUrl}
; update link points to the release feed that manager update checks also inspect
AppUpdatesURL={#MyAppUpdatesUrl}
; installs the manager app itself under program files while runtime content stays in local app data
DefaultDirName={autopf}\CinePro Manager
; start menu group keeps manager shortcuts under a short cinepro folder
DefaultGroupName=CinePro
; lets the user choose whether the start menu folder should be changed
DisableProgramGroupPage=no
; keeps generated setup output separate from the script and source files
OutputDir=output
; versioned setup name lets the manager compare app updates from release assets
OutputBaseFilename=cinepro-manager-setup-{#MyAppVersion}
; lzma2 keeps the flutter runtime package small without adding extra tools
Compression=lzma2
; solid compression improves installer size because flutter outputs many related files
SolidCompression=yes
; modern wizard gives the setup a native windows 11 style without custom pages
WizardStyle=modern
; admin is required because the default app folder is program files
PrivilegesRequired=admin
; x64 compatible keeps the package aligned with the flutter windows build output
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; windows 10 is the practical floor for the flutter desktop runtime and shell behavior
MinVersion=10.0
; setup mutex prevents two installer instances from racing over the same files
SetupMutex=CineProManagerSetupMutex
; asks windows to close a running manager before files are replaced
CloseApplications=yes
; limits app closing to the manager exe instead of unrelated cinepro processes
CloseApplicationsFilter={#MyAppExeName}
; avoids surprise restart prompts during normal manager installation
RestartIfNeededByRun=no
; writes setup logs so install failures can be diagnosed after the wizard closes
SetupLogging=yes
; uses the cinepro icon for setup instead of the default inno icon
SetupIconFile=..\manager\windows\runner\resources\app_icon.ico
; keeps uninstall entries readable in windows apps and features
UninstallDisplayName={#MyAppName}
; points uninstall display icon at the installed manager exe
UninstallDisplayIcon={app}\{#MyAppExeName}
; preserves the previous install folder during upgrades
UsePreviousAppDir=yes
; preserves shortcut choices during upgrades
UsePreviousTasks=yes
; company metadata appears in the setup exe properties and windows trust prompts
VersionInfoCompany={#MyAppPublisher}
; description metadata keeps the signed setup readable in file properties
VersionInfoDescription={#MyAppName}
; product metadata groups manager versions under the same windows product name
VersionInfoProductName={#MyAppName}
; product version metadata mirrors the app version used by release checks
VersionInfoProductVersion={#MyAppVersion}
; file version metadata lets windows compare setup binaries during diagnostics
VersionInfoVersion={#MyAppVersion}

[Languages]
; multiple real language files make inno show the language picker at startup
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "tamil"; MessagesFile: "compiler:Languages\Tamil.isl"

[Tasks]
; desktop shortcut is optional because the start menu shortcut is always created
Name: "desktopicon"; Description: "create a desktop shortcut"; GroupDescription: "shortcuts"; Flags: unchecked

[Files]
; packages the complete flutter release folder including dlls, data, assets, and native plugins
Source: "..\manager\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; keeps a plain logo asset beside the app for tray and future shortcut workflows
Source: "..\manager\assets\cinepro-logo.png"; DestDir: "{app}\assets"; Flags: ignoreversion

[Icons]
; start menu shortcut is the primary way to reopen the installed manager
Name: "{group}\CinePro Manager"; Filename: "{app}\{#MyAppExeName}"
; desktop shortcut only appears when the user selects the optional task
Name: "{autodesktop}\CinePro Manager"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; launches the manager after setup so it can download and verify cinepro files
Filename: "{app}\{#MyAppExeName}"; Parameters: "--setup-install"; Description: "Launch CinePro Manager and install verified CinePro files"; Flags: nowait postinstall skipifsilent

[Code]
var
  // remembers whether the user also asked to remove manager data during uninstall
  RemoveManagerData: Boolean;

function InitializeUninstall(): Boolean;
begin
  // warns that managed core cleanup belongs inside the manager where ownership can be checked
  Result := MsgBox('Uninstall CinePro Manager? Use the in app uninstall button first if you also want to remove managed Core files.', mbConfirmation, MB_YESNO) = IDYES;
  if Result then
    // keeps logs, cache, and state unless the user explicitly asks to remove them
    RemoveManagerData := MsgBox('Remove manager logs, cache, and saved state too?', mbConfirmation, MB_YESNO) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // removes manager app data only after uninstall finishes and only when confirmed
  if (CurUninstallStep = usPostUninstall) and RemoveManagerData then
    DelTree(ExpandConstant('{localappdata}\CinePro Manager'), True, True, True);
end;
