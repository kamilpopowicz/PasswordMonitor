# Password Alert Smoke Test

Manual smoke test for password-expiration alerts in both the main app and the login-item helper.

## Goal

Verify that the blocking password alert appears only when the password expires in 7 days or less, and that urgent behavior works below 24 hours.

## Test Matrix

1. `28 days` - no alert
2. `8 days` - no alert
3. `7 days` - alert appears
4. `<24 hours` - alert appears and snooze is disabled

## Preconditions

- Build the app and helper from the current branch.
- Enable the login-item helper in Settings.
- Set the warning threshold to `7`.
- Note the configured notification time and quiet hours.
- Make sure logs are enabled so `daysRemaining` and `thresholdDays` are visible.

## How to Execute

For each scenario below, use a test account or a controlled environment where the password-expiration date can be adjusted safely.

Run each scenario twice:

1. with `PasswordMonitor.app` open
2. with `PasswordMonitor.app` fully closed and only the helper running in the background

## Scenario 1: 28 Days Remaining

- Set password expiry so the app resolves `daysRemaining=28`.
- Launch the app or trigger a helper refresh by logging in / waiting for the next refresh / waking the Mac.
- Confirm in logs that the threshold check sees `28` days.
- Expected result: no blocking alert appears.

## Scenario 2: 8 Days Remaining

- Set password expiry so the app resolves `daysRemaining=8`.
- Trigger a refresh.
- Confirm in logs that the threshold check sees `8` days.
- Expected result: no blocking alert appears.

## Scenario 3: 7 Days Remaining

- Set password expiry so the app resolves `daysRemaining=7`.
- Trigger a refresh.
- Confirm in logs that the threshold check sees `7` days.
- Expected result: the blocking alert appears.
- Expected result: the alert stays on top and cannot be minimized away.

## Scenario 4: Less Than 24 Hours Remaining

- Set password expiry so less than 24 hours remain.
- Trigger a refresh.
- Confirm in logs that the threshold check sees a value inside the warning window.
- Expected result: the blocking alert appears.
- Expected result: `Odloz` / `Snooze` is disabled.
- Expected result: `Zmien haslo` / `Change password` remains available.

## Helper-Specific Checks

- With the main app closed, confirm the helper still performs:
  - an immediate refresh after login,
  - hourly refreshes,
  - a refresh at the configured notification time,
  - a refresh after wake.
- Confirm the helper skips AD refreshes during quiet hours.

## QA Tip: Force a Helper Refresh

To trigger a helper refresh without rebooting the Mac:

1. fully quit `PasswordMonitor.app`
2. lock and unlock the Mac, or put it to sleep and wake it
3. check the log for:
   - `Helper automatic refresh triggered by system wake`
   - `Helper refresh started`
   - `Helper fetched password status`

If you want to test the exact scheduled path, temporarily set the notification time a few minutes ahead, save Settings, and wait for that minute to pass.
For a faster manual trigger while the main app is open, use `Settings -> Force helper refresh`.

## Pass Criteria

- No alert at `28` or `8` days.
- Alert at `7` days and below.
- Snooze disabled below `24` hours.
- Same behavior from the main app and from the helper-only path.
