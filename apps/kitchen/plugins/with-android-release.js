// Android release, on every prebuild (the android/ folder is generated):
//
// 1. Signing. A release build signs with the upload key named in
//    android/key.properties (storeFile/storePassword/keyAlias/keyPassword; the
//    same file the POS and Dawam workflows write). With no such file it falls
//    back to the debug key, which Play refuses; CI refuses it first.
// 2. versionCode from `-PversionCode=<n>` (CI passes the run number), 1 otherwise.
// 3. The `kitchen_orders` notification channel, created at startup with high
//    importance: the server's kitchen push names it (MadarRust push::kitchen
//    ANDROID_CHANNEL), so a new round rings and shows as a heads-up banner.
const { withAppBuildGradle, withMainApplication } = require("expo/config-plugins");

const CHANNEL = "kitchen_orders";

function signing(src) {
  if (src.includes("key.properties")) return src;
  const props = `def keyProps = new Properties()
def keyPropsFile = rootProject.file('key.properties')
if (keyPropsFile.exists()) { keyPropsFile.withInputStream { keyProps.load(it) } }

android {`;
  src = src.replace(/^android \{/m, props);
  src = src.replace(
    /(signingConfigs \{\n\s+debug \{[\s\S]*?\n\s+\}\n)/,
    `$1        release {
            if (keyPropsFile.exists()) {
                storeFile rootProject.file(keyProps['storeFile'])
                storePassword keyProps['storePassword']
                keyAlias keyProps['keyAlias']
                keyPassword keyProps['keyPassword']
            }
        }
`,
  );
  src = src.replace(
    /(release \{\n(?:\s*\/\/.*\n)*\s*)signingConfig signingConfigs\.debug/,
    "$1signingConfig keyPropsFile.exists() ? signingConfigs.release : signingConfigs.debug",
  );
  src = src.replace(/versionCode \d+/, "versionCode((findProperty('versionCode') ?: '1').toInteger())");
  if (!src.includes("signingConfigs.release") || !src.includes("findProperty('versionCode')")) {
    throw new Error("with-android-release: app/build.gradle no longer matches the expected template");
  }
  return src;
}

function channel(src) {
  if (src.includes(`"${CHANNEL}"`)) return src;
  const code = `    super.onCreate()
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
      getSystemService(android.app.NotificationManager::class.java).createNotificationChannel(
        android.app.NotificationChannel("${CHANNEL}", "Kitchen orders · طلبات المطبخ", android.app.NotificationManager.IMPORTANCE_HIGH)
      )
    }`;
  if (!src.includes("    super.onCreate()")) throw new Error("with-android-release: MainApplication.onCreate not found");
  return src.replace("    super.onCreate()", code);
}

module.exports = function withAndroidRelease(config) {
  config = withAppBuildGradle(config, (c) => {
    c.modResults.contents = signing(c.modResults.contents);
    return c;
  });
  return withMainApplication(config, (c) => {
    c.modResults.contents = channel(c.modResults.contents);
    return c;
  });
};
