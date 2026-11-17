# Builds the portable ZIP in dist/ExamRoutineWidget-<version>/ and .zip,
# plus a .sha256 sidecar. No admin, no external tools.
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\build.ps1

[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }

$version = (Get-Content -Raw -LiteralPath (Join-Path $root 'version.txt')).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "version.txt is not semver: '$version'" }

$name = "ExamRoutineWidget-$version"
$stage = Join-Path $OutDir $name
$zip = Join-Path $OutDir "$name.zip"
$hashFile = "$zip.sha256"

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
if (Test-Path -LiteralPath $hashFile) { Remove-Item -LiteralPath $hashFile -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$files = @(
    'ExamWidget.ps1',
    'ExamEditor.ps1',
    'Start Exam Widget.vbs',
    'Edit Exam Routine.vbs',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'version.txt'
)

foreach ($file in $files) {
    $source = Join-Path $root $file
    if (-not (Test-Path -LiteralPath $source)) { throw "missing file: $file" }
    Copy-Item -LiteralPath $source -Destination $stage -Force
}

foreach ($dir in @('lib', 'assets')) {
    $source = Join-Path $root $dir
    if (-not (Test-Path -LiteralPath $source)) { throw "missing folder: $dir" }
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
}

$docs = Join-Path $root 'docs'
if (Test-Path -LiteralPath $docs) {
    Copy-Item -LiteralPath $docs -Destination $stage -Recurse -Force
}

# The app creates data/ on first run; ship nothing user-specific.
$junk = @(Get-ChildItem -LiteralPath $stage -Recurse -Force -File |
    Where-Object { $_.Extension -in @('.log', '.tmp', '.bak') -or $_.Name -like 'test-*' })
foreach ($file in $junk) { Remove-Item -LiteralPath $file.FullName -Force }

Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText($hashFile, "$hash  $name.zip`r`n", (New-Object System.Text.UTF8Encoding($false)))

$sizeMb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 2)
Write-Output "version: $version"
Write-Output "stage:   $stage"
Write-Output "zip:     $zip ($sizeMb MB)"
Write-Output "sha256:  $hash"
