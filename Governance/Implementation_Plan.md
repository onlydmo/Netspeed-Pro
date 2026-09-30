# NetSpeed Pro Suite: v2 Upgrade Plan

## Overview
Based on your feedback, we are expanding the Dashboard into a fully interactive command center. The script will be upgraded to run as Administrator by default, unlocking powerful new tools like exact per-app data tracking, one-click bandwidth throttling, and editable data caps.

---

## Proposed Changes

### 1. Auto-Elevation (Administrator Mode)
* **Self-Elevating Engine:** The script will check its permissions on startup. If it is not running as Administrator, it will automatically relaunch itself using `RunAs`. This ensures it always has the permissions required to apply QoS limits and accurately read network stacks.

### 2. Per-App Data Breakdown & Drill-Down UI
* **App-Bandwidth Attribution Engine:** Instead of just logging one "Top App", the background engine will calculate and distribute the downloaded bytes to the active apps every second. This generates a complete profile of how much data *each* app used during a session.
* **Interactive Dashboard:** You will be able to **double-click** any session in the History Table. This will open a new "Session Details" view showing a list of every app that consumed data during that session.
* **Sorting Filters:** The detailed view will include column headers that can be clicked to sort the apps from Highest Data Used to Lowest (and vice versa).

### 3. Interactive Bandwidth Throttler (QoS UI)
* **Throttle Button:** The "Tools & Settings" tab will be upgraded with a functional UI for the QoS Throttler.
* **Inputs:** You can type in an app name (e.g., `msedge.exe`), select a speed limit (e.g., `500 KB/s`), and click an **"Apply Limit"** button to throttle it instantly.
* **Reset Button:** A "Remove All Limits" button to instantly restore full speed to all apps.

### 4. Editable Daily Quota
* **Quota Settings:** A new section in the "Tools & Settings" tab will allow you to type in your custom Daily Quota (e.g., `2.5 GB` or `500 MB`).
* **Save Config:** Clicking "Save Quota" will permanently store this limit so the HUD knows exactly when to warn you or trigger the safety disconnect on future runs.

---

## Verification Plan
1. Launch the script normally and verify the Windows UAC prompt appears to elevate it to Admin.
2. Generate network traffic with multiple apps (e.g., Edge, Spotify), double-click the session in the Dashboard, and verify the Per-App Breakdown accurately reflects the data distribution.
3. Throttle an app via the new UI button and verify `Get-NetQosPolicy` registers the rule.
