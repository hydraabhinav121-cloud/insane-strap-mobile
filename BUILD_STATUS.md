# Insane Strap Mobile — build status

This repository is the intended Android app project.

## Build pipeline
The Flutter Android APK build should be run from GitHub Actions after verifying the project source and workflow on `main`.

## Important security notes
- Never commit Gmail passwords, API keys, OAuth client secrets, or signing keys.
- App login, email verification, password reset, trial expiry, device limits, and Pro entitlements must be enforced by a backend. A local UI toggle or demo key is not secure licensing.
- This status file does not claim an APK has been built or that authentication/licensing is production-ready.

## Current blocker
The repository metadata is visible, but the GitHub file-content integration returns 404 for existing file paths. Existing source must be readable before safely modifying or replacing it. Once repository contents can be inspected, verify the Flutter project and GitHub Actions workflow, then trigger and verify a release build.
