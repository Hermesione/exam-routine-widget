# ---------------------------------------------------------------------------
# Exam Routine - layout settings, monitor math and per-user shell helpers
# ---------------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:LayoutScaleMin = 0.7
$script:LayoutScaleMax = 1.5
$script:LayoutAnchors = @(
    'top-left', 'top-center', 'top-right',
    'middle-left', 'center', 'middle-right',
    'bottom-left', 'bottom-center', 'bottom-right'
)
$script:LayoutSizePresets = [ordered]@{
    Compact  = 0.8
    Standard = 1.0
    Large    = 1.2
}

function Get-AppVersion {
    $path = Join-Path $script:WidgetRoot 'version.txt'
    if (Test-Path -LiteralPath $path) {
        return ((Get-Content -Raw -LiteralPath $path).Trim())
    }
    return '1.0.0'
}

function Get-DefaultLayout {
    [pscustomobject]@{
        Mode    = 'anchor'
        Anchor  = 'top-right'
        Margin  = 18
        Monitor = ''
        RelX    = 0.5
        RelY    = 0.5
        Scale   = 1.0
        Locked  = $true
    }
}

function Get-DefaultSettings {
    [pscustomobject]@{
        Version = 1
        Layout  = Get-DefaultLayout
    }
}

function Get-ClampedScale {
    param([double]$Scale)
    if ($Scale -lt $script:LayoutScaleMin) { return $script:LayoutScaleMin }
    if ($Scale -gt $script:LayoutScaleMax) { return $script:LayoutScaleMax }
    return $Scale
}

function Read-Settings {
    param([string]$Path = $script:SettingsFile)
    $default = Get-DefaultSettings
    if (-not (Test-Path -LiteralPath $Path)) { return $default }

    try {
        $raw = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
        $layout = Get-JsonField $raw 'layout'
        if ($null -eq $layout) { return $default }

        $mode = ([string](Get-JsonField $layout 'mode')).ToLowerInvariant()
        if ($mode -ne 'custom') { $mode = 'anchor' }

        $anchor = ([string](Get-JsonField $layout 'anchor')).ToLowerInvariant()
        if ($script:LayoutAnchors -notcontains $anchor) { $anchor = 'top-right' }

        $margin = 18.0
        $marginValue = Get-JsonField $layout 'margin'
        if ($null -ne $marginValue) {
            $parsed = 0.0
            if ([double]::TryParse([string]$marginValue, [ref]$parsed)) { $margin = $parsed }
            if ($margin -lt 0) { $margin = 0 }
            if ($margin -gt 300) { $margin = 300 }
        }

        $scale = 1.0
        $scaleValue = Get-JsonField $layout 'scale'
        if ($null -ne $scaleValue) {
            $parsed = 0.0
            if ([double]::TryParse([string]$scaleValue, [ref]$parsed)) { $scale = $parsed }
        }
        $scale = Get-ClampedScale $scale

        $relX = 0.5
        $relY = 0.5
        try {
            $relXValue = Get-JsonField $layout 'relX'
            if ($null -ne $relXValue) { $relX = [double]$relXValue }
            $relYValue = Get-JsonField $layout 'relY'
            if ($null -ne $relYValue) { $relY = [double]$relYValue }
        }
        catch { }
        if ($relX -lt 0) { $relX = 0 }
        if ($relX -gt 1) { $relX = 1 }
        if ($relY -lt 0) { $relY = 0 }
        if ($relY -gt 1) { $relY = 1 }

        $lockedValue = Get-JsonField $layout 'locked'
        $locked = $true
        if ($null -ne $lockedValue) { $locked = [bool]$lockedValue }

        return [pscustomobject]@{
            Version = 1
            Layout  = [pscustomobject]@{
                Mode    = $mode
                Anchor  = $anchor
                Margin  = $margin
                Monitor = ([string](Get-JsonField $layout 'monitor'))
                RelX    = $relX
                RelY    = $relY
                Scale   = $scale
                Locked  = $locked
            }
        }
    }
    catch {
        return $default
    }
}

function Write-Settings {
    param(
        [object]$Settings,
        [string]$Path = $script:SettingsFile
    )
    if ($null -eq $Settings) { $Settings = Get-DefaultSettings }
    $layout = $Settings.Layout

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('{')
    [void]$lines.Add('  "version": 1,')
    [void]$lines.Add('  "layout": {')
    [void]$lines.Add('    "mode": ' + (ConvertTo-Json -InputObject ([string]$layout.Mode) -Compress) + ',')
    [void]$lines.Add('    "anchor": ' + (ConvertTo-Json -InputObject ([string]$layout.Anchor) -Compress) + ',')
    [void]$lines.Add('    "margin": ' + ([double]$layout.Margin).ToString([System.Globalization.CultureInfo]::InvariantCulture) + ',')
    [void]$lines.Add('    "monitor": ' + (ConvertTo-Json -InputObject ([string]$layout.Monitor) -Compress) + ',')
    [void]$lines.Add('    "relX": ' + ([double]$layout.RelX).ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture) + ',')
    [void]$lines.Add('    "relY": ' + ([double]$layout.RelY).ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture) + ',')
    [void]$lines.Add('    "scale": ' + ([double]$layout.Scale).ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture) + ',')
    [void]$lines.Add('    "locked": ' + $(if ($layout.Locked) { 'true' } else { 'false' }))
    [void]$lines.Add('  }')
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
# Screens / DPI
# ---------------------------------------------------------------------------

