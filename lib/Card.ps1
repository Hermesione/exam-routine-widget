# ---------------------------------------------------------------------------
# Exam Routine - shared card renderer + exam data helpers
#
# Dot-sourced by ExamWidget.ps1 (the desktop widget) and ExamEditor.ps1 (the
# GUI editor) so both draw exactly the same card and read the same JSON file.
# ---------------------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

$script:WidgetRoot = Split-Path -Parent $PSScriptRoot
if (-not $script:WidgetRoot) { $script:WidgetRoot = $PSScriptRoot }
$script:DataDir      = Join-Path $script:WidgetRoot 'data'
$script:DataFile     = Join-Path $script:DataDir 'exams.json'
$script:SettingsFile = Join-Path $script:DataDir 'settings.json'
$script:BackupDir    = Join-Path $script:DataDir 'backups'
$script:EditRequestFile = Join-Path $script:DataDir 'edit-layout.request'
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture
if (-not $script:BrushCache) { $script:BrushCache = @{} }

function Initialize-DataStorage {
    if (-not (Test-Path -LiteralPath $script:DataDir)) {
        New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }

    # One-time migration from the old flat layout (pre data/ folder).
    $legacy = Join-Path $script:WidgetRoot 'exams.json'
    if ((Test-Path -LiteralPath $legacy) -and -not (Test-Path -LiteralPath $script:DataFile)) {
        Move-Item -LiteralPath $legacy -Destination $script:DataFile -Force
    }
    $legacySettings = Join-Path $script:WidgetRoot 'settings.json'
    if ((Test-Path -LiteralPath $legacySettings) -and -not (Test-Path -LiteralPath $script:SettingsFile)) {
        Move-Item -LiteralPath $legacySettings -Destination $script:SettingsFile -Force
    }
}

Initialize-DataStorage


# ---------------------------------------------------------------------------
# THEME  (tuned for a dark / black wallpaper)
# ---------------------------------------------------------------------------
$T = @{
    card        = '#11151A'   # card background
    cardBorder  = '#2A323B'   # 1px outline so the card reads against pure black
    title       = '#F3F7FA'
    sub         = '#8894A3'
    divider     = '#1E242C'
    rowAlt      = '#151A20'
    date        = '#EAEFF5'
    day         = '#6C7784'
    code        = '#F2577C'   # course code accent
    titleText   = '#B6C1CE'
    meta        = '#7B8697'
    nextRow     = '#191016'
    accent      = '#F2577C'
    badgeBg     = '#1A2028'
    badgeFg     = '#96A1AF'
    badgeNextBg = '#3A1B26'
    badgeNextFg = '#FF9FB4'
    todayBg     = '#F2577C'
    todayFg     = '#12070A'
    doneBg      = '#161A20'
    doneFg      = '#4E5865'
    pastText    = '#59636F'
    pastMeta    = '#49525D'
    footer      = '#5A6472'
    pillBg      = '#1D1116'
    pillFg      = '#FF9FB4'
    pillBorder  = '#4A2331'
}

# Light base used for print/export. Accent-dependent keys are derived below.
$T_light = @{
    card        = '#FFFFFF'
    cardBorder  = '#E1E6EE'
    title       = '#11151A'
    sub         = '#5B6675'
    divider     = '#E6EAF1'
    rowAlt      = '#F7F8FA'
    date        = '#11151A'
    day         = '#7A8595'
    code        = '#C2255C'
    titleText   = '#2D3745'
    meta        = '#6B7686'
    nextRow     = '#FDF2F6'
    accent      = '#F2577C'
    badgeBg     = '#F0F2F6'
    badgeFg     = '#5B6675'
    badgeNextBg = '#FBE4EC'
    badgeNextFg = '#A61E4D'
    todayBg     = '#F2577C'
    todayFg     = '#FFFFFF'
    doneBg      = '#F0F2F6'
    doneFg      = '#A6AFBB'
    pastText    = '#9AA4B2'
    pastMeta    = '#A6AFBB'
    footer      = '#8A94A3'
    pillBg      = '#FDF2F6'
    pillFg      = '#A61E4D'
    pillBorder  = '#F3C6D6'
}


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
function Br([string]$hex) {
    if (-not $script:BrushCache.ContainsKey($hex)) {
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $b = New-Object System.Windows.Media.SolidColorBrush $c
        $b.Freeze()
        $script:BrushCache[$hex] = $b
    }
    $script:BrushCache[$hex]
}

