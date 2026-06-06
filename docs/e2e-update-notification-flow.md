# E2E: Update Notification Flow

Use this checklist when the implementation is ready for final manual E2E validation.

## Preparation

- Build or install an older PasswordMonitor version than the release under test.
- Confirm notification permission is either freshly unset or intentionally allowed for PasswordMonitor.
- Confirm the login item helper is enabled in System Settings.
- Reset or record the shared update defaults before each scenario when checking cooldown behavior.
- Prepare two signed release manifests: one with `urgency: "normal"` and one with `urgency: "critical"`.

## Normal Update

- Launch the older app and confirm the automatic check detects the newer GitHub Release.
- Verify a regular macOS notification appears for the available update.
- Verify each visible app window shows a subtle update badge without layout overlap: menu bar popover, Settings, Logs, About, and password-change window.
- Click the badge and confirm it starts the verified update flow directly.
- Click the macOS notification action/body and confirm it starts the verified update flow directly.
- Confirm repeated badge or notification clicks do not start duplicate downloads or duplicate install flows.
- Use `Remind later` and verify regular update prompts are suppressed for 7 days.
- Confirm the About window still supports manual check, download, verification, install, and relaunch.

## Critical Update

- Publish or point the app at a signed manifest with `urgency: "critical"`.
- Launch the older app and confirm a time-sensitive macOS notification appears.
- Verify regular app views are blocked with stable critical-update copy until installation starts or completes.
- Verify the About/update path remains available.
- Verify password-expiration notifications are paused while the critical update is pending.
- Confirm `Remind later` does not hide or downgrade the critical blocker.
- Click the blocker action and confirm it starts the verified update flow directly.
- Simulate a failed update and confirm the critical blocker remains, the error is visible, and retry is available.
- Complete installation and relaunch, then confirm the critical state clears and password-expiration notifications resume.

## Helper, Cooldowns, And Failures

- Launch main app and helper close together and confirm only one automatic GitHub check is claimed within the in-flight TTL.
- Trigger app activation, menu open, wake, and helper startup; confirm successful checks respect the weekly success cooldown.
- Force a background network or GitHub failure and confirm the error is visible in Settings/About.
- Confirm automatic retries after failure respect the hourly failure cooldown.
- Confirm a fresh signed manifest candidate is reused for immediate install.
- Confirm a stale candidate older than 30 minutes is refreshed before install.

## Regression

- Confirm password-expiration alerts, snooze, quiet hours, and manual password checks behave as before when no critical app update is pending.
- Confirm update notification denial does not hide the in-app badge path.
- Verify Polish and English copy for normal update, critical update, paused notifications, errors, and update actions.
- Check light, dark, and auto theme rendering for badges and blocker views.
- Verify VoiceOver labels and keyboard focus reach the update actions.
