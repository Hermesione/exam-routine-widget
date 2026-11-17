# Exam Routine Editor (Windows 11)
#
# A small GUI for exams.json:
#   left  - card details, add/edit form, the upcoming exam list
#   right - live preview of the real desktop card
#
# Launch it with "Edit Exam Routine.vbs" (no console window), or:
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\ExamEditor.ps1
#
# -SnapshotPath is a development helper: renders the window to a PNG and exits.

param(
    [string]$SnapshotPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

. (Join-Path $PSScriptRoot 'lib\Card.ps1')
. (Join-Path $PSScriptRoot 'lib\Layout.ps1')
. (Join-Path $PSScriptRoot 'lib\Export.ps1')

# ---------------------------------------------------------------------------
# Window layout
# ---------------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Exam Routine Editor"
        Width="1240" Height="860" MinWidth="1040" MinHeight="720"
        WindowStartupLocation="CenterScreen"
        SnapsToDevicePixels="True" UseLayoutRounding="True"
        Background="#090D12" Foreground="#E8EEF5"
        FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display">
    <Window.Resources>

        <Style x:Key="Field" TargetType="TextBox">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="#E8EEF5"/>
            <Setter Property="Background" Value="#0B1016"/>
            <Setter Property="BorderBrush" Value="#242E3A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="CaretBrush" Value="#F2577C"/>
            <Setter Property="SelectionBrush" Value="#F2577C"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="Shell" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"
                                          VerticalAlignment="Center" Background="Transparent"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Shell" Property="BorderBrush" Value="#33404F"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="Shell" Property="BorderBrush" Value="#F2577C"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="FieldCompact" TargetType="TextBox" BasedOn="{StaticResource Field}">
            <Setter Property="Height" Value="34"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Padding" Value="9,4"/>
        </Style>

        <Style x:Key="Btn" TargetType="Button">
            <Setter Property="Background" Value="#121922"/>
            <Setter Property="Foreground" Value="#DCE5EE"/>
            <Setter Property="BorderBrush" Value="#263140"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="B" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="B" Property="Background" Value="#18212C"/>
                                <Setter TargetName="B" Property="BorderBrush" Value="#33404F"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="B" Property="Background" Value="#0E141B"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="Primary" TargetType="Button">
            <Setter Property="Background" Value="#F2577C"/>
            <Setter Property="Foreground" Value="#190A10"/>
            <Setter Property="BorderBrush" Value="#F2577C"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="B" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="B" Property="Background" Value="#FF7195"/>
                                <Setter TargetName="B" Property="BorderBrush" Value="#FF7195"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="B" Property="Background" Value="#D9446B"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="IconBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#7B8697"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="B" Property="Background" Value="#1A222C"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="B" Property="Background" Value="#232D39"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ColorSlider" TargetType="Slider">
            <Setter Property="Height" Value="18"/>
            <Setter Property="Minimum" Value="0"/>
            <Setter Property="Maximum" Value="255"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Slider">
                        <Grid VerticalAlignment="Center" Height="18">
                            <Border Height="6" CornerRadius="3" Background="#1A222C" VerticalAlignment="Center"/>
                            <Track x:Name="PART_Track" VerticalAlignment="Center">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="Slider.DecreaseLarge" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Width="14" Height="14">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Ellipse Fill="#F3F7FA" Stroke="#0B1016" StrokeThickness="2"/>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="Slider.IncreaseLarge" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="Panel" TargetType="Border">
            <Setter Property="Background" Value="#0D131A"/>
            <Setter Property="BorderBrush" Value="#1B242E"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="12"/>
            <Setter Property="Padding" Value="16,14"/>
        </Style>

        <Style x:Key="SectionLabel" TargetType="TextBlock">
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#8894A3"/>
        </Style>

        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="Foreground" Value="#6C7784"/>
        </Style>

        <Style x:Key="ExamRow" TargetType="Border">
            <Setter Property="Background" Value="#0C1118"/>
            <Setter Property="BorderBrush" Value="#1A222C"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="9"/>
            <Setter Property="Padding" Value="10,9"/>
            <Setter Property="Margin" Value="0,0,0,6"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#121A23"/>
                    <Setter Property="BorderBrush" Value="#26313D"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="ToolTip">
            <Setter Property="Background" Value="#1A222C"/>
            <Setter Property="Foreground" Value="#E8EEF5"/>
            <Setter Property="BorderBrush" Value="#2C3742"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>

        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="9"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="Transparent">
                            <Track x:Name="PART_Track" IsDirectionReversed="True"
                                   Orientation="{TemplateBinding Orientation}">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageUpCommand" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb>
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border Background="#2C3742" CornerRadius="4" Margin="1,2"/>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageDownCommand" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- ================= header ================= -->
        <Border Grid.Row="0" Background="#0D1218" BorderBrush="#1B232D" BorderThickness="0,0,0,1" Padding="24,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Width="36" Height="36" CornerRadius="9" Background="#1D1116"
                            BorderBrush="#4A2331" BorderThickness="1" Margin="0,0,12,0">
                        <TextBlock Text="&#x25A6;" FontSize="17" Foreground="#FF9FB4"
                                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="Exam Routine Editor" FontSize="16" FontWeight="SemiBold" Foreground="#F3F7FA"/>
                        <TextBlock Text="Saves to data\exams.json - the desktop widget updates itself."
                                   FontSize="11" Foreground="#6C7784" Margin="0,2,0,0"/>
                    </StackPanel>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse x:Name="DirtyDot" Width="7" Height="7" Fill="#F2577C"
                             Margin="0,0,10,0" VerticalAlignment="Center" Visibility="Collapsed"/>
                    <Button x:Name="LayoutBtn" Style="{StaticResource Btn}" Content="Layout"
                            Margin="0,0,10,0" ToolTip="Position and size presets"/>
                    <Button x:Name="ExportBtn" Style="{StaticResource Btn}" Content="Export"
                            Margin="0,0,10,0" ToolTip="Export the routine as PNG or PDF"/>
                    <Button x:Name="RestartBtn" Style="{StaticResource Btn}" Content="Restart widget"
                            Margin="0,0,10,0" ToolTip="Stop and relaunch the desktop widget"/>
                    <Button x:Name="SaveBtn" Style="{StaticResource Primary}" Content="Save changes"
                            MinWidth="130" ToolTip="Save to exams.json (Ctrl+S)"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ================= body ================= -->
        <Grid Grid.Row="1" Margin="24,18,24,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="430"/>
                <ColumnDefinition Width="18"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- ========== left: editing ========== -->
            <Grid Grid.Column="0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- add / edit form -->
                <Border Grid.Row="0" Style="{StaticResource Panel}">
                    <StackPanel>
                        <TextBlock x:Name="FormTitle" Text="ADD EXAM" Style="{StaticResource SectionLabel}"/>

                        <Grid Margin="0,9,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="78"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="78"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel>
                                <Grid>
                                    <TextBlock Text="Date" Style="{StaticResource FieldLabel}"/>
                                    <TextBlock x:Name="WeekdayHint" HorizontalAlignment="Right" FontSize="10.5"
                                               FontWeight="SemiBold" Foreground="#F2577C"/>
                                </Grid>
                                <TextBox x:Name="DateBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="yyyy-mm-dd - e.g. 2026-12-07"/>
                            </StackPanel>

                            <StackPanel Grid.Column="2">
                                <TextBlock Text="Start" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="StartBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="24-hour - e.g. 11:00"/>
                            </StackPanel>

                            <StackPanel Grid.Column="4">
                                <TextBlock Text="End" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="EndBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="24-hour - e.g. 13:00"/>
                            </StackPanel>
                        </Grid>

                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="132"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock Text="Course code" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="CodeBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="e.g. CS 101"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2">
                                <TextBlock Text="Course title" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="TitleBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="e.g. Introduction to Programming"/>
                            </StackPanel>
                        </Grid>

                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock Text="Section" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="SectionBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="e.g. L01"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2">
                                <TextBlock Text="Room" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="RoomBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="e.g. B-204"/>
                            </StackPanel>
                            <StackPanel Grid.Column="4">
                                <TextBlock Text="CRN" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="CrnBox" Style="{StaticResource Field}" Margin="0,5,0,0"
                                         ToolTip="e.g. 10001"/>
                            </StackPanel>
                        </Grid>

                        <TextBlock x:Name="FormError" Foreground="#FF6B81" FontSize="11" Margin="0,9,0,0"
                                   TextWrapping="Wrap" MinHeight="15"/>

                        <Grid Margin="0,3,0,0">
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="AddBtn" Style="{StaticResource Primary}" Content="Add exam" MinWidth="120"/>
                                <Button x:Name="CancelEditBtn" Style="{StaticResource Btn}" Content="Cancel"
                                        Margin="10,0,0,0" Visibility="Collapsed"/>
                            </StackPanel>
                            <TextBlock Text="Ctrl+Enter" HorizontalAlignment="Right" VerticalAlignment="Center"
                                       FontSize="10.5" Foreground="#4E5865"/>
                        </Grid>
                    </StackPanel>
                </Border>

                <!-- schedule -->
                <Grid Grid.Row="1" Margin="0,14,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Grid>
                        <TextBlock Text="SCHEDULE" Style="{StaticResource SectionLabel}" VerticalAlignment="Center"/>
                        <TextBlock x:Name="ScheduleCount" HorizontalAlignment="Right" VerticalAlignment="Center"
                                   FontSize="10.5" Foreground="#6C7784"/>
                    </Grid>

                    <Border Grid.Row="1" Style="{StaticResource Panel}" Padding="8" Margin="0,8,0,0">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                            <StackPanel x:Name="ScheduleList"/>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </Grid>

            <!-- ========== right: live preview ========== -->
            <Border Grid.Column="2" Background="#0A0E13" BorderBrush="#1B232D" BorderThickness="1" CornerRadius="12">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Grid Margin="18,14,18,10">
                        <TextBlock Text="LIVE PREVIEW" Style="{StaticResource SectionLabel}" VerticalAlignment="Center"/>
                        <TextBlock Text="what sits on your desktop" HorizontalAlignment="Right" VerticalAlignment="Center"
                                   FontSize="10.5" Foreground="#4E5865"/>
                    </Grid>

                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="18,0,18,10">
                        <TextBlock Text="Term" Style="{StaticResource FieldLabel}" VerticalAlignment="Center"/>
                        <TextBox x:Name="TermBox" Style="{StaticResource FieldCompact}" Width="150" Margin="8,0,0,0"
                                 ToolTip="Shown under the card title, e.g. Fall 2026"/>
                        <TextBlock Text="Term code" Style="{StaticResource FieldLabel}" VerticalAlignment="Center"
                                   Margin="18,0,0,0"/>
                        <TextBox x:Name="TermCodeBox" Style="{StaticResource FieldCompact}" Width="140" Margin="8,0,0,0"
                                 ToolTip="e.g. Term 101"/>
                    </StackPanel>

                    <Grid Grid.Row="2" Margin="18,0,18,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Title" Style="{StaticResource FieldLabel}" VerticalAlignment="Center"/>
                        <TextBox x:Name="CardTitleBox" Grid.Column="1" Style="{StaticResource FieldCompact}"
                                 Margin="8,0,0,0" ToolTip="Card heading, e.g. Final Exam Routine"/>
                        <TextBlock Text="Footer" Grid.Column="3" Style="{StaticResource FieldLabel}"
                                   VerticalAlignment="Center" Margin="16,0,0,0"/>
                        <TextBox x:Name="CardFooterBox" Grid.Column="4" Style="{StaticResource FieldCompact}"
                                 Margin="8,0,0,0" ToolTip="Small footer text, e.g. times are local"/>
                    </Grid>

                    <Grid Grid.Row="3" Margin="18,0,18,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Text="Accent" Style="{StaticResource FieldLabel}" VerticalAlignment="Center"/>
                        <Border x:Name="AccentSwatch" Grid.Column="1" Width="28" Height="28" CornerRadius="8"
                                Background="#F2577C" BorderBrush="#40FFFFFF" BorderThickness="1" Margin="8,0,0,0"/>
                        <TextBox x:Name="AccentHexBox" Grid.Column="2" Style="{StaticResource FieldCompact}"
                                 Width="94" Margin="8,0,0,0" CharacterCasing="Upper"
                                 ToolTip="Hex colour, e.g. #F2577C"/>
                        <StackPanel x:Name="PresetPanel" Grid.Column="3" Orientation="Horizontal"
                                    VerticalAlignment="Center" Margin="14,0,10,0"/>
                        <TextBlock x:Name="AccentNote" Grid.Column="4" Style="{StaticResource FieldLabel}"
                                   VerticalAlignment="Center" TextTrimming="CharacterEllipsis"
                                   MaxWidth="150" TextAlignment="Right"/>
                    </Grid>

                    <Grid Grid.Row="4" Margin="18,0,18,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="14"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="34"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="R" Style="{StaticResource FieldLabel}" VerticalAlignment="Center"
                                       FontWeight="SemiBold" Foreground="#FF9AA6"/>
                            <Slider x:Name="RedSlider" Grid.Column="1" Style="{StaticResource ColorSlider}"
                                    VerticalAlignment="Center"/>
                            <TextBlock x:Name="RedValue" Grid.Column="2" Text="242" FontSize="10.5"
                                       Foreground="#8894A3" TextAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>

                        <Grid Grid.Column="2">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="14"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="34"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="G" Style="{StaticResource FieldLabel}" VerticalAlignment="Center"
                                       FontWeight="SemiBold" Foreground="#9BE2A6"/>
                            <Slider x:Name="GreenSlider" Grid.Column="1" Style="{StaticResource ColorSlider}"
                                    VerticalAlignment="Center"/>
                            <TextBlock x:Name="GreenValue" Grid.Column="2" Text="87" FontSize="10.5"
                                       Foreground="#8894A3" TextAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>

                        <Grid Grid.Column="4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="14"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="34"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="B" Style="{StaticResource FieldLabel}" VerticalAlignment="Center"
                                       FontWeight="SemiBold" Foreground="#9AB8FF"/>
                            <Slider x:Name="BlueSlider" Grid.Column="1" Style="{StaticResource ColorSlider}"
                                    VerticalAlignment="Center"/>
                            <TextBlock x:Name="BlueValue" Grid.Column="2" Text="124" FontSize="10.5"
                                       Foreground="#8894A3" TextAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                    </Grid>

                    <Border Grid.Row="5" Margin="12,0,12,12" CornerRadius="10" ClipToBounds="True">
                        <Border.Background>
                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                <GradientStop Color="#06090D" Offset="0"/>
                                <GradientStop Color="#0F1A26" Offset="0.55"/>
                                <GradientStop Color="#1A111E" Offset="1"/>
                            </LinearGradientBrush>
                        </Border.Background>

                        <Viewbox Stretch="Uniform" StretchDirection="DownOnly" Margin="20"
                                 HorizontalAlignment="Center" VerticalAlignment="Center">
                            <Border x:Name="PreviewHost">
                                <Border.Effect>
                                    <DropShadowEffect BlurRadius="36" ShadowDepth="8" Direction="270"
                                                      Opacity="0.55" Color="#000000"/>
                                </Border.Effect>
                            </Border>
                        </Viewbox>
                    </Border>
                </Grid>
            </Border>
        </Grid>

        <!-- ================= status bar ================= -->
        <Border Grid.Row="2" Background="#0D1218" BorderBrush="#1B232D" BorderThickness="0,1,0,0" Padding="24,8">
            <Grid>
                <TextBlock x:Name="StatusText" Foreground="#8894A3" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock Text="Finished exams remove themselves automatically."
                           HorizontalAlignment="Right" VerticalAlignment="Center"
                           FontSize="11" Foreground="#4E5865"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$script:Win = [System.Windows.Markup.XamlReader]::Parse($xaml)
if (-not $script:Win.Icon) {
    $iconFile = Join-Path $script:WidgetRoot 'assets\exam.ico'
    if (Test-Path -LiteralPath $iconFile) {
        try { $script:Win.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconFile) } catch { }
    }
}

