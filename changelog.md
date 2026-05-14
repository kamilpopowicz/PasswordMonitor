# Changelog

All notable changes to this project will be documented in this file.

## Unreleased
- Replaced Sparkle-based updates with a custom GitHub Releases updater:
  - checks `releases/latest`,
  - compares the remote version with `CFBundleShortVersionString`,
  - downloads only the expected `.app.zip` and signed manifest assets,
  - verifies the manifest signature with an embedded public key,
  - verifies SHA256 before installation,
  - stages extraction on the same volume and rejects zip-slip / symlink payloads,
  - performs a guarded bundle swap and relaunch from the shared update panel.
- Centralized the UI into a single About window update panel:
  - Settings, the menu bar, and the app menu all open About for update actions,
  - opening About alone does not trigger a check,
  - clicking `Check for updates` in any entry point sends the request to the same panel.
- Added a Settings `Updates` section with current version and a `Check for updates` entry point that forwards to About.
- Added core tests for semantic version ordering, archive path validation, symlink rejection, and manifest signature verification.

## PasswordMonitor 1.7.2
- `Delete app` now also unloads and removes the legacy `com.company.password-monitor` LaunchAgent plus its shell/log artifacts, preventing old pre-login-item installs from continuing to fire alerts after the app is removed.
- Added cleanup coverage and stronger uninstall behavior: `Delete app` now unregisters and terminates the helper, removes main/helper/shared preferences, and deletes app/helper user data paths.
- Added unit tests for stale helper selection, duplicate helper filtering, and uninstall cleanup paths.
- Main app and helper now clean up stale helper processes from older app bundles so an old login item cannot keep firing duplicate scheduled alerts after an update.
- Main app periodic timer no longer emits `scheduledTime`; scheduled notifications are owned by the helper only, and bare scheduled live refreshes without a helper `requestID` are rejected.
- Split notification evaluation from live refresh so `scheduledTime` no longer re-enters the same decision path after helper refresh completes.
- Main app periodic notification timer now bails out when the helper process is actually running, so `scheduledTime` is owned by one process instead of being evaluated twice through an unreliable service-status check.
- Added an in-process scheduledTime slot guard so the same slot cannot be handled twice by the same helper session even if a second callback slips through after the first alert.
- Scheduled `scheduledTime` refreshes now perform exactly one explicit notification decision in the helper after the live refresh completes, instead of letting `NotificationManager` auto-check and then re-enter the same slot again through a second callback.
- Prevented duplicate helper alerts for the same expiration cycle:
  - settings changes now only sync configuration and reschedule the next check,
  - scheduled refreshes are deduplicated in the helper so the same scheduled slot does not re-enter the alert flow twice and the same `expirationDate` does not re-present twice in a short window,
  - the `scheduledTime` decision now claims the slot before any live refresh so a second callback for the same slot cannot reach the alert path,
  - helper live refresh and notification decision now share one request-scoped identifier so the same refresh cannot re-enter the alert path through a second callback,
  - alert presentation now keeps a short-lived duplicate guard for the same `expirationDate`,
  - automatic alerts are suppressed while `PasswordMonitor.app` is active.
