import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

/** Copies the shared contract fixtures' sample media into the app's assets. */
abstract class CopySampleMedia : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val media: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val target = outputDir.get().asFile
        target.deleteRecursively()
        target.mkdirs()
        media.files.forEach { it.copyTo(target.resolve(it.name)) }
    }
}

val copySampleMedia = tasks.register<CopySampleMedia>("copySampleMedia") {
    val fixtures = rootProject.layout.projectDirectory.dir("../../tests/fixtures/media")
    media.from(fixtures.file("ai-generated.png"), fixtures.file("fake-video.mp4"))
    outputDir.set(layout.buildDirectory.dir("generated/sampleMedia"))
}

android {
    namespace = "com.neuraldefend.example"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.neuraldefend.example"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = providers.gradleProperty("VERSION_NAME").get()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            // The example is never distributed; debug signing lets CI and reviewers install the
            // minified build to check that the SDK survives R8.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    lint {
        warningsAsErrors = true
        abortOnError = true
        checkDependencies = true
        // Dependency and SDK version freshness is handled by Dependabot, not lint.
        disable += setOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion", "OldTargetApi")
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            it.systemProperty("neuraldefend.fixtures", rootProject.file("../../tests/fixtures").absolutePath)
            it.systemProperty("robolectric.graphicsMode", "NATIVE")
            it.systemProperty("neuraldefend.screenshots", layout.buildDirectory.dir("screenshots").get().asFile.absolutePath)
            // Robolectric's newer Android sandboxes reach into FileDescriptor internals.
            it.jvmArgs(
                "--add-opens=java.base/java.io=ALL-UNNAMED",
                "--add-exports=java.base/jdk.internal.access=ALL-UNNAMED",
            )
        }
    }

    // The screen tests run on the JVM under Robolectric and on emulators.
    sourceSets {
        getByName("test").kotlin.directories += "src/sharedTest/kotlin"
        getByName("androidTest").kotlin.directories += "src/sharedTest/kotlin"
    }

    packaging {
        resources.excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1")
    }
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(copySampleMedia, CopySampleMedia::outputDir)
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}

dependencies {
    implementation(project(":neuraldefend-android"))
    // Apps may bring a newer OkHttp and coroutines than the SDK's lower bounds; the example
    // deliberately does, so CI exercises the SDK against OkHttp 5.
    implementation(libs.example.okhttp)
    implementation(libs.example.coroutines.android)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    testImplementation(libs.junit4)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.example.coroutines.test)
    testImplementation(libs.example.mockwebserver)
    testImplementation(libs.example.okhttp.tls)
    testImplementation(libs.serialization.json)
    testImplementation(libs.robolectric)
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.androidx.test.ext.junit)

    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.kotlin.test)
    androidTestImplementation(libs.example.mockwebserver)
    androidTestImplementation(libs.example.okhttp.tls)
}
