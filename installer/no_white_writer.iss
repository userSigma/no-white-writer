; Build through: dart run tool/build_windows_installer.dart
; Only application payload and shortcuts are owned by this installer.
#ifndef AppVersion
  #error AppVersion must be supplied by the Dart packaging command.
#endif
#ifndef WindowsVersion
  #error WindowsVersion must be supplied by the Dart packaging command.
#endif
#ifndef SourceDir
  #error SourceDir must identify the validated, staged x64 Release bundle.
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by the Dart packaging command.
#endif
#ifndef OutputBaseName
  #error OutputBaseName must be supplied by the Dart packaging command.
#endif
#ifndef InstallerAppId
  #define InstallerAppId "ce99ca45-fdcf-4d6f-8f1c-74f7dd3b086b"
#endif
#define AppName "不白写作"
#define AppExeName "no_white_writer.exe"

#if GetVersionNumbersString(SourceDir + "\" + AppExeName) != WindowsVersion
  #error Executable version does not match pubspec.yaml. Rebuild Windows Release.
#endif

[Setup]
AppId={{{#InstallerAppId}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=com.usersigma
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#WindowsVersion}
VersionInfoDescription={#AppName} Setup
DefaultDirName={localappdata}\Programs\不白写作
DefaultGroupName=不白写作
UsePreviousAppDir=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DisableProgramGroupPage=yes
AllowNoIcons=yes
CloseApplications=no
RestartApplications=no
UninstallRestartComputer=no
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
LicenseFile=..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\不白写作"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{userdesktop}\不白写作"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,不白写作}"; Flags: nowait postinstall skipifsilent unchecked

[CustomMessages]
CloseAppFirst=请先在不白写作中保存作品并退出，然后重试。程序文件正被使用，或当前用户没有替换权限。%nPlease save your work and close No White Writer, then retry. The installed executable is busy or cannot be replaced.

[Code]
function CanReplaceApp(): Boolean;
var
  Stream: TFileStream;
  AppPath: String;
begin
  AppPath := ExpandConstant('{app}\{#AppExeName}');
  Result := True;
  if FileExists(AppPath) then
  begin
    try
      Stream := TFileStream.Create(AppPath, fmOpenReadWrite or fmShareExclusive);
      Stream.Free;
    except
      Result := False;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not CanReplaceApp() then
    Result := CustomMessage('CloseAppFirst');
end;

function InitializeUninstall(): Boolean;
begin
  Result := CanReplaceApp();
  if not Result then
    SuppressibleMsgBox(CustomMessage('CloseAppFirst'), mbError, MB_OK, IDOK);
end;