$controlNames = @(
    'TermBox', 'TermCodeBox', 'DateBox', 'StartBox', 'EndBox', 'CodeBox', 'TitleBox',
    'SectionBox', 'RoomBox', 'CrnBox', 'AddBtn', 'CancelEditBtn', 'FormError',
    'FormTitle', 'WeekdayHint', 'ScheduleList', 'ScheduleCount', 'PreviewHost',
    'SaveBtn', 'RestartBtn', 'StatusText', 'DirtyDot',
    'CardTitleBox', 'CardFooterBox', 'LayoutBtn', 'ExportBtn',
    'AccentSwatch', 'AccentHexBox', 'PresetPanel', 'AccentNote',
    'RedSlider', 'GreenSlider', 'BlueSlider', 'RedValue', 'GreenValue', 'BlueValue'
)
foreach ($name in $controlNames) {
    Set-Variable -Name $name -Value $script:Win.FindName($name) -Scope Script
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
$script:Exams = New-Object System.Collections.ArrayList
$script:EditingIndex = -1
$script:Dirty = $false
$script:Suppress = $false
$script:Accent = '#F2577C'
$script:ColorSuppress = $false

$script:PreviewTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:PreviewTimer.Interval = [TimeSpan]::FromMilliseconds(140)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Set-Status {
    param([string]$Text)
    $script:StatusText.Text = $Text
}

function Set-Dirty {
    param([bool]$Value)
    $script:Dirty = $Value
    if ($Value) {
        $script:DirtyDot.Visibility = 'Visible'
        $script:Win.Title = 'Exam Routine Editor - unsaved changes'
    }
    else {
        $script:DirtyDot.Visibility = 'Collapsed'
        $script:Win.Title = 'Exam Routine Editor'
    }
}

function Update-Preview {
    if (-not $script:PreviewHost) { return }
    try {
        $card = Build-Card -ExamList @($script:Exams) `
            -TermText $script:TermBox.Text.Trim() `
            -TermCodeText $script:TermCodeBox.Text.Trim() `
            -CardWidth 440 `
            -Accent $script:Accent `
            -TitleText $script:CardTitleBox.Text.Trim() `
            -FooterText $script:CardFooterBox.Text.Trim()
        $script:PreviewHost.Child = $card
    }
    catch {
        Set-Status "Preview error: $($_.Exception.Message)"
    }
}

function Request-Preview {
    $script:PreviewTimer.Stop()
    $script:PreviewTimer.Start()
}

function Read-SliderAccent {
    $r = [int][math]::Round($script:RedSlider.Value)
    $g = [int][math]::Round($script:GreenSlider.Value)
    $b = [int][math]::Round($script:BlueSlider.Value)
    return ('#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b)
}

function Update-AccentNote {
    $pal = Get-CardPalette $script:Accent
    if ($pal.accentInk -ne $script:Accent -or $pal.accentFill -ne $script:Accent) {
        $script:AccentNote.Text = 'auto-contrast'
        $script:AccentNote.Foreground = Br '#F5C542'
        $script:AccentNote.ToolTip = ("This colour is lightened where needed so the card text stays readable.`n" +
            "Text uses $($pal.accentInk); fills use $($pal.accentFill).")
    }
    else {
        $script:AccentNote.Text = ''
        $script:AccentNote.Foreground = Br '#6C7784'
        $script:AccentNote.ToolTip = $null
    }
}

function Refresh-Presets {
    $script:PresetPanel.Children.Clear()
    $presets = @('#F2577C', '#FF8A3D', '#F5C542', '#4ECB71', '#2BC4A9', '#4A9EFF', '#8B7CFF', '#E879F9', '#F3F7FA')
    foreach ($hex in $presets) {
        $dot = New-Object System.Windows.Controls.Border
        $dot.Width = 18
        $dot.Height = 18
        $dot.CornerRadius = New-Object System.Windows.CornerRadius 9
        $dot.Background = Br $hex
        $dot.Margin = Pad 0 0 5 0
        $dot.Cursor = 'Hand'
        $dot.ToolTip = $hex
        $dot.Tag = $hex
        if ($script:Accent -eq $hex) {
            $dot.BorderBrush = Br '#F3F7FA'
            $dot.BorderThickness = New-Object System.Windows.Thickness 2
        }
        $dot.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; [void](Set-Accent $s.Tag) })
        [void]$script:PresetPanel.Children.Add($dot)
    }
}