function Txt([string]$text, [double]$size, [string]$color, [string]$weight = 'Normal') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    $t.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI'
    $t.FontSize = $size
    if ($weight -eq 'Bold' -or $weight -eq 'SemiBold') {
        $t.FontWeight = [System.Windows.FontWeights]::SemiBold
    }
    $t.Foreground = Br $color
    $t.TextTrimming = 'CharacterEllipsis'
    $t
}

function Pad([double]$l, [double]$t, [double]$r, [double]$b) {
    New-Object System.Windows.Thickness $l, $t, $r, $b
}

# ---------------------------------------------------------------------------
# Colour helpers (accent palette + WCAG contrast protection)
# ---------------------------------------------------------------------------
function Convert-HexColor {
    param([string]$Hex)
    if ([string]::IsNullOrWhiteSpace($Hex)) { return $null }
    $h = $Hex.Trim()
    if ($h.StartsWith('#')) { $h = $h.Substring(1) }
    if ($h -match '^[0-9A-Fa-f]{3}$') {
        $h = [string]$h[0] + [string]$h[0] + [string]$h[1] + [string]$h[1] + [string]$h[2] + [string]$h[2]
    }
    if ($h -match '^[0-9A-Fa-f]{6}$') { return ('#' + $h.ToUpperInvariant()) }
    return $null
}

function Get-ColorLuminance {
    param([string]$Hex)
    $c = Convert-HexColor $Hex
    if (-not $c) { return 0.0 }
    $channels = @()
    for ($i = 1; $i -lt 7; $i += 2) {
        $v = [Convert]::ToInt32($c.Substring($i, 2), 16) / 255.0
        if ($v -le 0.03928) { $v = $v / 12.92 }
        else { $v = [math]::Pow((($v + 0.055) / 1.055), 2.4) }
        $channels += $v
    }
    return (0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2])
}

function Get-ContrastRatio {
    param([string]$A, [string]$B)
    $la = Get-ColorLuminance $A
    $lb = Get-ColorLuminance $B
    if ($la -lt $lb) { $swap = $la; $la = $lb; $lb = $swap }
    return (($la + 0.05) / ($lb + 0.05))
}

function Mix-CardColor {
    param([string]$From, [string]$To, [double]$Amount)
    $a = Convert-HexColor $From
    $b = Convert-HexColor $To
    if (-not $a) { $a = '#000000' }
    if (-not $b) { $b = '#FFFFFF' }
    if ($Amount -lt 0) { $Amount = 0 }
    if ($Amount -gt 1) { $Amount = 1 }
    $out = '#'
    for ($i = 1; $i -lt 7; $i += 2) {
        $av = [Convert]::ToInt32($a.Substring($i, 2), 16)
        $bv = [Convert]::ToInt32($b.Substring($i, 2), 16)
        $v = [int][math]::Round($av + ($bv - $av) * $Amount)
        $out += ('{0:X2}' -f $v)
    }
    return $out
}

