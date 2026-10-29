<#
普通启动验收：release 构建成功不等于能正常启动（docs/env.md §6、§10：
本机构建目录产物可能继承 Low 完整性标签，默认 AppData 写入被拒）。
流程：打包 -> 解压到普通目录 -> 默认数据根启动 -> 窗口/完整性/退出/作品文件校验。
任何一步失败即 FAIL；不得用 NWW_DATA_ROOT 等开发变量替代默认路径。
#>
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path $PSScriptRoot -Parent
$pubspec = Join-Path $root 'pubspec.yaml'
$version = 'unknown'
if (Test-Path -LiteralPath $pubspec) {
  $match = Select-String -LiteralPath $pubspec -Pattern '^version:\s*([0-9A-Za-z.+-]+)' | Select-Object -First 1
  if ($null -ne $match) { $version = $match.Matches[0].Groups[1].Value -replace '\+', '-' }
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$name = 'no-white-writer-' + $version + '-windows-x64-' + $stamp
$source = Join-Path $root 'build\windows\x64\runner\Release'
$packageDir = Join-Path $root 'build\packages'
$zip = Join-Path $packageDir ($name + '.zip')
$target = Join-Path (Join-Path $env:USERPROFILE 'Downloads') $name
$proof = Join-Path $root ('.devdata\verify-normal-startup-' + $stamp)
New-Item -ItemType Directory -Path $proof | Out-Null
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $source 'no_white_writer.exe'))) {
  throw 'Release build output not found; run flutter build windows --release first.'
}
if ((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath $target)) {
  throw 'Refusing to overwrite an existing release.'
}
function Get-FileManifest([string]$directory) {
  if (-not (Test-Path -LiteralPath $directory)) { return @() }
  return @(Get-ChildItem -LiteralPath $directory -Recurse -File | Sort-Object FullName | ForEach-Object {
    [pscustomobject]@{ Path = $_.FullName.Substring($directory.Length + 1); SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
  })
}
$before = Get-FileManifest $source
$before | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $proof 'source-manifest.json') -Encoding UTF8
Compress-Archive -Path (Join-Path $source '*') -DestinationPath $zip -CompressionLevel Optimal
Expand-Archive -LiteralPath $zip -DestinationPath $target
$after = Get-FileManifest $target
if (@(Compare-Object $before $after -Property Path,SHA256).Count -ne 0) { throw 'Extracted bundle differs from the build.' }
Write-Output ('MATCHED_FILES=' + $after.Count)
Write-Output ('ZIP=' + $zip)
Write-Output ('ZIP_SHA256=' + (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash)
Write-Output ('EXTRACTED=' + $target)
$exe = Join-Path $target 'no_white_writer.exe'
$aclText = (& icacls $exe | Out-String)
Write-Output $aclText
if ($aclText -match 'Low Mandatory Level|S-1-16-4096') { throw 'Extracted executable is still Low integrity.' }
$env:NWW_DATA_ROOT = $null
$env:NWW_DEV_PAGE = $null
$env:NWW_DEV_TYPE = $null
$appFolder = [string]::Join('', [char[]]@(0x4e0d,0x767d,0x5199,0x4f5c))
$dataRoot = Join-Path $env:APPDATA $appFolder
$booksDir = Join-Path $dataRoot 'books'
$booksBefore = Get-FileManifest $booksDir
$booksBefore | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $proof 'books-before.json') -Encoding UTF8
$outFile = Join-Path $proof 'stdout.txt'
$errFile = Join-Path $proof 'stderr.txt'
$app = $null
try {
  $app = Start-Process -FilePath $exe -WorkingDirectory $target -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
  # Retain the native process handle before it exits, so ExitCode stays available.
  $processHandle = $app.Handle
  Write-Output ('APP_PID=' + $app.Id)
  $deadline = (Get-Date).AddSeconds(12)
  do {
    $app.Refresh()
    if ($app.HasExited -or ($app.MainWindowHandle -ne 0 -and $app.MainWindowTitle -eq $appFolder)) { break }
    Start-Sleep -Milliseconds 100
  } while ((Get-Date) -lt $deadline)
  $app.Refresh()
  if ($app.HasExited -or $app.MainWindowHandle -eq 0 -or $app.MainWindowTitle -ne $appFolder) {
    throw 'Normal launch failed to show the expected window (another instance holding the single-instance lock also causes this).'
  }
  Write-Output ('WINDOW=' + $app.MainWindowHandle)
  Write-Output ('TITLE=' + $app.MainWindowTitle)
  $null = $app.CloseMainWindow()
  if (-not $app.WaitForExit(5000)) { throw 'Verified app did not close normally.' }
  Write-Output ('EXIT_CODE=' + $app.ExitCode)
  if ($app.ExitCode -ne 0) { throw 'App exited unsuccessfully.' }
} finally {
  if ($null -ne $app) {
    $app.Refresh()
    if (-not $app.HasExited) { Stop-Process -Id $app.Id }
  }
}
$booksAfter = Get-FileManifest $booksDir
if (@(Compare-Object $booksBefore $booksAfter -Property Path,SHA256).Count -ne 0) { throw 'Existing book files changed during the startup check.' }
Write-Output ('UNCHANGED_BOOK_FILES=' + $booksAfter.Count)
if (@(Compare-Object $before (Get-FileManifest $target) -Property Path,SHA256).Count -ne 0) { throw 'Bundle files changed during launch.' }
Write-Output 'STDERR:'
Get-Content -LiteralPath $errFile -Encoding UTF8
if ((Get-Content -LiteralPath $errFile -Raw -Encoding UTF8) -match 'Unhandled Exception|\[ERROR:') { throw 'Native startup reported an error.' }
[pscustomobject]@{ Zip=$zip; Extracted=$target; Exe=$exe; Proof=$proof; FileCount=$after.Count; BookFiles=$booksAfter.Count } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root '.devdata\verify-normal-startup-latest.json') -Encoding UTF8
Write-Output 'PASS: release bundle starts normally with default AppData and unchanged book files.'
