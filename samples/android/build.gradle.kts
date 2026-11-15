plugins {
    id("io.github.takahirom.roborazzi") version "1.39.0" apply false
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

check(JavaVersion.current() == JavaVersion.VERSION_17) {
    "Field Guide requires JDK 17. Set JAVA_HOME to a JDK 17 installation."
}

// Convention: a feature-* module depends on *-api modules, never on *-impl.
tasks.register("checkFeatureBoundaries") {
    doLast {
        val features = subprojects.filter { it.name.startsWith("feature-") }
        check(features.isNotEmpty()) { "No feature-* modules found" }

        features.forEach { feature ->
            val edges = feature.configurations["implementation"].allDependencies
                .withType<ProjectDependency>().map { it.path }

            check(edges.none { it.endsWith("-impl") }) {
                "${feature.path} must depend on -api modules, never on -impl"
            }
        }
    }
}
