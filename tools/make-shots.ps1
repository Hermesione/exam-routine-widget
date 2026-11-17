# Renders the sanitized documentation screenshots in docs/:
#   card-dark.png, card-light.png  (demo data, no personal information)
#   editor.png                     (editor UI, demo data)
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\make-shots.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$docs = Join-Path $root 'docs'
if (-not (Test-Path -LiteralPath $docs)) { New-Item -ItemType Directory -Path $docs -Force | Out-Null }

# 1. Card renders via the export tool (already demo data).
$qaDir = Join-Path $env:TEMP 'exam-widget-shots'
if (Test-Path -LiteralPath $qaDir) { Remove-Item -LiteralPath $qaDir -Recurse -Force }
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'qa-export.ps1') -OutDir $qaDir
if ($LASTEXITCODE -ne 0) { throw 'export checks failed' }
Copy-Item -LiteralPath (Join-Path $qaDir 'png-desktop.png') -Destination (Join-Path $docs 'card-dark.png') -Force
Copy-Item -LiteralPath (Join-Path $qaDir 'png-print.png') -Destination (Join-Path $docs 'card-light.png') -Force

# 2. Editor snapshot from a temp copy with demo data.
$stage = Join-Path $env:TEMP 'exam-widget-demo'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'ExamEditor.ps1') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root 'ExamWidget.ps1') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root 'lib') -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'assets') -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'version.txt') -Destination $stage -Force

$demoDir = Join-Path $stage 'data'
New-Item -ItemType Directory -Path $demoDir -Force | Out-Null
$today = (Get-Date).Date
$demo = [ordered]@{
    term = 'Demo Term 2026'
    termCode = 'Term 202610'
    accent = '#F2577C'
    title = 'Final Exam Routine'
    footer = 'times are local'
    exams = @(
        @{ date = $today.AddDays(14).ToString('yyyy-MM-dd'); time = '09:00-11:00'; code = 'CMPS 200'; title = 'Introduction to Programming'; section = 'L01'; room = 'B-101'; crn = '10001' },
        @{ date = $today.AddDays(16).ToString('yyyy-MM-dd'); time = '13:30-15:30'; code = 'MATH 210'; title = 'Linear Algebra'; section = 'L02'; room = 'C-204'; crn = '10002' },
        @{ date = $today.AddDays(21).ToString('yyyy-MM-dd'); time = '08:00-10:00'; code = 'PHYS 150'; title = 'General Physics'; section = 'L03'; room = 'D-310'; crn = '10003' }
    )
}
$json = $demo | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $demoDir 'exams.json'), $json, (New-Object System.Text.UTF8Encoding($false)))

$editorShot = Join-Path $docs 'editor.png'
if (Test-Path -LiteralPath $editorShot) { Remove-Item -LiteralPath $editorShot -Force }
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $stage 'ExamEditor.ps1') -SnapshotPath $editorShot
if (-not (Test-Path -LiteralPath $editorShot)) { throw 'editor snapshot was not produced' }

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "docs ready: $docs"
Get-ChildItem -LiteralPath $docs -File | ForEach-Object { "  $($_.Name) ($([math]::Round($_.Length / 1KB)) KB)" }
