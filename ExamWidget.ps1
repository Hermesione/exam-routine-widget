# Exam Routine desktop widget (Windows 10/11)
# Visible on the desktop (including after Win+D), never covers apps, never steals clicks.
# Exam data and layout live in .\data\ - use "Edit Exam Routine.vbs" to manage them.

param(
    [string]$SnapPath,                       # render the card to a PNG and exit
    [ValidateSet('dark', 'light')]
    [string]$Theme = 'dark',
    [switch]$DebugLog
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

$script:LogPath = Join-Path $PSScriptRoot 'widget.log'

function Add-WidgetLog {
    param([string]$Message)
    if (-not $DebugLog) { return }
    try { "$(Get-Date -Format 'HH:mm:ss.fff') $Message" | Add-Content -LiteralPath $script:LogPath } catch { }
}

# single instance guard (snapshot renders never take it)
if (-not $SnapPath) {
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Local\ExamRoutineWidget')
    $owned = $false
    try { $owned = $script:Mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { return }
}

# shared theme, card renderer, data helpers, layout settings
. (Join-Path $PSScriptRoot 'lib\Card.ps1')
. (Join-Path $PSScriptRoot 'lib\Layout.ps1')

$script:WidthBase = 440
$script:Editing = $false
$script:Quitting = $false
$script:Scale = 1.0
$script:Dragging = $false
$script:DragScale = 1.0
$script:DragCursor = $null
$script:DragWinLeft = 0.0
$script:DragWinTop = 0.0
$script:CardHeightDip = 200
$script:LastDay = (Get-Date).Date
$script:ScreenTicks = 0

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------
function Load-Data {
    $seed = Read-ExamData
    $live = @(Select-UpcomingExams $seed.Exams)
    if ($live.Count -ne $seed.Exams.Count) {
        # Persist the cleanup so finished exams are gone from the file too.
        Write-ExamData -Term $seed.Term -TermCode $seed.TermCode -Accent $seed.Accent `
            -Title $seed.Title -Footer $seed.Footer -ExamList $live
        $script:ExamStamp = Get-FileStamp $script:DataFile
    }
    $script:Data = [pscustomobject]@{
        Term     = $seed.Term
        TermCode = $seed.TermCode
        Accent   = $seed.Accent
        Title    = $seed.Title
        Footer   = $seed.Footer
        Exams    = $live
    }
}

Load-Data

# ---------------------------------------------------------------------------
# Snapshot mode
# ---------------------------------------------------------------------------
if ($SnapPath) {
    $card = Build-Card -ExamList $script:Data.Exams -TermText $script:Data.Term `
        -TermCodeText $script:Data.TermCode -CardWidth $script:WidthBase `
        -Accent $script:Data.Accent -TitleText $script:Data.Title -FooterText $script:Data.Footer `
        -Theme $Theme
    $card.Measure([System.Windows.Size]::new($script:WidthBase, [double]::PositiveInfinity))
    $h = $card.DesiredSize.Height
    $card.Arrange([System.Windows.Rect]::new(0, 0, $script:WidthBase, $h))
    $card.UpdateLayout()

    $scale = 2.0
    $rtb = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        [int]($script:WidthBase * $scale), [int]($h * $scale), 96.0 * $scale, 96.0 * $scale,
        [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($card)

    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($SnapPath)
    $enc.Save($fs)
    $fs.Close()
    Write-Output "snapshot: $SnapPath ($($script:WidthBase) x $([math]::Round($h))) theme=$Theme"
    return
}

# ---------------------------------------------------------------------------
# Win32 interop (desktop layering)
# ---------------------------------------------------------------------------
if (-not ('WidgetWin' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class WidgetWin {

public delegate bool EnumProc(IntPtr h, IntPtr l);

[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr rect, IntPtr rgn, uint flags);

[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);

public struct RECT { public int L, T, R, B; }

public static string ClassName(IntPtr h) {
    var sb = new StringBuilder(256);
    GetClassName(h, sb, 256);
    return sb.ToString();
}

public static bool IsCloaked(IntPtr h) {
    int v;
    if (DwmGetWindowAttribute(h, 14, out v, 4) != 0) return false;   // DWMWA_CLOAKED
    return v != 0;
}

public static bool AreaClear(IntPtr ours) {
    RECT t;
    if (!GetWindowRect(ours, out t)) return false;
    bool blocked = false;

    EnumWindows((h, l) => {
        if (h == ours) return true;
        if (!IsWindowVisible(h)) return true;
        if (IsIconic(h)) return true;
        if (IsCloaked(h)) return true;

        string c = ClassName(h);
        if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" ||
            c == "Shell_SecondaryTrayWnd" || c == "Windows.UI.Core.CoreWindow" ||
            c == "IslandWindow" || c == "XamlExplorerHostIslandWindow") return true;

        RECT r;
        if (!GetWindowRect(h, out r)) return true;
        if ((r.R - r.L) < 80 || (r.B - r.T) < 80) return true;

        if (r.L < t.R && t.L < r.R && r.T < t.B && t.T < r.B) { blocked = true; return false; }
        return true;
    }, IntPtr.Zero);

    return !blocked;
}
}
'@
}

# ---------------------------------------------------------------------------
# Window + card host
# ---------------------------------------------------------------------------
$script:Win = New-Object System.Windows.Window
$script:Win.WindowStyle = 'None'
$script:Win.AllowsTransparency = $true
$script:Win.Background = [System.Windows.Media.Brushes]::Transparent
$script:Win.ShowInTaskbar = $false
$script:Win.ResizeMode = 'NoResize'
$script:Win.WindowStartupLocation = 'Manual'
$script:Win.SizeToContent = 'Height'

$script:AppIcon = Join-Path $script:WidgetRoot 'assets\exam.ico'
if (Test-Path -LiteralPath $script:AppIcon) {
    try { $script:Win.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$script:AppIcon) } catch { }
}

$script:Root = New-Object System.Windows.Controls.Grid
$script:CardHost = New-Object System.Windows.Controls.Grid
[void]$script:Root.Children.Add($script:CardHost)

$script:EditOutline = New-Object System.Windows.Shapes.Rectangle
$script:EditOutline.StrokeThickness = 2
$script:EditOutline.RadiusX = 14
$script:EditOutline.RadiusY = 14
$script:EditOutline.Margin = Pad 1 1 1 1
$script:EditOutline.IsHitTestVisible = $false
$script:EditOutline.Visibility = 'Collapsed'
$script:EditOutline.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection
[void]$script:EditOutline.StrokeDashArray.Add(4)
[void]$script:EditOutline.StrokeDashArray.Add(3)
[void]$script:Root.Children.Add($script:EditOutline)

$script:Grip = New-Object System.Windows.Controls.Primitives.Thumb
$script:Grip.Width = 28
$script:Grip.Height = 28
$script:Grip.HorizontalAlignment = 'Right'
$script:Grip.VerticalAlignment = 'Bottom'
$script:Grip.Margin = Pad 0 0 6 6
$script:Grip.Cursor = 'SizeNWSE'
$script:Grip.ToolTip = 'Drag to resize the card'
$script:Grip.Visibility = 'Collapsed'
[void]$script:Root.Children.Add($script:Grip)

$script:Win.Content = $script:Root

$wh = New-Object System.Windows.Interop.WindowInteropHelper($script:Win)
$script:Hwnd = $wh.EnsureHandle()

$GWL_EXSTYLE = -20
$WS_EX_TRANSPARENT = 0x00000020
$WS_EX_TOOLWINDOW = 0x00000080
$WS_EX_NOACTIVATE = 0x08000000

$ex = [WidgetWin]::GetWindowLong($script:Hwnd, $GWL_EXSTYLE)
$ex = $ex -bor $WS_EX_TRANSPARENT -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE
[void][WidgetWin]::SetWindowLong($script:Hwnd, $GWL_EXSTYLE, $ex)

$HWND_TOPMOST = [IntPtr]::new(-1)
$HWND_NOTOPMOST = [IntPtr]::new(-2)
$HWND_BOTTOM = [IntPtr]::new(1)
$SWP_FLAGS = 0x0013   # NOSIZE | NOMOVE | NOACTIVATE

$script:Mode = ''
$script:Ticks = 0
$script:FgHwnd = [IntPtr]::Zero
$script:FgClass = ''

# ---------------------------------------------------------------------------
# Layout helpers bound to the window
# ---------------------------------------------------------------------------
function New-Card {
    Build-Card -ExamList $script:Data.Exams -TermText $script:Data.Term `
        -TermCodeText $script:Data.TermCode -CardWidth $script:WidthBase `
        -Accent $script:Data.Accent -TitleText $script:Data.Title -FooterText $script:Data.Footer `
        -Theme 'dark'
}

function Get-WindowDpiScale {
    try {
        $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($script:Root)
        if ($dpi.DpiScaleX -gt 0) { return [double]$dpi.DpiScaleX }
    }
    catch { }
    return 1.0
}

function Stop-CardDrag {
    if (-not $script:Dragging) { return }
    $script:Dragging = $false
    try { [System.Windows.Input.Mouse]::Capture($null) } catch { }
    if ($script:Card) {
        try { $script:Card.ReleaseMouseCapture() } catch { }
    }
    Complete-WindowDrag
    try { $script:EditIdleTimer.Stop(); $script:EditIdleTimer.Start() } catch { }
}

function Attach-CardMouse {
    param($Card)

    # Manual drag: capture the mouse and move the window ourselves. This avoids
    # Window.DragMove(), which needs an OS move loop and only works when the
    # window is active - the failure mode that made synthetic drags do nothing.
    $Card.Add_MouseLeftButtonDown({
        param($s, $e)
        if (-not $script:Editing) { return }
        if ($e.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }
        Add-WidgetLog 'card-mousedown'
        try { $script:EditIdleTimer.Stop() } catch { }
        try {
            $script:DragScale = Get-WindowDpiScale
            $script:DragCursor = [System.Windows.Forms.Cursor]::Position
            $script:DragWinLeft = [double]$script:Win.Left
            $script:DragWinTop = [double]$script:Win.Top
            $script:Dragging = [bool]$s.CaptureMouse()
            Add-WidgetLog ("drag-start at {0},{1} captured={2}" -f $script:DragWinLeft, $script:DragWinTop, $script:Dragging)
        }
        catch {
            $script:Dragging = $false
            Add-WidgetLog "drag-start-error $($_.Exception.Message)"
        }
        $e.Handled = $true
    })

    $Card.Add_MouseMove({
        param($s, $e)
        if (-not $script:Dragging) { return }
        if ([System.Windows.Input.Mouse]::LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) {
            Stop-CardDrag
            return
        }
        try {
            $p = [System.Windows.Forms.Cursor]::Position
            $dx = ($p.X - $script:DragCursor.X) / $script:DragScale
            $dy = ($p.Y - $script:DragCursor.Y) / $script:DragScale
            if ([math]::Abs($dx) -lt 0.5 -and [math]::Abs($dy) -lt 0.5) { return }
            $script:Win.Left = $script:DragWinLeft + $dx
            $script:Win.Top = $script:DragWinTop + $dy
        }
        catch {
            Add-WidgetLog "drag-move-error $($_.Exception.Message)"
        }
    })

    $Card.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($script:Dragging) { Stop-CardDrag }
    })

    $Card.Add_LostMouseCapture({
        param($s, $e)
        if ($script:Dragging) { Stop-CardDrag }
    })
}

function Rebuild-Card {
    $card = New-Card
    Attach-CardMouse $card
    $script:Card = $card

    $script:CardHost.Children.Clear()
    [void]$script:CardHost.Children.Add($card)

    $card.Measure([System.Windows.Size]::new($script:WidthBase, [double]::PositiveInfinity))
    $h = $card.DesiredSize.Height
    if ($h -le 0) { $h = 200 }
    $script:CardHeightDip = $h
    $card.Arrange([System.Windows.Rect]::new(0, 0, $script:WidthBase, $h))

    $script:Scale = Get-ClampedScale $script:Layout.Scale
    $script:Win.Width = $script:WidthBase * $script:Scale
    $script:CardTransform.ScaleX = $script:Scale
    $script:CardTransform.ScaleY = $script:Scale
    $script:Win.UpdateLayout()

    if ($script:Editing) { Update-EditChrome }
}

function Get-WindowScreen {
    $screens = Get-ScreenList
    $w = $script:WidthBase * $script:Scale
    $h = $script:CardHeightDip * $script:Scale
    $cx = $script:Win.Left + $w / 2
    $cy = $script:Win.Top + $h / 2
    return (Find-ScreenAtPoint -Screens $screens -X $cx -Y $cy)
}

function Clamp-WindowToScreen {
    if (-not $script:Win) { return }
    $s = Get-WindowScreen
    if ($null -eq $s) { return }
    $w = $script:WidthBase * $script:Scale
    $h = $script:CardHeightDip * $script:Scale
    $maxX = $s.WorkLeft + [math]::Max(0, $s.WorkWidth - $w)
    $maxY = $s.WorkTop + [math]::Max(0, $s.WorkHeight - $h)
    $x = [math]::Max($s.WorkLeft, [math]::Min($script:Win.Left, $maxX))
    $y = [math]::Max($s.WorkTop, [math]::Min($script:Win.Top, $maxY))
    $script:Win.Left = $x
    $script:Win.Top = $y
}

function Apply-WindowLayout {
    if (-not $script:Win) { return }
    $script:Scale = Get-ClampedScale $script:Layout.Scale
    $script:Win.Width = $script:WidthBase * $script:Scale
    $script:CardTransform.ScaleX = $script:Scale
    $script:CardTransform.ScaleY = $script:Scale
    $script:Win.UpdateLayout()

    $w = $script:WidthBase * $script:Scale
    $h = $script:CardHeightDip * $script:Scale
    $screens = Get-ScreenList
    $pos = Get-LayoutPositionForSettings -Layout $script:Layout -Screens $screens -CardWidth $w -CardHeight $h
    $script:Win.Left = $pos.X
    $script:Win.Top = $pos.Y
    $script:CurrentScreen = $pos.Screen
}

function Save-WindowLayout {
    if (-not $script:Win) { return }
    $s = Get-WindowScreen
    if ($null -eq $s) { return }

    $w = $script:WidthBase * $script:Scale
    $layout = $script:Layout
    $layout.Scale = $script:Scale
    $layout.Monitor = $s.DeviceName

    $anchor = Find-NearestAnchor -WorkLeft $s.WorkLeft -WorkTop $s.WorkTop `
        -WorkWidth $s.WorkWidth -WorkHeight $s.WorkHeight `
        -CardWidth $w -CardHeight ($script:CardHeightDip * $script:Scale) `
        -X $script:Win.Left -Y $script:Win.Top -Margin $layout.Margin -Tolerance 30

    if ($anchor) {
        $layout.Mode = 'anchor'
        $layout.Anchor = $anchor
        $pos = Get-LayoutPositionForSettings -Layout $layout -Screens (Get-ScreenList) -CardWidth $w -CardHeight ($script:CardHeightDip * $script:Scale)
        $script:Win.Left = $pos.X
        $script:Win.Top = $pos.Y
    }
    else {
        $layout.Mode = 'custom'
        $availX = [math]::Max(1.0, $s.WorkWidth - $w)
        $availY = [math]::Max(1.0, $s.WorkHeight - ($script:CardHeightDip * $script:Scale))
        $rx = ($script:Win.Left - $s.WorkLeft) / $availX
        $ry = ($script:Win.Top - $s.WorkTop) / $availY
        $layout.RelX = [math]::Max(0.0, [math]::Min(1.0, $rx))
        $layout.RelY = [math]::Max(0.0, [math]::Min(1.0, $ry))
    }

    $layout.Locked = (-not $script:Editing)
    Write-Settings -Settings ([pscustomobject]@{ Version = 1; Layout = $layout })
    $script:SettingsStamp = Get-FileStamp $script:SettingsFile
    Update-TrayChecks
}

function Complete-WindowDrag {
    Add-WidgetLog ("drag-complete at {0},{1}" -f $script:Win.Left, $script:Win.Top)
    Clamp-WindowToScreen
    Save-WindowLayout
}

function Set-WindowScale {
    param([double]$NewScale)
    $new = Get-ClampedScale $NewScale
    if ([math]::Abs($new - $script:Scale) -lt 0.001) { return }

    $oldLeft = $script:Win.Left
    $oldTop = $script:Win.Top
    $script:Scale = $new
    $script:Layout.Scale = $new
    $script:Win.Width = $script:WidthBase * $new
    $script:CardTransform.ScaleX = $new
    $script:CardTransform.ScaleY = $new
    $script:Win.UpdateLayout()

    if ($script:Layout.Mode -eq 'anchor') {
        Apply-WindowLayout
    }
    else {
        $script:Win.Left = $oldLeft
        $script:Win.Top = $oldTop
        Clamp-WindowToScreen
    }
}

# ---------------------------------------------------------------------------
# Edit mode
# ---------------------------------------------------------------------------
function Update-EditChrome {
    $accent = '#F2577C'
    $fg = '#12070A'
    if ($script:ActivePalette) {
        $accent = $script:ActivePalette.accentFill
        $fg = $script:ActivePalette.todayFg
    }
    $script:EditOutline.Stroke = Br $accent
    $script:EditOutline.Opacity = 0.9

    $template = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Primitives.Thumb])
    $border = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
    $border.SetValue([System.Windows.Controls.Border]::BackgroundProperty, (Br $accent))
    $border.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, (New-Object System.Windows.CornerRadius 6))
    $border.SetValue([System.Windows.Controls.Border]::OpacityProperty, 0.95)

    $text = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
    $text.SetValue([System.Windows.Controls.TextBlock]::TextProperty, [string][char]0x2198)
    $text.SetValue([System.Windows.Controls.TextBlock]::ForegroundProperty, (Br $fg))
    $text.SetValue([System.Windows.Controls.TextBlock]::FontSizeProperty, 11.0)
    $text.SetValue([System.Windows.Controls.TextBlock]::FontWeightProperty, [System.Windows.FontWeights]::SemiBold)
    $text.SetValue([System.Windows.Controls.TextBlock]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
    $text.SetValue([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
    [void]$border.AppendChild($text)
    $template.VisualTree = $border
    $script:Grip.Template = $template
}

function Enter-EditMode {
    if ($script:Editing) { return }
    if ($script:Win.Visibility -ne 'Visible') {
        $script:Win.Visibility = 'Visible'
        Apply-WindowLayout
    }
    $script:Editing = $true
    try { $script:EditIdleTimer.Stop(); $script:EditIdleTimer.Start() } catch { }

    $script:Layout.Locked = $false
    Write-Settings -Settings ([pscustomobject]@{ Version = 1; Layout = $script:Layout })
    $script:SettingsStamp = Get-FileStamp $script:SettingsFile

    $ex = [WidgetWin]::GetWindowLong($script:Hwnd, $GWL_EXSTYLE)
    $ex = $ex -band (-bnot $WS_EX_TRANSPARENT) -band (-bnot $WS_EX_NOACTIVATE)
    [void][WidgetWin]::SetWindowLong($script:Hwnd, $GWL_EXSTYLE, $ex)
    [void][WidgetWin]::SetWindowPos($script:Hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0027)
    [void][WidgetWin]::RedrawWindow($script:Hwnd, [IntPtr]::Zero, [IntPtr]::Zero, 0x0185)

    Update-EditChrome
    $script:EditOutline.Visibility = 'Visible'
    $script:Grip.Visibility = 'Visible'
    $script:Win.Topmost = $true
    Apply-Mode 'top' -Force
    try { [void]$script:Win.Activate() } catch { }
    if ($script:Tray) {
        try { $script:Tray.ShowBalloonTip(7000, 'Layout unlocked', 'Drag the card to move it. Drag the bottom-right corner to resize. Press Esc or use the tray menu when done.', 'Info') } catch { }
    }
    Update-TrayChecks
    if ($DebugLog) { "$(Get-Date -Format 'HH:mm:ss.fff') edit-mode on" | Add-Content $script:LogPath }
}

function Exit-EditMode {
    if (-not $script:Editing) { return }
    $script:Editing = $false
    Save-WindowLayout
    $script:EditOutline.Visibility = 'Collapsed'
    $script:Grip.Visibility = 'Collapsed'

    $ex = [WidgetWin]::GetWindowLong($script:Hwnd, $GWL_EXSTYLE)
    $ex = $ex -bor $WS_EX_TRANSPARENT -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE
    [void][WidgetWin]::SetWindowLong($script:Hwnd, $GWL_EXSTYLE, $ex)
    [void][WidgetWin]::SetWindowPos($script:Hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0027)
    [void][WidgetWin]::RedrawWindow($script:Hwnd, [IntPtr]::Zero, [IntPtr]::Zero, 0x0185)

    $script:Win.Topmost = $false
    $script:Mode = ''
    $script:Win.InvalidateVisual()
    Apply-Mode 'bottom' -Force
    try { $script:EditIdleTimer.Stop() } catch { }
    Update-TrayChecks
    if ($DebugLog) { "$(Get-Date -Format 'HH:mm:ss.fff') edit-mode off" | Add-Content $script:LogPath }
}

$script:EditIdleTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:EditIdleTimer.Interval = [TimeSpan]::FromMinutes(3)
$script:EditIdleTimer.Add_Tick({
    $script:EditIdleTimer.Stop()
    Exit-EditMode
})

# ---------------------------------------------------------------------------
# Settings / tray helpers
# ---------------------------------------------------------------------------
function Save-And-ApplyLayout {
    $script:Layout.Locked = (-not $script:Editing)
    Write-Settings -Settings ([pscustomobject]@{ Version = 1; Layout = $script:Layout })
    $script:SettingsStamp = Get-FileStamp $script:SettingsFile
    Apply-WindowLayout
    Update-TrayChecks
}

function Set-LayoutScale {
    param([double]$Scale)
    $script:Layout.Scale = Get-ClampedScale $Scale
    Save-And-ApplyLayout
}

function Set-LayoutAnchor {
    param([string]$Anchor)
    if ($script:LayoutAnchors -notcontains $Anchor) { return }
    $script:Layout.Mode = 'anchor'
    $script:Layout.Anchor = $Anchor
    Save-And-ApplyLayout
}

function Reset-Layout {
    $defaults = Get-DefaultLayout
    $defaults.Monitor = $script:Layout.Monitor
    $script:Layout = $defaults
    Save-And-ApplyLayout
}

function Open-Editor {
    $vbs = Join-Path $script:WidgetRoot 'Edit Exam Routine.vbs'
    try { Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $vbs + '"') -WorkingDirectory $script:WidgetRoot }
    catch { }
}

function Open-DataFolder {
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $script:DataDir + '"') } catch { }
}

