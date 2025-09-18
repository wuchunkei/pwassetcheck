// 将 app 模块的构建目录重定向到无空格路径，规避 Windows 路径空格问题
val appNoSpaceBuildDir = file("C:/AndroidBuilds/FixAssetCheck/app/build")
layout.buildDirectory.set(appNoSpaceBuildDir)
@Suppress("UnstableApiUsage")
buildDir = appNoSpaceBuildDir

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