# System DPI scale: physical pixels per WPF DIP. 1.0 at 100%, 1.5 at 150%.
function Get-SystemDpiScale {
    try {
        $physical = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
        $logical = [System.Windows.SystemParameters]::PrimaryScreenWidth
        if ($physical -gt 0 -and $logical -gt 0) { return ($physical / $logical) }
    }
    catch { }
    return 1.0
}

function Get-ScreenList {
    $dpi = Get-SystemDpiScale
    $list = @()
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $b = $screen.Bounds
        $w = $screen.WorkingArea
        $list += [pscustomobject]@{
            DeviceName  = $screen.DeviceName
            Primary     = $screen.Primary
            Bounds      = $b
            WorkPx      = $w
            WorkLeft    = ($w.Left / $dpi)
            WorkTop     = ($w.Top / $dpi)
            WorkWidth   = ($w.Width / $dpi)
            WorkHeight  = ($w.Height / $dpi)
            DpiScale    = $dpi
        }
    }
    return @($list)
}

function Get-ScreenSignature {
    $parts = @()
    foreach ($s in Get-ScreenList) {
        $parts += ('{0}:{1},{2},{3},{4}' -f $s.DeviceName, $s.WorkPx.Left, $s.WorkPx.Top, $s.WorkPx.Width, $s.WorkPx.Height)
    }
    return ($parts -join '|')
}

function Get-FileStamp {
    param([string]$Path)
    try {
        $f = Get-Item -LiteralPath $Path -ErrorAction Stop
        return "$($f.LastWriteTimeUtc.Ticks):$($f.Length)"
    }
    catch {
        return ''
    }
}

function Find-ScreenAtPoint {
    param(
        [object[]]$Screens,
        [double]$X,
        [double]$Y
    )
    foreach ($s in $Screens) {
        if ($X -ge $s.WorkLeft -and $X -lt ($s.WorkLeft + $s.WorkWidth) -and
            $Y -ge $s.WorkTop -and $Y -lt ($s.WorkTop + $s.WorkHeight)) {
            return $s
        }
    }
    return (Find-Screen -Screens $Screens -PreferPrimary)
}

function Find-Screen {
    param(
        [object[]]$Screens,
        [string]$DeviceName,
        [switch]$PreferPrimary
    )
    if ($null -eq $Screens -or $Screens.Count -eq 0) { return $null }
    if ($DeviceName) {
        $match = $Screens | Where-Object { $_.DeviceName -eq $DeviceName } | Select-Object -First 1
        if ($match) { return $match }
    }
    if ($PreferPrimary) {
        $match = $Screens | Where-Object { $_.Primary } | Select-Object -First 1
        if ($match) { return $match }
    }
    return ($Screens | Select-Object -First 1)
}

# ---------------------------------------------------------------------------
# Layout math (all coordinates are WPF DIPs)
# ---------------------------------------------------------------------------
function Get-AnchorPosition {
    param(
        [double]$WorkLeft,
        [double]$WorkTop,
        [double]$WorkWidth,
        [double]$WorkHeight,
        [double]$CardWidth,
        [double]$CardHeight,
        [string]$Anchor,
        [double]$Margin
    )

    $right = $WorkLeft + $WorkWidth
    $bottom = $WorkTop + $WorkHeight
    $availX = [math]::Max(0.0, $WorkWidth - $CardWidth)
    $availY = [math]::Max(0.0, $WorkHeight - $CardHeight)

    $x = $WorkLeft + $Margin
    $y = $WorkTop + $Margin

    switch ($Anchor) {
        'top-left'     { $x = $WorkLeft + $Margin; $y = $WorkTop + $Margin }
        'top-center'   { $x = $WorkLeft + $availX / 2; $y = $WorkTop + $Margin }
        'top-right'    { $x = $right - $CardWidth - $Margin; $y = $WorkTop + $Margin }
        'middle-left'  { $x = $WorkLeft + $Margin; $y = $WorkTop + $availY / 2 }
        'center'       { $x = $WorkLeft + $availX / 2; $y = $WorkTop + $availY / 2 }
        'middle-right' { $x = $right - $CardWidth - $Margin; $y = $WorkTop + $availY / 2 }
        'bottom-left'  { $x = $WorkLeft + $Margin; $y = $bottom - $CardHeight - $Margin }
        'bottom-center'{ $x = $WorkLeft + $availX / 2; $y = $bottom - $CardHeight - $Margin }
        'bottom-right' { $x = $right - $CardWidth - $Margin; $y = $bottom - $CardHeight - $Margin }
    }

    if ($x -lt $WorkLeft) { $x = $WorkLeft }
    if ($y -lt $WorkTop) { $y = $WorkTop }
    if (($x + $CardWidth) -gt $right) { $x = [math]::Max($WorkLeft, $right - $CardWidth) }
    if (($y + $CardHeight) -gt $bottom) { $y = [math]::Max($WorkTop, $bottom - $CardHeight) }

    return [pscustomobject]@{ X = $x; Y = $y }
}

