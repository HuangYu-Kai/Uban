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
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    
    // Handle Kotlin tasks if they exist
    tasks.configureEach {
        if (this.name.contains("KotlinCompile")) {
            try {
                val kotlinOptions = this.property("kotlinOptions")
                kotlinOptions?.let {
                    val method = it.javaClass.getMethod("setJvmTarget", String::class.java)
                    method.invoke(it, "17")
                }
            } catch (e: Exception) {
                // Ignore if not a Kotlin task or method not found
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
