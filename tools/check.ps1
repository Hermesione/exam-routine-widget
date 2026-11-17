# Local checks for the Exam Routine Widget.
#
# Runs the same checks CI uses: PowerShell parse, layout math, settings and
# exam-data round-trips, backup rotation, legacy data migration and accent
# contrast. Never touches data/ - every write goes to a temp folder.
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\check.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$script:Failures = New-Object System.Collections.ArrayList

function Pass([string]$Message) { Write-Host "  ok   $Message" -ForegroundColor Green }
function Fail([string]$Message) {
    Write-Host "  FAIL $Message" -ForegroundColor Red
    [void]$script:Failures.Add($Message)
}
function Check([bool]$Condition, [string]$Message) {
    if ($Condition) { Pass $Message } else { Fail $Message }
}
function Approx([double]$Actual, [double]$Expected, [double]$Tolerance = 0.5) {
    return ([math]::Abs($Actual - $Expected) -le $Tolerance)
}

Write-Host ''
Write-Host 'Parse check' -ForegroundColor Cyan
$scripts = @(Get-ChildItem -Path $root -Recurse -Filter '*.ps1' -File |
    Where-Object { $_.FullName -notmatch '\\(dist|\.git|node_modules)\\' })
foreach ($file in $scripts) {
    $relative = $file.FullName.Substring($root.Length).TrimStart('\')
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -eq 0) {
        Pass "parse $relative"
    }
    else {
        foreach ($err in $errors) {
            Fail "parse $relative line $($err.Extent.StartLineNumber): $($err.Message)"
        }
    }
}

. (Join-Path $root 'lib\Card.ps1')
. (Join-Path $root 'lib\Layout.ps1')

Write-Host ''
Write-Host 'Version and scale' -ForegroundColor Cyan
$version = Get-AppVersion
Check ($version -match '^\d+\.\d+\.\d+$') "version is semver-like (got '$version')"
Check ((Get-ClampedScale 0.1) -eq 0.7) 'scale clamped to 0.7 minimum'
Check ((Get-ClampedScale 5.0) -eq 1.5) 'scale clamped to 1.5 maximum'
Check ((Get-ClampedScale 1.0) -eq 1.0) 'scale 1.0 unchanged'
Check ((Get-ClampedScale 0.7) -eq 0.7) 'scale minimum boundary kept'

Write-Host ''
Write-Host 'Layout math' -ForegroundColor Cyan
$screen = [pscustomobject]@{
    DeviceName = '\\.\DISPLAY1'
    Primary    = $true
    WorkLeft   = 100.0
    WorkTop    = 50.0
    WorkWidth  = 1920.0
    WorkHeight = 1040.0
}
$screens = @($screen)
$cardWidth = 440.0
$cardHeight = 545.0

$expected = [ordered]@{
    'top-left'      = @(118.0, 68.0)
    'top-center'    = @(840.0, 68.0)
    'top-right'     = @(1562.0, 68.0)
    'middle-left'   = @(118.0, 297.5)
    'center'        = @(840.0, 297.5)
    'middle-right'  = @(1562.0, 297.5)
    'bottom-left'   = @(118.0, 527.0)
    'bottom-center' = @(840.0, 527.0)
    'bottom-right'  = @(1562.0, 527.0)
}

foreach ($anchor in $expected.Keys) {
    $layout = Get-DefaultLayout
    $layout.Anchor = $anchor
    $layout.Monitor = ''
    $pos = Get-LayoutPositionForSettings -Layout $layout -Screens $screens -CardWidth $cardWidth -CardHeight $cardHeight
    $want = $expected[$anchor]
    Check ((Approx $pos.X $want[0]) -and (Approx $pos.Y $want[1])) "anchor $anchor at $($pos.X),$($pos.Y)"
}

$near = Find-NearestAnchor -WorkLeft 100 -WorkTop 50 -WorkWidth 1920 -WorkHeight 1040 `
    -CardWidth 440 -CardHeight 545 -X 1566 -Y 72 -Margin 18 -Tolerance 30
Check ($near -eq 'top-right') "nearest anchor snaps to top-right (got '$near')"

$far = Find-NearestAnchor -WorkLeft 100 -WorkTop 50 -WorkWidth 1920 -WorkHeight 1040 `
    -CardWidth 440 -CardHeight 545 -X 700 -Y 300 -Margin 18 -Tolerance 30
Check ($null -eq $far) 'free position does not snap'

$layout = Get-DefaultLayout
$layout.Mode = 'custom'
$layout.RelX = 0.0
$layout.RelY = 0.0
$pos = Get-LayoutPositionForSettings -Layout $layout -Screens $screens -CardWidth $cardWidth -CardHeight $cardHeight
Check ((Approx $pos.X 100.0) -and (Approx $pos.Y 50.0)) 'custom 0,0 maps to work-area origin'

