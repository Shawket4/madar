# Madar Rescue — get the queued sales off a stranded till

A one-screen Android app whose only job is to copy the POS's local SQLite store
to shared storage, so it can be fetched off a device that cannot sync.

It exists because of a real incident (2026-09-20, One Ninety): a till had weeks
of offline orders that would not drain, the tablet was a release build with no
USB debugging, and there was no way to read its database. `adb run-as` is
refused on a release build and `adb backup` needs debugging enabled, so the only
route left on Android is an app that is *the same app* reading its own sandbox.

**Keep this here.** When it is needed, it is needed under time pressure with a
shop unable to trade, and rebuilding it from memory is exactly the wrong thing
to be doing at that moment.

## How it can read the POS's files at all

Android gives each package a private directory and nothing else may look inside
it. This app ships with `applicationId = com.madar.cashier` — the POS's own id — and
is signed with the production key, so installing it is an **update** of the POS
rather than a new app, and it inherits that directory.

The POS was `com.madar.pos` on Android before 0.13. For a till still on that id,
build with `-P posId=com.madar.pos` (`flutter build apk --release -P posId=com.madar.pos`);
the id must match the installed POS exactly or Android installs it as a separate app
with an empty sandbox.

Two consequences, both important:

- It must be installed **over** the POS. Uninstalling first deletes the sandbox,
  which is precisely the data being rescued.
- It must be signed with the **production key**. Android refuses an update whose
  signature differs, and the only remedy then is an uninstall.

## What it deliberately does not do

It never opens the database. Opening it with any version of the core would run
schema migrations against the only copy of those sales — on a stranded till that
copy is irreplaceable. It copies bytes.

It copies `madar.db`, `madar.db-wal` and `madar.db-shm` together. The store runs
in WAL mode, so recent writes live in the `-wal` sidecar: in the incident above
the database was 1.1 MB and the WAL was **3.9 MB**. Copying `madar.db` alone
would have left most of the queued orders behind.

## Building it

The keystore is not in this repo (see `.gitignore` — a committed keystore is a
compromised keystore). Supply it at build time:

```sh
cp /path/to/madar-release.keystore apps/rescue/android/app/release.keystore
cp /path/to/key.properties          apps/rescue/android/key.properties
cd apps/rescue
flutter pub get
flutter build apk --release --target-platform android-arm64
```

**Set the version code before building.** `pubspec.yaml`'s build number becomes
the Android version code, and it has to sit *above the version on the tablet* and
*below the current POS release*, so the POS can be reinstalled over the rescue
app afterwards without an uninstall. At the time of writing POS 0.7.10 is
versionCode 2029 and this is pinned at `+2028`. Check the shipping release and
adjust if that has moved:

```sh
aapt2 dump badging app-release.apk | head -1   # reads versionCode
```

Verify before taking it anywhere near a shop:

```sh
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
# the SHA-256 digest must equal the shipping POS APK's
```

## Using it

1. Install over the POS. **Never uninstall.**
2. Open "Madar Rescue", grant All files access, tap **Copy database out**.
3. Check every file reports `OK`, then fetch them (FTP, MTP, whatever the device
   allows) from the printed path — normally `/storage/emulated/0/MadarDump`.
4. Only once the files are safely off the device, install the real POS over it.

With no database present it reports that and then probes each destination for
writability instead, so it can be rehearsed on any handset before being taken to
the site that matters.

## Verified

End to end on a Galaxy S25 Ultra, **Android 16 (SDK 36)** — the strictest case,
where scoped storage is most aggressive: installed over an existing
`com.madar.pos`, wrote to the public folder, three files byte-identical,
`PRAGMA integrity_check` → `ok`, outbox readable from the copy.

`targetSdk` is pinned to 28 on purpose: from API 29 scoped storage blocks writes
to a public folder, and a public folder is what an FTP server on the device can
actually serve. This APK is sideloaded onto one tablet and never published, so
the Play Store's target-API rule does not apply — the lint that enforces it is
disabled in `android/app/build.gradle.kts`, with the reason recorded there.
