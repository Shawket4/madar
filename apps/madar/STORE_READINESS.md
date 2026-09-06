# Madar Cashier — App Store / Google Play readiness

What the app already satisfies, what this branch adds, and what is still open before the
first store submission. Store console setup (accounts, listings, screenshots, upload) is a
separate task; this document is the requirements list that task works from.

## Identity and versions

| | Android | iOS |
|---|---|---|
| Id | `com.madar.pos` (debug: `.dev` suffix) | `com.madar.pos` (team `6HNBMW6X75`) |
| Display name | `@string/app_name` — "Madar Cashier" / «كاشير مدار» | "Madar Cashier" |
| Version | `pubspec.yaml` `1.0.0+1` → `versionName` / `versionCode` | → `CFBundleShortVersionString` / `CFBundleVersion` |
| Min / target | `flutter.minSdkVersion` (24) / `flutter.targetSdkVersion` (Flutter 3.47 → 36; Play requires ≥ 35 from Aug 2026) | iOS 15.0 |

Bump the **build number** (`+N`) on every upload; both stores refuse a reused one. CI can pass
`--build-number=$GITHUB_RUN_NUMBER`.

## Permissions and their declarations

| Capability | Android | iOS | Store form answer |
|---|---|---|---|
| Network | `INTERNET` | — | HTTPS to `api.madar-pos.cloud` only |
| Notifications | `POST_NOTIFICATIONS` (runtime prompt in app) | prompt at boot (`notifications.dart`) | "new order / ready / booking" alerts |
| Bluetooth printer | `BLUETOOTH_CONNECT` (31+), legacy ≤30; `uses-feature bluetooth required=false` | `NSBluetoothAlwaysUsageDescription` | paired thermal printer, no scanning, no location |
| Local network (LAN relay, KDS) | none needed | `NSLocalNetworkUsageDescription` + `NSBonjourServices` `_madar._tcp` | Bonjour discovery of Madar devices on the same Wi-Fi |

No location, camera, contacts, photos, or background modes. `allowBackup=false` (the SQLite
store holds order data; a restore onto another device must not carry it).

## Privacy

- Privacy policy URL (both stores): `https://legal.madar-pos.cloud/privacy-policy.html`.
- Account deletion URL (Play "Data safety"): `https://legal.madar-pos.cloud/delete-account.html`.
- iOS privacy manifest: `ios/Runner/PrivacyInfo.xcprivacy` — no tracking; collected: user id
  (staff account, linked), crash + performance data (self-hosted Sentry, not linked); required-
  reason APIs: UserDefaults (CA92.1), file timestamps (C617.1), disk space (E174.1), boot time
  (35F9.1). Plugins ship their own manifests. Keep it in step with the App Privacy label.
- Data safety / App Privacy answers (from `MadarRust/legal`): data collected = account
  identifiers (name, email/login), crash logs, app performance; shared with = none (Sentry is
  self-hosted; Google Translate/Gemini never receive POS data from this app); encrypted in
  transit = yes; deletable = yes (via the restaurant admin / email). No ads, no analytics SDK.
- Export compliance: `ITSAppUsesNonExemptEncryption = false` (standard HTTPS only).

## Build and packaging

- Release signing: `android/key.properties` from CI secrets (`KEYSTORE_BASE64`, …); R8 minify +
  resource shrink on; en/ar resources only. **Play needs an AAB** — `deploy.yml` now builds
  `flutter build appbundle --release` as an artifact next to the APKs.
- 16 KB page size (Play requirement for apps targeting 15+): NDK 28.2 (Flutter's default here)
  links `.so` files 16 KB-aligned by default and AGP 8.11 packages them uncompressed. Verify a
  release AAB once with `zipalign -c -P 16 -v 4 app-release.aab` (or Play's pre-launch report)
  because the Rust core is built by Cargokit, outside Gradle's own toolchain.
- Orientation: phones portrait, tablets landscape (`main.dart` + `Info.plist`); iPad supported.
- Per-app language (Android 13+): `res/xml/locales_config.xml` (en, ar); iOS
  `CFBundleLocalizations` (en, ar).
- Sentry DSN is a `--dart-define=SENTRY_DSN=…` at build time; an unreported build is fine.
- API base defaults to `https://api.madar-pos.cloud`; `MADAR_API` overrides for dev only.

## Open items (blockers marked ⚠)

- ⚠ **Legal review**: `MadarRust/legal/README.md` says the documents are drafts not reviewed by
  a lawyer; store listings cite them. Arabic versions of every public document are still to be
  written (`legal/ar/`).
- ⚠ **In-app account deletion**: `delete-account.md` promises "Settings → Account → Delete
  account" in the app; the POS has no such action (accounts are created and removed by the
  restaurant's manager in the dashboard). Either add the action (needs a backend endpoint and a
  manager-approval flow) or amend the document to describe the manager/email path only. Apple
  requires the in-app path only when the app itself offers account creation — it does not — but
  the policy must not promise what the app lacks.
- ⚠ **Review credentials**: App Review and Play reviewers need a working demo login (an org,
  a branch with a floor, a teller PIN and a manager) plus notes explaining the offline/LAN
  behaviour; prepare them on the demo backend, not prod.
- Store listing assets: 1024×1024 icon (present in `AppIcon.appiconset` / mipmaps), phone +
  7"/10" tablet screenshots, Play feature graphic 1024×500, short/long descriptions in en + ar,
  category (Business), content rating questionnaire (no user content, no ads), target audience
  (18+ / staff tool), "Business" declaration on Play (the app is for restaurant staff — consider
  a private/managed distribution track if the public listing is not wanted).
- iOS: an Apple Distribution certificate + App Store provisioning profile for `com.madar.pos`
  in the CI signing step (the workflow builds Android and macOS today; add `flutter build ipa
  --export-options-plist`).
- Test on a physical iPad and an Android tablet before submission (the printer path, LAN relay
  discovery prompt on iOS 14+, and the notification prompt each need a real device).