$layout.RelX = 1.0
$layout.RelY = 1.0
$pos = Get-LayoutPositionForSettings -Layout $layout -Screens $screens -CardWidth $cardWidth -CardHeight $cardHeight
Check ((Approx $pos.X 1580.0) -and (Approx $pos.Y 545.0)) 'custom 1,1 maps to bottom-right of work area'

$layout.RelX = 1.7
$layout.RelY = -0.4
$pos = Get-LayoutPositionForSettings -Layout $layout -Screens $screens -CardWidth $cardWidth -CardHeight $cardHeight
Check ((Approx $pos.X 1580.0) -and (Approx $pos.Y 50.0)) 'custom values clamped to the work area'

Write-Host ''
Write-Host 'Accent contrast' -ForegroundColor Cyan
foreach ($accent in @('#F3F7FA', '#F2577C', '#000000', '#FFFFFF', '#0B3D91')) {
    foreach ($theme in @('dark', 'light')) {
        $pal = Get-CardPalette -AccentHex $accent -Theme $theme
        $codeRatio = Get-ContrastRatio $pal.code $pal.card
        $pillRatio = Get-ContrastRatio $pal.pillFg $pal.pillBg
        $nextRatio = Get-ContrastRatio $pal.badgeNextFg $pal.badgeNextBg
        $todayRatio = Get-ContrastRatio $pal.todayFg $pal.todayBg
        Check ($codeRatio -ge 4.49) "accent $accent $theme code contrast $([math]::Round($codeRatio, 2))"
        Check ($pillRatio -ge 4.49) "accent $accent $theme pill contrast $([math]::Round($pillRatio, 2))"
        Check ($nextRatio -ge 4.49) "accent $accent $theme next-badge contrast $([math]::Round($nextRatio, 2))"
        Check ($todayRatio -ge 4.49) "accent $accent $theme today-badge contrast $([math]::Round($todayRatio, 2))"
    }
}

