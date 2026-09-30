# 🌐 NetSpeed Pro

A lightweight, native Windows bandwidth governor and network HUD built entirely in PowerShell and WPF.

NetSpeed Pro solves a specific problem: native Windows networking tools lack un-intrusive, easily accessible, per-app granular tracking for metered connections (like Mobile Hotspots). 

## 🛡️ Privacy Guarantee (100% Local)
**NetSpeed Pro is designed with extreme privacy in mind.**
- **Local Storage Only:** All session data, logs, and configurations are stored as raw JSON files (NetDataLog.json and NetConfig.json) directly in this folder.
- **No Cloud Sync:** There is no telemetry, no cloud backups, and no external tracking.
- **Secure Architecture:** The tool simply reads native Windows APIs locally (like WMI and 
etstat) and logs the results. Your network data never leaves your machine. 
*(Note: If you clone or fork this repository, the .gitignore specifically excludes these JSON files so you never accidentally upload your personal data to GitHub.)*

---

## ✨ Features

- **Ghost Mode HUD:** A frameless, dark-mode, always-on-top floating UI. Click right through it without interrupting your workflow.
- **Deep Attribution Engine:** Tracks data usage down to the individual background process using 
etstat and WMI, actively cutting through invisible shell wrappers (like cmd or powershell) to group usage accurately.
- **Session Drill-Down Matrix:** Double-click any past session in the Dashboard to see an exact hierarchical breakdown of parent applications and child processes.
- **QoS Bandwidth Governor:** Rogue app hogging your hotspot? Apply instant upload/download throttles to any active app directly from the dashboard using Windows Quality of Service (QoS) policies.
- **Daily Quota Alerts:** Set your GB/MB limits for the day. The HUD will flash aggressively if you approach your safety limit.
- **CSV Data Portability:** One-click export of all session analytics.

---

## ⚙️ How It Works (Technical Architecture)
NetSpeed Pro is a monolithic script (NetSpeedPro.ps1) that executes a 1000ms telemetry loop:
1. **Network Adapters:** Uses Get-NetAdapterStatistics for high-speed, accurate Delta measurements (Current UL/DL speeds).
2. **Connection Scanning:** Scans active TCP/UDP ports to resolve PIDs to Applications.
3. **Bandwidth Throttling:** Utilizes New-NetQosPolicy under the hood to limit apps without installing invasive third-party firewall drivers.
4. **WPF UI:** Renders native Windows Presentation Foundation (WPF) windows purely from PowerShell, circumventing the need for compiled C# binaries.

---

## 🚀 Setup Walkthrough

### 1. Prerequisites
- Windows 10 or 11
- Administrator Privileges (The script requires Admin rights to read WMI process trees and apply QoS policies. It is coded to auto-elevate itself upon launch).

### 2. Installation
1. Download or clone this repository to a secure location (e.g., your Documents folder).
2. **Right-click** NetSpeedPro.ps1 and select **Run with PowerShell**.
3. *Optional but recommended:* Create a Desktop Shortcut for instant access. 
   - Right-click your Desktop -> New -> Shortcut.
   - For the location, enter: powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Path\To\Your\NetSpeedPro.ps1"
   - Click Next and name it **NetSpeed Pro**.

### 3. Usage
- The HUD will instantly appear on your screen.
- **System Tray:** Find the NetSpeed Pro icon in your Windows taskbar tray (bottom right). Right-click it to access the Dashboard or toggle Ghost Mode.
- **Dashboard:** Open the Dashboard to view your Session History, set your Daily Quotas, and access the App Bandwidth Throttler.

