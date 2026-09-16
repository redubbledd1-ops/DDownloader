# Downloads yt-dlp, ffmpeg and deno into a tools\ folder for the Windows release.
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDir
)

$ErrorActionPreference = "Stop"

$ytDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
$ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$denoUrl = "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip"

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
$cache = Join-Path $PSScriptRoot "..\.tools-cache"
New-Item -ItemType Directory -Force -Path $cache | Out-Null

function Get-CachedFile([string]$Url, [string]$FileName) {
    $dest = Join-Path $cache $FileName
    if (Test-Path $dest) {
        Write-Host "Cache hit: $FileName"
        return $dest
    }
    Write-Host "Downloading $FileName ..."
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
    return $dest
}

$ytDlp = Get-CachedFile $ytDlpUrl "yt-dlp.exe"
Copy-Item -Force $ytDlp (Join-Path $TargetDir "yt-dlp.exe")

$ffmpegZip = Get-CachedFile $ffmpegUrl "ffmpeg-master-latest-win64-gpl.zip"
$ffmpegExtract = Join-Path $cache "ffmpeg-extract"
if (Test-Path $ffmpegExtract) { Remove-Item -Recurse -Force $ffmpegExtract }
Expand-Archive -Path $ffmpegZip -DestinationPath $ffmpegExtract -Force
$ffmpegExe = Get-ChildItem -Path $ffmpegExtract -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
$ffprobeExe = Get-ChildItem -Path $ffmpegExtract -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
if (-not $ffmpegExe -or -not $ffprobeExe) {
    throw "ffmpeg.exe/ffprobe.exe niet gevonden in zip"
}
Copy-Item -Force $ffmpegExe.FullName (Join-Path $TargetDir "ffmpeg.exe")
Copy-Item -Force $ffprobeExe.FullName (Join-Path $TargetDir "ffprobe.exe")

$denoZip = Get-CachedFile $denoUrl "deno-x86_64-pc-windows-msvc.zip"
$denoExtract = Join-Path $cache "deno-extract"
if (Test-Path $denoExtract) { Remove-Item -Recurse -Force $denoExtract }
Expand-Archive -Path $denoZip -DestinationPath $denoExtract -Force
$denoExe = Get-ChildItem -Path $denoExtract -Recurse -Filter "deno.exe" | Select-Object -First 1
if (-not $denoExe) { throw "deno.exe niet gevonden in zip" }
Copy-Item -Force $denoExe.FullName (Join-Path $TargetDir "deno.exe")

Write-Host "Tools gebundeld in: $TargetDir"
Get-ChildItem $TargetDir | Format-Table Name, Length
