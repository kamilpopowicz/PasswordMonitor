# Changelog

All notable changes to this project will be documented in this file.

## PasswordMonitor 1.1
- Added privacy-first logging with PII masking (usernames, domains, paths, emails).
- Added Minimal Logging mode (debug logs disabled by default).
- Added privacy copy in Logs view and helper background explanation in Settings.
- Removed hardcoded AD domain from build; domain is now user-configured only.
- Updated menu bar icon handling and app icon assets.
- Added live log viewer with export/clear actions and auto-scroll improvements.
- General stability fixes and UI polish for alerts and localization.

## PasswordMonitor 1.0
- Menu bar app that checks password expiration and shows alerts.
- Background helper for scheduled checks at a chosen time.
- Settings for AD domain, password age, and warning threshold.
- Basic localization (English, Polish).
