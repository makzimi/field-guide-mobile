plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "dev.fieldguide.feature.catalog"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":catalog-api"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.lifecycle.viewmodel)
    implementation(libs.lifecycle.runtime)
    testImplementation(project(":catalog-impl"))
    testImplementation("com.google.code.gson:gson:2.11.0")
    testImplementation("junit:junit:4.13.2")
}

tasks.withType<Test>().configureEach {
    val contractDirectory = rootProject.layout.projectDirectory.dir("../contract").asFile
    inputs.dir(contractDirectory)
    systemProperty("fieldGuide.contractDirectory", contractDirectory.canonicalPath)
    testLogging { events("passed", "failed", "skipped") }
}

apply(from = "$rootDir/gradle/scripts/screenshot-testing.gradle")
