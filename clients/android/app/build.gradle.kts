plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.svoyigra.mobile"
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

        applicationId = "dev.svoyigra.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Host of the Android App Links share URLs (https://<host>/g/<PIN>), protocol §8.
        // Set with `-PAPP_LINK_HOST=igra.example.com` or the APP_LINK_HOST env var.
        val appLinkHost = (project.findProperty("APP_LINK_HOST") as String?)
            ?.takeIf { it.isNotBlank() }
            ?: System.getenv("APP_LINK_HOST")?.takeIf { it.isNotBlank() }
            ?: "app-links.invalid"
        manifestPlaceholders["appLinkHost"] = appLinkHost
    }

    // fvp plays video on Windows and Linux only; Android keeps the official
    // player, so its native libraries are left out of the APK (its Java part
    // only loads them when fvp is used, which never happens on Android).
    // libc++_shared comes with fvp too; no other library in the APK needs it.
    packaging {
        jniLibs {
            excludes += setOf(
                "**/libfvp.so", "**/libmdk.so", "**/libmdk-*.so", "**/libffmpeg.so",
                "**/libass.so", "**/libc++_shared.so",
            )
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
