param([switch]$AutoStart, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'Ryujin-Usb.ps1')
. (Join-Path $PSScriptRoot 'Ryujin-Storage.ps1')

[xml]$layout = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Ryujin LCD" Width="850" Height="680" MinWidth="720" MinHeight="620"
        Background="#101727" Foreground="#F1F5FA" FontFamily="Segoe UI"
        WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="18,9"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Grid Margin="26">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="65"/>
    </Grid.RowDefinitions>
    <DockPanel Margin="0,0,0,16">
      <Button Name="Storage" DockPanel.Dock="Right" Content="LCD storage..." Background="#DCE6F7"/>
      <TextBlock Text="Ryujin LCD" FontSize="28" FontWeight="SemiBold"/>
    </DockPanel>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
      <Border Background="#080D18" BorderBrush="#26354C" BorderThickness="1"
            CornerRadius="10" ClipToBounds="True">
      <Viewbox Stretch="Uniform">
      <Canvas Width="320" Height="240" ClipToBounds="True" Background="#080D18">
        <TextBlock Name="Placeholder" Text="Select an MP4 or GIF" Foreground="#AFBDD2"
                   Canvas.Top="110" Canvas.Left="12"/>
        <Image Name="GifPreview" Stretch="Uniform"/>
        <MediaElement Name="Preview" LoadedBehavior="Manual" UnloadedBehavior="Close"
                      Stretch="Uniform" Volume="0" ScrubbingEnabled="True"/>
      </Canvas>
      </Viewbox>
    </Border>
    <DockPanel Grid.Column="1" Margin="18,0,0,0">
      <TextBlock DockPanel.Dock="Top" Text="Playback order" FontWeight="SemiBold" Margin="0,0,0,8"/>
      <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
        <Button Name="Up" Content="Up"/>
        <Button Name="Down" Content="Down" Margin="6,0"/>
        <Button Name="Remove" Content="Remove"/>
      </StackPanel>

      <ListBox Name="Queue" Background="#080D18" Foreground="#F1F5FA" BorderBrush="#26354C" DisplayMemberPath="Name"/>
    </DockPanel>
    </Grid>
    <WrapPanel Grid.Row="2" Margin="0,16,0,8">
      <Button Name="Choose" Content="Add MP4 / GIF" Background="#DCE6F7" Margin="0,0,8,8"/>
      <Button Name="Toggle" Content="Pause" Margin="0,0,8,8" IsEnabled="False"/>
      <Button Name="Send" Content="Upload &amp; play" Background="#3DE0CB" Margin="0,0,8,8" IsEnabled="False"/>
      <Button Name="Stop" Content="Stop rotation" Background="#DCE6F7" Margin="0,0,0,8" IsEnabled="False"/>
    </WrapPanel>
    <StackPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" Margin="0,8,0,6">
        <TextBlock Text="LCD framing" Foreground="#AFBDD2" VerticalAlignment="Center" Margin="0,0,12,0"/>
        <ComboBox Name="Framing" Width="270" SelectedIndex="1">
          <ComboBoxItem Content="Fit - keep entire image"/>
          <ComboBoxItem Content="Fill - crop to cover screen"/>
          <ComboBoxItem Content="Stretch - resize to screen"/>
        </ComboBox>
      </StackPanel>
      <Grid Name="CropControls" Margin="0,4,0,6">
        <Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="100"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
        <TextBlock Text="Horizontal" Foreground="#AFBDD2" VerticalAlignment="Center"/>
        <Slider Name="CropX" Grid.Column="1" Minimum="0" Maximum="100" Value="50" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,5"/>
        <TextBlock Grid.Row="1" Text="Vertical" Foreground="#AFBDD2" VerticalAlignment="Center"/>
        <Slider Name="CropY" Grid.Row="1" Grid.Column="1" Minimum="0" Maximum="100" Value="50" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,5"/>
        <Button Name="CenterCrop" Grid.Column="2" Grid.RowSpan="2" Content="Center" Margin="12,0,0,0"/>
      </Grid>
      <CheckBox Name="Startup" Foreground="#AFBDD2" Margin="0,8,0,12" Content="Start playlist when I sign in to Windows"/>
    </StackPanel>
    <TextBlock Grid.Row="4" Name="Status" Foreground="#AFBDD2" TextWrapping="Wrap"
               Text="Add files and arrange them in playback order."/>
  </Grid>
