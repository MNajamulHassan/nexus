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

// mapbox_maps_flutter 3.0.0 applies kotlin-android only when AGP < 9, then
// always uses a kotlin {} block. This app uses AGP 9.1.0 with
// android.builtInKotlin=false (Flutter 3.47 template), so that module
// evaluates without a Kotlin plugin. Apply KGP before evaluation.
subprojects {
    if (name == "mapbox_maps_flutter_mobile") {
        beforeEvaluate {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
