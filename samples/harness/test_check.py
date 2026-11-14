"""Observable selection rules for the Field Guide check runner."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).with_name("check.py")


def plan(*args: str) -> dict:
    run = subprocess.run(
        [sys.executable, str(CHECKER), "--plan", *args],
        text=True,
        capture_output=True,
        check=False,
    )
    assert run.returncode == 0, (run.returncode, run.stdout, run.stderr)
    return json.loads(run.stdout)


class ChangedFileSelectionTest(unittest.TestCase):
    def test_android_change_runs_android_checks_only(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/android/catalog-impl/src/main/kotlin/dev/fieldguide/catalog/impl/WalkUseCases.kt"),
            {"scope": "android", "checks": ["source-lint", "android-jvm"]},
        )

    def test_flutter_change_runs_flutter_checks_only(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/flutter/packages/catalog_impl/lib/catalog_impl.dart"),
            {"scope": "flutter", "checks": ["flutter-assets", "source-lint", "flutter-test", "flutter-analyze"]},
        )

    def test_shared_contract_change_runs_both_platforms(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/contract/catalog-valid.json"),
            {"scope": "both", "checks": ["flutter-assets", "contract", "source-lint", "android-jvm", "android-build", "flutter-test", "flutter-analyze", "flutter-build", "flutter-asset-check"]},
        )

    def test_unknown_change_falls_back_to_full_check(self):
        actual = plan("--fast", "--changed", "project/DECISIONS.md")
        self.assertEqual(actual["scope"], "full-fallback")
        self.assertEqual(
            actual["checks"],
            ["contract", "source-lint", "flutter-assets", "android-jvm", "android-build", "android-instrumentation-build", "android-graph", "flutter-test", "flutter-analyze", "flutter-build", "flutter-graph", "boundary-check", "flutter-asset-check"],
        )

    def test_no_changed_paths_falls_back_to_full_check(self):
        self.assertEqual(plan("--fast"), plan("--full"))

    def test_missing_changed_file_falls_back_to_full_check(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/android/does-not-exist.kt")["scope"],
            "full-fallback",
        )

    def test_build_configuration_change_falls_back_to_full_check(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/android/app/build.gradle.kts")["scope"],
            "full-fallback",
        )

    def test_app_composition_change_includes_build(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/android/app/src/main/kotlin/dev/fieldguide/app/MainActivity.kt")["checks"],
            ["source-lint", "android-jvm", "android-build", "android-instrumentation-build"],
        )

    def test_flutter_app_change_includes_build(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/flutter/apps/field_guide/lib/main.dart")["checks"],
            ["flutter-assets", "source-lint", "flutter-test", "flutter-analyze", "flutter-build", "flutter-asset-check"],
        )

    def test_android_instrumented_test_change_compiles_test_apk(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/android/app/src/androidTest/kotlin/dev/fieldguide/app/DeviceEvidenceTest.kt")["checks"],
            ["source-lint", "android-jvm", "android-build", "android-instrumentation-build"],
        )

    def test_unknown_android_source_set_falls_back_to_full(self):
        self.assertEqual(
            plan("--fast", "--changed", "samples/android/feature-catalog/build.gradle.kts")["scope"],
            "full-fallback",
        )


class CommandExecutionTest(unittest.TestCase):
    def test_failing_check_is_recorded_and_makes_run_fail(self):
        # A swallowed subprocess failure would falsely declare the harness green.
        from samples.harness.check import Check, run_checks

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            checks = [
                Check("fails", [sys.executable, "-c", "raise SystemExit(7)"], output),
                Check("passes", [sys.executable, "-c", "print('fixed')"], output),
            ]
            self.assertEqual(run_checks(checks, output), 1)
            results = json.loads((output / "results.json").read_text())
            self.assertEqual([item["exitCode"] for item in results], [7, 0])
            self.assertEqual((output / "passes.log").read_text().strip(), "fixed")

    def test_corrected_check_exits_zero(self):
        from samples.harness.check import Check, run_checks

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            checks = [Check("passes", [sys.executable, "-c", "print('fixed')"], output)]
            self.assertEqual(run_checks(checks, output), 0)
            self.assertEqual(json.loads((output / "results.json").read_text())[0]["exitCode"], 0)


class PreviewIntegrationTest(unittest.TestCase):
    def test_full_harness_verifies_android_and_regenerates_flutter_previews(self):
        from unittest.mock import patch
        from samples.harness.check import configured_checks
        with patch.dict('os.environ', {'FIELD_GUIDE_JAVA_HOME': '/jdk', 'ANDROID_HOME': '/sdk'}):
            checks = configured_checks(Path('/tmp/field-guide-test'))
        self.assertIn(':feature-catalog:verifyRoborazziDebug', checks['android-jvm'].argv)
        self.assertEqual(checks['flutter-test'].argv[0], './scripts/test.sh')
        self.assertNotIn('--update-goldens', checks['flutter-test'].argv)


if __name__ == "__main__":
    unittest.main()