</Window>
"@
$window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($layout))
$preview = $window.FindName('Preview')
$choose = $window.FindName('Choose')
$toggle = $window.FindName('Toggle')
$send = $window.FindName('Send')
$stop = $window.FindName('Stop')
$status = $window.FindName('Status')
$placeholder = $window.FindName('Placeholder')
$queue = $window.FindName('Queue')
$gifPreview = $window.FindName('GifPreview')
$up = $window.FindName('Up')
$down = $window.FindName('Down')
$remove = $window.FindName('Remove')
$state = @{
    Process = $null; Task = $null; Temp = $null; Paused = $false; Attempt = 0
    Running = $false; Stop = $false; Index = 0; Slots = @{}; Phase = ''; Next = $null
}
$presets = @(
    @{ Fps = 10; Colors = 64 },
    @{ Fps = 8; Colors = 32 },
    @{ Fps = 6; Colors = 16 },
    @{ Fps = 5; Colors = 16 },
    @{ Fps = 4; Colors = 8 },
    @{ Fps = 3; Colors = 8 }
)

$appData = Join-Path $env:LOCALAPPDATA 'RyujinLCD'
$mediaCache = Join-Path $appData 'prepared'
$playlistPath = Join-Path $appData 'playlist.json'
$startup = $window.FindName('Startup')
$framing = $window.FindName('Framing')
$state.Framing = 'Fill'
$cropX = $window.FindName('CropX')
$cropY = $window.FindName('CropY')
$cropControls = $window.FindName('CropControls')
$centerCrop = $window.FindName('CenterCrop')
$state.Crops = @{}
$state.LoadingCrop = $false
$storageButton = $window.FindName('Storage')
$state.OpenStorage = $false
$taskName = 'RyujinLCD-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$state.Exit = $false

function Save-Playlist {
    [void][IO.Directory]::CreateDirectory($appData)
    $data = @{ Files = @($queue.Items | ForEach-Object { $_.Path }); Slots = $state.Slots; Framing = $state.Framing; Crops = $state.Crops }
    $temp = Join-Path $appData ('playlist-' + [Guid]::NewGuid() + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, ($data | ConvertTo-Json), [Text.Encoding]::UTF8)
        if (Test-Path -LiteralPath $playlistPath) {
            $backup = $temp + '.bak'
            [IO.File]::Replace($temp, $playlistPath, $backup)
            Remove-Item -LiteralPath $backup -ErrorAction SilentlyContinue
        }
        else { [IO.File]::Move($temp, $playlistPath) }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
    }
}

function Start-Upload {
    $status.Text = "Uploading $($queue.Items[$state.Index].Name)..."
    $state.Phase = 'Upload'
    $state.Task = [RyujinLcd]::UploadAsync($state.Hid, $state.Usb, [IO.File]::ReadAllBytes($state.Temp))
}

function Get-MediaKey($entry) {
    if ($state.Framing -eq 'Fit') { return $entry.Key }
    if ($state.Framing -eq 'Fill') {
        $crop = Get-Crop $entry
        if ($crop.X -ne 50 -or $crop.Y -ne 50) {
            return $entry.Key + '|framing=Fill|x=' + $crop.X + '|y=' + $crop.Y
        }
    }
    return $entry.Key + '|framing=' + $state.Framing
}

function Get-Crop($entry) {
    if ($entry -and $state.Crops.ContainsKey($entry.Key)) { return $state.Crops[$entry.Key] }
    return @{ X = 50; Y = 50 }
}

