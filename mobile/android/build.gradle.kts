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

subprojects {
    val applyNamespace = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val getNamespace = android.javaClass.methods.find { it.name == "getNamespace" }
                val namespace = getNamespace?.invoke(android)
                if (namespace == null) {
                    val manifest = file("src/main/AndroidManifest.xml")
                    if (manifest.exists()) {
                        val content = manifest.readText()
                        val match = """package="([^"]+)"""".toRegex().find(content)
                        if (match != null) {
                            val setNamespace = android.javaClass.methods.find { it.name == "setNamespace" && it.parameterTypes.size == 1 }
                            setNamespace?.invoke(android, match.groupValues[1])
                        }
                    }
                }
                
                // Force compileSdkVersion to fix android:attr/lStar resource linking errors in old plugins
                if (project.name == "flutter_app_badger") {
                    val compileSdkMethod = android.javaClass.methods.find { it.name == "compileSdkVersion" && it.parameterTypes.size == 1 && it.parameterTypes[0] == Int::class.java }
                    if (compileSdkMethod != null) {
                        compileSdkMethod.invoke(android, 34)
                    } else {
                        val setCompileSdkMethod = android.javaClass.methods.find { it.name == "setCompileSdkVersion" && it.parameterTypes.size == 1 && it.parameterTypes[0] == Int::class.java }
                        setCompileSdkMethod?.invoke(android, 34)
                    }
                }
            } catch (e: Exception) {
                // Ignore reflection errors
            }
        }
    }

    if (project.state.executed) {
        applyNamespace()
    } else {
        project.afterEvaluate { applyNamespace() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
