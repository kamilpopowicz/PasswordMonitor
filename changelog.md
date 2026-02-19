# Changelog

All notable changes to this project will be documented in this file.

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
