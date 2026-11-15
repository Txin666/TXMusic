# Prepare the libmpv archive required by media_kit on Windows.
#
# The media_kit_libs_windows_audio CMake script downloads
# mpv-dev-x86_64-*.7z from GitHub Releases and verifies its MD5 at
# configure time. On flaky networks this often ends up as a 0-byte file
# and the build fails with "Integrity check failed". `flutter clean`
# wipes the build directory, so the archive has to be fetched again.
#
# Usage (from the project root):
#   powershell -ExecutionPolicy Bypass -File tools\prepare_windows_build.ps1
# Suggested order: flutter clean -> this script -> flutter run / build windows
param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$archiveName = 'mpv-dev-x86_64-20230924-git-652a1dd.7z'
$expectedMd5 = 'cd738e16e2a19626d7cfa48801524f8c'
$url = "https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/$archiveName"

$buildDir = Join-Path $ProjectRoot 'build\windows\x64'
$cacheDir = Join-Path $ProjectRoot '.local\third_party\mpv'
$target = Join-Path $buildDir $archiveName
$cached = Join-Path $cacheDir $archiveName

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

function Test-Archive([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  if ((Get-Item $Path).Length -eq 0) { return $false }
  $hash = (Get-FileHash $Path -Algorithm MD5).Hash.ToLower()
  return ($hash -eq $expectedMd5)
}

if (Test-Archive $target) {
  Write-Host "[ok] libmpv archive already present in build dir, nothing to do."
  exit 0
}

if (Test-Archive $cached) {
  Copy-Item $cached $target -Force
  Write-Host "[ok] libmpv archive restored from local cache: $cached"
  exit 0
}

Write-Host "[..] No usable cache found, downloading (~5.4 MB)..."
# --ssl-no-revoke: skips the schannel revocation check, which otherwise
# fails on many machines with CRYPT_E_NO_REVOCATION_CHECK.
& curl.exe -L --ssl-no-revoke --retry 3 --retry-delay 2 --connect-timeout 15 -o $target $url
if (-not (Test-Archive $target)) {
  Remove-Item $target -Force -ErrorAction SilentlyContinue
  throw "Download or MD5 check failed: $url (download it manually and put it in $cacheDir, then rerun this script)."
}

Copy-Item $target $cached -Force
Write-Host "[ok] Download complete, MD5 verified, synced to local cache."