Write-Host ''
Write-Host 'Settings round-trip' -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP ('exam-widget-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $settingsPath = Join-Path $tmp 'settings.json'
    $layout = Get-DefaultLayout
    $layout.Mode = 'anchor'
    $layout.Anchor = 'bottom-left'
    $layout.Margin = 24
    $layout.Scale = 1.2
    $layout.Locked = $false
    Write-Settings -Settings ([pscustomobject]@{ Version = 1; Layout = $layout }) -Path $settingsPath
    $settings = Read-Settings -Path $settingsPath
    Check ($settings.Layout.Anchor -eq 'bottom-left') 'settings anchor round-trips'
    Check ([double]$settings.Layout.Margin -eq 24) 'settings margin round-trips'
    Check ([double]$settings.Layout.Scale -eq 1.2) 'settings scale round-trips'
    Check ($settings.Layout.Locked -eq $false) 'settings locked round-trips'

    $missing = Read-Settings -Path (Join-Path $tmp 'nope.json')
    Check ($missing.Layout.Anchor -eq 'top-right' -and [double]$missing.Layout.Scale -eq 1.0) 'missing settings fall back to defaults'

    $badPath = Join-Path $tmp 'bad.json'
    Set-Content -LiteralPath $badPath -Value '{ not json'
    $bad = Read-Settings -Path $badPath
    Check ($bad.Layout.Anchor -eq 'top-right') 'corrupt settings fall back to defaults'

    Write-Host ''
    Write-Host 'Exam data round-trip' -ForegroundColor Cyan
    $dataPath = Join-Path $tmp 'exams.json'
    $soon = (Get-Date).Date.AddDays(2).ToString('yyyy-MM-dd')
    $later = (Get-Date).Date.AddDays(5).ToString('yyyy-MM-dd')
    $exams = @(
        [pscustomobject]@{ Date = $later; Time = '09:00-10:00'; Code = 'AAA 100'; Title = 'Later'; Section = 'S1'; Room = 'R1'; CRN = '1' },
        [pscustomobject]@{ Date = $soon; Time = '11:00-12:00'; Code = 'BBB 200'; Title = 'Sooner'; Section = 'S2'; Room = 'R2'; CRN = '2' }
    )
    Write-ExamData -Path $dataPath -Term 'Term X' -TermCode 'Term 1' -Accent '#F2577C' `
        -Title 'My Title' -Footer 'my footer' -ExamList $exams
    $read = Read-ExamData -Path $dataPath
    Check ($read.Term -eq 'Term X') 'term round-trips'
    Check ($read.TermCode -eq 'Term 1') 'termCode round-trips'
    Check ($read.Accent -eq '#F2577C') 'accent round-trips'
    Check ($read.Title -eq 'My Title') 'title round-trips'
    Check ($read.Footer -eq 'my footer') 'footer round-trips'
    Check ($read.Exams.Count -eq 2) 'exam count round-trips'
    Check ($read.Exams[0].Code -eq 'BBB 200') 'exams sorted by date'
    Check ($read.Exams[0].Time -eq '11:00-12:00') 'time round-trips'
    Check ($read.Exams[0].CRN -eq '2') 'CRN round-trips'

    $legacyJson = '{"term":"Old","accent":"#F2577C","exams":[{"date":"' + $soon + '","time":"08:00-09:00","code":"OLD 1","title":"Old exam"}]}'
    $legacyPath = Join-Path $tmp 'legacy-exams.json'
    Set-Content -LiteralPath $legacyPath -Value $legacyJson
    $legacy = Read-ExamData -Path $legacyPath
    Check ($legacy.Title -eq 'Final Exam Routine') 'missing title falls back to the default'
    Check ($legacy.Footer -eq 'times are local') 'missing footer falls back to the default'
    Check ($legacy.Exams.Count -eq 1) 'legacy data without title/footer still loads'

    Write-Host ''
    Write-Host 'Backup rotation' -ForegroundColor Cyan
    $oldBackup = $script:BackupDir
    try {
        $script:BackupDir = Join-Path $tmp 'backups'
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
        $fake = Join-Path $tmp 'fake-exams.json'
        Set-Content -LiteralPath $fake -Value '{"term":"Backup test","exams":[]}'
        for ($i = 0; $i -lt 12; $i++) {
            Backup-ExamData -Path $fake
            Start-Sleep -Milliseconds 5
        }
        $count = @(Get-ChildItem -LiteralPath $script:BackupDir -Filter 'exams-*.json' -File).Count
        Check ($count -gt 0 -and $count -le 10) "backup rotation keeps at most 10 files (found $count)"
    }
    finally {
        $script:BackupDir = $oldBackup
    }

    Write-Host ''
    Write-Host 'Legacy data/ migration' -ForegroundColor Cyan
    $oldRoot = $script:WidgetRoot
    $oldDataDir = $script:DataDir
    $oldDataFile = $script:DataFile
    $oldSettingsFile = $script:SettingsFile
    $oldBackupDir = $script:BackupDir
    try {
        $migRoot = Join-Path $tmp 'migrate'
        $migData = Join-Path $migRoot 'data'
        New-Item -ItemType Directory -Path $migRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $migRoot 'exams.json') -Value '{"term":"Legacy","exams":[]}'
        Set-Content -LiteralPath (Join-Path $migRoot 'settings.json') -Value '{"version":1,"layout":{"mode":"anchor","anchor":"top-right","margin":18,"monitor":"","relX":0.5,"relY":0.5,"scale":1,"locked":true}}'
        $script:WidgetRoot = $migRoot
        $script:DataDir = $migData
        $script:DataFile = Join-Path $migData 'exams.json'
        $script:SettingsFile = Join-Path $migData 'settings.json'
        $script:BackupDir = Join-Path $migData 'backups'
        Initialize-DataStorage
        Check (Test-Path -LiteralPath $script:DataFile) 'legacy exams.json moved into data/'
        Check (Test-Path -LiteralPath $script:SettingsFile) 'legacy settings.json moved into data/'
        Check (-not (Test-Path -LiteralPath (Join-Path $migRoot 'exams.json'))) 'legacy exams.json removed from the root'
        Initialize-DataStorage
        Check (Test-Path -LiteralPath $script:DataFile) 'migration is idempotent'
    }
    finally {
        $script:WidgetRoot = $oldRoot
        $script:DataDir = $oldDataDir
        $script:DataFile = $oldDataFile
        $script:SettingsFile = $oldSettingsFile
        $script:BackupDir = $oldBackupDir
    }

    Write-Host ''
    Write-Host 'Live data file (read-only)' -ForegroundColor Cyan
    $livePath = Join-Path $root 'data\exams.json'
    if (Test-Path -LiteralPath $livePath) {
        $live = Read-ExamData -Path $livePath
        Check ($live.Exams.Count -gt 0) "live data loads ($($live.Exams.Count) exams)"
        $bad = @($live.Exams | Where-Object { $_.Date -notmatch '^\d{4}-\d{2}-\d{2}$' -or $_.Time -notmatch '^\d{2}:\d{2}-\d{2}:\d{2}$' })
        Check ($bad.Count -eq 0) 'every live exam has a valid date and time range'
    }
    else {
        Write-Host '  skip: no data/exams.json in this checkout' -ForegroundColor DarkGray
    }
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) check(s)" -ForegroundColor Red
    exit 1
}

Write-Host 'All checks passed.' -ForegroundColor Green
exit 0
