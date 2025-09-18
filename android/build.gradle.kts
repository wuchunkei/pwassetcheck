allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 移除自定义 build 目录重定向，使用默认 android/build 目录

subprojects {
    project.evaluationDependsOn(":app")
    // 将 build 目录指向无空格路径，避免 Windows 上的路径解析问题
    layout.buildDirectory.set(file("C:/AndroidBuilds/FixAssetCheck/${project.name}/build"))
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