function Update-Framing {
    $cropControls.IsEnabled = !$state.Running -and $state.Framing -eq 'Fill'
    $element = $preview
    $width = $preview.NaturalVideoWidth
    $height = $preview.NaturalVideoHeight
    if ($queue.SelectedItem -and [IO.Path]::GetExtension($queue.SelectedItem.Path) -eq '.gif') {
        $element = $gifPreview
        $width = if ($gifPreview.Source) { $gifPreview.Source.PixelWidth } else { 0 }
        $height = if ($gifPreview.Source) { $gifPreview.Source.PixelHeight } else { 0 }
    }
    $preview.Stretch = 'Fill'
    $gifPreview.Stretch = 'Fill'
    if ($width -le 0 -or $height -le 0) { $width = 320; $height = 240 }
    if ($state.Framing -eq 'Stretch') { $drawWidth = 320.0; $drawHeight = 240.0 }
    else {
        $scale = if ($state.Framing -eq 'Fill') { [Math]::Max(320.0 / $width, 240.0 / $height) }
                 else { [Math]::Min(320.0 / $width, 240.0 / $height) }
        $drawWidth = $width * $scale
        $drawHeight = $height * $scale
    }
    $crop = Get-Crop $queue.SelectedItem
    $x = if ($state.Framing -eq 'Fill') { (320 - $drawWidth) * $crop.X / 100.0 } else { (320 - $drawWidth) / 2.0 }
    $y = if ($state.Framing -eq 'Fill') { (240 - $drawHeight) * $crop.Y / 100.0 } else { (240 - $drawHeight) / 2.0 }
    $element.Width = $drawWidth
    $element.Height = $drawHeight
    [Windows.Controls.Canvas]::SetLeft($element, $x)
    [Windows.Controls.Canvas]::SetTop($element, $y)
}

function Set-Startup([bool]$enabled) {
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')
    if (!$enabled) { $folder.DeleteTask($taskName, 0); return }
    $exe = $env:RYUJIN_EXE
    if (!$exe -or !(Test-Path -LiteralPath $exe)) { throw 'Enable startup from the EXE application.' }
    $definition = $scheduler.NewTask(0)
    $definition.RegistrationInfo.Description = 'Resume the saved Ryujin LCD playlist at user sign-in.'
    $definition.Principal.UserId = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $definition.Principal.LogonType = 3
    $definition.Principal.RunLevel = 1
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.ExecutionTimeLimit = 'PT0S'
    $definition.Settings.MultipleInstances = 2
    $definition.Settings.StartWhenAvailable = $true
    $trigger = $definition.Triggers.Create(9)
    $trigger.UserId = $definition.Principal.UserId
    $trigger.Delay = 'PT20S'
    $action = $definition.Actions.Create(0)
    $action.Path = $exe
    $action.Arguments = '--autostart'
    $action.WorkingDirectory = [IO.Path]::GetDirectoryName($exe)
    [void]$folder.RegisterTaskDefinition($taskName, $definition, 6, $definition.Principal.UserId, $null, 3, $null)
}

function Find-FFmpeg {
    if ($env:RYUJIN_FFMPEG -and (Test-Path -LiteralPath $env:RYUJIN_FFMPEG -PathType Leaf)) {
        return $env:RYUJIN_FFMPEG
    }
    $local = Join-Path $PSScriptRoot 'ffmpeg.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $command = Get-Command ffmpeg.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $folder = Get-ChildItem -LiteralPath $packages -Directory -Filter 'Gyan.FFmpeg_*' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($folder) {
        $exe = Get-ChildItem -LiteralPath $folder.FullName -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    throw 'FFmpeg not found. Install it with: winget install --id Gyan.FFmpeg -e'
}

function Clear-Operation {
    if ($state.Process) { $state.Process.Dispose() }
    $state.Process = $null
    $state.Task = $null
    $state.Temp = $null
    $state.Running = $false
    $state.Stop = $false
    $state.Next = $null
    $choose.IsEnabled = $true
    $framing.IsEnabled = $true
    Update-Framing
    $up.IsEnabled = $true
    $down.IsEnabled = $true
    $remove.IsEnabled = $true
    $stop.IsEnabled = $false
    $send.IsEnabled = $queue.Items.Count -gt 0
}
function Get-PreparedPrefix {
    [void][IO.Directory]::CreateDirectory($mediaCache)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($state.Key))).Replace('-', '') }
    finally { $sha.Dispose() }
    return Join-Path $mediaCache $hash
}