function Show-About {
    $version = Get-AppVersion
    $text = "Exam Routine Widget $version`n`nData: $($script:DataDir)`nLayout: $($script:Layout.Mode) / scale $([math]::Round($script:Layout.Scale * 100))%`n`nhttps://github.com/Hermesione/exam-routine-widget"
    [System.Windows.MessageBox]::Show($script:Win, $text, 'About Exam Routine Widget',
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
}

function Toggle-CardVisibility {
    if ($script:Win.Visibility -eq 'Visible') {
        if ($script:Editing) { Exit-EditMode }
        $script:Win.Visibility = 'Hidden'
    }
    else {
        $script:Win.Visibility = 'Visible'
        Apply-WindowLayout
    }
    if ($script:HideMenuItem) {
        $script:HideMenuItem.Text = if ($script:Win.Visibility -eq 'Visible') { 'Hide card' } else { 'Show card' }
    }
}

function Quit-Widget {
    $script:Quitting = $true
    try { $script:EditIdleTimer.Stop() } catch { }
    if ($script:Tray) {
        try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
        $script:Tray = $null
    }
    $script:Win.Close()
}

function Update-TrayChecks {
    if ($script:EditMenuItem) { $script:EditMenuItem.Checked = $script:Editing }
    if ($script:AutostartMenuItem) {
        try { $script:AutostartMenuItem.Checked = Test-Autostart } catch { }
    }
    if ($script:HideMenuItem) {
        $script:HideMenuItem.Text = if ($script:Win.Visibility -eq 'Visible') { 'Hide card' } else { 'Show card' }
    }
    if ($script:SizeMenuItems) {
        foreach ($name in $script:SizeMenuItems.Keys) {
            $target = [double]$script:LayoutSizePresets[$name]
            $script:SizeMenuItems[$name].Checked = ([math]::Abs($script:Layout.Scale - $target) -lt 0.011)
        }
    }
    if ($script:PositionMenuItems) {
        foreach ($anchor in $script:PositionMenuItems.Keys) {
            $script:PositionMenuItems[$anchor].Checked = ($script:Layout.Mode -eq 'anchor' -and $script:Layout.Anchor -eq $anchor)
        }
    }
}

function Initialize-Tray {
    $iconPath = Join-Path $script:WidgetRoot 'assets\exam.ico'
    $icon = $null
    if (Test-Path -LiteralPath $iconPath) {
        try { $icon = New-Object System.Drawing.Icon($iconPath) } catch { }
    }
    if ($null -eq $icon) { $icon = [System.Drawing.SystemIcons]::Application }

    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $script:Tray.Icon = $icon
    $script:Tray.Text = 'Exam Routine Widget'
    $script:Tray.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $open = $menu.Items.Add('Open editor')
    $open.Add_Click({ Open-Editor })

    $script:EditMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Edit layout')
    $script:EditMenuItem.Add_Click({
        if ($script:Editing) { Exit-EditMode } else { Enter-EditMode }
    })
    [void]$menu.Items.Add($script:EditMenuItem)

    $sizeMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Size')
    $script:SizeMenuItems = @{}
    foreach ($name in $script:LayoutSizePresets.Keys) {
        $item = New-Object System.Windows.Forms.ToolStripMenuItem($name)
        $item.Tag = [double]$script:LayoutSizePresets[$name]
        $item.Add_Click({ param($s, $e) Set-LayoutScale ([double]$s.Tag) })
        [void]$sizeMenu.DropDownItems.Add($item)
        $script:SizeMenuItems[$name] = $item
    }
    [void]$menu.Items.Add($sizeMenu)

    $posMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Position')
    $script:PositionMenuItems = @{}
    $labels = [ordered]@{
        'top-left' = 'Top left'; 'top-center' = 'Top center'; 'top-right' = 'Top right'
        'middle-left' = 'Middle left'; 'center' = 'Center'; 'middle-right' = 'Middle right'
        'bottom-left' = 'Bottom left'; 'bottom-center' = 'Bottom center'; 'bottom-right' = 'Bottom right'
    }
    foreach ($anchor in $labels.Keys) {
        $item = New-Object System.Windows.Forms.ToolStripMenuItem($labels[$anchor])
        $item.Tag = $anchor
        $item.Add_Click({ param($s, $e) Set-LayoutAnchor ([string]$s.Tag) })
        [void]$posMenu.DropDownItems.Add($item)
        $script:PositionMenuItems[$anchor] = $item
    }
    [void]$menu.Items.Add($posMenu)

    $reset = $menu.Items.Add('Reset layout')
    $reset.Add_Click({ Reset-Layout })

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $script:AutostartMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Start with Windows')
    $script:AutostartMenuItem.Add_Click({
        try { Set-Autostart (-not (Test-Autostart)) } catch { }
        Update-TrayChecks
    })
    [void]$menu.Items.Add($script:AutostartMenuItem)

    $script:HideMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Hide card')
    $script:HideMenuItem.Add_Click({ Toggle-CardVisibility })
    [void]$menu.Items.Add($script:HideMenuItem)

    $dataItem = $menu.Items.Add('Open data folder')
    $dataItem.Add_Click({ Open-DataFolder })

    $about = $menu.Items.Add('About')
    $about.Add_Click({ Show-About })

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $exit = $menu.Items.Add('Exit')
    $exit.Add_Click({ Quit-Widget })

    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.Add_DoubleClick({ Open-Editor })
    Update-TrayChecks
}

# ---------------------------------------------------------------------------
# Live widget
# ---------------------------------------------------------------------------
$script:DataStamp = $null
$settings = Read-Settings
if (-not (Test-Path -LiteralPath $script:SettingsFile)) {
    Write-Settings -Settings $settings
}
$script:Layout = $settings.Layout
$script:Scale = Get-ClampedScale $script:Layout.Scale
$script:SettingsStamp = Get-FileStamp $script:SettingsFile
$script:ExamStamp = Get-FileStamp $script:DataFile
$script:ScreenSignature = Get-ScreenSignature

$script:CardTransform = New-Object System.Windows.Media.ScaleTransform($script:Scale, $script:Scale)
$script:CardHost.LayoutTransform = $script:CardTransform

Rebuild-Card
Apply-WindowLayout
Initialize-Tray
Update-TrayChecks

function Apply-Mode([string]$mode, [switch]$Force) {
    if (-not $Force -and $mode -eq $script:Mode) { return }
    if ($mode -eq 'top') {
        $script:Win.Topmost = $true
        [void][WidgetWin]::SetWindowPos($script:Hwnd, $HWND_TOPMOST, 0, 0, 0, 0, $SWP_FLAGS)
    }
    else {
        $script:Win.Topmost = $false
        [void][WidgetWin]::SetWindowPos($script:Hwnd, $HWND_NOTOPMOST, 0, 0, 0, 0, $SWP_FLAGS)
        [void][WidgetWin]::SetWindowPos($script:Hwnd, $HWND_BOTTOM, 0, 0, 0, 0, $SWP_FLAGS)
    }
    $script:Mode = $mode
    $script:Win.InvalidateVisual()
    if ($script:Card) { $script:Card.InvalidateVisual() }
    [void][WidgetWin]::RedrawWindow($script:Hwnd, [IntPtr]::Zero, [IntPtr]::Zero, 0x0185)
}

function Get-DesiredMode {
    if ($script:Editing) { return 'top' }
    $fg = [WidgetWin]::GetForegroundWindow()
    if ($fg -ne $script:FgHwnd) {
        $script:FgHwnd = $fg
        $script:FgClass = if ($fg -eq [IntPtr]::Zero) { 'none' } else { [WidgetWin]::ClassName($fg) }
    }
    $cls = $script:FgClass
    $isDesktop = ($cls -eq 'Progman' -or $cls -eq 'WorkerW')
    $clear = $false
    if ($isDesktop) { $clear = [WidgetWin]::AreaClear($script:Hwnd) }
    $want = if ($isDesktop -and $clear) { 'top' } else { 'bottom' }

    if ($DebugLog -and $want -ne $script:Mode) {
        "$(Get-Date -Format 'HH:mm:ss.fff') fg=$cls clear=$clear want=$want was=$($script:Mode)" |
            Add-Content $script:LogPath
    }
    $want
}

function Reload-Data {
    Load-Data
    Rebuild-Card
    Apply-WindowLayout
    if ($DebugLog) {
        "$(Get-Date -Format 'HH:mm:ss.fff') reload exams=$($script:Data.Exams.Count) accent=$($script:Data.Accent)" |
            Add-Content $script:LogPath
    }
}

$layerTimer = New-Object System.Windows.Threading.DispatcherTimer
$layerTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$layerTimer.Add_Tick({
    $script:Ticks++
    $want = Get-DesiredMode
    if ($want -ne $script:Mode) {
        Apply-Mode $want
    }
    elseif ($script:Ticks % 15 -eq 0) {
        $isTop = ([WidgetWin]::GetWindowLong($script:Hwnd, -20) -band 0x8) -ne 0
        if (($want -eq 'top') -ne $isTop) { Apply-Mode $want -Force }
    }
})
$layerTimer.Start()

$fileTimer = New-Object System.Windows.Threading.DispatcherTimer
$fileTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
$fileTimer.Add_Tick({
    if ($script:Quitting) { return }

    $examStamp = Get-FileStamp $script:DataFile
    if ($examStamp -ne $script:ExamStamp) {
        $script:ExamStamp = $examStamp
        Reload-Data
    }

    $settingsStamp = Get-FileStamp $script:SettingsFile
    if ($settingsStamp -ne $script:SettingsStamp) {
        $script:SettingsStamp = $settingsStamp
        $script:Layout = (Read-Settings).Layout
        Apply-WindowLayout
        Update-TrayChecks
    }

    if (Test-Path -LiteralPath $script:EditRequestFile) {
        Remove-Item -LiteralPath $script:EditRequestFile -Force -ErrorAction SilentlyContinue
        if (-not $script:Editing) { Enter-EditMode }
    }

    $script:ScreenTicks++
    if ($script:ScreenTicks % 4 -eq 0) {
        $sig = Get-ScreenSignature
        if ($sig -ne $script:ScreenSignature) {
            $script:ScreenSignature = $sig
            Apply-WindowLayout
        }
    }
})
$fileTimer.Start()

$doneTimer = New-Object System.Windows.Threading.DispatcherTimer
$doneTimer.Interval = [TimeSpan]::FromSeconds(20)
$doneTimer.Add_Tick({
    if ($script:Quitting) { return }
    $now = Get-Date
    $live = @(Select-UpcomingExams $script:Data.Exams $now)
    if ($live.Count -ne $script:Data.Exams.Count) {
        Write-ExamData -Term $script:Data.Term -TermCode $script:Data.TermCode -Accent $script:Data.Accent `
            -Title $script:Data.Title -Footer $script:Data.Footer -ExamList $live
        $script:ExamStamp = Get-FileStamp $script:DataFile
        Reload-Data
    }
    elseif ($now.Date -ne $script:LastDay) {
        $script:LastDay = $now.Date
        Reload-Data
    }
})
$doneTimer.Start()

$script:Grip.Add_DragStarted({
    param($s, $e)
    if (-not $script:Editing) { return }
    Add-WidgetLog 'grip-drag-start'
    try { $script:EditIdleTimer.Stop() } catch { }
})
$script:Grip.Add_DragDelta({
    param($s, $e)
    if (-not $script:Editing) { return }
    Add-WidgetLog ("grip-delta {0},{1}" -f $e.HorizontalChange, $e.VerticalChange)
    try {
        $delta = ($e.HorizontalChange + $e.VerticalChange) / 2.0 / $script:WidthBase
        Set-WindowScale ($script:Scale + $delta)
    }
    catch {
        Add-WidgetLog "grip-delta-error $($_.Exception.Message)"
    }
    try { $script:EditIdleTimer.Stop(); $script:EditIdleTimer.Start() } catch { }
})
$script:Grip.Add_DragCompleted({
    param($s, $e)
    if (-not $script:Editing) { return }
    Add-WidgetLog ("grip-drag-complete scale={0}" -f $script:Scale)
    Save-WindowLayout
    try { $script:EditIdleTimer.Stop(); $script:EditIdleTimer.Start() } catch { }
})

$script:Win.Add_KeyDown({
    param($s, $e)
    if ($script:Editing -and $e.Key -eq [System.Windows.Input.Key]::Escape) {
        Exit-EditMode
        $e.Handled = $true
    }
})

$script:Win.Add_Loaded({
    Apply-Mode 'bottom' -Force
    Apply-WindowLayout
    Update-TrayChecks
    if (Test-Path -LiteralPath $script:EditRequestFile) {
        Remove-Item -LiteralPath $script:EditRequestFile -Force -ErrorAction SilentlyContinue
        Enter-EditMode
    }
})

$script:Win.Add_Closing({
    if ($script:Editing) { Exit-EditMode }
    try { $script:EditIdleTimer.Stop() } catch { }
    if ($script:Tray) {
        try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
        $script:Tray = $null
    }
})

$script:Win.Add_Closed({
    # We run the dispatcher manually (see below) so hiding the window keeps the
    # widget alive; close is the only thing that should end the message loop.
    try {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown(
            [System.Windows.Threading.DispatcherPriority]::Background)
    }
    catch { }
})

# ShowDialog() would return as soon as the card is hidden from the tray menu.
# Show() + Dispatcher.Run() keeps running while the window is hidden and stops
# only when Quit-Widget closes it.
$script:Win.Show()
[System.Windows.Threading.Dispatcher]::Run()
