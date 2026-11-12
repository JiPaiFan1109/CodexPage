#ifndef SourceRoot
  #error SourceRoot is required; use scripts/build-app.ps1
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifdef TestProgramsRoot
  #ifndef TestInstallRoot
    #error TestProgramsRoot requires an isolated TestInstallRoot
  #endif
  #define ProgramsRoot TestProgramsRoot
#else
  #define ProgramsRoot "{userprograms}"
#endif

[Setup]
#ifdef TestInstallRoot
AppId={{0E7720A7-D16D-4441-85E5-522908601905}
#else
AppId={{97EC4AF8-3971-4B65-A78E-16B0D870C41D}
#endif
AppName=CodexPage
AppVersion={#AppVersion}
AppPublisher=CodexPage contributors
AppPublisherURL=https://github.com/JiPaiFan1109/CodexPage
AppSupportURL=https://github.com/JiPaiFan1109/CodexPage/issues
#ifdef TestInstallRoot
DefaultDirName={#TestInstallRoot}
#else
DefaultDirName={localappdata}\CodexPage
#endif
UsePreviousAppDir=yes
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
SetupIconFile={#SourceRoot}\appearance\skin-manager.ico
UninstallDisplayIcon={app}\CodexSkinManager.exe
OutputBaseFilename=CodexPage-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile={#SourceRoot}\LICENSE
AppMutex=CodexDynamicSkinManager
CloseApplications=no
RestartApplications=no
Uninstallable=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: checkedonce

[Files]
Source: "{#SourceRoot}\engine\*"; DestDir: "{app}\engine"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\scripts\*"; DestDir: "{app}\scripts"; Excludes: "check-upgrade.ps1"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\scripts\check-upgrade.ps1"; Flags: dontcopy
Source: "{#SourceRoot}\appearance\*"; DestDir: "{app}\appearance"; Flags: ignoreversion
Source: "{#SourceRoot}\CodexSkinManager.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\VERSION"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

Source: "{#SourceRoot}\installed-files.json"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
#if !defined(TestInstallRoot) || defined(TestProgramsRoot)
Type: files; Name: "{#ProgramsRoot}\Codex Dream Skin.lnk"
Type: files; Name: "{#ProgramsRoot}\Codex Dream Skin - Tray.lnk"
Type: files; Name: "{#ProgramsRoot}\CodexPage\CodexPage.lnk"
Type: files; Name: "{#ProgramsRoot}\CodexPage\打开换肤版 Codex.lnk"
Type: files; Name: "{#ProgramsRoot}\CodexPage\卸载.lnk"
Type: dirifempty; Name: "{#ProgramsRoot}\CodexPage"
Type: files; Name: "{#ProgramsRoot}\Codex 换肤管理中心\Codex 换肤管理中心.lnk"
Type: files; Name: "{#ProgramsRoot}\Codex 换肤管理中心\打开换肤版 Codex.lnk"
Type: files; Name: "{#ProgramsRoot}\Codex 换肤管理中心\卸载.lnk"
Type: dirifempty; Name: "{#ProgramsRoot}\Codex 换肤管理中心"
#endif
#ifndef TestInstallRoot
Type: files; Name: "{userdesktop}\Codex 换肤管理中心.lnk"
#endif
Type: files; Name: "{app}\engine\assets\dream-skin.css"
Type: files; Name: "{app}\engine\assets\theme-package-validator.mjs"
Type: files; Name: "{app}\engine\assets\dream-reference.jpg"
Type: files; Name: "{app}\engine\scripts\tray-dream-skin.ps1"
Type: files; Name: "{app}\engine\scripts\apply-community-theme.ps1"
Type: files; Name: "{app}\engine\scripts\check-update.ps1"
Type: files; Name: "{app}\engine\scripts\install-dream-skin.ps1"
Type: files; Name: "{app}\engine\scripts\verify-dream-skin.ps1"

[Icons]
#if !defined(TestInstallRoot) || defined(TestProgramsRoot)
Name: "{#ProgramsRoot}\CodexPage"; Filename: "{app}\CodexSkinManager.exe"; AppUserModelID: "CodexDynamicSkin.Manager"
#endif
#ifndef TestInstallRoot
Name: "{userdesktop}\CodexPage"; Filename: "{app}\CodexSkinManager.exe"; AppUserModelID: "CodexDynamicSkin.Manager"; Tasks: desktopicon
#endif

[Run]
#ifndef TestInstallRoot
Filename: "{app}\CodexSkinManager.exe"; Description: "打开 CodexPage"; Flags: nowait postinstall skipifsilent
#endif

[Code]
var
  UpdateGate: THandle;
  UpdateGateHeld: Boolean;

function CreateFileW(FileName: String; Access, Share: LongWord; Security: NativeUInt; Creation, Flags: LongWord; Template: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

procedure DeinitializeSetup();
begin
  if UpdateGateHeld then begin
    CloseHandle(UpdateGate);
    UpdateGateHeld := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
  Params: String;
  BlockReason: AnsiString;
  GateAttempt: Integer;
begin
  Result := '';
  if not UpdateGateHeld then begin
    if not ForceDirectories(ExpandConstant('{app}')) then begin
      Result := '无法在所选位置安装 CodexPage。请重新运行安装程序并使用默认安装位置。';
      Exit;
    end;
    { A monitor may briefly hold a shared lease during its poll. Allow it to finish. }
    for GateAttempt := 1 to 50 do begin
      UpdateGate := CreateFileW(ExpandConstant('{app}\.update-gate'), $C0000000, 0, 0, 4, $80, 0);
      if UpdateGate <> THandle(-1) then Break;
      Sleep(100);
    end;
    if UpdateGate = THandle(-1) then begin
      Result := 'CodexPage 仍在运行，或另一项安装尚未结束。请关闭 CodexPage，并等其他安装完成后再试。';
      Exit;
    end;
    UpdateGateHeld := True;
  end;
  ExtractTemporaryFile('check-upgrade.ps1');
  Params := '-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + ExpandConstant('{tmp}\check-upgrade.ps1') + '" -InstallRoot "' + ExpandConstant('{app}') + '" -ResultPath "' + ExpandConstant('{tmp}\upgrade-check-result.txt') + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    Result := '无法完成安装前检查，本次安装未替换文件。请重新运行安装程序。'
  else if ExitCode <> 0 then begin
    if LoadStringFromFile(ExpandConstant('{tmp}\upgrade-check-result.txt'), BlockReason) and (Length(BlockReason) > 0) then begin
      Log(UTF8Decode(BlockReason));
      Result := '暂时无法安全开始安装，本次尚未替换程序文件。请关闭 CodexPage 后重新运行安装程序；若仍失败，请联系作者。';
    end
    else
      Result := '暂时无法安全开始安装，本次尚未替换程序文件。请关闭 CodexPage 后重新运行安装程序。';
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExitCode: Integer;
  Params: String;
begin
  if CurUninstallStep <> usUninstall then Exit;
  { This event runs after uninstall confirmation and before any files are deleted. }
  Params := '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + ExpandConstant('{app}\scripts\uninstall-app.ps1') + '"';
  if UninstallSilent then Params := Params + ' -Silent';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    RaiseException('卸载已停止。请先打开 CodexPage，在“管理与更新”中恢复原始外观，完成后再卸载。');
  if ExitCode = 2 then Abort;
  if ExitCode <> 0 then
    RaiseException('卸载已停止，因为还未恢复 Codex 的原始外观。请在 CodexPage 的“管理与更新”中恢复原始外观，完成后再卸载。');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  MonitorExitCode: Integer;
begin
  if (CurStep = ssPostInstall) and UpdateGateHeld then begin
    CloseHandle(UpdateGate);
    UpdateGateHeld := False;
  end;
#ifndef TestInstallRoot
  if CurStep = ssPostInstall then begin
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + ExpandConstant('{app}\engine\scripts\background-task.ps1') + '" -Action Enable',
      '', SW_HIDE, ewWaitUntilTerminated, MonitorExitCode) then
      Log('Could not register background monitor; the manager will retry.')
    else if MonitorExitCode <> 0 then
      Log('Background monitor registration failed; the manager will retry.');
  end;
#endif
end;
