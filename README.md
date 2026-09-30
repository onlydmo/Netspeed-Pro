# NetSpeed Pro

A lightweight Windows network HUD and bandwidth throttle utility built in PowerShell and WPF.

NetSpeed Pro provides an unobtrusive way to monitor network speeds, track per-app data usage on metered connections, and throttle specific applications.

## Privacy & Local Data
All data remains local.
- Session history and configuration are saved as JSON files (NetDataLog.json and NetConfig.json) in the project directory.
- No telemetry, analytics, or cloud sync.
- Network data is pulled via native Windows APIs (WMI, 
etstat) and never leaves the machine.
- Note: The .gitignore excludes personal JSON files to prevent accidental commits.

## Features
- **HUD Overlay:** A borderless, always-on-top UI. Includes a click-through mode so it doesn't block interactions.
- **Process Tracking:** Maps data usage to specific background processes using 
etstat and WMI, resolving intermediate shell wrappers to their parent applications.
- **Session History:** Double-click a session in the dashboard for a breakdown of parent and child process data consumption.
- **QoS Throttling:** Throttle upload/download speeds for specific apps via the dashboard using Windows QoS policies.
- **Data Quotas:** Configurable daily limits with visual HUD warnings when exceeded.
- **Export:** Export session history to CSV.

## Technical Details
The script (NetSpeedPro.ps1) runs a 1-second background loop:
1. **Stats:** Queries Get-NetAdapterStatistics for current UL/DL deltas.
2. **Scanning:** Uses 
etstat to map active TCP/UDP ports to processes.
3. **Throttling:** Wraps New-NetQosPolicy to apply bandwidth limits without requiring custom firewall drivers.
4. **UI:** Renders WPF windows directly from PowerShell (no C# compilation required).

## Setup

### Prerequisites
- Windows 10 or 11
- Administrator privileges (required for WMI process mapping and QoS policies; the script auto-elevates if needed).

### Installation
1. Clone this repository.
2. Right-click NetSpeedPro.ps1 and select **Run with PowerShell**.
3. (Optional) Create a desktop shortcut:
   - Target: powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Path\To\NetSpeedPro.ps1"

### Usage
- The HUD appears on launch.
- Find the NetSpeed Pro icon in the system tray (bottom right).
- Right-click the tray icon to open the Dashboard or toggle click-through mode.
- Use the Dashboard to view history, set quotas, or apply QoS limits.
