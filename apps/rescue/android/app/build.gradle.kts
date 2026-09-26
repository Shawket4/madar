import java.util.Properties
import java.io.FileInputStream

// The PRODUCTION signing key. Installing over the POS depends on it: Android
// refuses an update signed by a different certificate, and an uninstall would
// take the unsynced sales with it.
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.madar.madar_dump"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The POS's own id, so installing this is an UPDATE of the POS and it
        // inherits the POS's sandbox (see README). The POS is com.madar.cashier
        // from 0.13; a till still on the older com.madar.pos needs
        // `flutter build apk --release -P posId=com.madar.pos`.
        applicationId = (project.findProperty("posId") as String?) ?: "com.madar.cashier"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Target 28 deliberately. From API 29 scoped storage blocks writes to a
        // public folder, and an FTP server on the device can only serve what is
        // public. Targeting 28 keeps the legacy behaviour on the old tablet this
        // is for. Nothing here goes near Play, so the target is ours to choose.
        targetSdk = 28
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // This APK is sideloaded onto one tablet and never published, so the Play
    // Store's "must target API 33+" rule does not apply. Targeting 28 is the
    // whole point — see the note on targetSdk above.
    lint {
        disable += "ExpiredTargetSdkVersion"
        abortOnError = false
    }

    signingConfigs {
        create("release") {
            storeFile = file("release.keystore")
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
