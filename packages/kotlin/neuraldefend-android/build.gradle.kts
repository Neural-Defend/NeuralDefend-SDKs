import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

plugins {
    alias(libs.plugins.android.library)
    `maven-publish`
    signing
}

description = "Android helpers for the Neural Defend NeuroVerify SDK: upload photo-picker and camera content Uris."

android {
    namespace = "com.neuraldefend.android"
    compileSdk = 36

    defaultConfig {
        minSdk = 21
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        // Robolectric's newer Android sandboxes reach into FileDescriptor internals.
        unitTests.all {
            it.jvmArgs(
                "--add-opens=java.base/java.io=ALL-UNNAMED",
                "--add-exports=java.base/jdk.internal.access=ALL-UNNAMED",
            )
        }
    }

    lint {
        warningsAsErrors = true
        abortOnError = true
        // Dependency and SDK version freshness is handled by Dependabot, not lint.
        disable += setOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion", "OldTargetApi")
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }
}

kotlin {
    explicitApi()
    coreLibrariesVersion = "2.2.0"
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_1_8)
        apiVersion.set(KotlinVersion.KOTLIN_2_2)
        languageVersion.set(KotlinVersion.KOTLIN_2_2)
        allWarningsAsErrors.set(true)
    }
}

dependencies {
    api(project(":neuraldefend"))

    testImplementation(libs.junit4)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.kotlin.test)
}

publishing {
    publications {
        create<MavenPublication>("release") {
            artifactId = "neuraldefend-android"
            afterEvaluate { from(components["release"]) }
            pom {
                name.set("Neural Defend NeuroVerify SDK for Android")
                description.set(project.description)
            }
        }
    }
}
