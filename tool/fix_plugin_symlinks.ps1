# 在未开启 Windows 开发者模式时，预先为 Flutter 的插件符号链接占位。
# Flutter 要求 windows\flutter\ephemeral\.plugin_symlinks\<plugin> 是符号链接；
# 这里用 NTFS junction 占位（junction 不需要 SeCreateSymbolicLinkPrivilege）。
# 用法： powershell -ExecutionPolicy Bypass -File tool\fix_plugin_symlinks.ps1
# 注意： flutter clean 会删掉 ephemeral 目录，清完后需重跑本脚本。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dep = Join-Path $root '.flutter-plugins-dependencies'
if (-not (Test-Path $dep)) { Write-Host "no plugin manifest: $dep"; exit 0 }
$json = Get-Content $dep -Raw -Encoding UTF8 | ConvertFrom-Json
$sym = Join-Path $root 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $sym | Out-Null

$windows = $json.plugins.windows
if (-not $windows) { Write-Host 'no windows plugins'; exit 0 }

foreach ($pl in $windows) {
    $name = $pl.name
    $target = $pl.path -replace '\\\\', '\'
    $link = Join-Path $sym $name
    if (Test-Path $link) { Write-Host "ok       $name"; continue }
    if (-not (Test-Path $target)) { Write-Host "MISSING  $name -> $target"; continue }
    cmd /c mklink /J "$link" "$target" | Out-Null
    if (Test-Path $link) { Write-Host "junction $name" } else { Write-Host "FAILED   $name" }
}
