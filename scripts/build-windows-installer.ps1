# Bouwt de Windows-release + gebundelde tools + native host + Setup.exe
# Vereist: Flutter SDK, Dart SDK. Inno Setup 6 wordt via winget geinstalleerd indien nodig.
#
# Gebruik:
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows-installer.ps1

param(
    [switch]$SkipFlutterBuild,
    [switch]$SkipInnoInstall
)

$ErrorActionPreference = "Stop"
# Flutter/VS verwachten deze var; sommige shells hebben hem niet.
if (-not ${env:ProgramFiles(x86)}) {
    $env:ProgramFiles = "C:\Program Files"
    ${env:ProgramFiles(x86)} = "C:\Program Files (x86)"
}
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$releaseDir = Join-Path $root "build\windows\x64\runner\Release"
$distDir = Join-Path $root "dist"
$legacyRelease = Join-Path $root "Release"
$version = "1.2.2"

function Find-ISCC {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

Write-Host "=== 1/5 Flutter Windows release ===" -ForegroundColor Cyan
if (-not $SkipFlutterBuild) {
    flutter pub get
    flutter build windows --release
} else {
    Write-Host "Skip Flutter build"
}
if (-not (Test-Path (Join-Path $releaseDir "downoader.exe"))) {
    throw "Release-build ontbreekt: $releaseDir\downoader.exe"
}

Write-Host "=== 2/5 Tools bundelen (yt-dlp, ffmpeg, deno) ===" -ForegroundColor Cyan
$toolsDir = Join-Path $releaseDir "tools"
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "bundle-tools.ps1") -TargetDir $toolsDir

Write-Host "=== 3/5 Native messaging host compileren ===" -ForegroundColor Cyan
Push-Location (Join-Path $root "native_host")
try {
    dart pub get
    $hostOutDir = Join-Path $releaseDir "host"
    New-Item -ItemType Directory -Force -Path $hostOutDir | Out-Null
    $hostExe = Join-Path $hostOutDir "downoader_native_host.exe"
    dart compile exe bin/host.dart -o $hostExe
    # Houd ook extension\host bij voor unpacked-extentie tijdens development
    $extHostDir = Join-Path $root "extension\host"
    New-Item -ItemType Directory -Force -Path $extHostDir | Out-Null
    Copy-Item -Force $hostExe (Join-Path $extHostDir "downoader_native_host.exe")
} finally {
    Pop-Location
}


Write-Host "=== 3b/5 Extentie-bestanden kopieren ===" -ForegroundColor Cyan
# Fixed extension key/id: alleen opnieuw genereren als python beschikbaar is
# en extension-id.txt ontbreekt (anders blijft de vaste ID uit de repo).
$idFile = Join-Path $root "installer\extension-id.txt"
$genKey = Join-Path $root "installer\gen_ext_key.py"
$python = $null
foreach ($c in @("python", "py")) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source; break }
}
if ($python -and (Test-Path $genKey) -and -not (Test-Path $idFile)) {
    & $python $genKey | Write-Host
} elseif (-not (Test-Path $idFile)) {
    Write-Host "Waarschuwing: geen python en geen extension-id.txt — vaste fallback-ID wordt gebruikt."
}
$extSrc = Join-Path $root "extension"
$extDst = Join-Path $releaseDir "extension"
if (Test-Path $extDst) { Remove-Item -Recurse -Force $extDst }
New-Item -ItemType Directory -Force -Path $extDst | Out-Null
# Alleen de unpacked extentie (geen host-exe; die staat in {app}\host)
Copy-Item -Force (Join-Path $extSrc "manifest.json") $extDst
Copy-Item -Force (Join-Path $extSrc "background.js") $extDst
Copy-Item -Force (Join-Path $extSrc "popup.js") $extDst
Copy-Item -Force (Join-Path $extSrc "popup.html") $extDst
Copy-Item -Force (Join-Path $extSrc "popup.css") $extDst -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force (Join-Path $extSrc "icons") (Join-Path $extDst "icons")
Copy-Item -Force (Join-Path $root "installer\extension-guide.html") (Join-Path $extDst "INSTALL-EXTENSION.html")
$idLine = (Get-Content $idFile -ErrorAction SilentlyContinue | Where-Object { $_ -like "ExtensionId=*" } | Select-Object -First 1)
$extId = if ($idLine) { $idLine.Substring("ExtensionId=".Length).Trim() } else { "meecghmbaeipmpnopapdkknnjcgconeh" }
Write-Host "Extension ID: $extId"

Write-Host "=== 4/5 Release-map synchroniseren ===" -ForegroundColor Cyan
if (Test-Path $legacyRelease) { Remove-Item -Recurse -Force $legacyRelease }
Copy-Item -Recurse -Force $releaseDir $legacyRelease
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

Write-Host "=== 5/5 Setup.exe bouwen (Inno Setup) ===" -ForegroundColor Cyan
$iscc = Find-ISCC
if (-not $iscc -and -not $SkipInnoInstall) {
    Write-Host "Inno Setup niet gevonden, installeren via winget..."
    winget install --id JRSoftware.InnoSetup --accept-package-agreements --accept-source-agreements
    $iscc = Find-ISCC
}
if (-not $iscc) {
    throw "ISCC.exe niet gevonden. Installeer Inno Setup 6+ en probeer opnieuw."
}

$iss = Join-Path $root "installer\Downloader.iss"
& $iscc `
    "/DBuildDir=$releaseDir" `
    "/DDistDir=$distDir" `
    "/DMyAppVersion=$version" `
    "/DMyExtensionId=$extId" `
    $iss

$setup = Join-Path $distDir "DownloaderSetup-$version.exe"
if (-not (Test-Path $setup)) {
    throw "Setup.exe niet aangemaakt: $setup"
}

Write-Host ""
Write-Host "Klaar." -ForegroundColor Green
Write-Host "Installer: $setup"
Write-Host "Portable map: $legacyRelease (met tools\ en host\)"

