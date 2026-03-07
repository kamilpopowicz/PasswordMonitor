## Diagnostic Update

### Completed
- `/normalize`: All relevant controls now use shared theme tokens and helpers. `HelperServiceStatusDescriptor` centralizes the helper-status color + localized text so both `SettingsView` and `MenuBarView` render consistent states without relying on ad-hoc colors.
- `/optimize`: `LogsView` now caches filtered lines, switches to `LazyVStack`, keeps the search field width fixed, and only recomputes filtering when the input/state changes, so the long log surface no longer re-splits the entire string every render.
- `/harden`: Numeric fields and the language-assist `TextEditor` expose explicit accessibility labels, the NSSearchField uses the default focus ring and receives an accessibility label, the menu bar surfaces textual feedback for helper failures, and buttons/logging already cover focus+state feedback.
- Verified with `xcodebuild -project PasswordMonitor.xcodeproj -scheme PasswordMonitor -configuration Debug -destination 'platform=macOS' build`.

-### Outstanding
- **Top0 (Design Feel)**: After the recent theme updates the app lost part of its “PRO” aesthetic (glass/glow, hierarchy, spacing). Revisit `PMTheme` tokens + panel styling to restore that distinctive premium feel without breaking accessibility. Use the `theme-guard` skill to compare key views against the original reference and capture the exact regressions before making targeted adjustments.
- The helper status descriptor now centralizes color/text but any additional helper communication (e.g., error retries) should reuse the descriptor’s semantics to stay consistent.

### Next Priority
Implement observation of system appearance changes so `ThemeManager` re-evaluates `.auto` behavior in real time. Use the **theme-guard** skill to audit ThemeManager/Theme usage, add the required notifications/`NSDistributedNotificationCenter` hook, and verify every view honors the updated state without manual refresh.
