#!/usr/bin/env python3
"""Prove the contract validator rejects representative broken inputs."""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def run_case(name, change, expected_error):
    with tempfile.TemporaryDirectory(prefix="field-guide-contract-") as directory:
        target = Path(directory)
        shutil.copy(ROOT / "validate.py", target / "validate.py")
        for path in ROOT.glob("*.json"):
            shutil.copy(path, target / path.name)
        change(target)
        process = subprocess.run(
            [sys.executable, str(target / "validate.py")],
            text=True, capture_output=True, check=False,
        )
        passed = process.returncode == 1 and expected_error in process.stdout
        return f"{name}: {'PASS' if passed else 'FAIL'} (exit {process.returncode}; expected {expected_error!r})"


def change_json(target, filename, edit):
    path = target / filename
    data = json.loads(path.read_text(encoding="utf-8"))
    edit(data)
    path.write_text(json.dumps(data), encoding="utf-8")


def main():
    cases = [
        ("duplicate scenario ID", lambda t: change_json(t, "scenarios.json", lambda d: d["scenarios"][1].update(id="CAT-01")), "duplicate scenario ID"),
        ("broken fixture reference", lambda t: change_json(t, "scenarios.json", lambda d: d["scenarios"][0]["steps"][1].update(fixture="missing-catalog")), "unknown fixture"),
        ("wrong duration boundary", lambda t: change_json(t, "catalog-boundary.json", lambda d: d["walks"][0].update(durationMinutes=59)), "60/61-minute durations must be exact"),
        ("wrong TTL oracle", lambda t: change_json(t, "scenarios.json", lambda d: next(s for s in d["scenarios"] if s["id"] == "CLOCK-01")["steps"][2]["expect"].update(ageMs=299999)), "300000-ms stale boundary must be exact"),
    ]
    results = [run_case(*case) for case in cases]
    print("P3.2 validator negative checks")
    print("\n".join(results))
    print("Result:", "PASS" if all(": PASS" in result for result in results) else "FAIL")
    raise SystemExit(0 if all(": PASS" in result for result in results) else 1)


if __name__ == "__main__":
    main()