# Lighten (or darken) a colour until it clears the minimum contrast ratio
# against a background. The card is dark, so dark accents become pastel.
function Get-ReadableColor {
    param([string]$Color, [string]$Background, [double]$MinRatio = 4.5)
    $c = Convert-HexColor $Color
    $bg = Convert-HexColor $Background
    if (-not $c) { $c = '#F2577C' }
    if (-not $bg) { $bg = '#11151A' }
    if ((Get-ContrastRatio $c $bg) -ge $MinRatio) { return $c }

    $bgLum = Get-ColorLuminance $bg
    $target = if ($bgLum -lt 0.2) { '#FFFFFF' } else { '#000000' }
    $lo = 0.0
    $hi = 1.0
    for ($i = 0; $i -lt 18; $i++) {
        $mid = ($lo + $hi) / 2.0
        $blend = Mix-CardColor $c $target $mid
        if ((Get-ContrastRatio $blend $bg) -ge $MinRatio) { $hi = $mid }
        else { $lo = $mid }
    }
    return (Mix-CardColor $c $target $hi)
}

# Text drawn on top of a solid accent fill: whichever of near-black / white
# has the stronger contrast (always at least ~4.58:1 for any colour).
function Get-TextOnColor {
    param([string]$Background)
    $dark = '#12070A'
    $light = '#FFFFFF'
    if ((Get-ContrastRatio $dark $Background) -ge (Get-ContrastRatio $light $Background)) { return $dark }
    return $light
}

# Everything the card needs for a chosen accent:
#   accent/ink  - chosen colour, nudged just enough to stay visible/readable
#   accentFill  - used for chips, badges and the NEXT stripe (>= 3:1 on the card)
#   accentInk   - used for course-code text (>= 4.5:1 on the card)
#   todayFg     - readable text on the accent fill
function Get-CardPalette {
    param(
        [string]$AccentHex = '#F2577C',
        [string]$Theme = 'dark'
    )

    $base = if ($Theme -eq 'light') { $T_light } else { $T }
    $pal = @{}
    foreach ($k in $base.Keys) { $pal[$k] = $base[$k] }

    $raw = Convert-HexColor $AccentHex
    if (-not $raw) { $raw = '#F2577C' }

    $card = $base.card
    $fill = Get-ReadableColor $raw $card 3.0
    $ink = Get-ReadableColor $raw $card 4.5
    $onFill = Get-TextOnColor $fill

    $pillBg = Mix-CardColor $card $fill 0.14
    $badgeNextBg = Mix-CardColor $card $fill 0.26

    $pal.theme = $Theme
    $pal.rawAccent = $raw
    $pal.accentFill = $fill
    $pal.accentInk = $ink
    $pal.accent = $fill
    $pal.code = $ink
    $pal.nextRow = Mix-CardColor $card $fill 0.10
    $pal.pillBg = $pillBg
    $pal.pillBorder = Mix-CardColor $card $fill 0.45
    $pal['pillFg'] = Get-ReadableColor $ink $pillBg 4.5
    $pal.badgeNextBg = $badgeNextBg
    $pal.badgeNextFg = Get-ReadableColor $ink $badgeNextBg 4.5
    $pal.todayBg = $fill
    $pal.todayFg = $onFill
    return $pal
}

