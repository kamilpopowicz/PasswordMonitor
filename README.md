# PasswordMonitor

PasswordMonitor is a macOS menu bar app that helps users keep track of corporate password expiration. It checks Active Directory metadata, notifies you ahead of expiration, and can run automatically in the background via a login item helper even when the main app is closed.

This repository currently provides **an unsigned build for testing** (no Apple Developer certificate). That means Gatekeeper will show a warning and users must open the app manually (right‑click → Open).

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
- Settings for notification time, warning threshold, AD domain, and quiet hours
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
   - Notification time
   - Quiet hours
   - Warning threshold
   - Launch at login
3. The app will check your password status and alert you as needed.
4. Use **Logs** for troubleshooting or export.

---

## Logging
Logs are stored locally and can be viewed in the **Logs** window. You can copy or filter logs and reveal the log file in Finder.

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
