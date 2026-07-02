plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.madar.madar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Same id the native apps ship under; release replaces them in place.
        applicationId = "com.madar.pos"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // Installable alongside the native com.madar.pos for parity testing.
            applicationIdSuffix = ".dev"
            // One ABI in debug: every ABI costs a full Rust-workspace
            // cross-compile via Cargokit (~2 GB each) and this machine runs
            // disk-tight. Emulator (Apple Silicon) + modern devices are arm64.
            ndk { abiFilters += listOf("arm64-v8a") }
        }
        release {
            // Same ABI set the native app ships (deploy dropped x86_64).
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
