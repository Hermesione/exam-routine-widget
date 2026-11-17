# Headless export check for the Exam Routine Widget.
#
# Renders the card with demo data (never the user's data) and writes:
#   png-print.png, png-desktop.png, pdf-a4.pdf, pdf-card.pdf
# then validates the files. Run with:
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\qa-export.ps1
#
# -OutDir defaults to %TEMP%\exam-widget-qa so nothing lands in the repo.

[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP 'exam-widget-qa' }
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

. (Join-Path $root 'lib\Card.ps1')
. (Join-Path $root 'lib\Layout.ps1')
. (Join-Path $root 'lib\Export.ps1')

$failures = New-Object System.Collections.ArrayList
function Pass([string]$Message) { Write-Host "  ok   $Message" -ForegroundColor Green }
function Fail([string]$Message) {
    Write-Host "  FAIL $Message" -ForegroundColor Red
    [void]$failures.Add($Message)
}
function Check([bool]$Condition, [string]$Message) {
    if ($Condition) { Pass $Message } else { Fail $Message }
}

# Demo data, dates relative to today so the card always looks current.
$today = (Get-Date).Date
$demo = @(
    [pscustomobject]@{
        Date = $today.AddDays(14).ToString('yyyy-MM-dd'); Time = '09:00-11:00'
        Code = 'CMPS 200'; Title = 'Introduction to Programming'; Section = 'L01'
        Room = 'B-101'; CRN = '10001'
    },
    [pscustomobject]@{
        Date = $today.AddDays(16).ToString('yyyy-MM-dd'); Time = '13:30-15:30'
        Code = 'MATH 210'; Title = 'Linear Algebra'; Section = 'L02'
        Room = 'C-204'; CRN = '10002'
    },
    [pscustomobject]@{
        Date = $today.AddDays(21).ToString('yyyy-MM-dd'); Time = '08:00-10:00'
        Code = 'PHYS 150'; Title = 'General Physics'; Section = 'L03'
        Room = 'D-310'; CRN = '10003'
    }
)

$common = @{
    ExamList     = $demo
    TermText     = 'Demo Term 2026'
    TermCodeText = 'Term 202610'
    Accent       = '#F2577C'
    TitleText    = 'Final Exam Routine'
    FooterText   = 'times are local'
}

Write-Host ''
Write-Host 'Rendering exports with demo data' -ForegroundColor Cyan
Write-Host "  out: $OutDir"

$files = [ordered]@{
    'png-print.png'   = @{ Format = 'png'; Style = 'print'; Page = 'a4' }
    'png-desktop.png' = @{ Format = 'png'; Style = 'desktop'; Page = 'a4' }
    'pdf-a4.pdf'      = @{ Format = 'pdf'; Style = 'print'; Page = 'a4' }
    'pdf-card.pdf'    = @{ Format = 'pdf'; Style = 'print'; Page = 'card' }
}

foreach ($name in $files.Keys) {
    $spec = $files[$name]
    $path = Join-Path $OutDir $name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    try {
        Export-Routine -Path $path -Format $spec.Format -Style $spec.Style -Page $spec.Page `
            @common | Out-Null
        Pass "exported $name"
    }
    catch {
        Fail "export $name : $($_.Exception.Message)"
    }
}

function Test-PngFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'file missing' }
    $info = Get-Item -LiteralPath $Path
    if ($info.Length -lt 5000) { return "file too small ($($info.Length) bytes)" }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $stream = New-Object System.IO.MemoryStream(, $bytes)
        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit()
        $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $img.StreamSource = $stream
        $img.EndInit()
        $width = $img.PixelWidth
        $height = $img.PixelHeight
        $stream.Dispose()
        $expected = [int]((440 + 56) * 3)
        if ($width -ne $expected) { return "unexpected width $width, wanted $expected" }
        if ($height -lt 300) { return "unexpected height $height" }
        return $null
    }
    catch {
        return "decode failed: $($_.Exception.Message)"
    }
}

function Test-PdfFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'file missing' }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 5000) { return "file too small ($($bytes.Length) bytes)" }
    $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
    if (-not $ascii.StartsWith('%PDF-1.4')) { return 'missing %PDF-1.4 header' }
    if (-not $ascii.TrimEnd().EndsWith('%%EOF')) { return 'missing %%EOF trailer' }
    if (-not $ascii.Contains('/Root 1 0 R')) { return 'missing /Root reference' }

    $start = [regex]::Match($ascii, 'startxref\s+(\d+)\s+%%EOF\s*$')
    if (-not $start.Success) { return 'missing startxref' }
    $offset = [int]$start.Groups[1].Value
    if ($offset -lt 0 -or $offset -ge $bytes.Length) { return 'startxref out of range' }
    $chunk = [System.Text.Encoding]::ASCII.GetString($bytes, $offset, [math]::Min(40, $bytes.Length - $offset))
    if ($chunk -notmatch '^\s*xref') { return 'startxref does not point at the xref table' }

    $entries = [regex]::Matches($ascii, '(?m)^(\d{10}) 00000 n')
    if ($entries.Count -lt 5) { return "expected at least 5 xref entries, found $($entries.Count)" }
    $index = 1
    foreach ($entry in $entries) {
        $objOffset = [int]$entry.Groups[1].Value
        if ($objOffset -lt 0 -or $objOffset -ge $bytes.Length) { return "object $index offset out of range" }
        $objChunk = [System.Text.Encoding]::ASCII.GetString($bytes, $objOffset, [math]::Min(32, $bytes.Length - $objOffset))
        if ($objChunk -notmatch "^\s*$index\s+0\s+obj") {
            return "object $index at offset $objOffset does not start with '$index 0 obj'"
        }
        $index++
    }
    return $null
}

Write-Host ''
Write-Host 'Validating output' -ForegroundColor Cyan

foreach ($name in @('png-print.png', 'png-desktop.png')) {
    $path = Join-Path $OutDir $name
    $problem = Test-PngFile $path
    Check (-not $problem) ($(if ($problem) { "$name : $problem" } else { "$name is a valid 1488px-wide PNG" }))
}

foreach ($name in @('pdf-a4.pdf', 'pdf-card.pdf')) {
    $path = Join-Path $OutDir $name
    $problem = Test-PdfFile $path
    Check (-not $problem) ($(if ($problem) { "$name : $problem" } else { "$name has a valid header, xref table and objects" }))
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures.Count) check(s)" -ForegroundColor Red
    exit 1
}

Write-Host "All export checks passed. Files are in $OutDir" -ForegroundColor Green
Write-Host 'Open the PDFs in a viewer (Edge is fine) to confirm the image renders.' -ForegroundColor DarkGray
exit 0