function Start-Conversion {
    $state.Temp = (Get-PreparedPrefix) + '-' + $state.Attempt + '.gif'
    if (Test-Path -LiteralPath $state.Temp) { Start-Upload; return }
    $preset = $presets[$state.Attempt]
    $geometry = switch ($state.Framing) {
        'Fit' { 'scale=320:240:force_original_aspect_ratio=decrease,pad=320:240:(ow-iw)/2:(oh-ih)/2' }
        'Fill' {
            $crop = Get-Crop $queue.Items[$state.Index]
            $x = ([double]$crop.X / 100).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
            $y = ([double]$crop.Y / 100).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
            'scale=320:240:force_original_aspect_ratio=increase,crop=320:240:(iw-ow)*' + $x + ':(ih-oh)*' + $y
        }
        'Stretch' { 'scale=320:240' }
    }
    $filter = "fps=$($preset.Fps),$geometry,setsar=1,split[a][b];[a]palettegen=max_colors=$($preset.Colors)[p];[b][p]paletteuse=dither=bayer"
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $state.FFmpeg
    $info.Arguments = '-hide_banner -loglevel error -nostdin -y -filter_complex_threads 1 -i "' +
        $state.Video + '" -filter_complex "' + $filter + '" -an -loop 0 -f gif "' + $state.Temp + '.partial"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardError = $true
    $state.Process = [Diagnostics.Process]::Start($info)
    $state.Errors = $state.Process.StandardError.ReadToEndAsync()
    $status.Text = "Preparing 320 x 240 animation at $($preset.Fps) FPS..."
}

