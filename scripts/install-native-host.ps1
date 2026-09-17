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
$hostPathJson = $HostExe.Replace('\', '\\')

$hostDir = Split-Path -Parent $HostExe
$manifestPath = Join-Path $hostDir "com.downoader.host.json"
# Firefox weigert manifests met Chrome's allowed_origins — apart bestand.
$firefoxManifestPath = Join-Path $hostDir "com.downoader.host.firefox.json"

$json = @"
{
  "name": "com.downoader.host",
  "description": "Downloader Native Messaging host (yt-dlp)",
  "path": "$hostPathJson",
  "type": "stdio",
  "allowed_origins": [
    "$origin"
  ]
}
"@
[System.IO.File]::WriteAllText($manifestPath, $json)
Write-Host "Chrome/Edge host-manifest: $manifestPath"

$ffJson = @"
{
  "name": "com.downoader.host",
  "description": "Downloader Native Messaging host (yt-dlp)",
  "path": "$hostPathJson",
  "type": "stdio",
  "allowed_extensions": [
    "$firefoxId"
  ]
}
"@
[System.IO.File]::WriteAllText($firefoxManifestPath, $ffJson)
Write-Host "Firefox host-manifest: $firefoxManifestPath"

# Prefs: app_exe + migrate download_dir from legacy folder (PowerShell, geen python)
$prefsDir = Join-Path $env:APPDATA "com.example\Downloader"
New-Item -ItemType Directory -Force -Path $prefsDir | Out-Null
$prefsPath = Join-Path $prefsDir "shared_preferences.json"
$legacyPath = Join-Path $env:APPDATA "com.example\downoader\shared_preferences.json"
$prefs = @{}
foreach ($p in @($legacyPath, $prefsPath)) {
    if (-not (Test-Path $p)) { continue }
    try {
        $obj = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $obj.PSObject.Properties | ForEach-Object {
            if ($null -ne $_.Value -and "$($_.Value)" -ne "") {
                $prefs[$_.Name] = $_.Value
            }
        }
    } catch {}
}
if ($AppExe) { $prefs["flutter.app_exe"] = $AppExe }
($prefs | ConvertTo-Json -Depth 8) | Set-Content -Path $prefsPath -Encoding UTF8
Write-Host "prefs ok $($prefs['flutter.download_dir']) $($prefs['flutter.app_exe'])"

function Register-Host([string]$RegistryPath, [string]$ManifestFile) {
    New-Item -Path $RegistryPath -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name "(default)" -Value $ManifestFile -PropertyType String -Force | Out-Null
    Write-Host "Registry: $RegistryPath -> $ManifestFile"
}

if ($Browsers -eq "chrome" -or $Browsers -eq "both" -or $Browsers -eq "all") {
    Register-Host "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.downoader.host" $manifestPath
}
if ($Browsers -eq "edge" -or $Browsers -eq "both" -or $Browsers -eq "all") {
    Register-Host "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.downoader.host" $manifestPath
}
if ($Browsers -eq "firefox" -or $Browsers -eq "all") {
    Register-Host "HKCU:\Software\Mozilla\NativeMessagingHosts\com.downoader.host" $firefoxManifestPath
    $ffDir = Join-Path $env:APPDATA "Mozilla\NativeMessagingHosts"
    New-Item -ItemType Directory -Force -Path $ffDir | Out-Null
    Copy-Item -Force $firefoxManifestPath (Join-Path $ffDir "com.downoader.host.json")
    Write-Host "Firefox-manifest gekopieerd: $(Join-Path $ffDir 'com.downoader.host.json')"
}

Write-Host ""
Write-Host "Klaar. Herlaad de extentie:"
Write-Host "  Chrome/Edge: chrome://extensions of edge://extensions (knop refresh)"
Write-Host "  Firefox: about:debugging#/runtime/this-firefox -> Load Temporary Add-on"
Write-Host "           kies extension\manifest.json (zelfde map als Chrome)."
Write-Host "open daarna de popup opnieuw."