function Set-Accent {
    param(
        [string]$Hex,
        [switch]$FromHex,
        [switch]$Silent
    )
    $norm = Convert-HexColor $Hex
    if (-not $norm) { return $false }

    $script:Accent = $norm

    $r = [Convert]::ToInt32($norm.Substring(1, 2), 16)
    $g = [Convert]::ToInt32($norm.Substring(3, 2), 16)
    $b = [Convert]::ToInt32($norm.Substring(5, 2), 16)

    $script:ColorSuppress = $true
    if (-not $FromHex) { $script:AccentHexBox.Text = $norm }
    $script:RedSlider.Value = $r
    $script:GreenSlider.Value = $g
    $script:BlueSlider.Value = $b
    $script:RedValue.Text = [string]$r
    $script:GreenValue.Text = [string]$g
    $script:BlueValue.Text = [string]$b
    $script:AccentSwatch.Background = Br $norm
    $script:ColorSuppress = $false

    Update-AccentNote
    Refresh-Presets

    if (-not $Silent) {
        Set-Dirty $true
        Request-Preview
    }
    return $true
}

function Normalize-AccentHex {
    $norm = Convert-HexColor $script:AccentHexBox.Text
    if ($norm) {
        $script:ColorSuppress = $true
        $script:AccentHexBox.Text = $norm
        $script:ColorSuppress = $false
        if ($script:Accent -ne $norm) { [void](Set-Accent $norm -FromHex) }
    }
    else {
        $script:AccentNote.Text = 'use #RRGGBB'
        $script:AccentNote.Foreground = Br '#FF6B81'
    }
}

