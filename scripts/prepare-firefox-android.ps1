# Bouwt een Firefox-Android-klare kopie van de gedeelde extension/-map.
# Firefox Android weigert background.service_worker (ook als scripts erbij staat).
#
# Gebruik:
#   powershell -ExecutionPolicy Bypass -File scripts\prepare-firefox-android.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\run-firefox-android.ps1

param(
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "extension"
if (-not $OutDir) {
    $OutDir = Join-Path $root "extension-firefox-android"
}

if (-not (Test-Path (Join-Path $src "manifest.json"))) {
    throw "Bron-extentie niet gevonden: $src"
}

if (Test-Path $OutDir) {
    Remove-Item -Recurse -Force $OutDir
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($name in @("background.js", "popup.js", "popup.html", "popup.css")) {
    $from = Join-Path $src $name
    if (Test-Path $from) {
        Copy-Item -Force $from (Join-Path $OutDir $name)
    }
}
Copy-Item -Recurse -Force (Join-Path $src "icons") (Join-Path $OutDir "icons")

$manifest = Get-Content (Join-Path $src "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json

# Alleen event-page scripts — geen service_worker (Android-blokkeerder).
$manifest.background = [pscustomobject]@{ scripts = @("background.js") }

# Chrome-only "key" is niet nodig op Firefox.
if ($manifest.PSObject.Properties.Name -contains "key") {
    $manifest.PSObject.Properties.Remove("key")
}

# nativeMessaging bestaat niet op Android; weglaten voorkomt verwarring.
$perms = @($manifest.permissions | Where-Object { $_ -ne "nativeMessaging" })
if ($perms.Count -eq 0) { $perms = @("activeTab", "tabs", "storage") }
$manifest.permissions = $perms

# Zorg dat gecko_android expliciet staat (AMO/desktop vs Android).
if (-not $manifest.browser_specific_settings) {
    $manifest | Add-Member -NotePropertyName browser_specific_settings -NotePropertyValue ([pscustomobject]@{})
}
$bss = $manifest.browser_specific_settings
if (-not $bss.gecko) {
    $bss | Add-Member -NotePropertyName gecko -NotePropertyValue ([pscustomobject]@{
        id = "downloader@downoader.app"
        strict_min_version = "121.0"
    }) -Force
}
if (-not $bss.gecko_android) {
    $bss | Add-Member -NotePropertyName gecko_android -NotePropertyValue ([pscustomobject]@{
        strict_min_version = "121.0"
    }) -Force
}

$json = $manifest | ConvertTo-Json -Depth 10
# PowerShell ConvertTo-Json kan Unicode-escape; schrijf UTF-8 zonder BOM.
[System.IO.File]::WriteAllText(
    (Join-Path $OutDir "manifest.json"),
    $json,
    (New-Object System.Text.UTF8Encoding $false)
)

Write-Host "Firefox Android extentie klaar: $OutDir"
Write-Host "Manifest background = scripts only (geen service_worker)."
# Pad op stdout (laatste regel) zodat run-firefox-android.ps1 het kan pakken
Write-Output $OutDir
