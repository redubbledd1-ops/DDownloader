# Registers the Downloader Native Messaging host for Chrome, Edge and/or Firefox.
# Auto-detects the unpacked Extension ID when -ExtensionId is omitted.

param(
    [string]$ExtensionId = "",

    [string]$HostExe = "",

    [string]$AppExe = "",

    [ValidateSet("chrome", "edge", "firefox", "both", "all")]
    [string]$Browsers = "all"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (-not $HostExe) {
    foreach ($h in @(
        (Join-Path $root "extension\host\downoader_native_host.exe"),
        (Join-Path $root "Release\host\downoader_native_host.exe"),
        (Join-Path $root "build\windows\x64\runner\Release\host\downoader_native_host.exe"),
        "${env:ProgramFiles(x86)}\DownloaderD\host\downoader_native_host.exe",
        "${env:ProgramFiles}\DownloaderD\host\downoader_native_host.exe",
        "${env:ProgramFiles}\Downloader\host\downoader_native_host.exe"
    )) {
        if (Test-Path $h) { $HostExe = $h; break }
    }
    if (-not $HostExe) {
        $HostExe = Join-Path $root "extension\host\downoader_native_host.exe"
    }
}
$HostExe = [System.IO.Path]::GetFullPath($HostExe)

if (-not (Test-Path $HostExe)) {
    Write-Host "Host exe niet gevonden: $HostExe"
    Write-Host "Compileer eerst:"
    Write-Host "  cd native_host"
    Write-Host "  dart pub get"
    Write-Host "  dart compile exe bin/host.dart -o ..\extension\host\downoader_native_host.exe"
    exit 1
}

if (-not $AppExe) {
    $candidates = @(
        (Join-Path $root "build\windows\x64\runner\Release\downoader.exe"),
        (Join-Path $root "Release\downoader.exe"),
        "${env:ProgramFiles(x86)}\DownloaderD\downoader.exe",
        "${env:ProgramFiles}\DownloaderD\downoader.exe",
        "${env:ProgramFiles}\Downloader\downoader.exe",
        "${env:ProgramFiles(x86)}\Downloader\downoader.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $AppExe = [System.IO.Path]::GetFullPath($c); break }
    }
}

function Find-ExtensionId {
    $extensionFolder = [regex]::Escape((Join-Path $root "extension"))
    $securePrefs = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Secure Preferences",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Secure Preferences"
    )
    foreach ($pref in $securePrefs) {
        if (-not (Test-Path $pref)) { continue }
        try {
            $raw = Get-Content $pref -Raw -Encoding UTF8
            $match = [regex]::Match($raw, '"(?<id>[a-p]{32})"\s*:\s*\{[^}]*?"path"\s*:\s*"[^"]*Downloader[/\\]+extension"', 'IgnoreCase')
            if ($match.Success) { return $match.Groups['id'].Value }
            # Fallback: any id whose path contains our extension folder
            $escaped = $extensionFolder.Replace('\\', '\\\\')
            $match2 = [regex]::Match($raw, '"(?<id>[a-p]{32})"\s*:\s*\{[^}]*?"path"\s*:\s*"[^"]*' + $escaped.Replace('\\','\\\\') + '"', 'IgnoreCase')
            if ($match2.Success) { return $match2.Groups['id'].Value }
        } catch {}
    }
    return $null
}

if (-not $ExtensionId) {
    $ExtensionId = Find-ExtensionId
    if ($ExtensionId) {
        Write-Host "Extension ID automatisch gevonden: $ExtensionId"
    } else {
        # Vaste ID uit manifest "key" (zelfde als de Windows-installer gebruikt)
        $ExtensionId = "meecghmbaeipmpnopapdkknnjcgconeh"
        Write-Host "Geen geladen extentie gevonden; vaste ID gebruikt: $ExtensionId"
    }
}

$id = $ExtensionId.Trim().TrimEnd("/")
$origin = "chrome-extension://$id/"
$firefoxId = "downloader@downoader.app"

$hostDir = Split-Path -Parent $HostExe
$manifestPath = Join-Path $hostDir "com.downoader.host.json"

$json = @"
{
  "name": "com.downoader.host",
  "description": "Downloader Native Messaging host (yt-dlp)",
  "path": "$($HostExe.Replace('\', '\\'))",
  "type": "stdio",
  "allowed_origins": [
    "$origin"
  ],
  "allowed_extensions": [
    "$firefoxId"
  ]
}
"@
[System.IO.File]::WriteAllText($manifestPath, $json)
Write-Host "Host-manifest geschreven: $manifestPath"

# Prefs: app_exe + migrate download_dir from legacy folder
$prefsDir = Join-Path $env:APPDATA "com.example\Downloader"
New-Item -ItemType Directory -Force -Path $prefsDir | Out-Null
$prefsPath = Join-Path $prefsDir "shared_preferences.json"
$legacyPath = Join-Path $env:APPDATA "com.example\downoader\shared_preferences.json"
python -c @"
import json, os
prefs = {}
def load(p):
    if not os.path.exists(p): return {}
    with open(p, encoding='utf-8-sig') as f: return json.load(f)
legacy = load(r'$($legacyPath.Replace('\','\\'))')
current = load(r'$($prefsPath.Replace('\','\\'))')
prefs.update(legacy)
prefs.update(current)
if legacy.get('flutter.download_dir') and not current.get('flutter.download_dir'):
    prefs['flutter.download_dir'] = legacy['flutter.download_dir']
app = r'$($AppExe.Replace('\','\\'))'
if app:
    prefs['flutter.app_exe'] = app
with open(r'$($prefsPath.Replace('\','\\'))', 'w', encoding='utf-8') as f:
    json.dump(prefs, f, indent=2)
print('prefs ok', prefs.get('flutter.download_dir'), prefs.get('flutter.app_exe'))
"@

function Register-Host([string]$RegistryPath) {
    New-Item -Path $RegistryPath -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name "(default)" -Value $manifestPath -PropertyType String -Force | Out-Null
    Write-Host "Registry: $RegistryPath -> $manifestPath"
}

$targets = @()
if ($Browsers -eq "chrome" -or $Browsers -eq "both" -or $Browsers -eq "all") {
    $targets += "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.downoader.host"
}
if ($Browsers -eq "edge" -or $Browsers -eq "both" -or $Browsers -eq "all") {
    $targets += "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.downoader.host"
}
if ($Browsers -eq "firefox" -or $Browsers -eq "all") {
    $targets += "HKCU:\Software\Mozilla\NativeMessagingHosts\com.downoader.host"
    $ffDir = Join-Path $env:APPDATA "Mozilla\NativeMessagingHosts"
    New-Item -ItemType Directory -Force -Path $ffDir | Out-Null
    Copy-Item -Force $manifestPath (Join-Path $ffDir "com.downoader.host.json")
    Write-Host "Firefox-manifest: $(Join-Path $ffDir 'com.downoader.host.json')"
}

foreach ($key in $targets) {
    Register-Host $key
}

Write-Host ""
Write-Host "Klaar. Herlaad de extentie:"
Write-Host "  Chrome/Edge: chrome://extensions of edge://extensions (knop refresh)"
Write-Host "  Firefox: about:debugging#/runtime/this-firefox -> Load Temporary Add-on"
Write-Host "           kies extension\manifest.json (zelfde map als Chrome)."
Write-Host "open daarna de popup opnieuw."



