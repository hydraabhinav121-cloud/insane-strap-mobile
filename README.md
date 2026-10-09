# INSANE STRAPS MOBILE — v8 Account & Build Hardening

Android-first Flutter companion app with a black/red interface, game launch shortcuts, local performance/profile preferences, a JSON configuration editor, Pro plan UI, UPI payment-request flow, and a Node.js backend.

## Account/login system now included in source

- Branded sign-in, create-account, email-verification, forgot-password, reset-password, and logout screens.
- Username or email login; open registration; multiple concurrent sessions (each login receives its own 30-day bearer token).
- Email verification is required before first login. Verification and reset codes expire after 10 minutes, are single-use after successful verification/reset, and are limited to five attempts.
- Passwords are stored using Node.js `scrypt` with a random per-password salt. Passwords are never embedded in the mobile app or returned by the API.
- Password recovery sends a code to the registered email. Owner-assisted recovery must still verify identity and should never expose an old password.
- The app keeps its session token in Android secure storage and clears it on logout.
- Discord linking remains optional for username/password login. Existing Discord OAuth is retained.
- Owner-only backend routes accept an authenticated owner-role account token or the configured owner Discord identity. The app only displays owner management controls when the backend says the account role is `owner`.

## Owner bootstrap — required before owner login works

The owner identity is preconfigured as username `InSaNe`, email `hydraabhinav121@gmail.com`, and Discord user ID `985486854159753256`. The owner password is **not included in source code**. Because a password was shared in chat, create a new unique password and set it as the hosting secret `OWNER_INITIAL_PASSWORD` (minimum 12 characters; use a password manager-generated value).

Set these environment variables on the backend host using its private secret/environment settings:

