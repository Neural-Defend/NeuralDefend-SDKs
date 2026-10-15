plugins {
    java
    id("com.vanniktech.maven.publish") version "0.30.0"
}

group = "com.neuraldefend"
version = "1.0.0"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

repositories {
    mavenCentral()
}

val jacksonVersion = "2.17.1"

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.11.0")

    // Generated contract core (compile-time only; public facade uses OkHttp at runtime).
    implementation("com.google.code.findbugs:jsr305:3.0.2")
    implementation("com.fasterxml.jackson.core:jackson-core:$jacksonVersion")
    implementation("com.fasterxml.jackson.core:jackson-annotations:$jacksonVersion")
    implementation("com.fasterxml.jackson.core:jackson-databind:$jacksonVersion")
    implementation("com.fasterxml.jackson.datatype:jackson-datatype-jsr310:$jacksonVersion")
    implementation("org.openapitools:jackson-databind-nullable:0.2.6")
    implementation("jakarta.annotation:jakarta.annotation-api:1.3.5")
    implementation("org.apache.httpcomponents:httpmime:4.5.14")

    testImplementation(platform("org.junit:junit-bom:5.10.2"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

tasks.test {
    useJUnitPlatform()
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
}

mavenPublishing {
    publishToMavenCentral(automaticRelease = true)
    signAllPublications()

    coordinates("com.neuraldefend", "neuraldefend-sdk", version.toString())

    pom {
        name.set("NeuralDefend Java SDK")
        description.set(
            "Official Java client for the NeuroVerify image and video authenticity API.",
        )
        inceptionYear.set("2026")
        url.set("https://github.com/Neural-Defend/NeuralDefend-SDKs/tree/main/packages/java")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
            }
        }
        developers {
            developer {
                id.set("neural-defend")
                name.set("Neural Defend")
                url.set("https://github.com/Neural-Defend")
            }
        }
        scm {
            url.set("https://github.com/Neural-Defend/NeuralDefend-SDKs")
            connection.set("scm:git:git://github.com/Neural-Defend/NeuralDefend-SDKs.git")
            developerConnection.set("scm:git:ssh://git@github.com/Neural-Defend/NeuralDefend-SDKs.git")
        }
    }
}
