#!/usr/bin/env python3
"""Select and run Field Guide checks from the project root."""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
FULL = [
    "contract",
    "source-lint",
    "flutter-assets",
    "android-jvm",
    "android-build",
    "android-instrumentation-build",
    "android-graph",
    "flutter-test",
    "flutter-analyze",
    "flutter-build",
    "flutter-graph",
    "boundary-check",
    "flutter-asset-check",
]
ANDROID_FAST = ["source-lint", "android-jvm"]
FLUTTER_FAST = ["source-lint", "flutter-test", "flutter-analyze"]
SHARED_FAST = ["contract", "source-lint", "android-jvm", "android-build", "flutter-test", "flutter-analyze", "flutter-build", "flutter-asset-check"]
ANDROID = ROOT / "samples/android"
FLUTTER = ROOT / "samples/flutter"


@dataclass(frozen=True)
class Check:
    name: str
    argv: list[str]
    cwd: Path
    env: dict[str, str] = field(default_factory=dict)


def run_checks(checks: list[Check], output: Path) -> int:
    """Run every selected check and preserve each exact command and exit code."""
    output.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, object]] = []
    for check in checks:
        log = output / f"{check.name}.log"
        began = time.monotonic()
        with log.open("w", encoding="utf-8") as stream:
            try:
                result = subprocess.run(
                    check.argv,
                    cwd=check.cwd,
                    env=os.environ | check.env,
                    stdout=stream,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
                exit_code = result.returncode
            except OSError as error:
                stream.write(f"Unable to launch check: {error}\n")
                exit_code = 127
        results.append({
            "name": check.name,
            "argv": check.argv,
            "cwd": str(check.cwd),
            "envOverrides": check.env,
            "exitCode": exit_code,
            "durationSeconds": round(time.monotonic() - began, 3),
            "log": str(log),
        })
        if check.name == "flutter-graph" and exit_code == 0:
            (output / "flutter-pub-deps.json").write_bytes(log.read_bytes())
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return 1 if any(item["exitCode"] != 0 for item in results) else 0


def configured_checks(output: Path) -> dict[str, Check]:
    """Pin every product command and its working directory in one place."""
    graph_log = output / "android-graph.log"
    pub_json = output / "flutter-pub-deps.json"
    java_home = os.environ.get("FIELD_GUIDE_JAVA_HOME")
    android_home = os.environ.get("ANDROID_HOME")
    if not java_home or not android_home:
        raise ValueError(
            "Set FIELD_GUIDE_JAVA_HOME to JDK 17 and ANDROID_HOME to the Android SDK "
            "before executing product checks"
        )
    android_env = {
        "JAVA_HOME": java_home,
        "ANDROID_HOME": android_home,
        "ANDROID_SDK_ROOT": android_home,
        "GRADLE_USER_HOME": str(ANDROID / ".gradle-user-home"),
        "PATH": java_home + "/bin:" + os.environ.get("PATH", ""),
    }
    gradle = ["./gradlew", "--no-daemon", "--console=plain"]
    flutter_binary = os.environ.get(
        "FIELD_GUIDE_FLUTTER_BIN", str(ROOT / "samples/.toolchains/flutter/bin/flutter")
    )
    dart_binary = str(Path(flutter_binary).with_name("dart"))
    flutter_env = {
        "FIELD_GUIDE_FLUTTER_BIN": flutter_binary,
        "JAVA_HOME": java_home,
        "ANDROID_HOME": android_home,
        "ANDROID_SDK_ROOT": android_home,
        "PATH": java_home + "/bin:" + os.environ.get("PATH", ""),
        "PUB_CACHE": str(FLUTTER / ".pub-cache"),
        "GRADLE_USER_HOME": str(FLUTTER / ".gradle-cache"),
        "XDG_CONFIG_HOME": str(FLUTTER / ".config"),
        "ANALYZER_STATE_LOCATION_OVERRIDE": str(FLUTTER / ".analyzer-state"),
        "FLUTTER_SUPPRESS_ANALYTICS": "true",
        "DASH__SUPPRESS_ANALYTICS": "true",
    }
    return {
        "contract": Check("contract", [sys.executable, "samples/contract/validate.py", "--report", str(output / "contract-report.txt")], ROOT),
        "source-lint": Check("source-lint", [sys.executable, "samples/harness/lint.py", "--all"], ROOT),
        "flutter-assets": Check("flutter-assets", ["./scripts/prepare-assets.sh"], FLUTTER),
        "android-jvm": Check("android-jvm", gradle + [":catalog-api:test", ":catalog-impl:test", ":feature-catalog:verifyRoborazziDebug", ":app:testDebugUnitTest"], ANDROID, android_env),
        "android-build": Check("android-build", gradle + [":app:assembleDebug"], ANDROID, android_env),
        "android-instrumentation-build": Check("android-instrumentation-build", gradle + [":app:assembleDebugAndroidTest"], ANDROID, android_env),
        "android-graph": Check("android-graph", gradle + ["printDirectProjectEdges", "--init-script", "../harness/project-edges.init.gradle"], ANDROID, android_env),
        "flutter-test": Check("flutter-test", ["./scripts/test.sh", "--reporter", "expanded"], FLUTTER, flutter_env),
        "flutter-analyze": Check("flutter-analyze", [flutter_binary, "analyze", "--no-pub"], FLUTTER, flutter_env),
        "flutter-build": Check("flutter-build", [flutter_binary, "build", "apk", "--debug", "--no-pub"], FLUTTER / "apps/field_guide", flutter_env),
        "flutter-graph": Check("flutter-graph", [dart_binary, "pub", "deps", "--json"], FLUTTER, flutter_env),
        "boundary-check": Check("boundary-check", [sys.executable, "samples/harness/graph.py", "--android-log", str(graph_log), "--flutter-json", str(pub_json), "--source-root", "samples"], ROOT),
        "flutter-asset-check": Check("flutter-asset-check", [sys.executable, "scripts/check-generated-assets.py", "--apk", "apps/field_guide/build/app/outputs/flutter-apk/app-debug.apk"], FLUTTER),
    }


def select_checks(full: bool, changed: list[str]) -> dict[str, object]:
    if full or not changed:
        return {"scope": "full", "checks": FULL}
    kinds: set[str] = set()
    for item in changed:
        path = Path(item)
        if path.is_absolute() or ".." in path.parts or not (ROOT / path).is_file():
            return {"scope": "full-fallback", "checks": FULL}
        parts = path.parts
        if parts[:2] == ("samples", "android") and path.suffix == ".kt":
            if len(parts) < 6 or parts[2] not in {"app", "catalog-api", "catalog-impl", "feature-catalog"} or parts[3] != "src" or parts[4] not in {"main", "test", "androidTest"}:
                return {"scope": "full-fallback", "checks": FULL}
            if parts[4] == "androidTest":
                if parts[2] != "app":
                    return {"scope": "full-fallback", "checks": FULL}
                kinds.add("android-instrumentation-test")
            else:
                kinds.add("android-app" if parts[2] == "app" else "android-code")
        elif parts[:2] == ("samples", "flutter") and path.suffix == ".dart":
            kinds.add("flutter-app" if parts[2:4] == ("apps", "field_guide") else "flutter-code")
        elif parts[:2] == ("samples", "contract") and path.suffix == ".json":
            kinds.add("contract")
        else:
            return {"scope": "full-fallback", "checks": FULL}
    if kinds == {"android-code"}:
        return {"scope": "android", "checks": ANDROID_FAST}
    if kinds == {"android-app"}:
        return {"scope": "android", "checks": ["source-lint", "android-jvm", "android-build", "android-instrumentation-build"]}
    if kinds == {"android-instrumentation-test"}:
        return {"scope": "android", "checks": ["source-lint", "android-jvm", "android-build", "android-instrumentation-build"]}
    if kinds == {"flutter-code"}:
        return {"scope": "flutter", "checks": ["flutter-assets"] + FLUTTER_FAST}
    if kinds == {"flutter-app"}:
        return {"scope": "flutter", "checks": ["flutter-assets"] + FLUTTER_FAST + ["flutter-build", "flutter-asset-check"]}
    if kinds == {"contract"}:
        return {"scope": "both", "checks": ["flutter-assets"] + SHARED_FAST}
    return {"scope": "full-fallback", "checks": FULL}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--fast", action="store_true")
    mode.add_argument("--full", action="store_true")
    parser.add_argument("--changed", action="append", default=[], metavar="PROJECT_PATH")
    parser.add_argument("--plan", action="store_true", help="Print selection without running checks")
    parser.add_argument("--output", type=Path, help="Directory for exact command logs and results.json")
    args = parser.parse_args()
    selected = select_checks(args.full, args.changed)
    if args.plan:
        print(json.dumps(selected))
        return 0
    if args.output is None:
        parser.error("--output is required when executing checks")
    output = args.output.resolve()
    try:
        checks = configured_checks(output)
    except ValueError as error:
        parser.error(str(error))
    # Pub writes JSON to stdout. Preserve that exact stream for the graph checker.
    chosen = [checks[name] for name in selected["checks"]]
    (output / "selection.json").parent.mkdir(parents=True, exist_ok=True)
    (output / "selection.json").write_text(json.dumps(selected, indent=2) + "\n")
    outcome = run_checks(chosen, output)
    print(f"{selected['scope']}: {len(chosen)} checks, exit {outcome}; results: {output / 'results.json'}")
    return outcome


if __name__ == "__main__":
    raise SystemExit(main())
