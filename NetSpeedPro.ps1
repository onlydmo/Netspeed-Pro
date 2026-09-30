# NetSpeed Pro Suite v2
$ErrorActionPreference = "Continue"

# Auto-Elevate
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# P/Invoke for Ghost Mode
$pinvokeCode = @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const int GWL_EXSTYLE = (-20);
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);
}
"@
try { Add-Type -TypeDefinition $pinvokeCode -ErrorAction SilentlyContinue } catch {}

# --- Config & State ---
$script:logPath = "$PSScriptRoot\NetDataLog.json"
$script:configPath = "$PSScriptRoot\NetConfig.json"
$script:config = @{ QuotaBytes = 2GB }
if (Test-Path $script:configPath) {
    try { 
        $cfg = Get-Content $script:configPath | ConvertFrom-Json
        if ($cfg.QuotaBytes) { $script:config.QuotaBytes = [long]$cfg.QuotaBytes }
    } catch {}
}

$script:sessions = @()
$script:currentSession = @{
    Id = [guid]::NewGuid().ToString()
    StartTime = (Get-Date)
    EndTime = $null
    WifiSSID = "Unknown"
    TotalBytes = 0
    TopApps = @{}
}

$script:lastDown = 0; $script:lastUp = 0
$script:dailyBytes = 0
$script:dailyDate = (Get-Date).ToString("yyyy-MM-dd")
$script:ghostMode = $false
$script:graphHistoryDown = New-Object System.Collections.Generic.List[double]
$script:graphHistoryUp = New-Object System.Collections.Generic.List[double]
$script:maxGraphPoints = 60
$script:ipFetched = $false
$script:currentTopApp = "None"

# Load Log
if (Test-Path $script:logPath) {
    try {
        $data = Get-Content $script:logPath | ConvertFrom-Json
        if ($data) { $script:sessions = @($data) }
        
        $todayDate = (Get-Date).Date
        foreach ($s in $script:sessions) {
            $dt = $null
            try {
                if ($s.StartTime -is [datetime]) { $dt = $s.StartTime }
                elseif ($s.StartTime.value) { $dt = [datetime]::Parse($s.StartTime.value) }
                else { $dt = [datetime]::Parse($s.StartTime) }
            } catch {}
            
            if ($dt -ne $null -and $dt.Date -eq $todayDate) {
                $script:dailyBytes += [long]$s.TotalBytes
            }
        }
    } catch {}
}