function New-IconButton {
    param([string]$Glyph, [string]$Tip, [string]$Color = '#7B8697')
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $script:Win.FindResource('IconBtn')
    $b.Content = $Glyph
    $b.ToolTip = $Tip
    $b.Width = 26
    $b.Height = 26
    $b.Foreground = Br $Color
    $b
}

function New-ScheduleRow {
    param($Exam)

    $d = Get-DateValue ([string]$Exam.Date)
    $dateLabel = if ($null -ne $d) { $d.ToString('d MMM') } else { '?' }
    $dayLabel = if ($null -ne $d) { $d.ToString('ddd').ToUpper() } else { '' }

    $row = New-Object System.Windows.Controls.Border
    $row.Style = $script:Win.FindResource('ExamRow')
    $row.Tag = $Exam

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
    foreach ($c in @($c0, $c1, $c2, $c3)) { [void]$grid.ColumnDefinitions.Add($c) }

    # date
    $dateStack = New-Object System.Windows.Controls.StackPanel
    $dateStack.Width = 54
    $dateStack.VerticalAlignment = 'Center'
    $dl = Txt $dateLabel 11.5 '#DCE5EE' 'SemiBold'
    $dd = Txt $dayLabel 9 '#6C7784'
    $dd.Margin = Pad 0 1 0 0
    [void]$dateStack.Children.Add($dl)
    [void]$dateStack.Children.Add($dd)
    [System.Windows.Controls.Grid]::SetColumn($dateStack, 0)
    [void]$grid.Children.Add($dateStack)

    # code + title
    $mid = New-Object System.Windows.Controls.StackPanel
    $mid.VerticalAlignment = 'Center'
    $mid.Margin = Pad 6 0 8 0
    $codeTxt = Txt ([string]$Exam.Code) 12 '#F2577C' 'SemiBold'
    $titleTxt = Txt ([string]$Exam.Title) 10.5 '#8894A3'
    $titleTxt.Margin = Pad 0 1 0 0
    [void]$mid.Children.Add($codeTxt)
    [void]$mid.Children.Add($titleTxt)
    [System.Windows.Controls.Grid]::SetColumn($mid, 1)
    [void]$grid.Children.Add($mid)

    # time
    $timeTxt = Txt ([string]$Exam.Time) 10.5 '#7B8697'
    $timeTxt.VerticalAlignment = 'Center'
    $timeTxt.Margin = Pad 0 0 10 0
    [System.Windows.Controls.Grid]::SetColumn($timeTxt, 2)
    [void]$grid.Children.Add($timeTxt)

    # actions
    $actions = New-Object System.Windows.Controls.StackPanel
    $actions.Orientation = 'Horizontal'
    $actions.VerticalAlignment = 'Center'
    $editBtn = New-IconButton ([char]0x270E) 'Edit this exam' '#7B8697'
    $delBtn = New-IconButton ([char]0x2715) 'Remove this exam' '#A05E6B'
    $editBtn.Tag = $Exam
    $delBtn.Tag = $Exam
    $editBtn.Add_Click({ param($s, $e) $e.Handled = $true; Start-Edit $s.Tag })
    $delBtn.Add_Click({ param($s, $e) $e.Handled = $true; Remove-Exam $s.Tag })
    [void]$actions.Children.Add($editBtn)
    [void]$actions.Children.Add($delBtn)
    [System.Windows.Controls.Grid]::SetColumn($actions, 3)
    [void]$grid.Children.Add($actions)

    $row.Child = $grid
    $row.Add_MouseLeftButtonDown({ param($s, $e) Start-Edit $s.Tag })
    $row
}

function Refresh-Schedule {
    $script:ScheduleList.Children.Clear()

    if ($script:Exams.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = "Nothing scheduled.`nAdd an exam above and it appears in the preview instantly."
        $empty.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI'
        $empty.FontSize = 11.5
        $empty.Foreground = Br '#6C7784'
        $empty.TextWrapping = 'Wrap'
        $empty.Margin = Pad 10 14 10 14
        [void]$script:ScheduleList.Children.Add($empty)
    }
    else {
        foreach ($exam in @($script:Exams)) {
            [void]$script:ScheduleList.Children.Add((New-ScheduleRow $exam))
        }
    }

    $countText = if ($script:Exams.Count -eq 0) { 'none' }
        elseif ($script:Exams.Count -eq 1) { '1 upcoming' }
        else { "$($script:Exams.Count) upcoming" }
    $script:ScheduleCount.Text = $countText

    Request-Preview
}

function Sort-Exams {
    $sorted = @($script:Exams | Sort-Object -Property `
            @{ Expression = { Get-ExamDateValue $_ } }, `
            @{ Expression = { [string]$_.Code } })
    $script:Exams.Clear()
    foreach ($x in $sorted) { [void]$script:Exams.Add($x) }
}

function Reset-Form {
    $script:EditingIndex = -1
    $script:DateBox.Text = ''
    $script:StartBox.Text = ''
    $script:EndBox.Text = ''
    $script:CodeBox.Text = ''
    $script:TitleBox.Text = ''
    $script:SectionBox.Text = ''
    $script:RoomBox.Text = ''
    $script:CrnBox.Text = ''
    $script:WeekdayHint.Text = ''
    $script:FormError.Text = ''
    $script:FormTitle.Text = 'ADD EXAM'
    $script:AddBtn.Content = 'Add exam'
    $script:CancelEditBtn.Visibility = 'Collapsed'
}

function Start-Edit {
    param($Exam)
    $idx = $script:Exams.IndexOf($Exam)
    if ($idx -lt 0) { return }

    $script:EditingIndex = $idx
    $script:DateBox.Text = [string]$Exam.Date

    $parts = @([string]$Exam.Time -split '\s*[-\u2013\u2014]\s*')
    $script:StartBox.Text = if ($parts.Count -ge 1) { $parts[0] } else { '' }
    $script:EndBox.Text = if ($parts.Count -ge 2) { $parts[1] } else { '' }

    $script:CodeBox.Text = [string]$Exam.Code
    $script:TitleBox.Text = [string]$Exam.Title
    $script:SectionBox.Text = [string]$Exam.Section
    $script:RoomBox.Text = [string]$Exam.Room
    $script:CrnBox.Text = [string]$Exam.CRN

    $script:FormTitle.Text = 'EDIT EXAM'
    $script:AddBtn.Content = 'Update exam'
    $script:CancelEditBtn.Visibility = 'Visible'
    $script:FormError.Text = ''
    [void]$script:DateBox.Focus()
}

