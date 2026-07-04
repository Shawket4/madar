import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
        // Same id the native apps ship under; release replaces them in place.
        applicationId = "com.madar.pos"
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
            // Installable alongside the native com.madar.pos for parity testing.
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
