param(
    [Parameter(Mandatory = $true)][string]$PrefsPath,
    [Parameter(Mandatory = $true)][string]$AppExe,
    [Parameter(Mandatory = $true)][string]$DownloadDir
)

$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $PrefsPath
New-Item -ItemType Directory -Force -Path $dir | Out-Null
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

$prefs = [ordered]@{}
if (Test-Path $PrefsPath) {
    try {
        $raw = Get-Content -LiteralPath $PrefsPath -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) {
            $prefs[$p.Name] = $p.Value
        }
    } catch {}
}

$prefs["flutter.app_exe"] = $AppExe
$prefs["flutter.download_dir"] = $DownloadDir

# Keep folder history aware of the chosen dir
$history = @()
if ($prefs.Contains("flutter.folder_history") -and $prefs["flutter.folder_history"]) {
    try {
        $history = @($prefs["flutter.folder_history"] | ConvertFrom-Json)
    } catch {
        if ($prefs["flutter.folder_history"] -is [System.Array]) {
            $history = @($prefs["flutter.folder_history"])
        }
    }
}
if ($history -notcontains $DownloadDir) {
    $history = @($DownloadDir) + @($history | Where-Object { $_ -and $_ -ne $DownloadDir })
    if ($history.Count -gt 20) { $history = $history[0..19] }
}
$prefs["flutter.folder_history"] = ($history | ConvertTo-Json -Compress)

($prefs | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $PrefsPath -Encoding UTF8
Write-Host "prefs written: download_dir=$DownloadDir app_exe=$AppExe"
