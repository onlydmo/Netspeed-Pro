# 🌐 NetSpeed Pro: Universal Project Chronicle

**Project Status:** Active / v2.5 Stable  
**Platform:** Windows (PowerShell 5.1+ / WPF / .NET)  
**Architecture:** Monolithic Script (`NetSpeedPro.ps1`) + JSON State (`NetDataLog.json`, `NetConfig.json`)

---

## 1. Project Vision
NetSpeed Pro was conceived to solve a specific problem: native Windows networking tools lack lightweight, easily accessible, and per-app granular tracking for metered connections (like Mobile Hotspots). 

The goal was to build a virtually invisible, un-intrusive desktop HUD that tracks live data usage, paired with a powerful Admin Dashboard to drill down into historical analytics and actively control background bandwidth hogs.

---

## 2. Development Milestones & Evolution

### Phase 1: The Core HUD (v1.0)
*   **WPF Overlay:** Created a frameless, transparent, always-on-top floating window.
*   **Telemetry Engine:** Implemented a 1-second tick loop using `Get-NetAdapterStatistics` to calculate real-time Upload/Download speeds.
*   **System Integration:** Added a System Tray icon for context menus and introduced **Ghost Mode** (P/Invoke `SetWindowLong`), allowing the user to click *through* the HUD without interrupting their workflow.

### Phase 2: Analytics & Storage (v1.5)
*   **Data Persistence:** Built a JSON serialization engine to log individual sessions, storing Start/End times, Wi-Fi SSID, and Total Bytes.
*   **Dashboard UI:** Created a secondary, styled WPF window with a dark-mode Zinc palette (#18181B) to display the Session History DataGrid.

### Phase 3: The "Deep Attribution" Engine Upgrade (v2.0)
*   **Auto-Elevation:** Implemented self-elevating code to ensure the script always runs as Administrator, unlocking deep network metrics and WMI access.
*   **Multi-App Attribution:** Upgraded from a single "Top App" tracker to a comprehensive scanner that uses `netstat -ano` every second to track *all* apps with `ESTABLISHED` connections, distributing data proportionally.
*   **Parent/Child Process Resolution:** Wrote a custom WMI tree-walker (`Get-CimInstance Win32_Process`) that maps background workers (like `language_server`) up to their true user-facing applications (like `Antigravity`), explicitly skipping invisible shell intermediaries (`powershell.exe`, `cmd.exe`).
*   **Drill-Down Breakdown:** Added a double-click event to the Dashboard. Clicking a session opens a new window showing data grouped by parent app. Clicking a parent app row expands a hidden `RowDetailsTemplate` revealing individual child processes and their exact byte usage.

### Phase 4: Active Governor & Control (v2.5)
*   **QoS Bandwidth Throttler:** Built a Tools & Settings tab leveraging Windows `New-NetQosPolicy`. 
*   **Smart UX:** Replaced manual text inputs with an auto-populating `ComboBox` that reads the current session's active apps. 
*   **Live Policy Tracking:** Added an active monitoring text block that queries Windows for live limits, turning Red when an app is currently throttled and Green when clear.
*   **Quota Safety Limits:** Added persistent daily data limits (`NetConfig.json`). The HUD calculates today's total data separately from the current session's data, preparing to warn the user if the quota is approached.

---

## 3. Core Engine Architecture

1.  **The Tick Loop (1000ms Timer)**
    *   *Every 1 sec:* Calculates global speed delta. Scans active PIDs. Distributes bytes to Parent/Child caches. Updates XAML UI bindings.
    *   *Every 10 sec:* Checks Wi-Fi SSID to detect Hotspot switches.
    *   *Every 30 sec:* Commits the current session state to `NetDataLog.json` to prevent data loss on sudden shutdown.
2.  **State Management**
    *   All UI variables and data arrays are held in the `$script:` scope to survive WPF's non-blocking `$window.Show()` event boundaries.
3.  **Theme & Styling**
    *   Fully custom XAML templates overriding default Windows UI elements. Uses #18181B (Background), #27272A (Surface), #F472B6 (Pink Accents), and #34D399 (Green Success).

---

## 4. Current Capabilities Summary

*   **HUD:** Live UL/DL speed, Current Session Total, Today's Total, Parent App Currently Using the Most Data.
*   **History:** Scrollable log of all past sessions, formatted with readable dates (MMM dd - HH:mm) and sizes (KB/MB/GB).
*   **Drill-Down:** Double-click any session to see exactly which apps (and child processes) consumed data during that specific time frame.
*   **Throttler:** One-click application of strict Upload/Download limits to any rogue app hogging the hotspot.
*   **Settings:** Export to CSV, Quota Management, Remove All Limits.

*Chronicle recorded as of September 30, 2026. The foundation is stable and ready for future expansions.*
