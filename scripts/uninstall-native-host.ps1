# Unregisters the Downloader Native Messaging host from Chrome/Edge/Firefox.

$ErrorActionPreference = "SilentlyContinue"

$keys = @(
    "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.downoader.host",
    "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.downoader.host",
    "HKCU:\Software\Mozilla\NativeMessagingHosts\com.downoader.host"
)

foreach ($key in $keys) {
    if (Test-Path $key) {
        Remove-Item -Path $key -Recurse -Force
        Write-Host "Verwijderd: $key"
    } else {
        Write-Host "Niet aanwezig: $key"
    }
}

$ffManifest = Join-Path $env:APPDATA "Mozilla\NativeMessagingHosts\com.downoader.host.json"
if (Test-Path $ffManifest) {
    Remove-Item -Force $ffManifest
    Write-Host "Verwijderd: $ffManifest"
}

Write-Host "Klaar."
