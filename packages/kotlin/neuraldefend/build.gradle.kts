import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.dokka)
    `java-library`
    `maven-publish`
    signing
}

description = "Official Kotlin SDK for Neural Defend NeuroVerify image and video authenticity detection."

val latestDependencies = providers.gradleProperty("neuraldefend.latestDependencies").orNull == "true"
val testJavaVersion = providers.gradleProperty("neuraldefend.testJavaVersion").orNull

java {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
    withSourcesJar()
}

kotlin {
    explicitApi()
    // Kotlin 2.2 metadata and stdlib keep the SDK usable from apps that have not moved to
    // the newest compiler (Kotlin 2.1 and later can read it).
    coreLibrariesVersion = "2.2.0"
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_1_8)
        apiVersion.set(KotlinVersion.KOTLIN_2_2)
        languageVersion.set(KotlinVersion.KOTLIN_2_2)
        freeCompilerArgs.add("-Xjdk-release=1.8")
        allWarningsAsErrors.set(true)
    }
    @OptIn(org.jetbrains.kotlin.gradle.dsl.abi.ExperimentalAbiValidation::class)
    abiValidation {}
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(8)
    options.compilerArgs.addAll(listOf("-Xlint:-options"))
}

dependencies {
    api(libs.okhttp)
    api(libs.coroutines.core)
    implementation(libs.serialization.json)

    testImplementation(platform(libs.junit5.bom))
    testImplementation(libs.junit5.jupiter)
    testImplementation(libs.kotlin.test)
    testRuntimeOnly(libs.junit5.launcher)

    if (latestDependencies) {
        testImplementation("com.squareup.okhttp3:okhttp:+")
        testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:+")
        testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:+")
    }
}

if (latestDependencies) {
    configurations.matching { it.name.startsWith("test") }.configureEach {
        resolutionStrategy.componentSelection.all {
            if (Regex("(?i)(alpha|beta|rc|eap|dev|-m\\d)").containsMatchIn(candidate.version)) {
                reject("pre-release")
            }
        }
    }
}

val fixturesDirectory = rootProject.layout.projectDirectory.dir("../../tests/fixtures")

tasks.test {
    useJUnitPlatform {
        excludeTags("staging")
    }
}

tasks.withType<Test>().configureEach {
    // A small heap proves that large uploads stream instead of being buffered.
    maxHeapSize = "256m"
    systemProperty("neuraldefend.fixtures", fixturesDirectory.asFile.absolutePath)
    systemProperty("neuraldefend.version", version.toString())
    inputs.dir(fixturesDirectory).withPropertyName("fixtures").withPathSensitivity(PathSensitivity.RELATIVE)
    testLogging {
        events("failed", "skipped")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
    if (testJavaVersion != null) {
        systemProperty("neuraldefend.expectedJavaVersion", testJavaVersion)
        javaLauncher.set(
            javaToolchains.launcherFor { languageVersion.set(JavaLanguageVersion.of(testJavaVersion)) },
        )
    }
}

tasks.register<Test>("stagingTest") {
    description = "Runs the live staging smoke tests (requires NEURALDEFEND_STAGING_API_KEY)."
    group = "verification"
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    useJUnitPlatform {
        includeTags("staging")
    }
    environment("NEURALDEFEND_STAGING_IMAGE_DEFAULT", fixturesDirectory.file("media/ai-generated.png").asFile.absolutePath)
    environment("NEURALDEFEND_STAGING_VIDEO_DEFAULT", fixturesDirectory.file("media/fake-video.mp4").asFile.absolutePath)
    outputs.upToDateWhen { false }
}

val dokkaJavadocJar = tasks.register<Jar>("dokkaJavadocJar") {
    description = "Packages the Dokka HTML reference as the Maven Central javadoc jar."
    archiveClassifier.set("javadoc")
    from(tasks.named("dokkaGeneratePublicationHtml"))
}

dokka {
    moduleName.set("neuraldefend-kotlin")
    dokkaSourceSets.configureEach {
        includes.from("Module.md")
        sourceLink {
            localDirectory.set(file("src/main/kotlin"))
            remoteUrl("https://github.com/Neural-Defend/NeuralDefend-SDKs/tree/main/packages/kotlin/neuraldefend/src/main/kotlin")
        }
    }
}

tasks.jar {
    manifest {
        attributes(
            "Implementation-Title" to "neuraldefend-kotlin",
            "Implementation-Version" to version,
            "Automatic-Module-Name" to "com.neuraldefend.kotlin",
        )
    }
}

publishing {
    publications {
        create<MavenPublication>("release") {
            artifactId = "neuraldefend-kotlin"
            from(components["java"])
            artifact(dokkaJavadocJar)
            pom {
                name.set("Neural Defend NeuroVerify Kotlin SDK")
                description.set(project.description)
            }
        }
    }
}
