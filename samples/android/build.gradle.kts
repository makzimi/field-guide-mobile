plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

check(JavaVersion.current() == JavaVersion.VERSION_17) {
    "Field Guide requires JDK 17. Set JAVA_HOME to a JDK 17 installation."
}