- Restored user-intent semantics for manual verification (issues #34/#30/#29 follow-up):
  - `checkNow` again bypasses the `shownToday` gate so a manual "Check now" always surfaces the latest state, even if an alert already fired earlier today,
  - manual/`checkNow` still displays the alert despite active snooze, but no longer clears the snooze state globally (automatic/scheduled checks keep respecting the existing snooze window).
- Scheduled notification moment now overrides both the `shownToday` gate and an active snooze:
  - if an alert already fired earlier today, the scheduled hour still triggers another one,
  - if snooze is active until, e.g., 10:01 and the scheduled hour is 09:30, the alert fires at 09:30,
  - the old snooze state is cleared at that moment so any new snooze starts fresh from the scheduled trigger.
- Updated unit coverage: `testScheduledNotificationsBypassActiveSnooze` asserts scheduled triggers are not suppressed by snooze.
- Ensure the helper process is actually running after registration: main app now launches the embedded helper via `NSWorkspace.openApplication` when `SMAppService` reports enabled but the process is not alive (previously `.status == .enabled` only meant "registered for next login", so scheduled alerts never fired until logout/restart).
- Cross-process settings consistency (main app ↔ helper):
  - main app now mirrors saved settings to the shared suite `popo.PasswordMonitor` (values previously lived only in the main app's own `UserDefaults.standard` plist, so the helper process never saw user-changed thresholds or notification time),
  - save/reset now posts `HelperForceRefresh` distributed notification so the helper immediately re-syncs via `syncSharedSettings` and re-schedules the next notification moment,
  - helper now logs a full settings snapshot after every `syncSharedSettings` (so log diagnostics show exactly what the helper is operating on),
  - main app logs a full settings snapshot at launch (`Settings loaded at launch: ...`) instead of only the notification hour.
- Settings logging discipline:
  - removed `.onChange` logs for notification time / quiet hours (they fired on every UI tick before Save and created misleading log noise),
  - added a single `Settings saved: ...` log with a diff of changed keys only, emitted from the Save path,
  - removed the redundant load-time log for the notification hour (replaced by the full startup snapshot above).
- Helper process no longer runs the periodic 60-second `checkTimer` from `NotificationManager.startCheckingForNotificationTime`:
  - the helper has its own one-shot scheduled timer plus wake observer in `HelperAppDelegate`,
  - the extra periodic timer was duplicating every `Notification check: reason=automatic` log entry and reading stale `UserDefaults` between `syncSharedSettings` ticks.

## PasswordMonitor 1.7
- Fixed duplicate alert behavior after wake/manual check by removing runtime bypasses of:
  - `shownToday` gate for `checkNow`,
  - active snooze for `manual/checkNow`.
- Hardened startup domain state for notifications and password-change action:
  - domain is treated as unavailable until a refresh confirms connectivity.
- Updated alert countdown presentation to a strict two-line format:
  - line 1: day count only,
  - line 2: `HH:mm:SS` only.
- Menubar password-change action now requires confirmed domain availability.

## PasswordMonitor 1.6.0
- Reworked AI localization safety pipeline so low-quality outputs are rejected instead of rendered in UI:
  - placeholder integrity checks (`%@`, `%lld`, `%%`, `stringsdict` plural forms),
  - rejection of raw key-looking outputs (for example `alert_title_*`, `menu_*`),
  - rejection of PH marker leaks (`[PH_0]`, `[[PH_0]]`, `{PH_0}`, variants),
  - prompt-echo rejection (for example “Translate UI text key …”),
  - automatic fallback to base English when custom value is unsafe or empty.
- Added translation retry policy per key (up to 3 attempts in a single translation pass).
- Added persistent queue of problematic localization keys in user Application Support custom localization files.
- Added deferred self-heal retry of problematic keys:
  - once, 1 hour after translation completes,
  - once per app launch day (startup retry), no hourly background loop.
- Added manual retry control in `Settings → Language Assist` next to detect/permissions actions:
  - retries only queued problematic keys,
  - shows attempt/fixed/remaining status in Language Assist message.
- Hardened runtime localization fallback in alert/logger/menu paths so broken custom values are replaced by safe base text.
- Added dedicated menu check reason (`checkNow`) to support stronger manual verification from menubar “Check now”:
  - bypasses `shownToday` gate,
  - bypasses active snooze,
  - bypasses quiet-hours suppression.
- Preserved language-agnostic architecture: no language-specific hardcoded dictionaries/overrides for FR/DE/ES.

## PasswordMonitor 1.5.8
- Revamped Logs view with a Console.app-style toolbar, improved multi-line selection, and reliable live updates.
- Added in-window auto-refresh modes for Logs (immediate, 1 minute, 5 minutes) and default follow-latest behavior.
- Added AI language detection actions (on-device), permissions checklist window, and system-language prompt on launch.

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
