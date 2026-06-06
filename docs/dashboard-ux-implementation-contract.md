# Dashboard UX Implementation Contract (Issue #6)

This document mirrors the canonical Penpot boards and binds them to code-level types.
Penpot remains the visual source of truth for UX intent, while code is the formal implementation contract.

Current Task 8 status: `verified_complete`.
Last attempted Penpot verification: `2026-05-30 23:37 Europe/Warsaw` (MCP healthy, canonical-board verification pass).
Formal verification report: `docs/task8-penpot-verification-report.md`.

## Task 8 verification workflow

- `ready_for_verify`: repo hardening done, waiting for Penpot MCP pass.
- `verified_complete`: all Task 8 DoD checks passed, including canonical-board verification in Penpot.
- `blocked_mcp`: Penpot MCP unavailable or unstable, canonical-board verification not executable.

Transition rule: Task 8 can move to `verified_complete` only after a successful MCP health-check and full canonical-board verification pass.

## Penpot board structure

- `01 App Screens`
- `02 Components`
- `03 Motion & Behavior`
- `04 Visual Studies`
- `99 Archive`

Canonical dashboard references:

- `01 App Screens / Home Dashboard / healthy (canonical)`
- `01 App Screens / Home Dashboard / critical 24h (canonical)`

## Swift contract (PasswordMonitorCore)

Defined in `PasswordMonitorCore/DashboardUXContract.swift`:

- `AppDestinationID`: `home`, `password`, `settings`, `help`
- `ServiceModuleID`: `password`, `hrPortal`, `networkDrives`
- `DashboardTileID`: `password`, `hrPortal`, `networkDrives`, `help`
- `BubbleSeverity`: `healthy`, `warning`, `urgent`, `critical`
- `BubbleLayoutSpec`: `anchor`, `baseRadius`, `minRadius`, `maxRadius`, `collisionWeight`
- `MotionSpec`: `maxOffsetX`, `maxOffsetY`, `cursorInfluence`, `returnSpring`, `disabledByReduceMotion`
- `DashboardState`: `daysUntilExpiration`, `connectivity`, `adStatus`

## Semantic model

- App destinations are navigable screens. `home` is the dashboard screen, not a service module.
- Service modules are business capabilities that can grow into the employee self-service center.
- `DashboardTileID` models dashboard tiles on Home. The visual representation can be bubble-based.
- `help` is a dashboard tile and app destination, but it is not a service module.
- `settings` is an app destination only in the first 2.0 iteration.

### Semantic mapping (frozen for 2.0)

- `AppDestinationID.home` -> dashboard screen container only (never a service module).
- `AppDestinationID.password` -> password area; dashboard tile `DashboardTileID.password` resolves to `ServiceModuleID.password`.
- `AppDestinationID.settings` -> destination-only in v2.0 (no service-module mapping).
- `AppDestinationID.help` -> destination and tile shortcut (`DashboardTileID.help`), but no service-module mapping.

## Future modules contract (Task 9)

Task 9 extends the contract beyond placeholders for `hrPortal` and `networkDrives`.
The goal is deterministic UI behavior before backend-specific implementations are introduced.

### Formal scope in v2.0

- `hrPortal` and `networkDrives` are formalized at contract level (state + actions + presentation mode).
- No backend/API execution contract is introduced in this task.
- All module cards still live in Home dashboard context.

### Destination and module routing

- `ServiceModuleID.password` -> `AppDestinationID.password`
- `ServiceModuleID.hrPortal` -> `AppDestinationID.home`
- `ServiceModuleID.networkDrives` -> `AppDestinationID.home`

Rationale: `hrPortal` and `networkDrives` are dashboard-driven modules in v2.0, not standalone navigation destinations.

### Runtime state model

`ServiceModuleSnapshot` fields:

- `moduleID`
- `runtimeState`: `loading | healthy | warning | error | unavailable`
- `connectivity`: `online | degraded | offline`
- `authState`: `notRequired | authenticated | authenticationRequired | sessionExpired`
- `statusKey` (optional semantic key, no user-facing copy in Core)
- `lastRefreshAt` (optional)
- `primaryAction`
- `secondaryActions`

### Deterministic state -> severity mapping

- `healthy` -> `BubbleSeverity.healthy`
- `warning` -> `BubbleSeverity.warning`
- `loading` -> `BubbleSeverity.healthy` (neutral state, should use progress indicator instead of warning color)
- `error` -> `BubbleSeverity.urgent`
- `unavailable` -> `BubbleSeverity.critical`

### Presentation and actions contract

- `password`
  - launch mode: `nativePanel`
  - actions: `open`, `refresh`, `retry`
  - requires network/session: yes/yes
