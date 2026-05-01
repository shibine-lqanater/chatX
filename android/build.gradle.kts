allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// حل مشكلة الـ Namespace للمكتبات القديمة
subprojects {
    plugins.withType<com.android.build.gradle.api.AndroidBasePlugin> {
        project.extensions.configure<com.android.build.gradle.BaseExtension> {
            if (namespace == null) {
                namespace = "com.example.generated.${project.name}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
