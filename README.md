# PasswordMonitor

PasswordMonitor is a macOS menu bar app that helps users keep track of corporate password expiration. It checks Active Directory metadata, notifies you ahead of expiration, and can run automatically in the background via a login item helper even when the main app is closed.

This repository currently provides **testing builds**. Depending on your local setup, they may be unsigned, so Gatekeeper can show a warning and users must open the app manually (right‑click → Open).

Current version: **1.5.7**

---

## Quick Start (No Certificate)

### 1) Download
Get the latest unsigned build from **Releases** as a `.zip` containing `PasswordMonitor.app`.

### 2) Move to Applications
Drag `PasswordMonitor.app` to `/Applications`.

### 3) First Launch (Gatekeeper)
Because the app is unsigned, macOS will block it by default. To run it:

- Right‑click the app → **Open** → **Open**

This is required only the first time.

### 4) Enable Background Helper
If you want automatic checks:

`System Settings → General → Login Items → Allow in Background`

---

## Features
- Menu bar UI with at‑a‑glance password status
- Background helper checks on login, wake, hourly cadence, and the configured notification time
- Alerts and snooze support for expiring passwords
- Snooze state and “shown today” persist across relaunch and are shared between the main app and helper
- Manual checks and the configured notification time can intentionally break through quiet hours and active snooze
- Settings for notification time, warning threshold, quiet hours, and read-only AD domain info pulled from the system configuration
- Menu open performs a live AD check (with a 30s timeout) before showing alerts
- Automatic AD node resolution keeps the read-only domain (FQDN) in sync with the system’s Users & Groups entry so `dscl` can still read `SMBPasswordLastSet`
- Built‑in logs viewer with filtering, copy, and Finder reveal
- Privacy-safe log masking for host/domain values
- Runtime language switching (English/Polish)
- Manual Light/Dark/Auto theme switching

## Tech Stack
- Swift 5 / SwiftUI
- AppKit integration (alerts, menu bar)
- ServiceManagement (login item helper)
- NaturalLanguage (optional language detection)

---

## Usage
1. Launch the app — it appears in the menu bar.
2. Open **Settings** to configure:
   - Active Directory domain
      - (read-only; pulled from System Settings → Users & Groups, while the resolver picks the matching DSCL node internally)
   - Notification time
   - Quiet hours
   - Warning threshold
   - Launch at login
3. The app will check your password status and alert you as needed.
4. Automatic background checks respect quiet hours, but a manual check and the exact configured alert time can still show the alert when needed.
5. Use **Logs** for troubleshooting or export.

---

## Logging
Logs are stored locally and can be viewed in the **Logs** window. You can copy or filter logs, reveal the log file in Finder, and export the current view.
The Logs window supports auto refresh with three modes: immediate (default), 1 minute, or 5 minutes.

> Tip: For privacy, avoid sharing logs that may contain sensitive data.

---

## Build From Source (Optional)
If you want to build it yourself:

```bash
xcodebuild -project PasswordMonitor.xcodeproj -scheme PasswordMonitor -destination 'platform=macOS' build
```

---

## Roadmap
- Add unit tests for core logic
- Improve privacy controls (PII masking)
- Refactor alert UI out of core module

---

## License
Specify a license here (e.g., MIT). If not specified, all rights reserved.
