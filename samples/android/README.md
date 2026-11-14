# Field Guide for Android

Open this directory in Android Studio, keeping the sibling `contract` and
`harness` directories in place. The app uses Kotlin and Jetpack Compose with
four modules: `app`, `catalog-api`, `catalog-impl` and `feature-catalog`.

Use JDK 17, Android SDK platform 36 and build tools 35.0.0. The build pins
Gradle 8.13, AGP 8.13.2, Kotlin 2.2.10 and Compose BOM 2024.12.01. Minimum SDK
is 26 and target SDK is 35. Set `JAVA_HOME` and `ANDROID_HOME` before building.

```sh
./gradlew :app:assembleDebug
./gradlew :catalog-api:test :catalog-impl:test :feature-catalog:verifyRoborazziDebug :app:testDebugUnitTest
./gradlew :app:assembleDebugAndroidTest
```

The debug APK is `app/build/outputs/apk/debug/app-debug.apk`. The debug signing
key is generated inside the ignored build directory. No release key is included.
The app has no network permission; catalog data is bundled from `../contract`.

Device tests are in `app/src/androidTest`. With a configured emulator or device:

```sh
./gradlew :app:connectedDebugAndroidTest
```

These tests may change the sample app's local state. Host/JVM tests and APK
compilation are separate from actual device execution.

The launcher accepts the Intent string extra `fieldguide.catalogFixture` for
fixtures such as `catalog-changed`, `catalog-long-text` and
`catalog-invalid-duplicate`; `source-error` simulates a source failure.

See the [repository README](../../README.md), [shared behavior](../contract/README.md)
and [agent rules](../AGENTS.md) for the rest of the project.

## Appearance and automatic screenshot tests

The current R2 design uses shared light/dark color tokens, illustrated landscapes,
and bundled Source Serif 4 Semibold. The font license is included in
`feature-catalog/licenses/SourceSerif4-OFL.txt`.

Compose previews in `FieldGuideComponents.kt` are discovered automatically by
`gradle/scripts/screenshot-testing.gradle`. The shared setup uses Roborazzi
1.39.0, preview scanner 0.4.0 and Robolectric 4.17. Four light/dark component
baselines live in `feature-catalog/src/test/screenshots`.

```sh
# Verify discovered previews against the committed images.
./gradlew :feature-catalog:verifyRoborazziDebug

# Only for an intentional visual change: record candidates, then review the diff.
./gradlew :feature-catalog:recordRoborazziDebug
```

Ordinary verification never updates baselines. Device journeys remain separate.
