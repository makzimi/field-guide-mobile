plugins { alias(libs.plugins.kotlin.jvm) }

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":catalog-api"))
    implementation("com.google.code.gson:gson:2.11.0")
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    // Read the single shared source directly; do not copy fixture bytes into resources.
    val contractDirectory = rootProject.layout.projectDirectory.dir("../contract").asFile
    inputs.dir(contractDirectory)
    systemProperty("fieldGuide.contractDirectory", contractDirectory.canonicalPath)
    testLogging {
        events("passed", "failed", "skipped")
        showStandardStreams = true
    }
}
