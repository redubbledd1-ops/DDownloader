# Start de Downloader-extentie op een USB-gekoppelde Firefox-Android.
# Vereist: adb, Firefox op de telefoon, "Remote Debugging via USB" aan,
# en de Downloader-APK geinstalleerd (voor de knop Naar App).
#
# Gebruik:
#   powershell -ExecutionPolicy Bypass -File scripts\run-firefox-android.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\run-firefox-android.ps1 -Device 437d872e
#   powershell -ExecutionPolicy Bypass -File scripts\run-firefox-android.ps1 -FirefoxApk org.mozilla.firefox_beta

param(
    [string]$Device = "",
    [string]$FirefoxApk = "org.mozilla.firefox"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$prepareOut = & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "prepare-firefox-android.ps1")
$outDir = ($prepareOut | Select-Object -Last 1).ToString().Trim()
if (-not $outDir -or -not (Test-Path (Join-Path $outDir "manifest.json"))) {
    $outDir = Join-Path $root "extension-firefox-android"
}
if (-not (Test-Path (Join-Path $outDir "manifest.json"))) {
    throw "Prepare mislukt: $outDir"
}

# Toon aangesloten devices als -Device ontbreekt
if (-not $Device) {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if ($adb) {
        $lines = & adb devices | Where-Object { $_ -match "\tdevice$" }
        $ids = @($lines | ForEach-Object { ($_ -split "\s+")[0] })
        if ($ids.Count -eq 1) {
            $Device = $ids[0]
            Write-Host "Automatisch device: $Device"
        } elseif ($ids.Count -gt 1) {
            Write-Host "Meerdere Android-devices:"
            $ids | ForEach-Object { Write-Host "  $_" }
            throw "Kies er een met -Device <id>"
        } else {
            throw "Geen adb-device gevonden. Sluit je telefoon aan en zet USB-debugging aan."
        }
    } else {
        throw "adb niet gevonden in PATH. Installeer Android platform-tools."
    }
}

Write-Host ""
Write-Host "web-ext run → $outDir"
Write-Host "APK: $FirefoxApk  device: $Device"
Write-Host "Zorg dat Remote Debugging via USB in Firefox aanstaat."
Write-Host ""

npx --yes web-ext@8 run `
    -t firefox-android `
    --firefox-apk $FirefoxApk `
    --android-device=$Device `
    --source-dir $outDir `
    --adb-remove-old-artifacts
