; Downloader Windows installer (Inno Setup 6+)
; Built by scripts\build-windows-installer.ps1

#define MyAppName "Downloader"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Downloader"
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
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
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

[Languages]
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "extchrome"; Description: "Chrome-extentie klaarzetten (Load unpacked)"; GroupDescription: "Browser-extentie:"; Flags: unchecked; Check: ChromeInstalled
Name: "extedge"; Description: "Edge-extentie klaarzetten (Load unpacked)"; GroupDescription: "Browser-extentie:"; Flags: unchecked; Check: EdgeInstalled

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{group}\Extentie installeren (handleiding)"; Filename: "{app}\extension\INSTALL-EXTENSION.html"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
Filename: "{win}\explorer.exe"; Parameters: """{app}\extension"""; Description: "Extentie-map openen (voor Load unpacked)"; Flags: postinstall nowait skipifsilent; Check: WantAnyExtension
Filename: "{code:GetChromeExe}"; Parameters: "--new-window chrome://extensions"; Description: "Chrome-extentiepagina openen"; Flags: postinstall nowait skipifsilent; Check: WantChromeExtension
Filename: "{code:GetEdgeExe}"; Parameters: "--new-window edge://extensions"; Description: "Edge-extentiepagina openen"; Flags: postinstall nowait skipifsilent; Check: WantEdgeExtension
Filename: "{app}\extension\INSTALL-EXTENSION.html"; Description: "Handleiding: extentie laden"; Flags: postinstall shellexec skipifsilent; Check: WantAnyExtension

[Code]
var
  TasksPreselected: Boolean;

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

function ChromeInstalled: Boolean;
begin
  Result := ChromePath <> '';
end;

function EdgeInstalled: Boolean;
begin
  Result := EdgePath <> '';
end;

function GetChromeExe(Param: string): string;
begin
  Result := ChromePath;
end;

function GetEdgeExe(Param: string): string;
begin
  Result := EdgePath;
end;

function WantChromeExtension: Boolean;
begin
  Result := WizardIsTaskSelected('extchrome') and ChromeInstalled;
end;

function WantEdgeExtension: Boolean;
begin
  Result := WizardIsTaskSelected('extedge') and EdgeInstalled;
end;

function WantAnyExtension: Boolean;
begin
  Result := WantChromeExtension or WantEdgeExtension;
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
  HostExe, ManifestPath, Json, Origin: string;
begin
  HostExe := ExpandConstant('{app}\host\downoader_native_host.exe');
  ManifestPath := ExpandConstant('{app}\host\com.downoader.host.json');
  Origin := 'chrome-extension://{#MyExtensionId}/';
  Json :=
    '{' + #13#10 +
    '  "name": "com.downoader.host",' + #13#10 +
    '  "description": "Downloader Native Messaging host (yt-dlp)",' + #13#10 +
    '  "path": "' + EscapeJsonPath(HostExe) + '",' + #13#10 +
    '  "type": "stdio",' + #13#10 +
    '  "allowed_origins": [' + #13#10 +
    '    "' + Origin + '"' + #13#10 +
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
    '<!DOCTYPE html><html lang="nl"><head><meta charset="utf-8"/>' +
    '<title>Downloader — extentie laden</title>' +
    '<style>body{font-family:Segoe UI,sans-serif;max-width:42rem;margin:2rem auto;padding:0 1.25rem;line-height:1.5}' +
    'h1{font-size:1.4rem}.path{font-family:Consolas,monospace;background:#0001;padding:.35rem .55rem;border-radius:4px;word-break:break-all}' +
    'li{margin:.55rem 0}.note{opacity:.85;font-size:.95rem}</style></head><body>' +
    '<h1>Downloader-extentie laden</h1>' +
    '<p>Chrome/Edge laten extenties niet stil installeren. Dit is eenmalig (~20 seconden).</p>' +
    '<ol>' +
    '<li>Open de extentiepagina (<code>chrome://extensions</code> of <code>edge://extensions</code>).</li>' +
    '<li>Zet rechtsboven <strong>Developer mode / Ontwikkelaarsmodus</strong> aan.</li>' +
    '<li>Klik <strong>Load unpacked / Uitgepakte extensie laden</strong>.</li>' +
    '<li>Kies deze map:<br/><span class="path">' + ExtPath + '</span></li>' +
    '</ol>' +
    '<p class="note">Native messaging is al door de installer geregistreerd. Daarna verschijnt het Downloader-icoon in de werkbalk.</p>' +
    '<p class="note">Later in de store is deze stap niet meer nodig.</p>' +
    '</body></html>';
  ForceDirectories(ExtractFileDir(Dest));
  SaveStringToFile(Dest, Html, False);
end;

procedure EnsureAppExePrefs;
var
  PrefsDir, PrefsPath, AppExe, Json: string;
begin
  PrefsDir := ExpandConstant('{userappdata}\com.example\Downloader');
  ForceDirectories(PrefsDir);
  PrefsPath := PrefsDir + '\shared_preferences.json';
  AppExe := ExpandConstant('{app}\{#MyAppExeName}');
  if not FileExists(PrefsPath) then
  begin
    Json := '{' + #13#10 +
      '  "flutter.app_exe": "' + EscapeJsonPath(AppExe) + '"' + #13#10 +
      '}';
    SaveStringToFile(PrefsPath, Json, False);
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
    else if ChromeInstalled then
      WizardSelectTasks(Trim(Keep + ' extchrome'))
    else if EdgeInstalled then
      WizardSelectTasks(Trim(Keep + ' extedge'));
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ManifestPath: string;
begin
  if CurStep = ssPostInstall then
  begin
    EnsureAppExePrefs;
    WriteExtensionGuide;
    if WantAnyExtension then
    begin
      WriteNativeHostManifest;
      ManifestPath := ExpandConstant('{app}\host\com.downoader.host.json');
      if WantChromeExtension then
        RegisterNativeHostFor('Software\Google\Chrome\NativeMessagingHosts\com.downoader.host', ManifestPath);
      if WantEdgeExtension then
        RegisterNativeHostFor('Software\Microsoft\Edge\NativeMessagingHosts\com.downoader.host', ManifestPath);
    end;
  end;
end;