function Remove-Exam {
    param($Exam)
    $idx = $script:Exams.IndexOf($Exam)
    if ($idx -lt 0) { return }

    $label = if ($Exam.Code) { "$($Exam.Code) - $($Exam.Title)" } else { 'this exam' }
    $answer = [System.Windows.MessageBox]::Show(
        $script:Win,
        "Remove $label from the schedule?",
        'Remove exam',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question,
        [System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    if ($script:EditingIndex -eq $idx) { Reset-Form }
    elseif ($script:EditingIndex -gt $idx) { $script:EditingIndex-- }

    $script:Exams.RemoveAt($idx)
    Set-Dirty $true
    Refresh-Schedule
    Set-Status "Removed $($Exam.Code)."
}

function Read-Form {
    $errors = New-Object System.Collections.ArrayList

    $date = Get-DateValue $script:DateBox.Text
    if ($null -eq $date) {
        [void]$errors.Add('Date must be yyyy-mm-dd (e.g. 2026-12-07).')
    }

    $start = $null
    if ([string]::IsNullOrWhiteSpace($script:StartBox.Text)) {
        [void]$errors.Add('Start time is required.')
    }
    else {
        $start = Get-TimeSpanValue $script:StartBox.Text
        if ($null -eq $start) { [void]$errors.Add('Start must be 24-hour, e.g. 11:00.') }
    }

    $end = $null
    if ([string]::IsNullOrWhiteSpace($script:EndBox.Text)) {
        [void]$errors.Add('End time is required.')
    }
    else {
        $end = Get-TimeSpanValue $script:EndBox.Text
        if ($null -eq $end) { [void]$errors.Add('End must be 24-hour, e.g. 13:00.') }
    }

    $code = $script:CodeBox.Text.Trim()
    if (-not $code) { [void]$errors.Add('Course code is required.') }

    $title = $script:TitleBox.Text.Trim()
    if (-not $title) { [void]$errors.Add('Course title is required.') }

    $exam = $null
    if ($errors.Count -eq 0) {
        $timeText = '{0:D2}:{1:D2}-{2:D2}:{3:D2}' -f $start.Hours, $start.Minutes, $end.Hours, $end.Minutes
        $exam = [pscustomobject]@{
            Date    = $date.ToString('yyyy-MM-dd')
            Time    = $timeText
            Code    = $code
            Title   = $title
            Section = $script:SectionBox.Text.Trim()
            Room    = $script:RoomBox.Text.Trim()
            CRN     = $script:CrnBox.Text.Trim()
        }
    }

    [pscustomobject]@{
        Ok     = ($errors.Count -eq 0)
        Errors = @($errors)
        Exam   = $exam
    }
}

function Submit-Form {
    $form = Read-Form
    if (-not $form.Ok) {
        $script:FormError.Text = (@($form.Errors) -join '  ')
        return
    }

    $script:FormError.Text = ''
    $exam = $form.Exam
    $updated = $false

    if ($script:EditingIndex -ge 0 -and $script:EditingIndex -lt $script:Exams.Count) {
        $script:Exams[$script:EditingIndex] = $exam
        $updated = $true
    }
    else {
        [void]$script:Exams.Add($exam)
    }

    Sort-Exams
    Reset-Form
    Set-Dirty $true
    Refresh-Schedule

    if ($updated) {
        Set-Status "Updated $($exam.Code) - $($exam.Date) $($exam.Time)."
    }
    else {
        Set-Status "Added $($exam.Code) on $($exam.Date)."
    }
    [void]$script:DateBox.Focus()
}

function Save-Data {
    try {
        Write-ExamData -Term $script:TermBox.Text.Trim() `
            -TermCode $script:TermCodeBox.Text.Trim() `
            -Accent $script:Accent `
            -Title $script:CardTitleBox.Text.Trim() `
            -Footer $script:CardFooterBox.Text.Trim() `
            -ExamList @($script:Exams)
    }
    catch {
        [System.Windows.MessageBox]::Show(
            $script:Win,
            "Could not save data\exams.json:`n`n$($_.Exception.Message)",
            'Save failed',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
        return $false
    }

    Set-Dirty $false
    Set-Status 'Saved - the desktop widget refreshes within a couple of seconds.'
    return $true
}

function Restart-Widget {
    if ($script:Dirty) {
        if (-not (Save-Data)) { return }
    }

    $widget = Join-Path $script:WidgetRoot 'ExamWidget.ps1'
    $launcher = Join-Path $script:WidgetRoot 'Start Exam Widget.vbs'
    $killed = 0

    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf($widget, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            } |
            ForEach-Object {
                try {
                    Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
                    $killed++
                }
                catch { }
            }
    }
    catch { }

    Start-Sleep -Milliseconds 400

    try {
        Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $launcher + '"') -ErrorAction Stop
    }
    catch {
        Set-Status "Could not launch the widget: $($_.Exception.Message)"
        return
    }

    if ($killed -gt 0) { Set-Status 'Widget restarted.' }
    else { Set-Status 'Widget launched.' }
}

function Test-WidgetRunning {
    $widget = Join-Path $script:WidgetRoot 'ExamWidget.ps1'
    try {
        $hit = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf($widget, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            } |
            Select-Object -First 1
        return ($null -ne $hit)
    }
    catch { return $false }
}

function Start-DesktopLayoutEdit {
    New-Item -ItemType File -Path $script:EditRequestFile -Force | Out-Null
    if (-not (Test-WidgetRunning)) {
        $launcher = Join-Path $script:WidgetRoot 'Start Exam Widget.vbs'
        try { Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $launcher + '"') -WorkingDirectory $script:WidgetRoot } catch { }
    }
    $script:Win.WindowState = 'Minimized'
    Set-Status 'Layout unlocked on the desktop - drag/resize the card, press Esc when done.'
}

function New-DialogButton {
    param(
        [string]$Text,
        [string]$StyleKey = 'Btn'
    )
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $script:Win.FindResource($StyleKey)
    $b.Content = $Text
    $b.Margin = Pad 3 3 3 3
    $b
}

function New-DialogLabel {
    param([string]$Text, [double]$Size = 10.5, [string]$Color = '#8894A3')
    $t = Txt $Text $Size $Color
    $t.Margin = Pad 0 0 0 6
    $t
}

function Save-LayoutDialogSettings {
    Write-Settings -Settings ([pscustomobject]@{ Version = 1; Layout = $script:LayoutDlgLayout })
    Set-Status 'Layout saved - the desktop card updates in a moment.'
}

function Sync-LayoutDialog {
    if (-not $script:LayoutDlgWindow) { return }
    foreach ($key in $script:LayoutDlgPosButtons.Keys) {
        $selected = ($script:LayoutDlgLayout.Mode -eq 'anchor' -and $script:LayoutDlgLayout.Anchor -eq $key)
        $script:LayoutDlgPosButtons[$key].Style = if ($selected) { $script:Win.FindResource('Primary') } else { $script:Win.FindResource('Btn') }
    }
    foreach ($name in $script:LayoutDlgSizeButtons.Keys) {
        $target = [double]$script:LayoutSizePresets[$name]
        $selected = ([math]::Abs($script:LayoutDlgLayout.Scale - $target) -lt 0.011)
        $script:LayoutDlgSizeButtons[$name].Style = if ($selected) { $script:Win.FindResource('Primary') } else { $script:Win.FindResource('Btn') }
    }
    $script:LayoutDlgSuppress = $true
    $script:LayoutDlgSlider.Value = $script:LayoutDlgLayout.Scale
    $script:LayoutDlgSuppress = $false
    $script:LayoutDlgScaleLabel.Text = "$([math]::Round($script:LayoutDlgLayout.Scale * 100))%"
    if ($script:LayoutDlgAutostart) {
        try { $script:LayoutDlgAutostart.IsChecked = Test-Autostart } catch { }
    }
}

function Show-LayoutDialog {
    $script:LayoutDlgLayout = (Read-Settings).Layout
    $script:LayoutDlgRequestDesktop = $false
    $script:LayoutDlgPosButtons = @{}
    $script:LayoutDlgSizeButtons = @{}
    $script:LayoutDlgSuppress = $false

    $dlg = New-Object System.Windows.Window
    $script:LayoutDlgWindow = $dlg
    $dlg.Title = 'Card layout'
    $dlg.Width = 480
    $dlg.SizeToContent = 'Height'
    $dlg.ResizeMode = 'NoResize'
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $script:Win
    $dlg.ShowInTaskbar = $false
    $dlg.Background = Br '#0C1118'
    $dlg.Foreground = Br '#E8EEF5'
    $dlg.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI'

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = Pad 20 18 20 18

    $heading = Txt 'Card layout' 17 '#F3F7FA' 'SemiBold'
    $heading.Margin = Pad 0 0 0 2
    [void]$panel.Children.Add($heading)
    [void]$panel.Children.Add((New-DialogLabel 'Changes apply to the desktop card immediately.'))

    $posLabel = Txt 'POSITION' 10.5 '#8894A3' 'SemiBold'
    $posLabel.Margin = Pad 0 14 0 8
    [void]$panel.Children.Add($posLabel)

    $posGrid = New-Object System.Windows.Controls.Grid
    for ($i = 0; $i -lt 3; $i++) {
        [void]$posGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        [void]$posGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    }
    $arrow = @{
        'top-left' = [string][char]0x2196; 'top-center' = [string][char]0x2191; 'top-right' = [string][char]0x2197
        'middle-left' = [string][char]0x2190; 'center' = [string][char]0x2022; 'middle-right' = [string][char]0x2192
        'bottom-left' = [string][char]0x2199; 'bottom-center' = [string][char]0x2193; 'bottom-right' = [string][char]0x2198
    }
    $anchorNames = @{
        'top-left' = 'Top left'; 'top-center' = 'Top center'; 'top-right' = 'Top right'
        'middle-left' = 'Middle left'; 'center' = 'Center'; 'middle-right' = 'Middle right'
        'bottom-left' = 'Bottom left'; 'bottom-center' = 'Bottom center'; 'bottom-right' = 'Bottom right'
    }
    $coords = [ordered]@{
        'top-left' = @(0, 0); 'top-center' = @(1, 0); 'top-right' = @(2, 0)
        'middle-left' = @(0, 1); 'center' = @(1, 1); 'middle-right' = @(2, 1)
        'bottom-left' = @(0, 2); 'bottom-center' = @(1, 2); 'bottom-right' = @(2, 2)
    }
    foreach ($anchor in $coords.Keys) {
        $b = New-DialogButton $arrow[$anchor]
        $b.Tag = $anchor
        $b.ToolTip = $anchorNames[$anchor]
        $b.FontSize = 15
        $b.MinHeight = 34
        $b.Add_Click({
            param($s, $e)
            $script:LayoutDlgLayout.Mode = 'anchor'
            $script:LayoutDlgLayout.Anchor = [string]$s.Tag
            Save-LayoutDialogSettings
            Sync-LayoutDialog
        })
        $pos = $coords[$anchor]
        [System.Windows.Controls.Grid]::SetColumn($b, [int]($pos[0]))
        [System.Windows.Controls.Grid]::SetRow($b, [int]($pos[1]))
        [void]$posGrid.Children.Add($b)
        $script:LayoutDlgPosButtons[$anchor] = $b
    }
    [void]$panel.Children.Add($posGrid)

    [void]$panel.Children.Add((New-DialogLabel 'Positions use the monitor where the card currently lives.' 9.5 '#5A6472'))

    $sizeLabel = Txt 'SIZE' 10.5 '#8894A3' 'SemiBold'
    $sizeLabel.Margin = Pad 0 8 0 8
    [void]$panel.Children.Add($sizeLabel)

    $sizeRow = New-Object System.Windows.Controls.StackPanel
    $sizeRow.Orientation = 'Horizontal'
    foreach ($name in $script:LayoutSizePresets.Keys) {
        $b = New-DialogButton $name
        $b.Tag = [double]$script:LayoutSizePresets[$name]
        $b.MinWidth = 112
        $b.Add_Click({
            param($s, $e)
            $script:LayoutDlgLayout.Scale = Get-ClampedScale ([double]$s.Tag)
            Save-LayoutDialogSettings
            Sync-LayoutDialog
        })
        [void]$sizeRow.Children.Add($b)
        $script:LayoutDlgSizeButtons[$name] = $b
    }
    [void]$panel.Children.Add($sizeRow)

    $sliderRow = New-Object System.Windows.Controls.Grid
    $sliderRow.Margin = Pad 0 7 0 0
    $sc1 = New-Object System.Windows.Controls.ColumnDefinition; $sc1.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $sc2 = New-Object System.Windows.Controls.ColumnDefinition; $sc2.Width = [System.Windows.GridLength]::Auto
    [void]$sliderRow.ColumnDefinitions.Add($sc1)
    [void]$sliderRow.ColumnDefinitions.Add($sc2)
    $script:LayoutDlgSlider = New-Object System.Windows.Controls.Slider
    $script:LayoutDlgSlider.Style = $script:Win.FindResource('ColorSlider')
    $script:LayoutDlgSlider.Minimum = $script:LayoutScaleMin
    $script:LayoutDlgSlider.Maximum = $script:LayoutScaleMax
    $script:LayoutDlgSlider.VerticalAlignment = 'Center'
    $script:LayoutDlgSlider.Add_ValueChanged({
        if ($script:LayoutDlgSuppress) { return }
        $script:LayoutDlgLayout.Scale = Get-ClampedScale $script:LayoutDlgSlider.Value
        $script:LayoutDlgScaleLabel.Text = "$([math]::Round($script:LayoutDlgLayout.Scale * 100))%"
        Save-LayoutDialogSettings
    })
    [void]$sliderRow.Children.Add($script:LayoutDlgSlider)

    $script:LayoutDlgScaleLabel = Txt '100%' 11 '#E8EEF5' 'SemiBold'
    $script:LayoutDlgScaleLabel.Width = 42
    $script:LayoutDlgScaleLabel.TextAlignment = 'Right'
    $script:LayoutDlgScaleLabel.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($script:LayoutDlgScaleLabel, 1)
    [void]$sliderRow.Children.Add($script:LayoutDlgScaleLabel)
    [void]$panel.Children.Add($sliderRow)

    $script:LayoutDlgAutostart = New-Object System.Windows.Controls.CheckBox
    $script:LayoutDlgAutostart.Content = 'Start with Windows'
    $script:LayoutDlgAutostart.Foreground = Br '#B6C1CE'
    $script:LayoutDlgAutostart.Margin = Pad 0 12 0 0
    $script:LayoutDlgAutostart.Add_Click({
        try { Set-Autostart ([bool]$script:LayoutDlgAutostart.IsChecked) }
        catch { Set-Status 'Could not update autostart.' }
    })
    [void]$panel.Children.Add($script:LayoutDlgAutostart)

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.Margin = Pad 0 18 0 0

    $adjust = New-DialogButton 'Adjust on desktop' 'Primary'
    $adjust.MinWidth = 150
    $adjust.Add_Click({
        $script:LayoutDlgRequestDesktop = $true
        $script:LayoutDlgWindow.Close()
    })
    [void]$buttons.Children.Add($adjust)

    $reset = New-DialogButton 'Reset'
    $reset.Add_Click({
        $monitor = $script:LayoutDlgLayout.Monitor
        $script:LayoutDlgLayout = Get-DefaultLayout
        $script:LayoutDlgLayout.Monitor = $monitor
        Save-LayoutDialogSettings
        Sync-LayoutDialog
    })
    [void]$buttons.Children.Add($reset)

    $close = New-DialogButton 'Close'
    $close.Add_Click({ $script:LayoutDlgWindow.Close() })
    [void]$buttons.Children.Add($close)

    [void]$panel.Children.Add($buttons)
    $dlg.Content = $panel
    Sync-LayoutDialog
    [void]$dlg.ShowDialog()

    $requestDesktop = $script:LayoutDlgRequestDesktop
    $script:LayoutDlgWindow = $null
    $script:LayoutDlgPosButtons = $null
    $script:LayoutDlgSizeButtons = $null
    $script:LayoutDlgAutostart = $null
    $script:LayoutDlgSlider = $null
    $script:LayoutDlgScaleLabel = $null
    if ($requestDesktop) { Start-DesktopLayoutEdit }
}

# ---------------------------------------------------------------------------
# Export dialog
# ---------------------------------------------------------------------------
function Sync-ExportDialog {
    if (-not $script:ExportDlgWindow) { return }
    foreach ($key in $script:ExportFormatButtons.Keys) {
        $script:ExportFormatButtons[$key].Style = if ($script:ExportDlgFormat -eq $key) { $script:Win.FindResource('Primary') } else { $script:Win.FindResource('Btn') }
    }
    foreach ($key in $script:ExportStyleButtons.Keys) {
        $script:ExportStyleButtons[$key].Style = if ($script:ExportDlgStyle -eq $key) { $script:Win.FindResource('Primary') } else { $script:Win.FindResource('Btn') }
    }
    foreach ($key in $script:ExportPageButtons.Keys) {
        $script:ExportPageButtons[$key].Style = if ($script:ExportDlgPage -eq $key) { $script:Win.FindResource('Primary') } else { $script:Win.FindResource('Btn') }
        $script:ExportPageButtons[$key].IsEnabled = ($script:ExportDlgFormat -eq 'pdf')
    }
    $script:ExportPageHint.Text = if ($script:ExportDlgFormat -eq 'pdf') { 'PDF page size' } else { 'Page size is used by PDF only' }
    $script:ExportPageHint.Foreground = Br $(if ($script:ExportDlgFormat -eq 'pdf') { '#8894A3' } else { '#4E5865' })
}

function Export-CurrentRoutine {
    $format = $script:ExportDlgFormat
    $style = $script:ExportDlgStyle
    $page = $script:ExportDlgPage

    $term = $script:TermBox.Text.Trim()
    $slug = ($term -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'exam-routine' }
    else { $slug = "exam-routine-$slug" }

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = 'Export exam routine'
    $dialog.Filter = if ($format -eq 'png') { 'PNG image (*.png)|*.png' } else { 'PDF document (*.pdf)|*.pdf' }
    $dialog.DefaultExt = $format
    $dialog.FileName = "$slug.$format"
    if ($dialog.ShowDialog($script:Win) -ne $true) { return }

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        Export-Routine -Path $dialog.FileName -Format $format -Style $style -Page $page `
            -ExamList @($script:Exams) `
            -TermText $script:TermBox.Text.Trim() `
            -TermCodeText $script:TermCodeBox.Text.Trim() `
            -Accent $script:Accent `
            -TitleText $script:CardTitleBox.Text.Trim() `
            -FooterText $script:CardFooterBox.Text.Trim()
        Set-Status "Exported $($dialog.FileName)"
        $script:ExportDlgWindow.Close()
    }
    catch {
        [System.Windows.MessageBox]::Show($script:Win, "Export failed:`n`n$($_.Exception.Message)", 'Export failed',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
    finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
}

function Show-ExportDialog {
    $script:ExportDlgFormat = 'png'
    $script:ExportDlgStyle = 'print'
    $script:ExportDlgPage = 'a4'
    $script:ExportFormatButtons = @{}
    $script:ExportStyleButtons = @{}
    $script:ExportPageButtons = @{}

    $dlg = New-Object System.Windows.Window
    $script:ExportDlgWindow = $dlg
    $dlg.Title = 'Export routine'
    $dlg.Width = 470
    $dlg.SizeToContent = 'Height'
    $dlg.ResizeMode = 'NoResize'
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $script:Win
    $dlg.ShowInTaskbar = $false
    $dlg.Background = Br '#0C1118'
    $dlg.Foreground = Br '#E8EEF5'
    $dlg.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI'

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = Pad 20 18 20 18

    $heading = Txt 'Export routine' 17 '#F3F7FA' 'SemiBold'
    [void]$panel.Children.Add($heading)
    [void]$panel.Children.Add((New-DialogLabel 'Uses the current editor content, including unsaved changes.'))

    $fmtLabel = Txt 'FORMAT' 10.5 '#8894A3' 'SemiBold'
    $fmtLabel.Margin = Pad 0 12 0 6
    [void]$panel.Children.Add($fmtLabel)
    $fmtRow = New-Object System.Windows.Controls.StackPanel
    $fmtRow.Orientation = 'Horizontal'
    foreach ($fmt in @('png', 'pdf')) {
        $b = New-DialogButton $fmt.ToUpperInvariant()
        $b.Tag = $fmt
        $b.MinWidth = 110
        $b.Add_Click({
            param($s, $e)
            $script:ExportDlgFormat = [string]$s.Tag
            Sync-ExportDialog
        })
        [void]$fmtRow.Children.Add($b)
        $script:ExportFormatButtons[$fmt] = $b
    }
    [void]$panel.Children.Add($fmtRow)

    $styleLabel = Txt 'STYLE' 10.5 '#8894A3' 'SemiBold'
    $styleLabel.Margin = Pad 0 12 0 6
    [void]$panel.Children.Add($styleLabel)
    $styleRow = New-Object System.Windows.Controls.StackPanel
    $styleRow.Orientation = 'Horizontal'
    foreach ($styleKey in @('print', 'desktop')) {
        $text = if ($styleKey -eq 'print') { 'Print (light)' } else { 'Desktop (dark)' }
        $b = New-DialogButton $text
        $b.Tag = $styleKey
        $b.MinWidth = 140
        $b.Add_Click({
            param($s, $e)
            $script:ExportDlgStyle = [string]$s.Tag
            Sync-ExportDialog
        })
        [void]$styleRow.Children.Add($b)
        $script:ExportStyleButtons[$styleKey] = $b
    }
    [void]$panel.Children.Add($styleRow)

    $pageLabel = Txt 'PAGE' 10.5 '#8894A3' 'SemiBold'
    $pageLabel.Margin = Pad 0 12 0 6
    [void]$panel.Children.Add($pageLabel)
    $pageRow = New-Object System.Windows.Controls.StackPanel
    $pageRow.Orientation = 'Horizontal'
    foreach ($pageKey in @('a4', 'card')) {
        $text = if ($pageKey -eq 'a4') { 'A4' } else { 'Card size' }
        $b = New-DialogButton $text
        $b.Tag = $pageKey
        $b.MinWidth = 110
        $b.Add_Click({
            param($s, $e)
            $script:ExportDlgPage = [string]$s.Tag
            Sync-ExportDialog
        })
        [void]$pageRow.Children.Add($b)
        $script:ExportPageButtons[$pageKey] = $b
    }
    [void]$panel.Children.Add($pageRow)

    $script:ExportPageHint = New-DialogLabel 'Page size is used by PDF only' 9.5 '#4E5865'
    $script:ExportPageHint.Margin = Pad 0 4 0 0
    [void]$panel.Children.Add($script:ExportPageHint)

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.Margin = Pad 0 18 0 0

    $export = New-DialogButton 'Export...' 'Primary'
    $export.MinWidth = 140
    $export.Add_Click({ Export-CurrentRoutine })
    [void]$buttons.Children.Add($export)

    $cancel = New-DialogButton 'Cancel'
    $cancel.Add_Click({ $script:ExportDlgWindow.Close() })
    [void]$buttons.Children.Add($cancel)

    [void]$panel.Children.Add($buttons)
    $dlg.Content = $panel
    Sync-ExportDialog
    [void]$dlg.ShowDialog()

    $script:ExportDlgWindow = $null
    $script:ExportFormatButtons = $null
    $script:ExportStyleButtons = $null
    $script:ExportPageButtons = $null
}


# ---------------------------------------------------------------------------
# Load exams.json
# ---------------------------------------------------------------------------
$data = Read-ExamData
$upcoming = @(Select-UpcomingExams $data.Exams)
$script:RemovedOnLoad = $data.Exams.Count - $upcoming.Count

if ($script:RemovedOnLoad -gt 0) {
    # Finished exams are dropped from the file as soon as the editor opens.
    Write-ExamData -Term $data.Term -TermCode $data.TermCode -Accent $data.Accent `
        -Title $data.Title -Footer $data.Footer -ExamList $upcoming
}

foreach ($x in $upcoming) { [void]$script:Exams.Add($x) }

$script:Suppress = $true
$script:TermBox.Text = $data.Term
$script:TermCodeBox.Text = $data.TermCode
$script:CardTitleBox.Text = $data.Title
$script:CardFooterBox.Text = $data.Footer
$script:Suppress = $false

$script:Accent = $data.Accent
if (-not (Convert-HexColor $script:Accent)) { $script:Accent = '#F2577C' }
[void](Set-Accent $script:Accent -Silent)

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
$script:PreviewTimer.Add_Tick({
    $script:PreviewTimer.Stop()
    Update-Preview
})

$script:TermBox.Add_TextChanged({
    if ($script:Suppress) { return }
    Set-Dirty $true
    Request-Preview
})

$script:TermCodeBox.Add_TextChanged({
    if ($script:Suppress) { return }
    Set-Dirty $true
    Request-Preview
})

$script:CardTitleBox.Add_TextChanged({
    if ($script:Suppress) { return }
    Set-Dirty $true
    Request-Preview
})

$script:CardFooterBox.Add_TextChanged({
    if ($script:Suppress) { return }
    Set-Dirty $true
    Request-Preview
})

$script:DateBox.Add_TextChanged({
    $d = Get-DateValue $script:DateBox.Text
    if ($null -ne $d) { $script:WeekdayHint.Text = $d.ToString('dddd').ToUpper() }
    else { $script:WeekdayHint.Text = '' }
})

foreach ($slider in @($script:RedSlider, $script:GreenSlider, $script:BlueSlider)) {
    $slider.Add_ValueChanged({
        if ($script:ColorSuppress) { return }
        [void](Set-Accent (Read-SliderAccent))
    })
}

$script:AccentHexBox.Add_TextChanged({
    if ($script:ColorSuppress) { return }
    $norm = Convert-HexColor $script:AccentHexBox.Text
    if ($norm) { [void](Set-Accent $norm -FromHex) }
})

$script:AccentHexBox.Add_LostFocus({ Normalize-AccentHex })

$script:AccentHexBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        Normalize-AccentHex
        $e.Handled = $true
    }
})

