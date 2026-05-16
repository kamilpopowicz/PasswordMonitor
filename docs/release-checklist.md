# Release Checklist

Use this checklist for the first real release and for later release runs.

1. Confirm `main` contains the latest updater, docs, and license changes.
2. Confirm unrelated local changes are still untouched.
3. Update `MARKETING_VERSION` and build number if the release version changes.
4. Verify `LICENSE`, `README.md`, `RELEASE.md`, and `SECURITY.md` match the intended public state.
5. Confirm the GitHub Environment `release-signing` exists and contains `UPDATE_MANIFEST_PRIVATE_KEY_BASE64`.
6. Confirm the `v*` repository ruleset is active and blocks force-move/deletion.
7. Push the version/build changes to `main`.
8. Confirm the auto-tag workflow creates the expected tag, for example `v1.8.0`.
9. Wait for the release workflow to finish:
   - tests
   - build
   - zip
   - SHA256
   - manifest signing
   - GitHub Release publication
10. Test the released build from an older installed version:
    - open `About PasswordMonitor...`
    - click `Check for updates`
11. Verify the updater:
    - detects the newer release
    - downloads the expected asset only
    - verifies SHA256
    - verifies the signed manifest
    - installs the app bundle
    - restarts the app
12. After restart, verify:
    - main app launches
    - helper is active
    - menu bar is present
    - About shows the new version
13. Close issue #36 only after the smoke test passes on a real release.
14. If this release follows a key rotation window, keep the old signing key trusted until the next shipped release no longer needs it.