- `hrPortal`
  - launch mode: `inAppWebView`
  - actions: `open`, `refresh`, `retry`, `openExternal`
  - requires network/session: yes/yes
- `networkDrives`
  - launch mode: `nativePanel`
  - actions: `open`, `refresh`, `retry`
  - requires network/session: yes/yes

### Initial placeholder snapshots (UI bootstrap)

- `password`: `healthy`, `online`, `authenticated`
- `hrPortal`: `loading`, `degraded`, `authenticationRequired`
- `networkDrives`: `loading`, `degraded`, `authenticationRequired`

These defaults are intentional. They allow canonical Home tiles to render consistently in E2E and design sync runs even when module backends are missing.

### Contract integrity rules

`PMDashboardSpec.serviceModuleContractValidationErrors()` must return empty list:

- each `ServiceModuleID` has entries in `moduleDestination`, `serviceModulePresentation`, `initialServiceModuleSnapshot`
- `snapshot.primaryAction` is allowed by module presentation contract
- `snapshot.secondaryActions` are unique and allowed
- `primaryAction` is not duplicated in `secondaryActions`

This validation is covered by core tests and protects against partial map drift.

### UI localization adapter rule

- Core provides only semantic status keys.
- UI resolves keys through `DashboardStatusCopy` using `PMDashboardSpec.statusLocalizationKey(for:)`.
- User-facing copy must stay in localization resources (`Localizable.xcstrings`), not in Core runtime models.

## State and scaling rules

- Severity thresholds:
  - `>= 30 days`: `healthy`
  - `14...29 days`: `warning`
  - `2...13 days`: `urgent`
  - `<= 24h`: `critical`
- Deterministic radius scale:
  - `healthy`: `0.72`
  - `warning`: `1.00`
  - `urgent`: `1.22`
  - `critical`: `1.54`
- CTA safe area:
  - Minimum gap from max critical bubble radius: `14 px`

### Source of numeric truth

All numeric motion and scaling values in this document mirror `PMDashboardSpec` in code.
If any number in docs differs from `PMDashboardSpec`, code wins and docs must be updated.

## Accessibility and motion

- `Reduce Motion` must disable drift/parallax/pulse.
- Status semantics, color identity, and layout anchors remain active when motion is disabled.

## Color contract

Sidebar destinations use:

- `home`: `#72D8E1`
- `password`: `#86E58C`
- `settings`: `#5F8CFF`
- `help`: `#F7C95D`

Dashboard tiles use:

- `password`: `#86E58C`
- `hrPortal`: `#A682FF`
- `networkDrives`: `#5F8CFF`
- `help`: `#F7C95D`

## Components naming policy (02 Components)

Canonical component names must use one of these prefixes:

- `destination-sidebar-*`
- `tile-*`
- `action-*`
- `form-*`
- `feedback-*`
- `surface-*`
- `logs-*`

Canonical Home boards use these component instances:

- Sidebar: `destination-sidebar-home-active`, `destination-sidebar-password-default`, `destination-sidebar-settings-default`, `destination-sidebar-help-default`
- Healthy state: `tile-password-healthy`, `tile-hr-portal`, `tile-network-drives`, `tile-help`, `action-password-cta-default`
- Critical 24h state: `tile-password-critical`, `tile-hr-compressed`, `tile-drives-compressed`, `tile-help-compressed`, `action-password-cta-critical`

Legacy/test aliases outside that policy are treated as archive-only and cannot be referenced by canonical boards.

## Sync checklist (post-code)

### Verified

- [x] Penpot structure uses `01 App Screens`, `02 Components`, `03 Motion & Behavior`, `04 Visual Studies`, `99 Archive`.
- [x] Semantic split in Penpot mirrors code contract (`AppDestinationID`, `ServiceModuleID`, `DashboardTileID`).
- [x] Explicit mapping preserved: `help` = destination + tile, not service module; `settings` = destination-only in v2.0.
- [x] Motion board contract references exact runtime values: `cursorInfluence=0.22`, spring (`response=0.36`, `dampingFraction=0.82`, `blendDuration=0.05`), `disabledByReduceMotion=true`.
- [x] Visual studies remain visual-only and do not redefine semantics.
- [x] Archive boards are excluded from implementation decisions.

### Penpot verification pass

- [x] `01 App Screens / Home Dashboard / healthy (canonical)` confirmed as instance-only for sidebar/tile/CTA elements.
- [x] `01 App Screens / Home Dashboard / critical 24h (canonical)` confirmed as instance-only for sidebar/tile/CTA elements.
- [x] Legacy/test aliases in canonical references removed from canonical usage; component alias moved to archive-legacy naming.
- [x] MCP health-check pass (2/2 successful attempts in current verification run).