function Start-Item {
    $entry = $queue.Items[$state.Index]
    $state.Video = $entry.Path
    $state.Key = Get-MediaKey $entry
    $probe = Join-Path ([IO.Path]::GetDirectoryName($state.FFmpeg)) 'ffprobe.exe'
    if (!(Test-Path -LiteralPath $probe)) {
        $probeCommand = Get-Command ffprobe.exe -CommandType Application -ErrorAction SilentlyContinue
        if (!$probeCommand) { throw 'ffprobe.exe is required alongside ffmpeg.exe to read clip duration.' }
        $probe = $probeCommand.Source
    }
    $probeInfo = [Diagnostics.ProcessStartInfo]::new()
    $probeInfo.FileName = $probe
    $probeInfo.Arguments = '-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $state.Video + '"'
    $probeInfo.UseShellExecute = $false
    $probeInfo.CreateNoWindow = $true
    $probeInfo.RedirectStandardOutput = $true
    $probeInfo.RedirectStandardError = $true
    $probeProcess = [Diagnostics.Process]::Start($probeInfo)
    $probeOutput = $probeProcess.StandardOutput.ReadToEndAsync()
    $probeError = $probeProcess.StandardError.ReadToEndAsync()
    try {
        if (!$probeProcess.WaitForExit(10000)) {
            $probeProcess.Kill()
            throw 'Reading clip duration timed out.'
        }
        $duration = 0.0
        if ($probeProcess.ExitCode -ne 0 -or
            ![double]::TryParse($probeOutput.GetAwaiter().GetResult().Trim(),
                [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration) -or
            [double]::IsNaN($duration) -or [double]::IsInfinity($duration) -or $duration -le 0) {
            throw 'The duration of this media file could not be read.'
        }
        $state.Duration = $duration
    } finally { $probeProcess.Dispose() }
    $state.Attempt = 0
    $prefix = Get-PreparedPrefix
    $paths = [string[]]@(0..($presets.Count - 1) | ForEach-Object { $prefix + '-' + $_ + '.gif' })
    $preferred = if ($state.Slots.ContainsKey($state.Key)) { [int]$state.Slots[$state.Key] } else { -1 }
    $state.Phase = 'Lookup'
    $status.Text = 'Checking whether this animation is already stored on the LCD...'
    $state.Task = [RyujinLcd]::FindExistingAsync($state.Hid, $preferred, $paths)
}

function Start-Playback([int]$slot) {
    $state.Phase = 'Play'

    $state.Task = [RyujinLcd]::PlayAsync($state.Hid, $slot)
    $status.Text = "LCD: $($state.Index + 1) / $($queue.Items.Count) - $($queue.Items[$state.Index].Name)"
}

function Move-Selection([int]$offset) {
    $index = $queue.SelectedIndex
    $target = $index + $offset
    if ($index -lt 0 -or $target -lt 0 -or $target -ge $queue.Items.Count) { return }
    $entry = $queue.Items[$index]
    $queue.Items.RemoveAt($index)
    $queue.Items.Insert($target, $entry)
    $queue.SelectedIndex = $target
    Save-Playlist
}

$queue.Add_SelectionChanged({
    $preview.Close()
    $gifPreview.Source = $null
    $toggle.IsEnabled = $false
    $entry = $queue.SelectedItem
    $crop = Get-Crop $entry
    $state.LoadingCrop = $true
    $cropX.Value = $crop.X
    $cropY.Value = $crop.Y
    $state.LoadingCrop = $false
    if (!$entry) { $placeholder.Visibility = 'Visible'; return }
    $placeholder.Visibility = 'Collapsed'
    if ([IO.Path]::GetExtension($entry.Path) -eq '.gif') {
        $preview.Visibility = 'Collapsed'
        $gifPreview.Visibility = 'Visible'
        try {
            $image = [Windows.Media.Imaging.BitmapImage]::new()
            $image.BeginInit()
            $image.CacheOption = 'OnLoad'
            $image.UriSource = [Uri]::new($entry.Path)
            $image.EndInit()
            $gifPreview.Source = $image
        } catch { $status.Text = 'GIF preview could not be loaded.' }
    } else {
        $preview.Visibility = 'Visible'
        $gifPreview.Visibility = 'Collapsed'
        $preview.Source = [Uri]::new($entry.Path)
        $state.Paused = $false
        $preview.Play()
        $toggle.Content = 'Pause'
        $toggle.IsEnabled = $true
    }
    Update-Framing
})
$choose.Add_Click({
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Filter = 'MP4 and GIF (*.mp4;*.gif)|*.mp4;*.gif'
    $dialog.Multiselect = $true
    if (!$dialog.ShowDialog($window)) { return }
    foreach ($file in $dialog.FileNames) {
        if ($queue.Items.Count -ge 10) { break }
        $media = Get-Item -LiteralPath $file
        if (@($queue.Items | Where-Object Path -eq $media.FullName).Count) { continue }
        [void]$queue.Items.Add([pscustomobject]@{
            Path = $media.FullName; Name = $media.Name
            Key = "$($media.FullName)|$($media.Length)|$($media.LastWriteTimeUtc.Ticks)"
        })
        $queue.SelectedIndex = $queue.Items.Count - 1
    }
    if ($queue.SelectedIndex -lt 0) { $queue.SelectedIndex = 0 }
    Save-Playlist
    $send.IsEnabled = $queue.Items.Count -gt 0
    $status.Text = 'File list saved. Select an item and use Upload & play to show it now.'
})
$up.Add_Click({ Move-Selection -1 })
$down.Add_Click({ Move-Selection 1 })
$remove.Add_Click({
    $index = $queue.SelectedIndex
    if ($index -ge 0) {
        $queue.Items.RemoveAt($index)
        if ($queue.Items.Count) { $queue.SelectedIndex = [Math]::Min($index, $queue.Items.Count - 1) }
    }
    $send.IsEnabled = $queue.Items.Count -gt 0
    Save-Playlist
})
$preview.Add_MediaEnded({ if (!$state.Paused) { $preview.Position = [TimeSpan]::Zero; $preview.Play() } })
$preview.Add_MediaOpened({ Update-Framing })
$preview.Add_MediaFailed({ if (!$state.Running) { $status.Text = 'Windows could not preview this file.' } })
$toggle.Add_Click({
    $state.Paused = !$state.Paused
    if ($state.Paused) { $preview.Pause(); $toggle.Content = 'Play' }
    else { $preview.Play(); $toggle.Content = 'Pause' }
})
$send.Add_Click({
    if ($state.Task -or $state.Process -or $state.Stop) {
        $status.Text = 'The current LCD operation is still in progress.'
        return
    }
    try {
        $state.FFmpeg = Find-FFmpeg
        $state.Hid = Get-InterfacePath 'HID\VID_0B05&PID_1AA2&MI_01' '4d1e55b2-f16f-11cf-88cb-001111000030'
        $state.Usb = Get-InterfacePath 'USB\VID_0B05&PID_1AA2&MI_00' '53e99217-6a72-4b4f-8385-07c455b7b7a8'
        $state.Index = [Math]::Max(0, $queue.SelectedIndex)
        $state.Next = $null
        $state.Stop = $false
        $state.Running = $true
        $up.IsEnabled = $down.IsEnabled = $remove.IsEnabled = $false
        $framing.IsEnabled = $false
        $cropControls.IsEnabled = $false
        $send.IsEnabled = $false
        $stop.IsEnabled = $true
        Start-Item
    } catch { $status.Text = $_.Exception.GetBaseException().Message; Clear-Operation }
})
$stop.Add_Click({
    $state.Stop = $true
    $send.IsEnabled = $false
    $stop.IsEnabled = $false
    $status.Text = 'Stopping after the current LCD operation finishes...'
})

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $send.IsEnabled = $queue.Items.Count -gt 0 -and !$state.Task -and !$state.Process -and !$state.Stop
    $stop.IsEnabled = $state.Running -and !$state.Stop
    if (!$state.Running) { return }
    try {
        if ($state.Task -and $state.Task.IsCompleted) {
            $result = $state.Task.GetAwaiter().GetResult()
            $state.Task = $null
            if ($state.Phase -eq 'Lookup') {
                if (!$state.Stop) {
                    if ([int]$result -ge 0) {
                        $state.Slots[$state.Key] = [int]$result
                        Save-Playlist
                        Start-Playback ([int]$result)
                    } else {
                        $state.Slots.Remove($state.Key)
                        Start-Conversion
                    }
                }
            } elseif ($state.Phase -eq 'Upload') {
                foreach ($key in @($state.Slots.Keys)) {
                    if ($key -ne $state.Key -and $state.Slots[$key] -eq [int]$result) { $state.Slots.Remove($key) }
                }
                $state.Slots[$state.Key] = [int]$result
                Save-Playlist
                $state.Temp = $null
                if (!$state.Stop) { Start-Playback $result }
            } else {
                $state.Next = [datetime]::UtcNow.AddSeconds($state.Duration)
            }
        } elseif ($state.Process -and $state.Process.HasExited) {
            $exitCode = $state.Process.ExitCode
            $state.Process.Dispose()
            $state.Process = $null
            if (!$state.Stop) {
                if ($exitCode -ne 0) { throw $state.Errors.GetAwaiter().GetResult() }
                Move-Item -LiteralPath ($state.Temp + '.partial') -Destination $state.Temp -Force
                Start-Upload
            }
        } elseif (!$state.Stop -and $state.Next -and [datetime]::UtcNow -ge $state.Next) {
            $state.Next = $null
            $state.Index = ($state.Index + 1) % $queue.Items.Count
            if ($queue.Items.Count -gt 1) { Start-Item }
            else { $state.Next = [datetime]::UtcNow.AddSeconds($state.Duration) }
        }
        if ($state.Stop -and !$state.Task -and !$state.Process) {
            $status.Text = 'Rotation stopped. The LCD keeps showing the last active item.'
            Clear-Operation
            if ($state.OpenStorage) {
                $state.OpenStorage = $false
                Show-LcdStorage $window
            }
        }
    } catch {
        $message = $_.Exception.GetBaseException().Message
        if ($message -like 'Not enough LCD storage*' -and
            $state.Attempt + 1 -lt $presets.Count -and !$state.Stop) {
            $state.Task = $null
            $state.Attempt++
            Start-Conversion
        } else {
            $status.Text = $message
            Clear-Operation
        }
    }
})
$storageButton.Add_Click({
    if ($state.Running -or $state.Task -or $state.Process) {
        $state.OpenStorage = $true
        $state.Stop = $true
        $send.IsEnabled = $false
        $status.Text = 'Opening storage after the current LCD operation finishes...'
    } else {
        try { Show-LcdStorage $window }
        catch { $status.Text = $_.Exception.GetBaseException().Message }
    }
})
$startup.Add_Click({
    try {
        Set-Startup ([bool]$startup.IsChecked)
        $status.Text = if ($startup.IsChecked) { 'Saved playlist resumes 20 seconds after Windows sign-in. Keep this EXE and media files in place.' }
                       else { 'Windows startup disabled.' }
    } catch {
        $startup.IsChecked = !$startup.IsChecked
        $status.Text = $_.Exception.GetBaseException().Message
    }
})
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.SystemIcons]::Application
$tray.Text = 'Ryujin LCD'
$trayMenu = New-Object Windows.Forms.ContextMenuStrip
$showMenu = $trayMenu.Items.Add('Open Ryujin LCD')
$exitMenu = $trayMenu.Items.Add('Exit')
$tray.ContextMenuStrip = $trayMenu
$showAction = { $window.Show(); $window.WindowState = 'Normal'; [void]$window.Activate() }
$tray.Add_DoubleClick($showAction)
$showMenu.Add_Click($showAction)
$exitMenu.Add_Click({
    if ($state.Task -or $state.Process) {
        $state.Stop = $true
        $status.Text = 'Wait for the current operation, then choose Exit again.'
        $window.Show()
    } else { $state.Exit = $true; $window.Close() }
})
$window.Add_StateChanged({
    if ($window.WindowState -eq 'Minimized') {
        $preview.Pause()
        $window.Hide()
    } elseif (!$state.Paused -and $queue.SelectedItem -and
        [IO.Path]::GetExtension($queue.SelectedItem.Path) -ne '.gif') { $preview.Play() }
})
$window.Add_Closing({
    param($sender, $eventArgs)
    if (!$state.Exit -and ($state.Running -or $state.Task -or $state.Process)) {
        $eventArgs.Cancel = $true
        $window.WindowState = 'Minimized'
    }
})
if (!$ValidateOnly) {
    try {
        if (Test-Path -LiteralPath $playlistPath) {
            $saved = Get-Content -LiteralPath $playlistPath -Raw | ConvertFrom-Json
            if ($saved.Framing -in @('Fit','Fill','Stretch')) { $state.Framing = $saved.Framing }
            if ($saved.Crops) {
                foreach ($property in $saved.Crops.PSObject.Properties) {
                    $state.Crops[$property.Name] = @{
                        X = [Math]::Max(0, [Math]::Min(100, [int]$property.Value.X))
                        Y = [Math]::Max(0, [Math]::Min(100, [int]$property.Value.Y))
                    }
                }
            }
            if ($saved.Slots) {
                foreach ($property in $saved.Slots.PSObject.Properties) {
                    $slot = [int]$property.Value
                    if ($slot -ge 0 -and $slot -lt 10) { $state.Slots[$property.Name] = $slot }
                }
            }
            foreach ($file in $saved.Files) {
                if (!(Test-Path -LiteralPath $file -PathType Leaf)) { continue }
                if ($queue.Items.Count -ge 10) { break }
                $media = Get-Item -LiteralPath $file
                [void]$queue.Items.Add([pscustomobject]@{
                    Path = $media.FullName; Name = $media.Name
                    Key = "$($media.FullName)|$($media.Length)|$($media.LastWriteTimeUtc.Ticks)"
                })
            }
            if ($queue.Items.Count) { $queue.SelectedIndex = 0; $send.IsEnabled = $true }
        }
        $scheduler = New-Object -ComObject 'Schedule.Service'
        $scheduler.Connect()
        try {
            $existingTask = $scheduler.GetFolder('\').GetTask($taskName)
            $startup.IsChecked = [bool]$existingTask.Enabled
            if ($startup.IsChecked -and $env:RYUJIN_EXE -and
                $existingTask.Definition.Actions.Item(1).Path -ne $env:RYUJIN_EXE) { Set-Startup $true }
        } catch { }
    } catch { $status.Text = $_.Exception.GetBaseException().Message }
}
Update-Framing
$framing.SelectedIndex = [array]::IndexOf(@('Fit','Fill','Stretch'), $state.Framing)
$framing.Add_SelectionChanged({
    $state.Framing = @('Fit','Fill','Stretch')[$framing.SelectedIndex]
    Update-Framing
    Save-Playlist
})
$cropChanged = {
    if ($state.LoadingCrop -or !$queue.SelectedItem -or $state.Running) { return }
    $state.Crops[$queue.SelectedItem.Key] = @{ X = [int]$cropX.Value; Y = [int]$cropY.Value }
    Update-Framing
    Save-Playlist
}
$cropX.Add_ValueChanged($cropChanged)
$cropY.Add_ValueChanged($cropChanged)
$centerCrop.Add_Click({ $cropX.Value = 50; $cropY.Value = 50 })
if ($ValidateOnly) { $tray.Dispose(); $window.Close(); return }
$tray.Visible = $true
if ($AutoStart) {
    $window.Add_ContentRendered({
        $window.WindowState = 'Minimized'
        if ($queue.Items.Count) {
            $send.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        }
    })
}
$timer.Start()
try {
    $application = [Windows.Application]::new()
    $application.ShutdownMode = 'OnMainWindowClose'
    $null = $application.Run($window)
}
finally {
    $timer.Stop()
    $preview.Close()
    $tray.Dispose()
    Clear-Operation
}