# ---------------------------------------------------------------------------
# Date / time helpers
# ---------------------------------------------------------------------------
function Get-DateValue {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $trimmed = $Text.Trim()
    $formats = [string[]]@('yyyy-MM-dd', 'd/M/yyyy', 'd-M-yyyy', 'd.M.yyyy', 'yyyy/MM/dd')
    $parsed = [datetime]::MinValue
    try {
        if ([datetime]::TryParseExact($trimmed, $formats, $script:Invariant,
                [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed.Date
        }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($trimmed, $script:Invariant,
                [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed.Date
        }
    }
    catch { }
    return $null
}

function Get-TimeSpanValue {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(\d{1,2})\s*:\s*(\d{2})')
    if (-not $m.Success) { return $null }
    $h = [int]$m.Groups[1].Value
    $mi = [int]$m.Groups[2].Value
    if ($h -gt 23 -or $mi -gt 59) { return $null }
    return (New-Object System.TimeSpan -ArgumentList $h, $mi, 0)
}

# Sort key: date + start time
function Get-ExamDateValue {
    param($Exam)
    if ($null -eq $Exam) { return [datetime]::MaxValue }
    $d = Get-DateValue ([string]$Exam.Date)
    if ($null -eq $d) { return [datetime]::MaxValue }
    $start = Get-TimeSpanValue ([string]$Exam.Time)
    if ($null -ne $start) { return $d.Add($start) }
    return $d
}

# When is the exam over? Exact end time when known, otherwise end of that day.
function Get-ExamEndValue {
    param($Exam)
    if ($null -eq $Exam) { return $null }
    $d = Get-DateValue ([string]$Exam.Date)
    if ($null -eq $d) { return $null }

    $parts = @([string]$Exam.Time -split '\s*[-\u2013\u2014]\s*' | Where-Object { $_ -ne '' })
    $start = $null
    $end = $null
    if ($parts.Count -ge 1) { $start = Get-TimeSpanValue $parts[0] }
    if ($parts.Count -ge 2) { $end = Get-TimeSpanValue $parts[1] }

    if ($null -eq $end) { return $d.AddDays(1) }   # unknown end -> keep for the day

    $endDate = $d.Add($end)
    if ($null -ne $start -and $endDate -lt $d.Add($start)) {
        $endDate = $endDate.AddDays(1)             # past-midnight exam
    }
    return $endDate
}

function Test-ExamDone {
    param($Exam, [datetime]$Now = (Get-Date))
    $end = Get-ExamEndValue $Exam
    if ($null -eq $end) { return $false }
    return ($end -le $Now)
}

function Sort-ExamList {
    param([object[]]$ExamList)
    if ($null -eq $ExamList -or $ExamList.Count -eq 0) { return @() }
    @($ExamList | Where-Object { $null -ne $_ } | Sort-Object -Property `
            @{ Expression = { Get-ExamDateValue $_ } }, `
            @{ Expression = { [string]$_.Code } })
}

# Exams that are still upcoming or currently in progress.
function Select-UpcomingExams {
    param([object[]]$ExamList, [datetime]$Now = (Get-Date))
    $keep = @()
    foreach ($e in @($ExamList)) {
        if ($null -eq $e) { continue }
        if (-not (Test-ExamDone $e $Now)) { $keep += $e }
    }
    @(Sort-ExamList $keep)
}

# ---------------------------------------------------------------------------
# exams.json
# ---------------------------------------------------------------------------
function Get-JsonField {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($prop) { return $prop.Value }
    return $null
}

function ConvertTo-Exam {
    param($Raw)
    if ($null -eq $Raw) { return $null }
    $d = Get-DateValue ([string](Get-JsonField $Raw 'date'))
    if ($null -eq $d) { return $null }
    [pscustomobject]@{
        Date    = $d.ToString('yyyy-MM-dd')
        Time    = ([string](Get-JsonField $Raw 'time')).Trim()
        Code    = ([string](Get-JsonField $Raw 'code')).Trim()
        Title   = ([string](Get-JsonField $Raw 'title')).Trim()
        Section = ([string](Get-JsonField $Raw 'section')).Trim()
        Room    = ([string](Get-JsonField $Raw 'room')).Trim()
        CRN     = ([string](Get-JsonField $Raw 'crn')).Trim()
    }
}

function Read-ExamData {
    param([string]$Path = $script:DataFile)
    $empty = [pscustomobject]@{
        Term = ''; TermCode = ''; Accent = '#F2577C'
        Title = 'Final Exam Routine'; Footer = 'times are local'
        Exams = @()
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $empty }

    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($text)) { return $empty }
        $raw = $text | ConvertFrom-Json
    }
    catch {
        return $empty
    }

    $list = New-Object System.Collections.ArrayList
    foreach ($item in @(Get-JsonField $raw 'exams')) {
        $exam = ConvertTo-Exam $item
        if ($null -ne $exam) { [void]$list.Add($exam) }
    }

    $accent = Convert-HexColor ([string](Get-JsonField $raw 'accent'))
    if (-not $accent) { $accent = '#F2577C' }

    $titleRaw = Get-JsonField $raw 'title'
    $title = if ($null -eq $titleRaw) { 'Final Exam Routine' } else { ([string]$titleRaw).Trim() }
    if ([string]::IsNullOrWhiteSpace($title)) { $title = 'Final Exam Routine' }

    $footerRaw = Get-JsonField $raw 'footer'
    $footer = if ($null -eq $footerRaw) { 'times are local' } else { ([string]$footerRaw).Trim() }

    [pscustomobject]@{
        Term     = ([string](Get-JsonField $raw 'term')).Trim()
        TermCode = ([string](Get-JsonField $raw 'termCode')).Trim()
        Accent   = $accent
        Title    = $title
        Footer   = $footer
        Exams    = @(Sort-ExamList $list.ToArray())
    }
}

function Backup-ExamData {
    param([string]$Path = $script:DataFile)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }
    try {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        Copy-Item -LiteralPath $Path -Destination (Join-Path $script:BackupDir "exams-$stamp.json") -Force
        Get-ChildItem -LiteralPath $script:BackupDir -Filter 'exams-*.json' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 10 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch { }
}

function Write-ExamData {
    param(
        [string]$Term = '',
        [string]$TermCode = '',
        [string]$Accent = '#F2577C',
        [string]$Title = 'Final Exam Routine',
        [string]$Footer = 'times are local',
        [object[]]$ExamList = @(),
        [string]$Path = $script:DataFile
    )

    $accentColor = Convert-HexColor $Accent
    if (-not $accentColor) { $accentColor = '#F2577C' }
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = 'Final Exam Routine' }

    if ($Path -eq $script:DataFile) { Backup-ExamData -Path $Path }

    $ordered = @(Sort-ExamList @($ExamList))
    $lines = New-Object System.Collections.ArrayList

    [void]$lines.Add('{')
    [void]$lines.Add('  "term": ' + (ConvertTo-Json -InputObject ([string]$Term) -Compress) + ',')
    [void]$lines.Add('  "termCode": ' + (ConvertTo-Json -InputObject ([string]$TermCode) -Compress) + ',')
    [void]$lines.Add('  "accent": ' + (ConvertTo-Json -InputObject $accentColor -Compress) + ',')
    [void]$lines.Add('  "title": ' + (ConvertTo-Json -InputObject ([string]$Title) -Compress) + ',')
    [void]$lines.Add('  "footer": ' + (ConvertTo-Json -InputObject ([string]$Footer) -Compress) + ',')

    if ($ordered.Count -eq 0) {
        [void]$lines.Add('  "exams": []')
    }
    else {
        [void]$lines.Add('  "exams": [')
        for ($i = 0; $i -lt $ordered.Count; $i++) {
            $e = $ordered[$i]
            $entry = [ordered]@{
                date    = [string]$e.Date
                time    = [string]$e.Time
                code    = [string]$e.Code
                title   = [string]$e.Title
                section = [string]$e.Section
                room    = [string]$e.Room
                crn     = [string]$e.CRN
            }
            $compact = ConvertTo-Json -InputObject $entry -Compress
            $suffix = if ($i -lt ($ordered.Count - 1)) { ',' } else { '' }
            [void]$lines.Add('    ' + $compact + $suffix)
        }
        [void]$lines.Add('  ]')
    }
    [void]$lines.Add('}')

    $json = ($lines -join "`r`n") + "`r`n"
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ---------------------------------------------------------------------------
# Build the card
# ---------------------------------------------------------------------------
function Build-Card {
    param(
        [object[]]$ExamList = @(),
        [string]$TermText = '',
        [string]$TermCodeText = '',
        [double]$CardWidth = 440,
        [string]$Accent = '#F2577C',
        [string]$TitleText = 'Final Exam Routine',
        [string]$FooterText = 'times are local',
        [string]$Theme = 'dark'
    )

    if ([string]::IsNullOrWhiteSpace($TitleText)) { $TitleText = 'Final Exam Routine' }

    # From here on $T is this card's palette: the base theme plus the
    # accent-derived colours (all contrast-checked).
    $T = Get-CardPalette -AccentHex $Accent -Theme $Theme
    $script:ActivePalette = $T
    $script:ActiveTheme = $Theme

    if ($null -eq $ExamList) { $ExamList = @() }
    else { $ExamList = @($ExamList | Where-Object { $null -ne $_ }) }

    $script:BadgeRefs = New-Object System.Collections.ArrayList

    $stack = New-Object System.Windows.Controls.StackPanel

    # ---------------- header ----------------
    $hdr = New-Object System.Windows.Controls.Grid
    $hdr.Margin = Pad 18 16 18 14

    $hc1 = New-Object System.Windows.Controls.ColumnDefinition
    $hc1.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $hc2 = New-Object System.Windows.Controls.ColumnDefinition
    $hc2.Width = [System.Windows.GridLength]::Auto
    [void]$hdr.ColumnDefinitions.Add($hc1)
    [void]$hdr.ColumnDefinitions.Add($hc2)

    $hl = New-Object System.Windows.Controls.StackPanel
    $title = Txt $TitleText 19 $T.title 'SemiBold'
    $subText = (@($TermText, $TermCodeText) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '  |  '
    $sub = Txt $subText 11.5 $T.sub
    $sub.Margin = Pad 0 3 0 0
    [void]$hl.Children.Add($title)
    [void]$hl.Children.Add($sub)
    [System.Windows.Controls.Grid]::SetColumn($hl, 0)
    [void]$hdr.Children.Add($hl)

    switch ($ExamList.Count) {
        0 { $pillText = 'NO EXAMS' }
        1 { $pillText = '1 EXAM' }
        default { $pillText = "$($ExamList.Count) EXAMS" }
    }

    $pill = New-Object System.Windows.Controls.Border
    $pill.Background = Br $T.pillBg
    $pill.BorderBrush = Br $T.pillBorder
    $pill.BorderThickness = New-Object System.Windows.Thickness 1
    $pill.CornerRadius = New-Object System.Windows.CornerRadius 99
    $pill.Padding = Pad 11 4 11 4
    $pill.VerticalAlignment = 'Center'
    $pill.Child = (Txt $pillText 10.5 $T.pillFg 'SemiBold')
    [System.Windows.Controls.Grid]::SetColumn($pill, 1)
    [void]$hdr.Children.Add($pill)

    [void]$stack.Children.Add($hdr)

    $rule = New-Object System.Windows.Controls.Border
    $rule.Height = 1
    $rule.Background = Br $T.divider
    [void]$stack.Children.Add($rule)

    # ---------------- rows ----------------
    $today = (Get-Date).Date
    $nextExam = $null
    foreach ($e in $ExamList) {
        $eDate = Get-DateValue ([string]$e.Date)
        if ($null -ne $eDate -and $eDate -ge $today) { $nextExam = $e; break }
    }

    if ($ExamList.Count -eq 0) {
        # Nothing left in the schedule - keep the card friendly instead of empty.
        $emptyWrap = New-Object System.Windows.Controls.Border
        $emptyWrap.Padding = Pad 18 24 18 26
        $emptyInner = New-Object System.Windows.Controls.StackPanel
        $emptyInner.HorizontalAlignment = 'Center'
        $e1 = Txt 'No upcoming exams' 13 $T.titleText 'SemiBold'
        $e1.HorizontalAlignment = 'Center'
        $e1.TextAlignment = 'Center'
        $e2 = Txt 'Add exams from the Exam Routine Editor.' 10.5 $T.meta
        $e2.HorizontalAlignment = 'Center'
        $e2.TextAlignment = 'Center'
        $e2.Margin = Pad 0 5 0 0
        [void]$emptyInner.Children.Add($e1)
        [void]$emptyInner.Children.Add($e2)
        $emptyWrap.Child = $emptyInner
        [void]$stack.Children.Add($emptyWrap)
    }

    $i = 0
    foreach ($e in $ExamList) {
        $d = Get-DateValue ([string]$e.Date)
        if ($null -eq $d) { $d = (Get-Date).Date }
        $isNext = ($null -ne $nextExam) -and ($e -eq $nextExam)
        $isPast = $d -lt $today

        $row = New-Object System.Windows.Controls.Grid
        $row.Background = if ($isNext) { Br $T.nextRow } elseif ($i % 2 -eq 1) { Br $T.rowAlt } else { Br $T.card }

        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength 3
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
        foreach ($c in @($c0, $c1, $c2, $c3)) { [void]$row.ColumnDefinitions.Add($c) }

        $stripe = New-Object System.Windows.Controls.Border
        $stripe.Background = if ($isNext) { Br $T.accent } else { Br 'Transparent' }
        [System.Windows.Controls.Grid]::SetColumn($stripe, 0)
        [void]$row.Children.Add($stripe)

        # date block
        $dateCol = New-Object System.Windows.Controls.StackPanel
        $dateCol.Margin = Pad 14 11 10 11
        $dateCol.Width = 86
        $dateCol.VerticalAlignment = 'Center'
        $dt = Txt $d.ToString('d/M/yyyy') 13.5 ($(if ($isPast) { $T.pastText } else { $T.date })) 'SemiBold'
        $dy = Txt $d.ToString('dddd').ToUpper() 9.5 $T.day
        $dy.Margin = Pad 0 2 0 0
        [void]$dateCol.Children.Add($dt)
        [void]$dateCol.Children.Add($dy)
        [System.Windows.Controls.Grid]::SetColumn($dateCol, 1)
        [void]$row.Children.Add($dateCol)

        # course block
        $mid = New-Object System.Windows.Controls.StackPanel
        $mid.Margin = Pad 0 10 8 10
        $mid.VerticalAlignment = 'Center'

        $line1 = New-Object System.Windows.Controls.StackPanel
        $line1.Orientation = 'Horizontal'
        [void]$line1.Children.Add((Txt $e.Code 12.5 ($(if ($isPast) { $T.pastText } else { $T.code })) 'SemiBold'))
        if ($isNext) {
            $chip = New-Object System.Windows.Controls.Border
            $chip.Background = Br $T.accent
            $chip.CornerRadius = New-Object System.Windows.CornerRadius 4
            $chip.Padding = Pad 5 1 5 2
            $chip.Margin = Pad 7 1 0 0
            $chip.VerticalAlignment = 'Center'
            $chip.Child = (Txt 'NEXT' 8.5 $T.todayFg 'SemiBold')
            [void]$line1.Children.Add($chip)
        }
        [void]$mid.Children.Add($line1)

        $titleTxt = Txt $e.Title 11.5 ($(if ($isPast) { $T.pastText } else { $T.titleText }))
        $titleTxt.Margin = Pad 0 2 0 0
        $titleTxt.ToolTip = "$($e.Title)  |  Section $($e.Section)  |  CRN $($e.CRN)"
        [void]$mid.Children.Add($titleTxt)

        $metaTxt = Txt ("{0}   |   {1}   |   {2}" -f $e.Time, $e.Section, $e.Room) 10.5 ($(if ($isPast) { $T.pastMeta } else { $T.meta }))
        $metaTxt.Margin = Pad 0 3 0 0
        [void]$mid.Children.Add($metaTxt)

        [System.Windows.Controls.Grid]::SetColumn($mid, 2)
        [void]$row.Children.Add($mid)

        # countdown badge
        $badge = New-Object System.Windows.Controls.Border
        $badge.CornerRadius = New-Object System.Windows.CornerRadius 99
        $badge.Padding = Pad 9 4 9 4
        $badge.HorizontalAlignment = 'Right'
        $badge.VerticalAlignment = 'Center'
        $badge.Margin = Pad 0 0 14 0
        $badge.MinWidth = 58
        $badgeTxt = Txt '' 10.5 $T.badgeFg 'SemiBold'
        $badgeTxt.TextAlignment = 'Center'
        $badge.Child = $badgeTxt
        [void]$script:BadgeRefs.Add([pscustomobject]@{ Border = $badge; Text = $badgeTxt; Date = $d; IsNext = $isNext })
        [System.Windows.Controls.Grid]::SetColumn($badge, 3)
        [void]$row.Children.Add($badge)

        $wrap = New-Object System.Windows.Controls.Border
        $wrap.BorderBrush = Br $T.divider
        $wrap.BorderThickness = New-Object System.Windows.Thickness 0, 0, 0, 1
        $wrap.Child = $row
        [void]$stack.Children.Add($wrap)

        $i++
    }

    # ---------------- footer ----------------
    $foot = New-Object System.Windows.Controls.Grid
    $foot.Margin = Pad 18 11 18 13

    $fc1 = New-Object System.Windows.Controls.ColumnDefinition
    $fc1.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $fc2 = New-Object System.Windows.Controls.ColumnDefinition
    $fc2.Width = [System.Windows.GridLength]::Auto
    [void]$foot.ColumnDefinitions.Add($fc1)
    [void]$foot.ColumnDefinitions.Add($fc2)

    $footLeft = Txt $FooterText 9.5 $T.footer
    $footLeft.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($footLeft, 0)
    [void]$foot.Children.Add($footLeft)

    $script:UpdatedTxt = Txt '' 9.5 $T.footer
    $script:UpdatedTxt.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($script:UpdatedTxt, 1)
    [void]$foot.Children.Add($script:UpdatedTxt)

    [void]$stack.Children.Add($foot)

    # ---------------- card shell ----------------
    $card = New-Object System.Windows.Controls.Border
    $card.Width = $CardWidth
    $card.CornerRadius = New-Object System.Windows.CornerRadius 14
    $card.Background = Br $T.card
    $card.BorderBrush = Br $T.cardBorder
    $card.BorderThickness = New-Object System.Windows.Thickness 1
    $card.Child = $stack

    Update-Countdowns
    $card
}

function Update-Countdowns {
    if (-not $script:ActivePalette) { $script:ActivePalette = Get-CardPalette '#F2577C' }
    $T = $script:ActivePalette
    $today = (Get-Date).Date
    foreach ($b in $script:BadgeRefs) {
        $days = ($b.Date.Date - $today).Days
        if ($days -lt 0) {
            $b.Text.Text  = 'done'
            $b.Border.Background = Br $T.doneBg
            $b.Text.Foreground   = Br $T.doneFg
        }
        elseif ($days -eq 0) {
            $b.Text.Text  = 'TODAY'
            $b.Border.Background = Br $T.todayBg
            $b.Text.Foreground   = Br $T.todayFg
        }
        elseif ($days -eq 1) {
            $b.Text.Text  = '1 day'
            $b.Border.Background = Br $T.badgeNextBg
            $b.Text.Foreground   = Br $T.badgeNextFg
        }
        else {
            $b.Text.Text  = "$days days"
            if ($b.IsNext) {
                $b.Border.Background = Br $T.badgeNextBg
                $b.Text.Foreground   = Br $T.badgeNextFg
            } else {
                $b.Border.Background = Br $T.badgeBg
                $b.Text.Foreground   = Br $T.badgeFg
            }
        }
    }
    if ($script:UpdatedTxt) {
        $script:UpdatedTxt.Text = 'as of ' + (Get-Date).ToString('d MMM')
    }
}
