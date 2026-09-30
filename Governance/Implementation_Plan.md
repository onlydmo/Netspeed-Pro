# NetSpeed Pro - Implementation Plan (v2.0 - v2.5)

## Overview
This plan outlines the upgrades required to expand the Dashboard into an interactive command center, incorporating auto-elevation, per-app data tracking, bandwidth throttling, and configurable data caps.

---

## Component Changes

### 1. Privilege Escalation
* **Auto-Elevation:** Check permissions on startup. If not elevated, restart the process using RunAs. Required for New-NetQosPolicy and WMI process mapping.

### 2. Data Attribution & Drill-Down
* **Attribution Engine:** Modify the background loop to attribute downloaded/uploaded bytes proportionally to all active TCP/UDP connections rather than a single "Top App".
* **Dashboard Drill-Down:** Add a double-click event to the session history DataGrid to open a hierarchical view.
* **Process Mapping:** Implement a RowDetailsTemplate showing parent applications and their associated child processes.

### 3. QoS Throttling UI
* **Throttler Controls:** Add UI components in the "Tools & Settings" tab to manage QoS policies.
* **App Selection:** Implement a ComboBox populated with active apps from the current session.
* **Policy Management:** Add "Apply" and "Remove All" buttons, wrapping New-NetQosPolicy and Remove-NetQosPolicy.
* **Active Limits Display:** Add a visual indicator showing currently active policies.

### 4. Quota Configuration
* **Editable Quotas:** Add inputs in "Tools & Settings" to configure daily data limits (MB/GB).
* **Persistence:** Save limits to NetConfig.json and load on startup.
* **Visual Warning:** Update the HUD tick loop to flash warning colors if $script:dailyBytes exceeds the configured quota.

---

## Verification
1. Verify the script triggers a UAC prompt on launch if not elevated.
2. Generate multi-app traffic, double-click the session in the Dashboard, and confirm the RowDetailsTemplate displays correct child processes.
3. Apply a throttle via the UI and verify Get-NetQosPolicy registers the rule.
