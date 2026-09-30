---
title: "NetSpeed Pro v2.5 - Final Windows Architecture"
date: "2026-09-30"
category: "feature"
tags: ["powershell", "wpf", "qos", "wmi", "networking", "windows-internals"]
---

# NetSpeed Pro v2.5 - Final State

## Overview
Completed the NetSpeed Pro Windows architecture (v1.0 to v2.5). The script evolved from a simple floating UI into a complex bandwidth governor and attribution engine.

## Key Technical Learnings & Solutions

### 1. WMI Parent-Child Resolution Skipping Shells
**Problem:** language_server was showing up independently because it was spawned by powershell.exe, disconnecting it from its true parent Antigravity.
**Solution:** Built a recursive WMI tree-walker (Get-CimInstance Win32_Process) that actively skips known shell intermediaries (pwsh, powershell, cmd, bash, wsl, WindowsTerminal, OpenConsole).

### 2. Multi-App netstat Attribution
**Problem:** Previous engine only tracked the #1 highest connection app, meaning drill-downs were empty.
**Solution:** Modified the 1-second tick loop to process all active connections from netstat -ano. Mapped PIDs to processes, resolved parents, and distributed data proportionally based on active socket counts.

### 3. Windows QoS Throttling via PowerShell
**Problem:** Need non-intrusive way to throttle bandwidth of background apps.
**Solution:** Used New-NetQosPolicy -AppPathNameMatchCondition. 
**Gotcha:** Requires Administrator privileges (implemented self-elevation). Replaced manual typing with an auto-populating WPF ComboBox containing live session apps.

### 4. WPF Non-Blocking Scoping
**Problem:** Changing Dashboard from ShowDialog() to Show() broke the UI event handlers because variables went out of scope.
**Solution:** Promoted all UI element references (e.g., $txtQosLimit) to the $script: scope before attaching .Add_Click handlers.

## Next Steps
Project is frozen for Windows. Next phase discussed is a mobile rewrite targeting Android, which will require replacing NetQosPolicy with a Local VpnService for throttling.
