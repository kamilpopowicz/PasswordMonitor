# Release Pipeline

This document covers the maintainer-facing release and update pipeline.

## Release Flow
Release builds are published from version tags created by GitHub Actions.

- Push version/build changes to `main`.
- The auto-tag workflow reads `MARKETING_VERSION`, verifies the matching changelog heading, and creates `v<MARKETING_VERSION>` if that tag does not exist yet.
- The release workflow runs from that tag.
- The workflow runs tests, builds the app, ad hoc signs the bundle, zips it, computes SHA256, and signs the update manifest.
- The signing step runs in a protected GitHub Environment named `release-signing` with required reviewers.
- Store `UPDATE_MANIFEST_PRIVATE_KEY_BASE64` as an environment secret there, not as a plain repository secret.
- The embedded public key list in `PasswordMonitorCore/UpdateManager.swift` currently trusts `passwordmonitor-2026-04` and `passwordmonitor-2026-05` during rotation.
- New manifests are signed with `passwordmonitor-2026-05`; keep both keys trusted until the next release has shipped.
- GitHub Releases publishes three assets for the updater:
  - `PasswordMonitor.app.zip`
  - `PasswordMonitor.app.zip.sha256`
  - `PasswordMonitor.update-manifest.json`
Security and rotation details for the updater are documented in [SECURITY.md](SECURITY.md).

## Update Model
The app uses a single in-app update panel centered on the About window.

- Update checks do not run automatically on launch.
- `About PasswordMonitor...`, `Settings → Check for updates`, and the menu-bar update action all open the same panel.
- The About window is the only place where update status, verification, and installation are handled.
- Updates are verified with both SHA256 and a signed manifest before the app bundle is replaced.
