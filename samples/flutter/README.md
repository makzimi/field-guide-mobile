# Field Guide for Flutter

This Pub workspace contains `apps/field_guide` and three packages:
`catalog_api`, `catalog_impl` and `feature_catalog`. Keep the sibling `contract`
directory in place. All workspace members share the root `pubspec.lock`.

Use Flutter 3.47.7 with Dart 3.13.5 and JDK 17. The included Android host uses
SDK 36, build tools 36.0.0, NDK 28.2.13676358, Gradle 9.3.1 and AGP 9.1.0.
Minimum Android SDK is 24. Release signing is not configured.

From this directory, with the pinned Flutter executable on PATH:

```sh
./scripts/prepare-assets.sh
flutter pub get
flutter test --reporter expanded
flutter analyze
cd apps/field_guide
flutter run
flutter build apk --debug
```

The debug APK is `apps/field_guide/build/app/outputs/flutter-apk/app-debug.apk`.
Tests use hand-authored expectations from `../contract`; asset generation copies
six catalog fixtures into the app. Do not edit generated asset copies.

Launch variants:

```sh
flutter run --dart-define=FIELD_GUIDE_FAIL_FIRST=true
flutter run --dart-define=FIELD_GUIDE_CATALOG=catalog-long-text
```

`FIELD_GUIDE_FAIL_FIRST` exercises Retry. Other packaged fixtures include
`catalog-changed`, `catalog-boundary`, `catalog-invalid-duplicate` and
`catalog-invalid-enum`.

The golden suite uses the pinned Flutter SDK fonts and 393 by 852 logical
pixels. Review intended visual changes before updating baselines. Device tests
live in `apps/field_guide/integration_test`; their source is separate from the
host widget and golden suites. With a configured device, from the app directory:

```sh
flutter drive --driver=test_driver/p37_driver.dart --target=integration_test/p37_test.dart
```

The device driver saves captures under `samples/flutter/evidence/p3.7/device`
(relative to the repository root), which is ignored by Git.

See the [repository README](../../README.md) and [agent rules](../AGENTS.md).
