<#
.SYNOPSIS
  Pull the personal Basalt files (model configs and launcher scripts) from the private
  basalt4win-private repository into this machine.

.DESCRIPTION
  The public Basalt4Win repository holds source only. Your model configs, launcher scripts and
  patch scripts live in a private repository, because they carry your drive layout. This script
  clones or refreshes that repository and copies the files into place, asking before it
  overwrites anything.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tools\win\fetch-personal-config.ps1
  powershell -ExecutionPolicy Bypass -File .\tools\win\fetch-personal-config.ps1 -InstallDir D:\Sergey\Basalt4Win -ScriptsDir D:\Sergey\DevScripts
#>
[CmdletBinding()]
param(
    [string]$Repo        = "sbsamarski/basalt4win-private",
    [string]$InstallDir  = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))),
    [string]$ScriptsDir  = "$PSScriptRoot\..\..\..\DevScripts",
    [string]$CacheDir    = "$env:USERPROFILE\.cache\basalt4win-private",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not on PATH." }

if (Test-Path (Join-Path $CacheDir ".git")) {
    Write-Host "refreshing $CacheDir"
    git -C $CacheDir pull --ff-only | Out-Null
} else {
    Write-Host "cloning $Repo into $CacheDir"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CacheDir) | Out-Null
    git clone "https://github.com/$Repo.git" $CacheDir | Out-Null
}

# basalt-*.json go beside the install (BASALT-RUN.ps1 looks for <install>\basalt-<name>.json);
# the scripts go to your script folder.
$jobs = @(
    @{ From = (Join-Path $CacheDir "basalt-configs\*.json");     To = $InstallDir }
    @{ From = (Join-Path $CacheDir "devscripts\*");             To = $ScriptsDir }
)

foreach ($j in $jobs) {
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $j.From))) { Write-Warning "nothing to copy from $($j.From)"; continue }
    New-Item -ItemType Directory -Force -Path $j.To | Out-Null
    foreach ($f in Get-ChildItem -Path $j.From -File) {
        $dest = Join-Path $j.To $f.Name
        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            $answer = Read-Host "overwrite $dest ? [y/N]"
            if ($answer -notmatch "^[yY]") { Write-Host "  kept   $($f.Name)"; continue }
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "  copied $($f.Name)"
    }
}

Write-Host ""
Write-Host "Done. Configs are in $InstallDir, scripts in $ScriptsDir."
Write-Host "If you changed the model pack paths inside a basalt-*.json, edit them for this machine before starting the server."
