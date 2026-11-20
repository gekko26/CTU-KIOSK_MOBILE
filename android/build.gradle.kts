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

// Keep legacy Flutter plugins (which hardcode an old compileSdk) building with
// the modern Android SDK required by current AndroidX dependencies.
subprojects {
    fun applyCompileSdkOverride() {
        val androidExt = extensions.findByName("android") ?: return
        val methods = androidExt.javaClass.methods
        val compileSdkSetter =
            methods.firstOrNull {
                it.name == "compileSdkVersion" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            } ?: methods.firstOrNull {
                it.name == "setCompileSdk" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }
        if (compileSdkSetter != null) {
            compileSdkSetter.invoke(androidExt, 36)
        }
    }

    if (state.executed) {
        applyCompileSdkOverride()
    } else {
        afterEvaluate { applyCompileSdkOverride() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
