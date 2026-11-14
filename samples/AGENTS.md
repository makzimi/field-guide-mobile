# Field Guide sample agent rules

These rules apply to the original Android and Flutter Field Guide examples (R1 behavior, R2 appearance). The shared hand-authored acceptance behavior is in `samples/contract/README.md` and `samples/contract/scenarios.json`. Do not add an account, service, payment flow or third screen.

## Product boundaries

- Keep exactly four product boundaries on each platform: app, catalog API, catalog implementation and catalog feature.
- App composes the feature, API and implementation. Feature depends on API. Implementation depends on API. API has no platform/UI dependency. Feature cannot import implementation. Implementation cannot import feature.
- Put transport validation, refresh/cache policy, query and bookmark persistence in implementation; immutable models/ports in API; screen state, actions and rendering in feature; local adapters and entry point in app.
- Run `python3 samples/harness/graph.py --android-log ... --flutter-json ... --source-root samples` after resolving the actual Gradle/Pub graphs. Do not infer compiled dependencies from folder names alone.

## UI and data

- Use Material theme semantic colors. In Compose use `MaterialTheme.colorScheme` rather than raw `Color(0x...)` inside `WalkList` or `WalkDetail`. Keep interactive controls named for accessibility. Preserve light/dark rendering, large-text reachability and local original art.
- R2 appearance rules: screens read colors from the feature theme. Art colors come from the named art palette, never raw values in scene code. The two platforms' palettes, fit rule and scene geometry stay in step. The bundled Source Serif 4 font and its OFL license travel together.
- Edit `samples/contract/*.json` as the one canonical scenario/fixture source. Regenerate Flutter app assets with `samples/flutter/scripts/prepare-assets.sh`; do not hand-edit generated copies. Hand-authored expected values must remain independent of production mappers and query logic.
- Preserve R1's fake monotonic clock boundaries: 299999 ms is fresh and 300000 ms is stale. Bookmark persistence and catalog cache have separate lifetimes.

## Verification and evidence

- From the project root, `python3 samples/harness/check.py --fast --changed samples/android/path/to/changed.kt --output verification/my-fast-run` selects safe focused checks. Pass each changed path with another `--changed`. An unknown, missing or build-configuration path falls back to the full suite. Without changed paths, fast also runs full.
- `python3 samples/harness/check.py --full --output verification/my-full-run` runs canonical contract validation, static source lint, generated Flutter assets, Android JVM tests/app build/test APK build/resolved graph, Flutter tests/analyzer/build/resolved graph, architecture boundary check and APK asset comparison. The command writes exact argv, working directory, exit and timing to `results.json`, plus one full log per check. Set `FIELD_GUIDE_JAVA_HOME` to JDK 17 and `ANDROID_HOME` to the Android SDK before execution. Set `FIELD_GUIDE_FLUTTER_BIN` to the absolute path of your Flutter executable.
- Do not call a unit, widget or in-process graph test a device result. Android instrumented tests and Flutter emulator journeys must state device identity, environment, exact action matcher, captured state and screen evidence. An APK build proves compilation and packaging, not behavior.
- Each demonstrated rule needs a bad input with a nonzero check, a corrected input with zero exit and retained logs. Preserve source/config/fixture hashes and exact command output. A test created by an agent should use an expected value that does not come from the production code it checks.
