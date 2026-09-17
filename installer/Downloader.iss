; Downloader Windows installer (Inno Setup 6+)
; Built by scripts\build-windows-installer.ps1

#define MyAppName "Downloader"
#define MyAppDirName "DownloaderD"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Downloader"
#define MyAppURL "https://github.com/redubbledd1-ops/Downloader"
#define MyAppExeName "downoader.exe"
#define MyExtensionId "meecghmbaeipmpnopapdkknnjcgconeh"
#ifndef BuildDir
  #define BuildDir "..\build\windows\x64\runner\Release"
#endif
#ifndef DistDir
  #define DistDir "..\dist"
#endif

[Setup]
AppId={{A7C3E5F1-8B2D-4E9A-9C1F-6D4B2A8E0F31}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
; Always install under 32-bit Program Files so everything lives together:
; {app}\downoader.exe, tools\, host\, extension\
DefaultDirName={commonpf32}\{#MyAppDirName}
DefaultGroupName={#MyAppDirName}
DisableProgramGroupPage=yes
OutputDir={#DistDir}
OutputBaseFilename=DownloaderSetup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Downloader — video/audio via yt-dlp
VersionInfoProductName={#MyAppName}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}
; Without an Authenticode certificate Windows SmartScreen may still warn.
; Sign with SignTool after buying a code-signing cert to reduce that warning.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "extchrome"; Description: "Set up Chrome extension (Load unpacked)"; GroupDescription: "Browser extension:"; Flags: unchecked; Check: ChromeInstalled
Name: "extedge"; Description: "Set up Edge extension (Load unpacked)"; GroupDescription: "Browser extension:"; Flags: unchecked; Check: EdgeInstalled
Name: "extfirefox"; Description: "Set up Firefox extension (same folder; Load temporary add-on)"; GroupDescription: "Browser extension:"; Flags: unchecked; Check: FirefoxInstalled

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "write-prefs.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{group}\Install extension (guide)"; Filename: "{app}\extension\INSTALL-EXTENSION.html"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
Filename: "{win}\explorer.exe"; Parameters: """{app}\extension"""; Description: "Open extension folder (for Load unpacked)"; Flags: postinstall nowait skipifsilent; Check: WantAnyExtension
Filename: "{code:GetChromeExe}"; Parameters: "--new-window chrome://extensions"; Description: "Open Chrome extensions page"; Flags: postinstall nowait skipifsilent; Check: WantChromeExtension
Filename: "{code:GetEdgeExe}"; Parameters: "--new-window edge://extensions"; Description: "Open Edge extensions page"; Flags: postinstall nowait skipifsilent; Check: WantEdgeExtension
Filename: "{code:GetFirefoxExe}"; Parameters: "-new-window about:debugging#/runtime/this-firefox"; Description: "Open Firefox debugging (Load Temporary Add-on)"; Flags: postinstall nowait skipifsilent; Check: WantFirefoxExtension
Filename: "{app}\extension\INSTALL-EXTENSION.html"; Description: "Open extension install guide"; Flags: postinstall shellexec skipifsilent; Check: WantAnyExtension

[Code]
var
  TasksPreselected: Boolean;
  DownloadDirPage: TInputDirWizardPage;

function ChromePath: string;
begin
  Result := ExpandConstant('{localappdata}\Google\Chrome\Application\chrome.exe');
  if FileExists(Result) then Exit;
  Result := ExpandConstant('{pf}\Google\Chrome\Application\chrome.exe');
  if FileExists(Result) then Exit;
  Result := ExpandConstant('{pf32}\Google\Chrome\Application\chrome.exe');
  if not FileExists(Result) then Result := '';
end;

function EdgePath: string;
begin
  Result := ExpandConstant('{localappdata}\Microsoft\Edge\Application\msedge.exe');
  if FileExists(Result) then Exit;
  Result := ExpandConstant('{pf}\Microsoft\Edge\Application\msedge.exe');
  if FileExists(Result) then Exit;
  Result := ExpandConstant('{pf32}\Microsoft\Edge\Application\msedge.exe');
  if not FileExists(Result) then Result := '';
end;

function FirefoxPath: string;
begin
  Result := ExpandConstant('{pf}\Mozilla Firefox\firefox.exe');
  if FileExists(Result) then Exit;
  Result := ExpandConstant('{pf32}\Mozilla Firefox\firefox.exe');
  if FileExists(Result) then Exit;
  Result := ExpandConstant('{localappdata}\Mozilla Firefox\firefox.exe');
  if FileExists(Result) then Exit;
  Result := ExpandConstant('{pf}\Firefox Developer Edition\firefox.exe');
  if not FileExists(Result) then Result := '';
end;

function ChromeInstalled: Boolean;
begin
  Result := ChromePath <> '';
end;

function EdgeInstalled: Boolean;
begin
  Result := EdgePath <> '';
end;

function FirefoxInstalled: Boolean;
begin
  Result := FirefoxPath <> '';
end;

function GetChromeExe(Param: string): string;
begin
  Result := ChromePath;
end;

function GetEdgeExe(Param: string): string;
begin
  Result := EdgePath;
end;

function GetFirefoxExe(Param: string): string;
begin
  Result := FirefoxPath;
end;

function WantChromeExtension: Boolean;
begin
  Result := WizardIsTaskSelected('extchrome') and ChromeInstalled;
end;

function WantEdgeExtension: Boolean;
begin
  Result := WizardIsTaskSelected('extedge') and EdgeInstalled;
end;

function WantFirefoxExtension: Boolean;
begin
  Result := WizardIsTaskSelected('extfirefox') and FirefoxInstalled;
end;

function WantAnyExtension: Boolean;
begin
  Result := WantChromeExtension or WantEdgeExtension or WantFirefoxExtension;
end;

function GetDefaultBrowserProgId: string;
begin
  if not RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice', 'ProgId', Result) then
    if not RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice', 'ProgId', Result) then
      Result := '';
end;

function EscapeJsonPath(const Path: string): string;
begin
  Result := Path;
  StringChangeEx(Result, '\', '\\', True);
end;

procedure WriteNativeHostManifest;
var
  HostExe, ManifestPath, Json, Origin, FirefoxId: string;
begin
  HostExe := ExpandConstant('{app}\host\downoader_native_host.exe');
  ManifestPath := ExpandConstant('{app}\host\com.downoader.host.json');
  Origin := 'chrome-extension://{#MyExtensionId}/';
  FirefoxId := 'downloader@downoader.app';
  Json :=
    '{' + #13#10 +
    '  "name": "com.downoader.host",' + #13#10 +
    '  "description": "Downloader Native Messaging host (yt-dlp)",' + #13#10 +
    '  "path": "' + EscapeJsonPath(HostExe) + '",' + #13#10 +
    '  "type": "stdio",' + #13#10 +
    '  "allowed_origins": [' + #13#10 +
    '    "' + Origin + '"' + #13#10 +
    '  ],' + #13#10 +
    '  "allowed_extensions": [' + #13#10 +
    '    "' + FirefoxId + '"' + #13#10 +
    '  ]' + #13#10 +
    '}';
  ForceDirectories(ExtractFileDir(ManifestPath));
  SaveStringToFile(ManifestPath, Json, False);
end;

procedure RegisterNativeHostFor(const RegSubKey: string; const ManifestPath: string);
begin
  RegWriteStringValue(HKCU, RegSubKey, '', ManifestPath);
end;

procedure WriteExtensionGuide;
var
  Dest, ExtPath, Html: string;
begin
  Dest := ExpandConstant('{app}\extension\INSTALL-EXTENSION.html');
  ExtPath := ExpandConstant('{app}\extension');
  Html :=
    '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"/>' +
    '<title>Downloader — load extension</title>' +
    '<style>body{font-family:Segoe UI,sans-serif;max-width:42rem;margin:2rem auto;padding:0 1.25rem;line-height:1.5}' +
    'h1{font-size:1.4rem}.path{font-family:Consolas,monospace;background:#0001;padding:.35rem .55rem;border-radius:4px;word-break:break-all}' +
    'li{margin:.55rem 0}.note{opacity:.85;font-size:.95rem}</style></head><body>' +
    '<h1>Load the Downloader extension</h1>' +
    '<p>Browsers do not allow silent extension installs. This is a one-time step (~20 seconds). Chrome, Edge and Firefox all use the <strong>same folder</strong>.</p>' +
    '<p><strong>Chrome / Edge</strong></p>' +
    '<ol>' +
    '<li>Open the extensions page (<code>chrome://extensions</code> or <code>edge://extensions</code>).</li>' +
    '<li>Turn on <strong>Developer mode</strong> (top right).</li>' +
    '<li>Click <strong>Load unpacked</strong>.</li>' +
    '<li>Select this folder:<br/><span class="path">' + ExtPath + '</span></li>' +
    '</ol>' +
    '<p><strong>Firefox (desktop)</strong></p>' +
    '<ol>' +
    '<li>Open <code>about:debugging#/runtime/this-firefox</code>.</li>' +
    '<li>Click <strong>Load Temporary Add-on</strong>.</li>' +
    '<li>Select <code>manifest.json</code> in the same folder:<br/><span class="path">' + ExtPath + '</span></li>' +
    '</ol>' +
    '<p class="note">Firefox temporary add-ons are removed when Firefox restarts. For a permanent install, use Firefox Developer Edition or a signed .xpi from GitHub releases later.</p>' +
    '<p><strong>Firefox for Android</strong></p>' +
    '<p class="note">Install the Downloader APK, then in Firefox for Android: Settings → About Firefox → tap the logo 5 times → Add-ons → Install add-on from file (or Debug via about:debugging from desktop). The same extension folder is used; on Android it opens the Downloader app instead of native messaging.</p>' +
    '<p class="note">Native messaging is already registered by the installer for the browsers you selected.</p>' +
    '</body></html>';
  ForceDirectories(ExtractFileDir(Dest));
  SaveStringToFile(Dest, Html, False);
end;

procedure WriteAppPrefs;
var
  PrefsPath, AppExe, DownloadDir, Params: string;
  ResultCode: Integer;
begin
  PrefsPath := ExpandConstant('{userappdata}\com.example\Downloader\shared_preferences.json');
  AppExe := ExpandConstant('{app}\{#MyAppExeName}');
  DownloadDir := Trim(DownloadDirPage.Values[0]);
  if DownloadDir = '' then
    DownloadDir := ExpandConstant('{userdocs}\Downloads');
  ForceDirectories(DownloadDir);

  Params :=
    '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\write-prefs.ps1') + '"' +
    ' -PrefsPath "' + PrefsPath + '"' +
    ' -AppExe "' + AppExe + '"' +
    ' -DownloadDir "' + DownloadDir + '"';
  if not Exec('powershell.exe', Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log('Failed to run write-prefs.ps1')
  else if ResultCode <> 0 then
    Log('write-prefs.ps1 exit code ' + IntToStr(ResultCode));
end;

procedure InitializeWizard;
var
  DefaultDownloads: string;
begin
  DownloadDirPage := CreateInputDirPage(
    wpSelectDir,
    'Download folder',
    'Where should Downloader save video and audio files?',
    'Choose a download folder. You can change this later in the app settings.',
    False,
    ''
  );
  DownloadDirPage.Add('&Download folder:');
  DefaultDownloads := GetEnv('USERPROFILE') + '\Downloads';
  if not DirExists(DefaultDownloads) then
    DefaultDownloads := ExpandConstant('{userdocs}');
  DownloadDirPage.Values[0] := DefaultDownloads;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = DownloadDirPage.ID then
  begin
    if Trim(DownloadDirPage.Values[0]) = '' then
    begin
      MsgBox('Please choose a download folder.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  ProgId, Keep: string;
begin
  if (CurPageID = wpSelectTasks) and (not TasksPreselected) then
  begin
    TasksPreselected := True;
    Keep := WizardSelectedTasks(False);
    ProgId := LowerCase(GetDefaultBrowserProgId);
    if (Pos('chrome', ProgId) > 0) and ChromeInstalled then
      WizardSelectTasks(Trim(Keep + ' extchrome'))
    else if ((Pos('edge', ProgId) > 0) or (Pos('msedge', ProgId) > 0)) and EdgeInstalled then
      WizardSelectTasks(Trim(Keep + ' extedge'))
    else if (Pos('firefox', ProgId) > 0) and FirefoxInstalled then
      WizardSelectTasks(Trim(Keep + ' extfirefox'))
    else if ChromeInstalled then
      WizardSelectTasks(Trim(Keep + ' extchrome'))
    else if EdgeInstalled then
      WizardSelectTasks(Trim(Keep + ' extedge'))
    else if FirefoxInstalled then
      WizardSelectTasks(Trim(Keep + ' extfirefox'));
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ManifestPath, FirefoxManifest: string;
begin
  if CurStep = ssPostInstall then
  begin
    WriteAppPrefs;
    WriteExtensionGuide;
    if WantAnyExtension then
    begin
      WriteNativeHostManifest;
      ManifestPath := ExpandConstant('{app}\host\com.downoader.host.json');
      if WantChromeExtension then
        RegisterNativeHostFor('Software\Google\Chrome\NativeMessagingHosts\com.downoader.host', ManifestPath);
      if WantEdgeExtension then
        RegisterNativeHostFor('Software\Microsoft\Edge\NativeMessagingHosts\com.downoader.host', ManifestPath);
      if WantFirefoxExtension then
      begin
        RegisterNativeHostFor('Software\Mozilla\NativeMessagingHosts\com.downoader.host', ManifestPath);
        FirefoxManifest := ExpandConstant('{userappdata}\Mozilla\NativeMessagingHosts');
        ForceDirectories(FirefoxManifest);
        FileCopy(ManifestPath, FirefoxManifest + '\com.downoader.host.json', False);
      end;
    end;
  end;
end;
