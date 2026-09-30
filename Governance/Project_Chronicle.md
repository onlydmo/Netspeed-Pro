# NetSpeed Pro - Project History

**Project Status:** Active / v2.5 Stable  
**Platform:** Windows (PowerShell 5.1+ / WPF / .NET)  
**Architecture:** Monolithic Script (NetSpeedPro.ps1) + JSON State (NetDataLog.json, NetConfig.json)

---

## 1. Project Overview
NetSpeed Pro tracks network data usage on a per-app basis for Windows environments, aimed primarily at metered connections. It pairs a low-overhead, transparent desktop HUD with a dashboard for historical analytics and bandwidth throttling.

---

## 2. Development Milestones

### v1.0 (Core Engine)
*   **WPF Overlay:** Frameless, transparent floating window.
*   **Telemetry Loop:** 1-second interval using Get-NetAdapterStatistics for real-time Upload/Download speeds.
*   **System Integration:** System Tray icon context menu and click-through mode via P/Invoke (SetWindowLong).

### v1.5 (Analytics & Storage)
*   **Data Persistence:** JSON serialization engine logs sessions, storing Start/End times, Wi-Fi SSID, and Total Bytes.
*   **Dashboard UI:** WPF window with custom dark theme for viewing session history.

### v2.0 (Attribution Logic Upgrade)
*   **Auto-Elevation:** Self-elevating code to run as Administrator for WMI/network metrics access.
*   **Multi-App Attribution:** Scanner uses 
etstat -ano per tick to track active connections, distributing bytes proportionally.
*   **Process Resolution:** Custom WMI tree-walker (Get-CimInstance Win32_Process) maps background processes to their parent applications, skipping intermediate shells (e.g., powershell.exe).
*   **Session Drill-Down:** Dashboard supports double-clicking a session to view parent/child process data usage via a RowDetailsTemplate DataGrid.

### v2.5 (QoS Integration)
*   **Bandwidth Throttling:** UI wrapper around Windows New-NetQosPolicy.
*   **App Selection:** Auto-populating ComboBox showing apps from the current session.
*   **Policy Tracking:** Queries and displays active QoS limits in the dashboard.
*   **Data Quotas:** Configurable daily limits saved to NetConfig.json, with visual HUD warnings.

---

## 3. Architecture

1.  **Event Loop (1000ms)**
    *   *Every 1s:* Calculate speed delta, scan active PIDs, distribute bytes to process caches, update XAML bindings.
    *   *Every 10s:* Check Wi-Fi SSID for connection changes.
    *   *Every 30s:* Save session state to NetDataLog.json.
2.  **State Management**
    *   Variables are maintained in the $script: scope to persist across non-blocking WPF ($window.Show()) event handlers.
3.  **UI Design**
    *   Custom XAML templates overriding default controls.

---

## 4. Feature Summary

*   **HUD:** Live UL/DL speed, Current Session Total, Today's Total, Top App.
*   **History:** Log of past sessions (MMM dd - HH:mm) and data sizes.
*   **Drill-Down:** Parent/child process breakdowns per session.
*   **Throttling:** Apply Upload/Download limits to background apps.
*   **Settings:** CSV Export, Quota Management, Limit Removal.

*Last Updated: 2026-09-30*
