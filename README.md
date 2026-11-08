# Field Guide

The same small mobile app implemented in **Kotlin / Jetpack Compose** and
**Dart / Flutter**, with examples of behavior tests, screenshot tests,
integration tests, device journeys and structural checks.

Browse fictional walks, filter by title and walking time, open a route and save
it locally. Both apps use bundled data and work without an account or backend.
The central promise is simple: when the UI says a walk is saved, persistence
has already succeeded.

## Projects

| Path | Contents |
| --- | --- |
| [samples/android](samples/android) | Native Android app, four Gradle modules and tests |
| [samples/flutter](samples/flutter) | Flutter app, four Pub workspace members and tests |
| [samples/contract](samples/contract) | Shared fictional catalogs and hand-authored behavior expectations |
| [samples/harness](samples/harness) | Source conventions, dependency checks and a local check runner |

The shared fixtures and harness are part of these projects. Keep their relative
paths when opening either app. See [agent rules](samples/AGENTS.md) for the
architecture and [the contract](samples/contract/README.md) for expected behavior.

## Requirements

- JDK 17 and Android SDK platform 36, with accepted licenses.
- Android build tools 35.0.0 and 36.0.0.
- Flutter 3.47.7, including Dart 3.13.5, for the Flutter project.
- NDK 28.2.13676358 for the Flutter Android build.
- Python 3 for the shared checks.

Gradle wrappers and dependency lockfiles are included. Initial dependency
downloads need network access. SDKs, build outputs and local signing keys are
not committed. Release signing is not configured.

## Run Android

Set `JAVA_HOME` to your JDK 17 directory and `ANDROID_HOME` to your installed
SDK, then open `samples/android` in Android Studio. Or build from the repository
root:

```sh
cd samples/android
./gradlew :app:assembleDebug
```

The debug APK is `samples/android/app/build/outputs/apk/debug/app-debug.apk`.
See [Android setup and tests](samples/android/README.md).

## Run Flutter

With the pinned Flutter SDK on your PATH, run from the repository root:

```sh
./samples/flutter/scripts/prepare-assets.sh
cd samples/flutter
flutter pub get
cd apps/field_guide
flutter run
```

Asset generation copies the canonical JSON fixtures into the app. Edit the
files in `samples/contract`, then regenerate. The included Flutter host targets
Android. See [Flutter setup and tests](samples/flutter/README.md).

## Run the checks

Lightweight shared checks, from the repository root:

```sh
python3 samples/contract/validate.py
python3 samples/contract/test_validate.py
python3 -m unittest discover -s samples/harness -p 'test_*.py'
python3 samples/harness/lint.py --all
```

For the full host suite, set `FIELD_GUIDE_JAVA_HOME` to your JDK 17 directory,
`ANDROID_HOME` to your Android SDK, and `FIELD_GUIDE_FLUTTER_BIN` to the absolute
path of `flutter/bin/flutter`. Prepare dependencies, then run:

```sh
./samples/flutter/scripts/prepare-assets.sh
cd samples/flutter
"$FIELD_GUIDE_FLUTTER_BIN" pub get
cd ../..
python3 samples/harness/check.py --full --output verification/full
```

The harness runs JVM and Flutter tests, analysis, both debug APK builds,
Android instrumentation compilation, resolved dependency checks and asset
checks. It does not run device journeys. Each result includes its command and
exit status under the selected output directory.

Flutter golden images are test fixtures tied to the pinned SDK and fonts.
Inspect intentional visual changes before accepting new baselines. Compilation
and passing host tests do not establish behavior on every device.

## Examples to explore

- A cache is fresh at 299999 ms and stale at 300000 ms.
- Failed storage writes must not publish a successful save.
- A late request must not replace the result of a newer request.
- UI modules depend on interfaces, without importing implementations.
- Module/package dependency checks use the resolved build graph.

Try breaking one of these rules, run the relevant check and inspect its failure.
