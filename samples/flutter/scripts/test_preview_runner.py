"""The test entry point must discover new previews before verifying them."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).with_name('test.sh')


class PreviewRunnerTest(unittest.TestCase):
    def run_runner(self, generation_exit=0, *args):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            log = root / 'calls'
            for tool in ['dart', 'flutter']:
                binary = root / tool
                binary.write_text(
                    '#!/bin/sh\n'
                    f'echo "{tool} $*" >> "$CALL_LOG"\n'
                    + (f'exit {generation_exit}\n' if tool == 'dart' else '')
                )
                binary.chmod(0o755)
            run = subprocess.run(
                ['sh', str(RUNNER), *args], capture_output=True, text=True,
                env=os.environ | {'FIELD_GUIDE_FLUTTER_BIN': str(root / 'flutter'),
                                  'CALL_LOG': str(log)},
            )
            return run.returncode, log.read_text().splitlines() if log.exists() else []

    def test_discovers_before_verification_without_recording(self):
        code, calls = self.run_runner(0, 'test/preview_golden_test.dart')
        self.assertEqual(code, 0)
        self.assertEqual(calls, ['dart run build_runner build',
                                'flutter test --no-pub test/preview_golden_test.dart'])

    def test_generation_failure_prevents_stale_tests(self):
        code, calls = self.run_runner(7)
        self.assertEqual(code, 7)
        self.assertEqual(calls, ['dart run build_runner build'])

    def test_recording_requires_explicit_argument(self):
        code, calls = self.run_runner(0, 'test/preview_golden_test.dart', '--update-goldens')
        self.assertEqual(code, 0)
        self.assertEqual(calls[-1], 'flutter test --no-pub test/preview_golden_test.dart --update-goldens')


if __name__ == '__main__':
    unittest.main()