function Format-Bytes($bytes) {
    if ($bytes -gt 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -gt 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    if ($bytes -gt 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

# --- XAML: HUD ---
$hudXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NetSpeedHUD" Height="220" Width="200" 
        WindowStyle="None" AllowsTransparency="True" Background="#D0101014"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        BorderBrush="#33FFFFFF" BorderThickness="1"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Consolas" />
            <Setter Property="FontWeight" Value="Bold" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="Margin" Value="0,2,0,2" />
        </Style>
    </Window.Resources>
    <Border CornerRadius="8" Padding="10">
        <StackPanel>
            <TextBlock x:Name="lblIP" Foreground="#F472B6" Text="IP: Checking..." FontSize="10" />
            <TextBlock x:Name="lblDownload" Foreground="#4ADE80" Text="DL 0.0 KB/s" FontSize="14" />
            <TextBlock x:Name="lblUpload" Foreground="#60A5FA" Text="UP 0.0 KB/s" FontSize="14" />
            <Canvas x:Name="cvsGraph" Height="30" Width="180" Background="#11FFFFFF" Margin="0,5,0,5" ClipToBounds="True">
                <Polyline x:Name="polyDown" Stroke="#4ADE80" StrokeThickness="1" />
                <Polyline x:Name="polyUp" Stroke="#60A5FA" StrokeThickness="1" />
            </Canvas>
            <TextBlock x:Name="lblSession" Foreground="#C084FC" Text="Session: 0.0 MB" />
            <TextBlock x:Name="lblDaily" Foreground="#FBBF24" Text="Today: 0.0 MB" />
            <TextBlock x:Name="lblQuota" Foreground="#F87171" Text="Quota Warning!" Visibility="Collapsed" />
            <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,5,0,5" />
            <TextBlock x:Name="lblPing" Foreground="#9CA3AF" Text="Ping: -- ms" />
            <TextBlock x:Name="lblProcess" Foreground="#2DD4BF" Text="App: --" TextTrimming="CharacterEllipsis" />
        </StackPanel>
    </Border>
</Window>
"@
$reader = (New-Object System.Xml.XmlNodeReader ([xml]$hudXaml))
$hudWindow = [System.Windows.Markup.XamlReader]::Load($reader)

$lblIP = $hudWindow.FindName("lblIP")
$lblDownload = $hudWindow.FindName("lblDownload")
$lblUpload = $hudWindow.FindName("lblUpload")
$lblSession = $hudWindow.FindName("lblSession")
$lblDaily = $hudWindow.FindName("lblDaily")
$lblQuota = $hudWindow.FindName("lblQuota")
$lblPing = $hudWindow.FindName("lblPing")
$lblProcess = $hudWindow.FindName("lblProcess")
$polyDown = $hudWindow.FindName("polyDown")
$polyUp = $hudWindow.FindName("polyUp")
$cvsGraph = $hudWindow.FindName("cvsGraph")

# Network Init
$nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object OperationalStatus -eq 'Up'
foreach ($nic in $nics) {
    $stats = $nic.GetIPv4Statistics()
    $script:lastDown += $stats.BytesReceived
    $script:lastUp += $stats.BytesSent
}

$hudWindow.Add_MouseLeftButtonDown({ if (-not $script:ghostMode) { $hudWindow.DragMove() } })

# Fetch IP Async
$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$powershell = [powershell]::Create().AddScript({
    try { return (Invoke-RestMethod -Uri 'https://ifconfig.me/ip' -TimeoutSec 5) } catch { return "Offline" }
})
$powershell.Runspace = $runspace
$ipJob = $powershell.BeginInvoke()

# Cache for parent app lookups so we don't re-query WMI constantly
$script:parentCache = @{}
$script:systemProcs = @("explorer","services","svchost","wininit","csrss","smss","lsass","System","Idle","RuntimeBroker","sihost","taskhostw","conhost","dwm","fontdrvhost")
$script:shellProcs = @("powershell","pwsh","cmd","bash","wsl","WindowsTerminal","OpenConsole")

function Get-ParentAppName($procPid) {
    try {
        $proc = [System.Diagnostics.Process]::GetProcessById([int]$procPid)
        $procName = $proc.ProcessName
        
        # Check cache first
        if ($script:parentCache.ContainsKey($procName)) { return $script:parentCache[$procName] }
        
        # Walk up the parent chain, skipping shells
        $currentPid = [int]$procPid
        $topName = $procName
        for ($depth = 0; $depth -lt 8; $depth++) {
            try {
                $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $currentPid" -ErrorAction Stop
                if (-not $cim -or -not $cim.ParentProcessId) { break }
                $parentProc = [System.Diagnostics.Process]::GetProcessById($cim.ParentProcessId)
                $pName = $parentProc.ProcessName
                
                # Stop at system-level processes
                if ($pName -in $script:systemProcs) { break }
                
                # Skip shell intermediaries (powershell, cmd, etc.) — keep walking
                if ($pName -in $script:shellProcs) {
                    $currentPid = $cim.ParentProcessId
                    continue
                }
                
                # Found a real parent app
                $topName = $pName
                $currentPid = $cim.ParentProcessId
            } catch { break }
        }
        
        $script:parentCache[$procName] = $topName
        return $topName
    } catch { return "Unknown" }
}

function Get-TopNetworkApp {
    $netstat = netstat -ano | Select-String "ESTABLISHED"
    if (-not $netstat) { return "None" }
    $pidCounts = @{}
    foreach ($line in $netstat) {
        $parts = $line.ToString() -split '\s+'
        $targetPid = $parts[-1]
        if ($targetPid -ne "0") { $pidCounts[$targetPid]++ }
    }
    if ($pidCounts.Count -eq 0) { return "None" }
    $topPid = ($pidCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name
    try {
        $parentName = Get-ParentAppName $topPid
        return $parentName
    } catch { return "Unknown" }
}

# --- Main Engine Timer ---
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$tickCount = 0

$timer.Add_Tick({
    $script:tickCount++
    
    if (-not $script:ipFetched -and $ipJob.IsCompleted) {
        $ip = $powershell.EndInvoke($ipJob)
        $lblIP.Text = "IP: $ip"
        $script:ipFetched = $true
        $runspace.Close(); $powershell.Dispose()
    }
    
    $currentDown = 0; $currentUp = 0
    $activeNics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object OperationalStatus -eq 'Up'
    foreach ($nic in $activeNics) {
        $stats = $nic.GetIPv4Statistics()
        $currentDown += $stats.BytesReceived
        $currentUp += $stats.BytesSent
    }
    
    $downDelta = $currentDown - $script:lastDown
    if ($downDelta -lt 0) { $downDelta = 0 }
    $upDelta = $currentUp - $script:lastUp
    if ($upDelta -lt 0) { $upDelta = 0 }
    
    $script:lastDown = $currentDown; $script:lastUp = $currentUp
    $totalDelta = $downDelta + $upDelta
    
    $script:currentSession.TotalBytes += $totalDelta
    $script:dailyBytes += $totalDelta
    
    $lblDownload.Text = "DL " + (Format-Bytes $downDelta) + "/s"
    $lblUpload.Text = "UP " + (Format-Bytes $upDelta) + "/s"
    $lblSession.Text = "Session: " + (Format-Bytes $script:currentSession.TotalBytes)
    $lblDaily.Text = "Today: " + (Format-Bytes $script:dailyBytes)
    
    if ($script:dailyBytes -gt $script:config.QuotaBytes) {
        $lblQuota.Visibility = "Visible"
        $lblDaily.Foreground = "#EF4444"
    } else {
        $lblQuota.Visibility = "Collapsed"
        $lblDaily.Foreground = "#FBBF24"
    }
    
    # Graph update
    if ($script:graphHistoryDown.Count -ge $script:maxGraphPoints) {
        $script:graphHistoryDown.RemoveAt(0); $script:graphHistoryUp.RemoveAt(0)
    }
    $script:graphHistoryDown.Add($downDelta); $script:graphHistoryUp.Add($upDelta)
    
    $maxGraph = 1000000 # 1MB/s minimum scale
    foreach ($v in $script:graphHistoryDown) { if ($v -gt $maxGraph) { $maxGraph = $v } }
    foreach ($v in $script:graphHistoryUp) { if ($v -gt $maxGraph) { $maxGraph = $v } }
    
    $ptsDown = New-Object System.Windows.Media.PointCollection
    $ptsUp = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $script:graphHistoryDown.Count; $i++) {
        $x = ($i / $script:maxGraphPoints) * $cvsGraph.Width
        $yD = $cvsGraph.Height - (($script:graphHistoryDown[$i] / $maxGraph) * $cvsGraph.Height)
        $yU = $cvsGraph.Height - (($script:graphHistoryUp[$i] / $maxGraph) * $cvsGraph.Height)
        $ptsDown.Add((New-Object System.Windows.Point $x, $yD))
        $ptsUp.Add((New-Object System.Windows.Point $x, $yU))
    }
    $polyDown.Points = $ptsDown; $polyUp.Points = $ptsUp
    
    # Background Heavy Tasks (every 2 seconds)
    if ($script:tickCount % 2 -eq 0) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send("1.1.1.1", 1000)
            if ($reply.Status -eq 'Success') { $lblPing.Text = "Ping: $($reply.RoundtripTime) ms" }
            else { $lblPing.Text = "Ping: Timeout" }
        } catch { $lblPing.Text = "Ping: Err" }
        
        $script:currentTopApp = Get-TopNetworkApp
        $lblProcess.Text = "App: " + $script:currentTopApp
    }
    
    # App-Bandwidth Attribution - track ALL active apps grouped by parent
    if ($totalDelta -gt 0) {
        if (-not $script:currentSession.TopApps) { $script:currentSession.TopApps = @{} }
        if (-not $script:currentSession.AppProcesses) { $script:currentSession.AppProcesses = @{} }
        
        # Get all processes with established connections
        $netstat = netstat -ano | Select-String "ESTABLISHED"
        $pidCounts = @{}
        if ($netstat) {
            foreach ($line in $netstat) {
                $parts = $line.ToString() -split '\s+'
                $targetPid = $parts[-1]
                if ($targetPid -ne "0") { $pidCounts[$targetPid]++ }
            }
        }
        
        # Resolve PID to process name + parent app, count connections
        $appConnections = @{}  # parent -> connection count
        $procConnections = @{} # "parent|child" -> connection count
        $totalConnections = 0
        foreach ($p in $pidCounts.GetEnumerator()) {
            try {
                $procName = [System.Diagnostics.Process]::GetProcessById([int]$p.Name).ProcessName
                $parentName = Get-ParentAppName $p.Name
                
                if (-not $appConnections.ContainsKey($parentName)) { $appConnections[$parentName] = 0 }
                $appConnections[$parentName] += $p.Value
                
                $procKey = "$parentName|$procName"
                if (-not $procConnections.ContainsKey($procKey)) { $procConnections[$procKey] = 0 }
                $procConnections[$procKey] += $p.Value
                
                $totalConnections += $p.Value
            } catch {}
        }
        
        # Distribute bytes proportionally
        if ($totalConnections -gt 0) {
            # Parent app totals
            foreach ($app in $appConnections.GetEnumerator()) {
                $share = [long](($app.Value / $totalConnections) * $totalDelta)
                if (-not $script:currentSession.TopApps.ContainsKey($app.Name)) { $script:currentSession.TopApps[$app.Name] = 0 }
                $script:currentSession.TopApps[$app.Name] += $share
            }
            # Child process detail
            foreach ($proc in $procConnections.GetEnumerator()) {
                $share = [long](($proc.Value / $totalConnections) * $totalDelta)
                if (-not $script:currentSession.AppProcesses.ContainsKey($proc.Name)) { $script:currentSession.AppProcesses[$proc.Name] = 0 }
                $script:currentSession.AppProcesses[$proc.Name] += $share
            }
        }
    }
    
    # Check Hotspot (every 10 seconds)
    if ($script:tickCount % 10 -eq 0) {
        $wifiName = (netsh wlan show interfaces | Select-String "SSID" | Select-Object -First 1) -replace '^\s+SSID\s+:\s+',''
        if ($wifiName) { 
            $script:currentSession.WifiSSID = $wifiName 
            if ($wifiName -match "(iPhone|Galaxy|Hotspot)") {
                netsh wlan set profileparameter name=$wifiName cost=Fixed | Out-Null
            }
        }
    }
    
    # Periodic Save
    if ($script:tickCount % 30 -eq 0) { Save-DataLog }
})

function Save-DataLog {
    $script:currentSession.EndTime = (Get-Date)
    $found = $false
    for ($i = 0; $i -lt $script:sessions.Count; $i++) {
        if ($script:sessions[$i].Id -eq $script:currentSession.Id) {
            $script:sessions[$i] = $script:currentSession
            $found = $true; break
        }
    }
    if (-not $found) { $script:sessions += $script:currentSession }
    $script:sessions | ConvertTo-Json -Depth 5 | Out-File $script:logPath -Force
}

# --- Session Details Window ---
function Show-SessionDetails($sessId) {
    $sess = $null
    foreach ($s in $script:sessions) {
        if ($s.Id -eq $sessId) { $sess = $s; break }
    }
    if (-not $sess) { return }
    
    # Extract parent app data
    $appData = @()
    
    if ($sess.TopApps) {
        $topAppsObj = $sess.TopApps
        if ($topAppsObj -is [hashtable]) {
            foreach ($k in $topAppsObj.Keys) {
                $appData += [PSCustomObject]@{ AppName = $k; FormattedBytes = (Format-Bytes $topAppsObj[$k]); RawBytes = [long]$topAppsObj[$k]; ChildProcs = "" }
            }
        } else {
            $members = @($topAppsObj | Get-Member -MemberType NoteProperty)
            foreach ($m in $members) {
                $k = $m.Name; $v = $topAppsObj.$k
                $appData += [PSCustomObject]@{ AppName = $k; FormattedBytes = (Format-Bytes $v); RawBytes = [long]$v; ChildProcs = "" }
            }
        }
    } elseif ($sess.TopApp) {
        $appData += [PSCustomObject]@{ AppName = $sess.TopApp; FormattedBytes = (Format-Bytes $sess.TotalBytes); RawBytes = [long]$sess.TotalBytes; ChildProcs = "" }
    }
    
    # Build child process text for each parent app
    $procObj = $sess.AppProcesses
    if ($procObj) {
        $procEntries = @{}
        if ($procObj -is [hashtable]) {
            foreach ($k in $procObj.Keys) { $procEntries[$k] = $procObj[$k] }
        } else {
            $pMembers = @($procObj | Get-Member -MemberType NoteProperty)
            foreach ($m in $pMembers) { $procEntries[$m.Name] = $procObj.($m.Name) }
        }
        
        foreach ($row in $appData) {
            $childLines = @()
            foreach ($pk in $procEntries.Keys) {
                if ($pk -like "$($row.AppName)|*") {
                    $childName = $pk.Split("|")[1]
                    if ($childName -ne $row.AppName) {
                        $childLines += "  $childName - $(Format-Bytes $procEntries[$pk])"
                    }
                }
            }
            if ($childLines.Count -gt 0) { $row.ChildProcs = $childLines -join "`n" }
        }
    }
    
    $appData = @($appData | Sort-Object RawBytes -Descending)
    
    $detXaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Session Breakdown" Height="450" Width="500" Background="#18181B" Foreground="#E4E4E7"
            WindowStartupLocation="CenterScreen" WindowStyle="ToolWindow" Topmost="True">
        <Window.Resources>
            <Style TargetType="DataGrid">
                <Setter Property="Background" Value="#18181B"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="RowBackground" Value="#27272A"/>
                <Setter Property="AlternatingRowBackground" Value="#3F3F46"/>
                <Setter Property="Foreground" Value="#E4E4E7"/>
                <Setter Property="GridLinesVisibility" Value="None"/>
                <Setter Property="HeadersVisibility" Value="Column"/>
            </Style>
            <Style TargetType="DataGridColumnHeader">
                <Setter Property="Background" Value="#09090B"/>
                <Setter Property="Foreground" Value="#A1A1AA"/>
                <Setter Property="FontWeight" Value="Bold"/>
                <Setter Property="Padding" Value="10,5,10,5"/>
            </Style>
            <Style TargetType="DataGridCell">
                <Setter Property="Padding" Value="10,5,10,5"/>
                <Setter Property="BorderThickness" Value="0"/>
            </Style>
        </Window.Resources>
        <Grid Margin="15">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="lblTitle" Text="Per-App Data Usage" FontSize="20" FontWeight="Bold" Margin="0,0,0,5" Foreground="#F472B6" />
            <TextBlock Grid.Row="1" Text="Click a row to see child processes" Foreground="#71717A" FontStyle="Italic" Margin="0,0,0,10" />
            <DataGrid x:Name="dgApps" Grid.Row="2" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="True" RowDetailsVisibilityMode="Collapsed">
                <DataGrid.Columns>
                    <DataGridTextColumn Header="Application" Binding="{Binding AppName}" Width="200" />
                    <DataGridTextColumn Header="Data Consumed" Binding="{Binding FormattedBytes}" SortMemberPath="RawBytes" Width="150" />
                </DataGrid.Columns>
                <DataGrid.RowDetailsTemplate>
                    <DataTemplate>
                        <Border Background="#09090B" Padding="15,8" Margin="0,2">
                            <TextBlock Text="{Binding ChildProcs}" FontFamily="Consolas" Foreground="#34D399" TextWrapping="Wrap" />
                        </Border>
                    </DataTemplate>
                </DataGrid.RowDetailsTemplate>
            </DataGrid>
        </Grid>
    </Window>
"@
    $detReader = (New-Object System.Xml.XmlNodeReader ([xml]$detXaml))
    $detWin = [System.Windows.Markup.XamlReader]::Load($detReader)
    $script:dgAppsDetail = $detWin.FindName("dgApps")
    $script:lblTitleDetail = $detWin.FindName("lblTitle")
    
    if ($appData.Count -gt 0) {
        $script:lblTitleDetail.Text = "Per-App Data ($($appData.Count) apps)"
        $script:dgAppsDetail.ItemsSource = $appData
        
        # Toggle expand on click if the row has child processes
        $script:dgAppsDetail.Add_SelectionChanged({
            param($sender, $e)
            foreach ($item in $e.AddedItems) {
                $row = $script:dgAppsDetail.ItemContainerGenerator.ContainerFromItem($item)
                if ($row -and $item.ChildProcs) {
                    if ($row.DetailsVisibility -eq [System.Windows.Visibility]::Visible) {
                        $row.DetailsVisibility = [System.Windows.Visibility]::Collapsed
                    } else {
                        $row.DetailsVisibility = [System.Windows.Visibility]::Visible
                    }
                }
            }
        })
    } else {
        $script:lblTitleDetail.Text = "No per-app data for this session"
    }
    
    $detWin.ShowDialog() | Out-Null
}

# --- Dashboard Function ---
function Open-Dashboard {
    if ($script:dashWin -and $script:dashWin.IsLoaded) {
        $script:dashWin.Activate()
        return
    }
    
    Save-DataLog
    $dashXaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="NetSpeed Dashboard" Height="550" Width="700" Background="#18181B" Foreground="#E4E4E7"
            WindowStartupLocation="CenterScreen" WindowStyle="ToolWindow">
        <Window.Resources>
            <Style TargetType="DataGrid">
                <Setter Property="Background" Value="#18181B"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="RowBackground" Value="#27272A"/>
                <Setter Property="AlternatingRowBackground" Value="#3F3F46"/>
                <Setter Property="Foreground" Value="#E4E4E7"/>
                <Setter Property="GridLinesVisibility" Value="None"/>
                <Setter Property="HeadersVisibility" Value="Column"/>
                <Setter Property="SelectionMode" Value="Single"/>
            </Style>
            <Style TargetType="DataGridColumnHeader">
                <Setter Property="Background" Value="#09090B"/>
                <Setter Property="Foreground" Value="#A1A1AA"/>
                <Setter Property="FontWeight" Value="Bold"/>
                <Setter Property="Padding" Value="10,5,10,5"/>
            </Style>
            <Style TargetType="DataGridCell">
                <Setter Property="Padding" Value="10,5,10,5"/>
                <Setter Property="BorderThickness" Value="0"/>
            </Style>
            <Style TargetType="Button">
                <Setter Property="Background" Value="#3B82F6"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="Padding" Value="15,8"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="FontWeight" Value="Bold"/>
                <Setter Property="Cursor" Value="Hand"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
            <Style TargetType="TabItem">
                <Setter Property="Background" Value="#27272A"/>
                <Setter Property="Foreground" Value="#A1A1AA"/>
                <Setter Property="Padding" Value="15,10"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Style.Triggers>
                    <Trigger Property="IsSelected" Value="True">
                        <Setter Property="Background" Value="#18181B"/>
                        <Setter Property="Foreground" Value="#3B82F6"/>
                    </Trigger>
                </Style.Triggers>
            </Style>
        </Window.Resources>
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Text="NetSpeed Pro Analytics (Admin)" FontSize="24" FontWeight="Bold" Margin="0,0,0,15" Foreground="#10B981" />
            
            <TabControl Grid.Row="1" Background="#18181B" BorderThickness="0">
                <TabItem Header="Session History">
                    <Grid>
                        <TextBlock Text="Double-click a session to view detailed per-app data usage." Foreground="#A1A1AA" Margin="0,10,0,0" FontStyle="Italic"/>
                        <DataGrid x:Name="dgHistory" AutoGenerateColumns="False" IsReadOnly="True" Margin="0,35,0,0">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Date &amp; Time" Binding="{Binding StartTime}" Width="160" />
                                <DataGridTextColumn Header="Wi-Fi SSID" Binding="{Binding WifiSSID}" Width="150" />
                                <DataGridTextColumn Header="Top Application" Binding="{Binding TopApp}" Width="150" />
                                <DataGridTextColumn Header="Data Used" Binding="{Binding TotalBytes}" Width="110" />
                            </DataGrid.Columns>
                        </DataGrid>
                    </Grid>
                </TabItem>
                <TabItem Header="Tools &amp; Settings">
                    <StackPanel Margin="10,20,10,10">
                        
                        <Border Background="#27272A" CornerRadius="8" Padding="15" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Daily Data Quota" FontWeight="Bold" Foreground="#60A5FA" Margin="0,0,0,5"/>
                                <TextBlock Text="Set your daily safety limit. HUD will flash red if exceeded." Foreground="#A1A1AA" Margin="0,0,0,10" />
                                <StackPanel Orientation="Horizontal">
                                    <TextBox x:Name="txtQuota" Width="100" Margin="0,0,10,0" VerticalContentAlignment="Center" Background="#18181B" Foreground="White" BorderThickness="0" Padding="5"/>
                                    <ComboBox x:Name="cmbQuotaType" Width="60" Margin="0,0,10,0" Background="#18181B" Foreground="Black">
                                        <ComboBoxItem Content="MB"/>
                                        <ComboBoxItem Content="GB" IsSelected="True"/>
                                    </ComboBox>
                                    <Button x:Name="btnSaveQuota" Content="Save Quota" Width="150" />
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <Border Background="#27272A" CornerRadius="8" Padding="15" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="App Bandwidth Throttler (QoS)" FontWeight="Bold" Foreground="#F472B6" Margin="0,0,0,5"/>
                                <TextBlock Text="Instantly throttle the download/upload speed of a heavy background app." Foreground="#A1A1AA" Margin="0,0,0,10" />
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="Select App:" VerticalAlignment="Center" Foreground="#E4E4E7" Margin="0,0,5,0"/>
                                    <ComboBox x:Name="cmbQosApp" Width="140" Margin="0,0,15,0" Background="#18181B" Foreground="Black" IsEditable="True"/>
                                    <TextBlock Text="Limit:" VerticalAlignment="Center" Foreground="#E4E4E7" Margin="0,0,5,0"/>
                                    <TextBox x:Name="txtQosLimit" Width="60" Margin="0,0,5,0" Text="1" VerticalContentAlignment="Center" Background="#18181B" Foreground="White" BorderThickness="0" Padding="5"/>
                                    <ComboBox x:Name="cmbQosType" Width="60" Margin="0,0,15,0" Background="#18181B" Foreground="Black">
                                        <ComboBoxItem Content="KB"/>
                                        <ComboBoxItem Content="MB" IsSelected="True"/>
                                    </ComboBox>
                                    <Button x:Name="btnApplyQos" Content="Apply" Width="80" Margin="0,0,10,0"/>
                                    <Button x:Name="btnRemoveQos" Content="Remove All" Width="100" Background="#EF4444"/>
                                </StackPanel>
                                <TextBlock x:Name="lblActiveQos" Text="Loading active limits..." Foreground="#34D399" Margin="0,10,0,0" FontStyle="Italic"/>
                            </StackPanel>
                        </Border>
                        
                        <Border Background="#27272A" CornerRadius="8" Padding="15">
                            <StackPanel>
                                <TextBlock Text="Export Data" FontWeight="Bold" Foreground="#10B981" Margin="0,0,0,5"/>
                                <Button x:Name="btnExport" Content="Export Sessions to CSV" HorizontalAlignment="Left" Width="200" />
                            </StackPanel>
                        </Border>
                        
                    </StackPanel>
                </TabItem>
            </TabControl>
        </Grid>
    </Window>
"@
    $dashReader = (New-Object System.Xml.XmlNodeReader ([xml]$dashXaml))
    $script:dashWin = [System.Windows.Markup.XamlReader]::Load($dashReader)
    
    $script:dgHistory = $script:dashWin.FindName("dgHistory")
    $script:txtQuota = $script:dashWin.FindName("txtQuota")
    $script:cmbQuotaType = $script:dashWin.FindName("cmbQuotaType")
    $script:btnSaveQuota = $script:dashWin.FindName("btnSaveQuota")
    $script:cmbQosApp = $script:dashWin.FindName("cmbQosApp")
    $script:lblActiveQos = $script:dashWin.FindName("lblActiveQos")
    $script:txtQosLimit = $script:dashWin.FindName("txtQosLimit")
    $script:cmbQosType = $script:dashWin.FindName("cmbQosType")
    $script:btnApplyQos = $script:dashWin.FindName("btnApplyQos")
    $script:btnRemoveQos = $script:dashWin.FindName("btnRemoveQos")
    $script:btnExport = $script:dashWin.FindName("btnExport")
    
    # Init Quota UI
    if ($script:config.QuotaBytes -ge 1GB) {
        $script:txtQuota.Text = [math]::Round($script:config.QuotaBytes / 1GB, 2).ToString()
        $script:cmbQuotaType.SelectedIndex = 1
    } else {
        $script:txtQuota.Text = [math]::Round($script:config.QuotaBytes / 1MB, 2).ToString()
        $script:cmbQuotaType.SelectedIndex = 0
    }
    
    $script:btnSaveQuota.Add_Click({
        $val = 0
        if ([double]::TryParse($script:txtQuota.Text, [ref]$val)) {
            if ($script:cmbQuotaType.Text -eq "GB") { $script:config.QuotaBytes = [long]($val * 1GB) }
            else { $script:config.QuotaBytes = [long]($val * 1MB) }
            $script:config | ConvertTo-Json | Out-File $script:configPath -Force
            $script:quotaBytes = $script:config.QuotaBytes
            [System.Windows.MessageBox]::Show("Quota saved successfully!")
        }
    })
    
    # Init QoS App List from current session
    if ($script:currentSession.TopApps) {
        $activeApps = $null
        if ($script:currentSession.TopApps -is [hashtable]) {
            $activeApps = @($script:currentSession.TopApps.GetEnumerator() | Sort-Object Value -Descending | Select-Object -ExpandProperty Name)
        } else {
            $members = @($script:currentSession.TopApps | Get-Member -MemberType NoteProperty)
            $activeApps = @()
            foreach ($m in $members) { $activeApps += $m.Name }
        }
        foreach ($app in $activeApps) { $script:cmbQosApp.Items.Add($app) | Out-Null }
        if ($script:cmbQosApp.Items.Count -gt 0) { $script:cmbQosApp.SelectedIndex = 0 }
    }
    
    # Helper to refresh active limits text
    function Refresh-QosList {
        try {
            $policies = @(Get-NetQosPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Throttle_*" })
            if ($policies.Count -gt 0) {
                $txt = "Active Limits:`n"
                foreach ($p in $policies) {
                    $limitMB = [math]::Round($p.ThrottleRateActionBitsPerSecond / 8 / 1MB, 2)
                    $txt += "  • $($p.AppPathNameMatchCondition) (Limit: $limitMB MB/s)`n"
                }
                $script:lblActiveQos.Text = $txt.TrimEnd()
                $script:lblActiveQos.Foreground = "#F87171" # Red warning color
            } else {
                $script:lblActiveQos.Text = "No active limits."
                $script:lblActiveQos.Foreground = "#34D399" # Green safe color
            }
        } catch {
            $script:lblActiveQos.Text = "No active limits."
            $script:lblActiveQos.Foreground = "#34D399"
        }
    }
    Refresh-QosList
    
    $script:btnApplyQos.Add_Click({
        $app = $script:cmbQosApp.Text.Trim()
        $limit = $script:txtQosLimit.Text
        $type = $script:cmbQosType.Text
        if ($app -and $limit) {
            if (-not $app.EndsWith(".exe")) { $app += ".exe" }
            try {
                $policyName = "Throttle_$app"
                $rate = "$limit$type"
                Remove-NetQosPolicy -Name $policyName -Confirm:$false -ErrorAction SilentlyContinue
                New-NetQosPolicy -Name $policyName -AppPathNameMatchCondition $app -ThrottleRateActionBitsPerSecond $rate -ErrorAction Stop | Out-Null
                Refresh-QosList
                [System.Windows.MessageBox]::Show("Throttled $app to $rate per second.")
            } catch { [System.Windows.MessageBox]::Show("Error applying QoS. Make sure script is Admin.`n$($_.Exception.Message)") }
        }
    })
    
    $script:btnRemoveQos.Add_Click({
        try {
            Get-NetQosPolicy | Where-Object Name -like "Throttle_*" | Remove-NetQosPolicy -Confirm:$false -ErrorAction SilentlyContinue
            Refresh-QosList
            [System.Windows.MessageBox]::Show("All app limits removed.")
        } catch { [System.Windows.MessageBox]::Show("Error removing limits.") }
    })
    
    $script:displayData = @()
    foreach ($s in $script:sessions) {
        $dateStr = ""
        try {
            if ($s.StartTime -is [datetime]) { $dateStr = $s.StartTime.ToString("MMM dd - HH:mm") } 
            elseif ($s.StartTime.value) { $dateStr = [datetime]::Parse($s.StartTime.value).ToString("MMM dd - HH:mm") }
            else { $dateStr = [datetime]::Parse($s.StartTime).ToString("MMM dd - HH:mm") }
        } catch { $dateStr = $s.StartTime }
        
        # Get overall TopApp from the new hashtable
        $topAppName = "Unknown"
        if ($s.TopApps) {
            $keys = if ($s.TopApps -is [hashtable]) { $s.TopApps.Keys } else { $s.TopApps.psobject.properties.name }
            $maxB = -1
            foreach ($k in $keys) {
                $b = if ($s.TopApps -is [hashtable]) { $s.TopApps[$k] } else { $s.TopApps.$k }
                if ($b -gt $maxB) { $maxB = $b; $topAppName = $k }
            }
        }
        
        $script:displayData += [PSCustomObject]@{
            Id = $s.Id
            StartTime = $dateStr
            WifiSSID = $s.WifiSSID
            TopApp = $topAppName
            TotalBytes = Format-Bytes $s.TotalBytes
        }
    }
    
    $script:dgHistory.ItemsSource = $script:displayData
    
    $script:dgHistory.Add_MouseDoubleClick({
        $selected = $script:dgHistory.SelectedItem
        if ($null -ne $selected) {
            Show-SessionDetails -sessId $selected.Id
        }
    })
    
    $script:btnExport.Add_Click({
        $csvPath = "$Environment:USERPROFILE\Desktop\NetSpeedHistory.csv"
        $script:displayData | Export-Csv -Path $csvPath -NoTypeInformation
        [System.Windows.MessageBox]::Show("Exported to $csvPath")
    })
    
    $script:dashWin.Show() | Out-Null
}

# --- System Tray ---
$components = New-Object System.ComponentModel.Container
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip($components)

$itemDash = New-Object System.Windows.Forms.ToolStripMenuItem("Open Dashboard")
$itemDash.Add_Click({ Open-Dashboard })
$contextMenu.Items.Add($itemDash) | Out-Null
$contextMenu.Items.Add("-") | Out-Null

$itemGhost = New-Object System.Windows.Forms.ToolStripMenuItem("Ghost Mode")
$itemGhost.Add_Click({
    $hwnd = new-object System.Windows.Interop.WindowInteropHelper($hudWindow)
    $handle = $hwnd.Handle
    $exStyle = [Win32]::GetWindowLong($handle, [Win32]::GWL_EXSTYLE)
    if (-not $script:ghostMode) {
        [Win32]::SetWindowLong($handle, [Win32]::GWL_EXSTYLE, $exStyle -bor [Win32]::WS_EX_TRANSPARENT) | Out-Null
        $script:ghostMode = $true; $itemGhost.Checked = $true
        $hudWindow.Background = "#70101014"
    } else {
        [Win32]::SetWindowLong($handle, [Win32]::GWL_EXSTYLE, $exStyle -bxor [Win32]::WS_EX_TRANSPARENT) | Out-Null
        $script:ghostMode = $false; $itemGhost.Checked = $false
        $hudWindow.Background = "#D0101014"
    }
})
$contextMenu.Items.Add($itemGhost) | Out-Null
$contextMenu.Items.Add("-") | Out-Null

$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")
$itemExit.Add_Click({
    Save-DataLog
    $trayIcon.Visible = $false
    $hudWindow.Close()
})
$contextMenu.Items.Add($itemExit) | Out-Null

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\shell32.dll")
$trayIcon.Text = "NetSpeed Pro v2"
$trayIcon.ContextMenuStrip = $contextMenu
$trayIcon.Visible = $true

$hudWindow.Add_Closed({ $trayIcon.Visible = $false })

$timer.Start()
$hudWindow.ShowDialog() | Out-Null