- `JWT_SECRET`: unique random secret with at least 32 random bytes.
- `OWNER_USERNAME=InSaNe`
- `OWNER_EMAIL=hydraabhinav121@gmail.com`
- `OWNER_DISCORD_ID=985486854159753256`
- `OWNER_INITIAL_PASSWORD`: new, private password; never commit this value.
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`: real email-provider SMTP credentials.
- `DATA_DIR`: persistent mounted disk directory.
- Optional Discord OAuth variables shown in `backend/.env.example`.

On first backend start, it creates the owner account if `OWNER_INITIAL_PASSWORD` is configured. The owner account starts unverified and the backend sends a verification code to the configured owner email when SMTP is working. Verify the email in the app before signing in. If SMTP is not configured or the email is not delivered, the verification/reset system will not work; configure SMTP and use the resend-verification action. If the configured owner username/email conflicts with a different existing account, bootstrap stops rather than silently taking over that account.

**Do not publish the backend until HTTPS, persistent storage, a private JWT secret, SMTP, and the owner password are configured.** If the server's filesystem is ephemeral, account, payment, and membership data may be lost on redeploy. Back up the persistent database.

## Backend setup

```bash
cd backend
npm install
cp .env.example .env
# Fill .env locally for testing only; use your host's secret manager in production.
npm start
```

Do not commit `.env`. Use Node.js 20+. `backend/data/db.json` is the default JSON store; configure `DATA_DIR` to a persistent disk on your host. For a public service, move to a managed database with backups and monitoring before scale.

### Account routes

- `POST /auth/register` — create account and email a verification code.
- `POST /auth/verify-email` — verify the code.
- `POST /auth/resend-verification` — resend verification code.
- `POST /auth/login` — username/email + password.
- `POST /auth/forgot-password` — send a reset code (response does not reveal whether an account exists).
- `POST /auth/reset-password` — validate code and set a new password.
- `GET /me` — signed-in account, role, and membership.

### Existing membership/admin routes

- `GET /health`, `GET /config/prices`
- `GET /auth/discord/start`, `GET /auth/discord/callback`, `POST /auth/discord/exchange`
- `POST /payments`, `GET /payments/mine`
- `GET /admin/payments`, `POST /admin/payments/:id/review`, `PUT /admin/prices`, `GET /admin/users`
- `POST /admin/keys`, `GET /admin/keys`, `POST /admin/keys/:suffix/revoke`, `POST /keys/redeem`

UPI payments are not automatically verified. Independently verify the transaction in the receiving account before approving a payment. Never approve based on a screenshot alone.

## Android build and download

The ZIP contains Flutter source; it is not an APK. This environment does not have Flutter/Dart installed, so I cannot honestly claim the APK has compiled or the install/download has been tested on a physical phone.

1. Upload the contents of this ZIP to the root of your GitHub repository (including `.github/workflows/build-apk.yml`, `lib/`, `assets/`, `backend/`, and `pubspec.yaml`).
2. In GitHub, open **Actions → Build Insane Straps Android APK → Run workflow**.
3. The workflow installs Flutter and Java, runs `flutter pub get`, `flutter analyze`, builds a release APK, checks the APK file exists and is non-empty, then uploads an artifact named `insane-straps-android-apk`.
4. Open the successful workflow run, scroll to **Artifacts**, and download `insane-straps-android-apk`. If the workflow fails, the APK artifact will not be available; open the failed step and inspect the logs.
5. To enable live login/email/Pro services, configure GitHub Actions secret `INSANE_API_BASE_URL` to your deployed HTTPS backend URL before building. Without it, the app intentionally cannot perform remote account login.
6. Install and test on a real Android phone. The workflow artifact download is the verified build output; the source ZIP itself is not an APK.

Flutter's official Android deployment guide describes release APK creation and device testing: https://docs.flutter.dev/deployment/android

## Performance and safety limits

- Game launch shortcuts require the target app to be installed.
- The performance profiles and FFlags UI save preferences and give guidance; they do not inject settings into Roblox/Free Fire, manipulate game memory, or guarantee FPS/ping improvements.
- Headshot Practice provides sensitivity and practice guidance only; no aimbot, auto-targeting, or hitbox manipulation.
- Local preferences remain device-local. Account, email, Pro entitlement and payment data require the deployed backend.
- Keep game passwords, cookies and session tokens out of Insane Straps. Use the official game sign-in screens.

## Checks performed for this source package

- Backend JavaScript syntax check (`node --check backend/server.js`).
- ZIP integrity check (`unzip -t`).
- Flutter analysis/build cannot be performed in this environment because Flutter and Dart are not installed. The GitHub Actions workflow is configured to perform dependency resolution, analysis, APK build and artifact existence verification; run it before distributing the app.


## Android and iOS build, app icon, and account service

The launcher icon is generated from `assets/insane_app_icon.png` (the supplied red dragon artwork on black). The workflow builds an Android APK and an unsigned iOS app artifact. An unsigned iOS app is not directly installable on a normal iPhone; Apple signing and provisioning are required for device/App Store distribution.

### Configure login before building

1. Deploy `backend/` as a Node.js 20+ service on a host with persistent storage. Configure variables in `backend/.env.example`, including a long random `JWT_SECRET`, a new private `OWNER_INITIAL_PASSWORD`, SMTP settings for email verification, and persistent `DATA_DIR`. Do not reuse a password shared in chat.
2. Copy the backend's public HTTPS base URL (no trailing path, e.g. `https://your-api.onrender.com`).
3. In GitHub, open **Settings → Secrets and variables → Actions → New repository secret**. Name it `INSANE_API_BASE_URL` and set its value to the deployed HTTPS URL.
4. Run **Build InSaNe Android and iOS**. The workflow fails early if the backend URL secret is missing, rather than creating an APK that cannot log in.
5. On first deployment, set the owner password securely on the backend and complete email verification before signing in. SMTP and the persistent database must be working; setting the URL alone does not deploy the backend.

Never commit backend secrets. `INSANE_API_BASE_URL` is a public service URL, not a password.

## One-click backend blueprint (Render)

This repository includes `render.yaml`. On Render, choose **New → Blueprint**, connect this GitHub repository, and let Render read the blueprint. If your app source is inside a subfolder, set the Blueprint Root Directory to that folder (the `render.yaml` must be at the repository root Render scans). Render will provision the Node service, health check, generated JWT secret, and persistent disk. Before deployment is usable, enter private values for `OWNER_INITIAL_PASSWORD`, `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS`, and `SMTP_FROM` in the Render service environment settings. Use a unique owner password of at least 12 characters and a real SMTP provider. Do not put secrets in GitHub or commit them to the repository.

After Render deploys, open `https://YOUR-SERVICE.onrender.com/health`. It should return JSON with `ok: true`. Copy only the base URL (no `/health`) into the GitHub Actions repository secret `INSANE_API_BASE_URL`, then run the Android/iOS workflow. The workflow embeds that URL at build time for both platforms.

**Important:** I cannot deploy the backend to your Render account or configure your account secrets on your behalf; that requires you to sign in and enter private credentials. Login cannot work until those account-specific steps are completed. The iOS artifact is unsigned; install/distribute it only after Apple signing/provisioning.