$script:AddBtn.Add_Click({ Submit-Form })
$script:CancelEditBtn.Add_Click({ Reset-Form })
$script:SaveBtn.Add_Click({ [void](Save-Data) })
$script:RestartBtn.Add_Click({ Restart-Widget })
$script:LayoutBtn.Add_Click({ Show-LayoutDialog })
$script:ExportBtn.Add_Click({ Show-ExportDialog })

$script:Win.Add_KeyDown({
    param($s, $e)
    if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
        if ($e.Key -eq [System.Windows.Input.Key]::S) {
            [void](Save-Data)
            $e.Handled = $true
        }
        elseif ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            Submit-Form
            $e.Handled = $true
        }
    }
})

$script:Win.Add_Closing({
    param($s, $e)
    if (-not $script:Dirty) { return }
    $answer = [System.Windows.MessageBox]::Show(
        $script:Win,
        'Save your changes before closing?',
        'Unsaved changes',
        [System.Windows.MessageBoxButton]::YesNoCancel,
        [System.Windows.MessageBoxImage]::Question,
        [System.Windows.MessageBoxResult]::Yes)

    if ($answer -eq [System.Windows.MessageBoxResult]::Cancel) {
        $e.Cancel = $true
    }
    elseif ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
        if (-not (Save-Data)) { $e.Cancel = $true }
    }
})

