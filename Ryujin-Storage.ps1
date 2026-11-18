function Show-LcdStorage {
    param($Owner)
    [xml]$storageLayout = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 Title="Ryujin LCD storage" Width="730" Height="490" MinWidth="620" MinHeight="400"
 Background="#101727" Foreground="#F1F5FA" FontFamily="Segoe UI" WindowStartupLocation="CenterOwner">
 <Grid Margin="22">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="65"/></Grid.RowDefinitions>
  <TextBlock Name="Summary" Text="Reading LCD storage..." FontSize="18" Margin="0,0,0,16"/>
  <DataGrid Name="Items" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True"
    SelectionMode="Extended" SelectionUnit="FullRow" Background="#E8EEF7" Foreground="#101727"
    CanUserAddRows="False" CanUserDeleteRows="False" HeadersVisibility="Column"
    GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#CFD9E8" RowHeight="28">
   <DataGrid.Columns>
    <DataGridTextColumn Header="Type" Binding="{Binding Kind}" Width="65"/>
    <DataGridTextColumn Header="Slot" Binding="{Binding Slot}" Width="60"/>
    <DataGridTextColumn Header="Name from local records" Binding="{Binding Name}" Width="*" MinWidth="350"/>
   </DataGrid.Columns>
  </DataGrid>
  <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,14,0,8">
   <Button Name="Refresh" Content="Refresh" Padding="16,8"/>
   <Button Name="Show" Content="Show on LCD" Padding="16,8" Margin="8,0"/>
   <Button Name="Delete" Content="Delete selected..." Padding="16,8"/>
  </StackPanel>
  <TextBlock Name="Info" Grid.Row="3" Foreground="#AFBDD2" TextWrapping="Wrap"
   Text="Select a row to show it on the LCD. Ctrl-click to select multiple rows for deletion. Older uploads may have no local name."/>
 </Grid>
</Window>
"@
    $storageWindow = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($storageLayout))
    $storageWindow.Owner = $Owner
    $items = $storageWindow.FindName('Items')
    $summary = $storageWindow.FindName('Summary')
    $info = $storageWindow.FindName('Info')
    $refresh = $storageWindow.FindName('Refresh')
    $show = $storageWindow.FindName('Show')
    $delete = $storageWindow.FindName('Delete')
    $memoryState = @{ Task = $null; Phase = ''; Groups = @(); Index = 0; Error = $null }
    $hidPath = Get-InterfacePath 'HID\VID_0B05&PID_1AA2&MI_01' '4d1e55b2-f16f-11cf-88cb-001111000030'

    function Set-StorageBusy([bool]$busy) {
        $refresh.IsEnabled = !$busy
        $show.IsEnabled = !$busy
        $delete.IsEnabled = !$busy
    }
    function Read-Storage {
        Set-StorageBusy $true
        $memoryState.Phase = 'Read'
        $memoryState.Task = [RyujinLcd]::StorageAsync($hidPath)
    }
    function Delete-StorageGroup {
        $group = $memoryState.Groups[$memoryState.Index]
        $memoryState.Phase = 'Delete'
        $memoryState.Task = [RyujinLcd]::DeleteAsync($hidPath, $group.Name,
            [int[]]@($group.Group | ForEach-Object { $_.Slot }))
    }
    $refresh.Add_Click({ $memoryState.Error = $null; Read-Storage })
    $show.Add_Click({
        if (!$items.SelectedItem) { return }
        Set-StorageBusy $true
        $row = $items.SelectedItem
        $memoryState.Phase = 'Show'
        $memoryState.Task = [RyujinLcd]::ShowStoredAsync($hidPath, $row.Kind, $row.Slot)
        $info.Text = "Showing $($row.Kind) slot $($row.Slot) on the physical LCD..."
    })
    $delete.Add_Click({
        $selected = @($items.SelectedItems)
        if (!$selected.Count) { return }
        $names = ($selected | ForEach-Object { "$($_.Kind) slot $($_.Slot)" }) -join ', '
        $answer = [Windows.MessageBox]::Show($storageWindow,
            "Permanently delete these stored items? They cannot be read back from the cooler for recovery." +
            [Environment]::NewLine + $names, 'Delete LCD media', 'YesNo', 'Warning', 'No')
        if ($answer -ne 'Yes') { return }
        $memoryState.Error = $null
        $memoryState.Groups = @($selected | Group-Object Kind)
        $memoryState.Index = 0
        Set-StorageBusy $true
        $info.Text = 'Deleting selected items and checking storage...'
        Delete-StorageGroup
    })
    $poll = [Windows.Threading.DispatcherTimer]::new()
    $poll.Interval = [TimeSpan]::FromMilliseconds(150)
    $poll.Add_Tick({
        if (!$memoryState.Task -or !$memoryState.Task.IsCompleted) { return }
        try {
            $phase = $memoryState.Phase
            $result = $memoryState.Task.GetAwaiter().GetResult()
            $memoryState.Task = $null
            if ($phase -eq 'Read') {
                $rows = @($result.Items | ForEach-Object {
                    $stored = $_
                    $known = @($state.Slots.Keys | Where-Object {
                        $stored.Kind -eq 'GIF' -and $state.Slots[$_] -eq $stored.Slot
                    } | ForEach-Object { [IO.Path]::GetFileName(($_ -split '\|')[0]) } | Select-Object -Unique)
                    [pscustomobject]@{
                        Kind = $stored.Kind; Slot = $stored.Slot
                        Name = if ($known.Count) { $known -join ', ' } else { 'Unknown - use Show on LCD to identify' }
                    }
                })
                $items.ItemsSource = $rows
                $gifSlots = @($result.Items | Where-Object Kind -eq 'GIF' | ForEach-Object Slot)
                foreach ($key in @($state.Slots.Keys)) {
                    if ($state.Slots[$key] -notin $gifSlots) { $state.Slots.Remove($key) }
                }
                Save-Playlist
                $summary.Text = '{0:N2} MB free / {1:N2} MB total - {2} stored items' -f
                    ($result.FreeBytes / 1MB), ($result.TotalBytes / 1MB), $rows.Count
                if ($memoryState.Error) { $info.Text = $memoryState.Error }
                else { $info.Text = 'Storage refreshed. Select rows to show or delete. Slot numbers start at 0. Local names are available for recorded uploads.' }
                Set-StorageBusy $false
            } elseif ($phase -eq 'Delete') {
                $memoryState.Index++
                if ($memoryState.Index -lt $memoryState.Groups.Count) { Delete-StorageGroup }
                else { Read-Storage }
            } else {
                Set-StorageBusy $false
                $info.Text = 'The selected stored item is now shown on the LCD.'
            }
        } catch {
            $message = $_.Exception.GetBaseException().Message
            $memoryState.Task = $null
            if ($memoryState.Phase -eq 'Delete') {
                $memoryState.Error = $message
                Read-Storage
            } else { $info.Text = $message; Set-StorageBusy $false }
        }
    })
    $storageWindow.Add_Closing({
        param($sender, $eventArgs)
        if ($memoryState.Task) { $eventArgs.Cancel = $true; $info.Text = 'Wait for the current LCD operation to finish.' }
    })
    try {
        Read-Storage
        $poll.Start()
        [void]$storageWindow.ShowDialog()
    } finally { $poll.Stop() }
}
