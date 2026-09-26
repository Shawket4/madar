import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (APP-6), only when its config is here: google-services.json is
// git-ignored because this repo is public, and the plugin fails the build when
// it is missing. `flutterfire configure` brings it back. Without it the app
// builds and runs; only push is off.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing (the sufrix_pos pattern): CI decodes the keystore from
// secrets and writes android/key.properties; local release builds without it
// fall back to debug signing so `flutter run --release` still works.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "com.madar.madar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications ships java.time usage — its AAR
        // metadata requires core-library desugaring on the consuming app.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // The same id as iOS (com.madar.cashier). Until 0.13 the Android app
        // was com.madar.pos; a package name cannot change in place, so a till
        // on the old id gets this as a NEW app beside it. Drain the old app's
        // outbox before switching (the rescue app, apps/rescue, can still read
        // a stranded com.madar.pos sandbox).
        applicationId = "com.madar.cashier"
        // The app localizes en + ar only — drop every other locale's
        // resources from plugins/AndroidX (a quiet multi-hundred-KB saving).
        resourceConfigurations += listOf("en", "ar")
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // com.madar.cashier.dev: installs beside the release app.
            applicationIdSuffix = ".dev"
            // One ABI in debug: every ABI costs a full Rust-workspace
            // cross-compile via Cargokit (~2 GB each) and this machine runs
            // disk-tight. Emulator (Apple Silicon) + modern devices are arm64.
            // SKIPPED under --split-per-abi: AGP refuses ndk.abiFilters on ANY
            // variant once splits are enabled, even for a release-only build.
            if (!project.hasProperty("split-per-abi")) {
                ndk { abiFilters += listOf("arm64-v8a") }
            }
        }
        release {
            // ABIs are controlled by the build command (CI passes
            // --split-per-abi --target-platform android-arm64,android-arm);
            // ndk abiFilters here would CONFLICT with the splits mechanism.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8: shrink + optimize the Java/Kotlin side and drop unused
            // resources (plugin locale files, unused drawables). Flutter's
            // default proguard rules ride along via the gradle plugin.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
