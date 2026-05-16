# Updater Security

This document describes the security properties and constraints of the custom updater.

## Trust Model
The updater trusts only:

- GitHub Releases as the distribution channel
- a signed update manifest
- SHA256 for payload integrity
- a pinned set of signing public keys embedded in the app

The app does not trust the raw release asset URL, the tag name by itself, or the archive contents before verification.

## What The Updater Defends Against
The updater is designed to reject:

- tampered release assets
- manifest forgery
- replayed or forged tag triggers
- path traversal in ZIP archives
- symlink abuse inside the archive
- unexpected asset hosts or non-HTTPS redirects
- bundle substitution that changes the app identifier or version
- archive payloads that do not pass code-signing verification

## Key Rotation
The app may trust more than one signing key during a rotation window.

- The manifest includes a `signingKeyID` so the app can select the expected public key explicitly.
- Keep the old key trusted only until the replacement release has shipped.
- Remove the old key from the trusted set once the new key is live and the older build is no longer needed for verification.

## Release Pipeline Hardening
The release workflow is split so the signing step is isolated:

- build/test/archive steps run without the manifest signing secret
- signing happens only in the protected `release-signing` GitHub Environment
- an auto-tag workflow creates `v*` tags from `MARKETING_VERSION`
- a repository ruleset blocks force-move and deletion of `v*` tags after creation

## Residual Risk
No direct-distribution updater can fully eliminate compromise of the publishing account or signing key.

If the signing key or release signing environment is compromised, an attacker can publish a trusted malicious update until the key is rotated and a clean build is shipped.

## Operational Rules

- Do not publish release assets outside the GitHub Actions release flow.
- Do not reuse the manifest signing key for other signatures.
- Rotate the manifest key before removing the old public key from the app.
- Keep release tags protected so update triggers cannot be rewritten or removed.
