# Changelog

All notable changes to this project will be documented in this file.

## PasswordMonitor 1.5.8
- Revamped Logs view with a Console.app-style toolbar, improved multi-line selection, and reliable live updates.
- Added in-window auto-refresh modes for Logs (immediate, 1 minute, 5 minutes) and default follow-latest behavior.

## PasswordMonitor 1.5.4
- AD domain resolver now matches the system’s FQDN against the available DSCL nodes so manual checks succeed with the read-only value shown in Settings.
- NotificationManager suppresses repeated “Brak daty wygaśnięcia hasła” logs and keeps the cached expiration date ready for future checks, ensuring helper/menu retries don’t spam AD.
- SMBPasswordLastSet parsing now selects the newest timestamp when multiple entries are returned (e.g., when reading via Search).
- Helper now checks cached expiration data on launch and wake so notifications can appear even when the main app is closed.
- Wake observer now uses NSWorkspace’s notification center to ensure it fires for the login item.
- Helper now resolves localized alert strings from the host app bundle so button labels render correctly.
- Menu bar now only shows “domain unavailable” after a real refresh attempt and disables “Zmień hasło” when the domain is confirmed unavailable.
- Prevented duplicate alerts by skipping automatic checks in the main app when the helper login item is enabled and by avoiding alert checks on menu open.
- Added resolver matching tests for the new node-selection logic and updated QA guidance to record the automated `xcodebuild test` run despite DerivedData permission warnings.

## PasswordMonitor 1.5.5
- Added shared, persisted notification state so snooze and “shown today” survive relaunch and stay consistent between main app and helper.
- Live-checks now run before alerts and menu opens, with a 30s timeout and cache fallback to avoid blocking.
- Offline domain alerts now disable “Change password”, allow snooze in urgent cases, and show a VPN message.
- Added 1-hour recheck scheduling for urgent expirations and offline snooze flows.

## PasswordMonitor 1.5.6
- Added explicit menu refresh start/finish logs to confirm live-check timing.
- Reduced duplicate helper settings sync on launch.

## PasswordMonitor 1.5.7
- Debounced menu refresh to prevent back-to-back live checks when the menu opens.

## PasswordMonitor 1.5.3
- Reduced AD query volume by throttling auto-refreshes, deduplicating in-flight requests, and relying on cached results when cooldown is active.
- Helper now only refreshes on wake or the configured notification time.
- Settings show the system domain in read-only mode, with the value pulled from macOS’s Users & Groups configuration.

## PasswordMonitor 1.5.2
- Centralized password-status refresh so the app, helper, menu bar, and scheduled checks use the same fetch/update/alert path.
- Fixed the menu bar open path so opening the menu no longer behaves like a manual alert trigger.
- Updated quiet-hours and snooze behavior so manual checks and the configured notification time can intentionally break through, while automatic background checks still stay quiet.
- Fixed the test alert so `Zakończ test` closes the test window correctly.
- Cleaned up Polish and English UI copy for helper refresh and quiet-hours descriptions.

## PasswordMonitor 1.5.1
- Fixed a day-count mismatch where the menu bar could show stale `days remaining` while the alert used the live expiry date.
- Unified remaining-day calculations so the menu bar, alert, cache fallback, and warning logic all use the same expiry-date-based path.
- Added regression coverage for cache reloads and shared day-count calculation.

## PasswordMonitor 1.5
- Restored the login-item helper as a real background path that checks password expiry even when the main app is closed.
- Added helper refresh scheduling for launch, wake, hourly checks, and the configured notification time.
- Added editable quiet hours to reduce unnecessary background AD queries overnight.
- Added a debug-only manual helper refresh action in Settings.
- Fixed the alert threshold so blocking password alerts only appear at the configured warning threshold or below.
- Added smoke-test documentation and unit coverage for helper scheduling and quiet-hours logic.

## PasswordMonitor 1.4
- Unified window panel styling and minimum size across app windows.
- Fixed menu bar window layout alignment.
- Added host/domain masking for logs.
- Improved notification/snooze stability and cleanup.
- Added core test target with coverage for cache, parsing, and notifications.

## PasswordMonitor 1.3
- Added app-wide theme switching with improved performance and a transition loader.
- Unified button styling and disabled-state visuals.
- Improved Logs rendering during theme changes to avoid heavy UI stalls.
- Minor localization catalog cleanup.

## PasswordMonitor 1.2
- Added in-app reset and delete actions for settings and app data.
- Fixed helper toggle behavior on Save to prevent unwanted UI reopen.
- Added immediate password check after domain change.
- Added localization check script to the build pipeline.

## PasswordMonitor 1.1
- Added privacy-first logging with PII masking (usernames, domains, paths, emails).
- Added Minimal Logging mode (debug logs disabled by default).
- Added privacy copy in Logs view and helper background explanation in Settings.
- Removed hardcoded AD domain from build; domain is now user-configured only.
- Updated menu bar icon handling and app icon assets.
- Added live log viewer with search, filters, and auto-scroll improvements.
- Added `Cmd+L` shortcut for Logs window.
- Simplified entitlements to the minimum required set.
- UI polish: log layout consistency and copyright footer.
- General stability fixes and localization polish.

## PasswordMonitor 1.0
- Menu bar app that checks password expiration and shows alerts.
- Background helper for scheduled checks at a chosen time.
- Settings for AD domain, password age, and warning threshold.
- Basic localization (English, Polish).
