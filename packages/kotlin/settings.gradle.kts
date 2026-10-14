pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "neuraldefend-kotlin"

include(":neuraldefend")

// JVM-only builds (backend contributors, the JDK matrix) do not need an Android SDK.
if (providers.gradleProperty("neuraldefend.jvmOnly").orNull != "true") {
    include(":neuraldefend-android")
    include(":example")
}