function Get-CustomPosition {
    param(
        [double]$WorkLeft,
        [double]$WorkTop,
        [double]$WorkWidth,
        [double]$WorkHeight,
        [double]$CardWidth,
        [double]$CardHeight,
        [double]$RelX,
        [double]$RelY
    )
    $availX = [math]::Max(0.0, $WorkWidth - $CardWidth)
    $availY = [math]::Max(0.0, $WorkHeight - $CardHeight)
    $x = $WorkLeft + $availX * [math]::Max(0.0, [math]::Min(1.0, $RelX))
    $y = $WorkTop + $availY * [math]::Max(0.0, [math]::Min(1.0, $RelY))
    return [pscustomobject]@{ X = $x; Y = $y }
}

function Find-NearestAnchor {
    param(
        [double]$WorkLeft,
        [double]$WorkTop,
        [double]$WorkWidth,
        [double]$WorkHeight,
        [double]$CardWidth,
        [double]$CardHeight,
        [double]$X,
        [double]$Y,
        [double]$Margin,
        [double]$Tolerance = 26
    )
    $best = $null
    $bestDist = [double]::MaxValue
    foreach ($anchor in $script:LayoutAnchors) {
        $p = Get-AnchorPosition -WorkLeft $WorkLeft -WorkTop $WorkTop -WorkWidth $WorkWidth `
            -WorkHeight $WorkHeight -CardWidth $CardWidth -CardHeight $CardHeight `
            -Anchor $anchor -Margin $Margin
        $d = [math]::Sqrt([math]::Pow($p.X - $X, 2) + [math]::Pow($p.Y - $Y, 2))
        if ($d -lt $bestDist) { $bestDist = $d; $best = $anchor }
    }
    if ($bestDist -le $Tolerance) { return $best }
    return $null
}

function Get-LayoutPositionForSettings {
    param(
        [object]$Layout,
        [object[]]$Screens,
        [double]$CardWidth,
        [double]$CardHeight
    )
    $screen = Find-Screen -Screens $Screens -DeviceName $Layout.Monitor -PreferPrimary
    if ($null -eq $screen) {
        $screen = [pscustomobject]@{
            DeviceName = ''
            WorkLeft = 0; WorkTop = 0
            WorkWidth = [System.Windows.SystemParameters]::PrimaryScreenWidth
            WorkHeight = [System.Windows.SystemParameters]::PrimaryScreenHeight
        }
    }

    if ($Layout.Mode -eq 'custom') {
        $p = Get-CustomPosition -WorkLeft $screen.WorkLeft -WorkTop $screen.WorkTop `
            -WorkWidth $screen.WorkWidth -WorkHeight $screen.WorkHeight `
            -CardWidth $CardWidth -CardHeight $CardHeight `
            -RelX $Layout.RelX -RelY $Layout.RelY
    }
    else {
        $p = Get-AnchorPosition -WorkLeft $screen.WorkLeft -WorkTop $screen.WorkTop `
            -WorkWidth $screen.WorkWidth -WorkHeight $screen.WorkHeight `
            -CardWidth $CardWidth -CardHeight $CardHeight `
            -Anchor $Layout.Anchor -Margin $Layout.Margin
    }
    return [pscustomobject]@{ X = $p.X; Y = $p.Y; Screen = $screen }
}

# ---------------------------------------------------------------------------
# Autostart (per-user Startup shortcut, no admin)
# ---------------------------------------------------------------------------
function Get-StartupShortcutPath {
    $startup = [Environment]::GetFolderPath('Startup')
    return (Join-Path $startup 'Exam Routine Widget.lnk')
}

function Test-Autostart {
    return (Test-Path -LiteralPath (Get-StartupShortcutPath))
}

function Set-Autostart {
    param([bool]$Enabled)
    $lnk = Get-StartupShortcutPath
    if ($Enabled) {
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $sc.Arguments = '"' + (Join-Path $script:WidgetRoot 'Start Exam Widget.vbs') + '"'
        $sc.WorkingDirectory = $script:WidgetRoot
        $ico = Join-Path $script:WidgetRoot 'assets\exam.ico'
        if (Test-Path -LiteralPath $ico) { $sc.IconLocation = "$ico,0" }
        $sc.Description = 'Exam Routine Widget'
        $sc.Save()
    }
    else {
        if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
    }
}
