plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}


buildDir = file("C:/dev/gradle_build/app")

android {
    namespace = "com.example.fix_asset_check"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.fix_asset_check"
        // 版本來自 pubspec.yaml：`version: x.y.z+build`
        // flutter.versionName / flutter.versionCode 由 Flutter Gradle 插件填充
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // NDK 需要 minSdk >= 21
        minSdk = maxOf(21, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            ndk {
                debugSymbolLevel = "none"
            }
        }
    }

    packaging {
        jniLibs {
            // Keep debug symbols in native libraries to avoid strip failures during AAB build
            keepDebugSymbols.add("**/*.so")
            // Additionally, skip stripping entirely to bypass missing strip tool in environment
            @Suppress("UnstableApiUsage")
            doNotStrip.add("**/*.so")
        }
    }
}

flutter {
    source = "../.."
}
