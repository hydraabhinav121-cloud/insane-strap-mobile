# InSaNe Straps Mobile

Flutter Android companion app for profile tools, JSON Fast Flags editing, and Pro plan information.

## Current Android build

The GitHub Actions workflow at `.github/workflows/build-apk.yml` builds a release APK on pushes to `main` that affect `mobile_v3/`, and can also be started manually from the Actions tab.

When a run succeeds, open the workflow run and download the artifact named `insane-straps-android-apk`. This artifact is a CI build; it is not yet a signed Google Play release.

## Current client features

- Dark red/black interface
- Home dashboard and quick access
- Free / Pro plan display: Free ₹0, weekly ₹39, monthly ₹79, yearly ₹390, lifetime ₹699
- UPI and Litecoin payment details, with a best-effort live LTC conversion quote
- JSON editor and syntax validation for Fast Flags
- Account, key redemption, and owner-dashboard placeholders clearly marked as not connected

## Important limitations

The current app is a client-side starter, not a production subscription system. It does not authenticate users, verify UPI or blockchain transactions, grant/revoke Pro, redeem keys, enforce trial/device limits, or provide a real owner dashboard. Those must be implemented in a secured backend before accepting payments or advertising paid features as active. Never put passwords or server secrets in this repository or Flutter app.

The app's JSON validation only checks syntax; it does not guarantee a setting is supported by a game or safe to apply.
