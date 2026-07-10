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

    // ─────────────────────────────────────────────────────────────
    // Force every Android library plugin to compile against the same
    // compileSdk our app uses (36). Some plugins hard-code compileSdk
    // 34 but their transitive deps require 36 (see gray_part_pitfalls
    // §2). Registered BEFORE evaluationDependsOn(":app") below so the
    // subprojects have not yet been evaluated when the afterEvaluate
    // callback is attached.
    // ─────────────────────────────────────────────────────────────
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
