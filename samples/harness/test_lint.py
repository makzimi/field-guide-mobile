"""Run the source linter against actual negative and corrected Kotlin examples."""

from pathlib import Path
import subprocess
import sys
import unittest


HERE = Path(__file__).parent
LINTER = HERE / "lint.py"


class SourceLintTest(unittest.TestCase):
    def run_lint(self, path: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(LINTER), str(path)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_bad_log_and_raw_ui_color_are_rejected_with_fixes(self):
        result = self.run_lint(HERE / "fixtures/bad-ui.kt")
        self.assertEqual(result.returncode, 1)
        self.assertIn("FG001", result.stdout)
        self.assertIn("Remove android.util.Log", result.stdout)
        self.assertIn("FG002", result.stdout)
        self.assertIn("MaterialTheme.colorScheme", result.stdout)

    def test_corrected_ui_passes(self):
        result = self.run_lint(HERE / "fixtures/good-ui.kt")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_comments_and_quoted_examples_do_not_trigger_rules(self):
        source = HERE / "fixtures/commented-ui.kt"
        result = self.run_lint(source)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_expression_body_raw_color_is_rejected(self):
        result = self.run_lint(HERE / "fixtures/bad-expression-ui.kt")
        self.assertEqual(result.returncode, 1)
        self.assertIn("FG002", result.stdout)


if __name__ == "__main__":
    unittest.main()
