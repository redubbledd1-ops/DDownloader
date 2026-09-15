# Unregisters the Downloader Native Messaging host from Chrome/Edge.

$ErrorActionPreference = "SilentlyContinue"

$keys = @(
    "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.downoader.host",
    "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.downoader.host"
)

foreach ($key in $keys) {
    if (Test-Path $key) {
        Remove-Item -Path $key -Recurse -Force
        Write-Host "Verwijderd: $key"
    } else {
        Write-Host "Niet aanwezig: $key"
    }
}

Write-Host "Klaar."
