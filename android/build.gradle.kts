allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 使用預設 android/build 目錄

subprojects {
    project.evaluationDependsOn(":app")
    // 使用默認 build 輸出目錄，避免 Flutter 無法定位 APK
}

// 為部分未跟上 AGP 8 的第三方模組自動補上 namespace，避免 build 失敗
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
            if (namespace == null || namespace!!.isBlank()) {
                namespace = (project.group?.toString()?.takeIf { it.isNotBlank() }
                    ?: "com.example.${project.name.replace('-', '_')}")
                println("[AGP8] Applied fallback namespace '${namespace}' to app module ${project.path}")
            }
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
            if (namespace == null || namespace!!.isBlank()) {
                namespace = (project.group?.toString()?.takeIf { it.isNotBlank() }
                    ?: "com.example.${project.name.replace('-', '_')}")
                println("[AGP8] Applied fallback namespace '${namespace}' to library module ${project.path}")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// 移除 rootProject 自定義 build 輸出目錄，改用默認
// (原行已刪除)
