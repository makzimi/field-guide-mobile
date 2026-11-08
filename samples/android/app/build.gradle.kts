plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val copyCatalogAssets by tasks.registering(Copy::class) {
    from(rootProject.layout.projectDirectory.dir("../contract")) { include("catalog-*.json") }
    into(layout.buildDirectory.dir("generated/assets/catalog"))
}

android {
    namespace = "dev.fieldguide.app"
    compileSdk = 36
    buildToolsVersion = "35.0.0"

    defaultConfig {
        applicationId = "dev.fieldguide.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0-scaffold"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    signingConfigs {
        getByName("debug") {
            storeFile = layout.buildDirectory.file("field-guide-debug.keystore").get().asFile
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/assets"))
}

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(copyCatalogAssets)
}

kotlin { jvmToolchain(17) }

val generateDebugKeystore by tasks.registering(Exec::class) {
    val keystore = layout.buildDirectory.file("field-guide-debug.keystore")
    outputs.file(keystore)
    onlyIf { !keystore.get().asFile.exists() }
    doFirst { keystore.get().asFile.parentFile.mkdirs() }
    commandLine(
        "${System.getProperty("java.home")}/bin/keytool",
        "-genkeypair", "-noprompt",
        "-keystore", keystore.get().asFile.absolutePath,
        "-storepass", "android", "-keypass", "android",
        "-alias", "AndroidDebugKey",
        "-dname", "CN=Android Debug,O=Android,C=US",
        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
    )
}

tasks.matching { it.name == "validateSigningDebug" }.configureEach {
    dependsOn(generateDebugKeystore)
}

dependencies {
    implementation(project(":feature-catalog"))
    implementation(project(":catalog-api"))
    implementation(project(":catalog-impl"))
    implementation(libs.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
