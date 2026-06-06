# PasswordMonitor

<p align="center">
  <img src="PasswordMonitor/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="PasswordMonitor app icon" width="128" />
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/kamilpopowicz/PasswordMonitor?label=release" />
  <img alt="License" src="https://img.shields.io/github/license/kamilpopowicz/PasswordMonitor" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-black" />
  <img alt="Swift" src="https://img.shields.io/badge/swift-5-F05138" />
</p>

PasswordMonitor is a macOS menu bar app that helps users keep track of corporate password expiration. It checks Active Directory metadata, notifies you ahead of expiration, lets AD/mobile users change their domain password from the app, and can run automatically in the background via a login item helper even when the main app is closed.

This repository currently provides **direct-distribution builds** produced through GitHub Releases only. GitHub Packages is not used for app distribution. Depending on your local setup, the builds may be ad hoc signed, so Gatekeeper can show a warning and users must open the app manually (right‑click → Open).

This project is open source under the MIT License. You can use, modify, and redistribute it, but the copyright notice and license text must remain with the code.

Author: Kamil Popowicz

Current version: **1.9.2**

---

## Quick Start (No Certificate)

### 1) Install
Download the latest release and install it into `/Applications` in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/kamilpopowicz/PasswordMonitor/main/scripts/install.sh | bash
```

If you prefer not to run a remote install script, download the `.zip` from Releases and drag `PasswordMonitor.app` into `/Applications`.

### 2) First Launch (Gatekeeper)
Because the app is unsigned, macOS will block it by default. To run it:

- Right‑click the app → **Open** → **Open**

This is required only the first time.

### 3) Enable Background Helper
If you want automatic checks:

`System Settings → General → Login Items → Allow in Background`

### 4) Updates
Open **About PasswordMonitor...** or use **Settings → Check for updates** to go to the single update panel.
The About window is the only place where update status, verification, and installation are handled.
Updates are verified with both SHA256 and a signed manifest before the app bundle is replaced.
PasswordMonitor does not auto-check on launch; update checks only start when you open the shared update panel or click a check button.
See [RELEASE.md](RELEASE.md) for the maintainer-facing release pipeline.

---

## Features
- Menu bar UI with at‑a‑glance password status
- Menu bar actions that open standalone windows close the popover first, while **Check now** stays inline and keeps the menu visible during refresh
- Background helper checks on login, wake, hourly cadence, and the configured notification time
- App startup cleans up stale helper processes from older app bundles so only the current embedded helper can own scheduled alerts
- Background helper is launched immediately after registration (no logout/restart required) and receives setting changes in real time via a shared preference suite
- Helper refreshes use a request-scoped ID so the same scheduled/wake/manual cycle cannot re-enter the alert path twice
- Alerts and snooze support for expiring passwords
- Automatic helper alerts stay silent while `PasswordMonitor.app` is active; the alert is only surfaced when the main app is inactive
- Duplicate alerts for the same `expirationDate` are suppressed for a short window, and the scheduled notification slot is only handled once so a single trigger cannot surface twice in a row
- Snooze state and “shown today” persist across relaunch and are shared between the main app and helper
- Manual checks and the configured notification time can intentionally break through quiet hours
- Menubar **Check now** performs a live refresh and, by design, bypasses `shownToday` and active `snooze` so a user-initiated manual verification always surfaces the latest state
- Scheduled notification moment overrides an active snooze: if snooze is active and the scheduled hour arrives, the alert fires and a fresh snooze window starts from that moment
- In-app AD/mobile password change flow through OpenDirectory, with inline validation, password strength feedback, mapped domain policy errors, automatic login-keychain password synchronization, and a Touch ID & Password fallback
- Password-change actions from scheduled helper alerts activate the main app before presenting the in-app password window
- Settings for notification time, warning threshold, quiet hours, and read-only AD domain info pulled from the system configuration
- Single in-app update flow centered on the About window, with Settings and the menu bar linking into the same panel
- Menu open performs a live AD check (with a 30s timeout) before showing alerts
- Alert countdown format is fixed to 2 lines: line 1 is day count, line 2 is `HH:mm:SS`
- Password-change action from menu is blocked until domain/VPN availability is confirmed
- Automatic AD node resolution keeps the read-only domain (FQDN) in sync with the system’s Users & Groups entry so `dscl` can still read `SMBPasswordLastSet`
- Built‑in logs viewer with filtering, copy, and Finder reveal
- Privacy-safe log masking for host/domain values
- Runtime language switching (English/Polish)
- AI-assisted on-device translation hardening:
  - rejects unsafe/broken translations,
  - falls back to English when needed,
  - retries problematic keys (immediate multi-attempt + deferred self-heal retries)
- Language Assist includes a manual **Retry problematic** action for failed keys
- Manual Light/Dark/Auto theme switching with guarded shared UI tokens for spacing, opacity, and default window sizing
- Dashboard UX contract for the 2.0 self-service direction, separating app destinations, service modules, dashboard bubbles, and motion rules; see [docs/dashboard-ux-implementation-contract.md](docs/dashboard-ux-implementation-contract.md)
- Future dashboard modules (`hrPortal`, `networkDrives`) use a formal placeholder contract (state/actions/presentation mapping) until backend integrations are introduced
- Dashboard module status messages use semantic keys in Core and localized copy in UI resources (no user-facing copy hardcoded in Core models)
- Penpot UX boards are synchronized with the 2.0 semantic contract and canonical naming (`01 App Screens` + `02 Components`), with final canonical-board verification completed (see `docs/task8-penpot-verification-report.md`)
- Safe custom updater architecture; see [SECURITY.md](SECURITY.md) for the updater threat model and hardening details.
- Settings → Delete app unregisters the helper, unloads legacy LaunchAgents, terminates running helper processes, and removes app/helper preferences plus local app data

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
   - Language (with optional AI-assisted detection and retry of problematic keys)
3. The app will check your password status and alert you as needed.
4. Use **Change password** from the menu or expiration alert to change an AD/mobile account password in app. If the domain controller is unavailable, connect VPN or corporate network first.
5. Automatic background checks respect quiet hours, but a manual check and the exact configured alert time can still show the alert when needed.
6. Use **Logs** for troubleshooting or export.

---

## AI Translation Reliability
PasswordMonitor uses on-device Apple Intelligence translation when available. The app treats generated localization as best-effort and applies strict validation before rendering it.

### Validation and fallback
- Placeholder mismatch or marker leaks are rejected.
- Raw localization-key-looking output is rejected.
- Prompt-echo style outputs are rejected.
- Rejected values automatically fall back to base English.

### Retry model (lightweight)
- Per key, translation uses up to 3 attempts in one pass.
- Keys that still fail are queued as “problematic”.
- Deferred retries:
  - once after 1 hour from translation completion,
  - once per app launch day on startup.
- Manual retry is available in Settings → Language Assist (`Retry problematic`).

This approach avoids aggressive hourly background workloads while still self-healing most temporary model/device quality issues.

---

## Logging
Logs are stored locally and can be viewed in the **Logs** window. You can copy or filter logs, reveal the log file in Finder, and export the current view.
The Logs window supports auto refresh with three modes: immediate (default), 1 minute, or 5 minutes.
The main app and background helper use one inter-process-safe writer, control characters are escaped to preserve log integrity, and active, rotated, lock, and exported log files are restricted to the current user (`0600`).
Release builds do not mirror PasswordMonitor logger entries to stdout. The password-change flow does not write password values, keychain secrets, or raw `dscl` output to the app log; password-change and keychain-sync failures use stable `PM-PWD-*` and `PM-KCH-*` diagnostic codes.

> Tip: Logs are masked and restricted locally, but they can still contain diagnostic metadata about the environment. Review exported logs before sharing them.

---

## License
See [LICENSE](LICENSE) for the MIT License. Copyright remains with Kamil Popowicz.