$script:Win.Add_Loaded({ [void]$script:DateBox.Focus() })

# Drop exams that finish while the editor is open.
$pruneTimer = New-Object System.Windows.Threading.DispatcherTimer
$pruneTimer.Interval = [TimeSpan]::FromSeconds(30)
$pruneTimer.Add_Tick({
    $now = Get-Date
    $removed = 0
    for ($i = $script:Exams.Count - 1; $i -ge 0; $i--) {
        if (Test-ExamDone $script:Exams[$i] $now) {
            if ($script:EditingIndex -eq $i) { Reset-Form }
            elseif ($script:EditingIndex -gt $i) { $script:EditingIndex-- }
            $script:Exams.RemoveAt($i)
            $removed++
        }
    }
    if ($removed -gt 0) {
        Refresh-Schedule
        Set-Status "Removed $removed finished exam(s) automatically."
    }
})
$pruneTimer.Start()

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------
Set-Dirty $false
Refresh-Schedule

if ($script:RemovedOnLoad -gt 0) {
    Set-Status "Removed $($script:RemovedOnLoad) finished exam(s) automatically."
}
elseif (-not (Test-Path -LiteralPath $script:DataFile)) {
    Set-Status 'No exams.json yet - add an exam and save to create it.'
}
else {
    Set-Status 'Ready.'
}

# Dev helper: render the window to a PNG and exit.
if ($SnapshotPath) {
    $snapTimer = New-Object System.Windows.Threading.DispatcherTimer
    $snapTimer.Interval = [TimeSpan]::FromMilliseconds(900)
    $snapTimer.Add_Tick({
        $snapTimer.Stop()
        try {
            $root = $script:Win.Content
            $w = [int][math]::Ceiling($root.ActualWidth)
            $h = [int][math]::Ceiling($root.ActualHeight)
            $rtb = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
                $w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
            $rtb.Render($root)
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs = [System.IO.File]::Create($SnapshotPath)
            $enc.Save($fs)
            $fs.Close()
        }
        finally {
            $script:Win.Close()
        }
    })
    $snapTimer.Start()
}

[void]$script:Win.ShowDialog()
