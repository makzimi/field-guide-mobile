#!/usr/bin/env python3
"""Verify resolved product edges and source imports for both Field Guide apps."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


ANDROID_EXPECTED = {
    ":app": {":catalog-api", ":catalog-impl", ":feature-catalog"},
    ":catalog-api": set(),
    ":catalog-impl": {":catalog-api"},
    ":feature-catalog": {":catalog-api"},
}
FLUTTER_EXPECTED = {
    "field_guide": {"flutter", "catalog_api", "catalog_impl", "feature_catalog"},
    "catalog_api": set(),
    "catalog_impl": {"catalog_api"},
    "feature_catalog": {"flutter", "catalog_api"},
}
ANDROID_EDGE = re.compile(r"^(:[\w-]+) \[(debugRuntimeClasspath|runtimeClasspath)\] -> (.*)$")
KOTLIN_IMPORT = re.compile(r"^\s*import\s+([\w.]+)", re.MULTILINE)
DART_IMPORT = re.compile(r"^\s*import\s+['\"]package:([^/'\"]+)", re.MULTILINE)
DART_SDK_IMPORT = re.compile(r"^\s*import\s+['\"](dart:[^'\"]+)", re.MULTILINE)
PLATFORM_DART_SDKS = ("dart:ui", "dart:io", "dart:html", "dart:js", "dart:ffi", "dart:mirrors")


def android_graph(path: Path) -> list[str]:
    found: dict[str, set[str]] = {}
    failures: list[str] = []
    for line in path.read_text().splitlines():
        match = ANDROID_EDGE.match(line)
        if not match:
            continue
        name, _, rendered = match.groups()
        if name in found:
            failures.append(f"duplicate resolved Android node {name}")
        found[name] = set() if rendered == "(none)" else set(rendered.split(", "))
    if set(found) != set(ANDROID_EXPECTED):
        failures.append(f"Android resolved graph nodes {sorted(found)}; expected {sorted(ANDROID_EXPECTED)}")
    for name, expected in ANDROID_EXPECTED.items():
        if name in found and found[name] != expected:
            failures.append(f"Android resolved {name} edges {sorted(found[name])}; expected {sorted(expected)}")
    return failures


def flutter_graph(path: Path) -> list[str]:
    data = json.loads(path.read_text())
    packages = data.get("packages", [])
    failures: list[str] = []
    found: dict[str, dict] = {}
    for item in packages:
        name = item.get("name")
        if name not in FLUTTER_EXPECTED:
            continue
        if name in found:
            failures.append(f"duplicate resolved Flutter node {name}")
        found[name] = item
    if set(found) != set(FLUTTER_EXPECTED):
        failures.append(f"Flutter resolved graph nodes {sorted(found)}; expected {sorted(FLUTTER_EXPECTED)}")
    for name, expected in FLUTTER_EXPECTED.items():
        if name not in found:
            continue
        item = found[name]
        edges = set(item.get("directDependencies", []))
        if item.get("source") != "root" or edges != expected:
            failures.append(f"Flutter resolved {name} edges {sorted(edges)}; expected {sorted(expected)}; source {item.get('source')}")
    return failures


def source_imports(root: Path) -> list[str]:
    failures: list[str] = []
    for name in ("catalog-api", "catalog-impl", "feature-catalog"):
        files = sorted((root / "android" / name / "src/main").rglob("*.kt"))
        if not files:
            failures.append(f"empty Android source discovery: {name}")
            continue
        for file in files:
            for imported in KOTLIN_IMPORT.findall(file.read_text()):
                forbidden = (
                    (name in {"catalog-api", "catalog-impl"} and imported.startswith(("android.", "androidx.")))
                    or (name == "catalog-api" and imported.startswith(("dev.fieldguide.catalog.impl", "dev.fieldguide.feature.catalog")))
                    or (name == "catalog-impl" and imported.startswith("dev.fieldguide.feature.catalog"))
                    or (name == "feature-catalog" and imported.startswith("dev.fieldguide.catalog.impl"))
                )
                if forbidden:
                    failures.append(f"Android {name} forbidden import {imported} in {file}")
    for name in ("catalog_api", "catalog_impl", "feature_catalog"):
        files = sorted((root / "flutter/packages" / name / "lib").rglob("*.dart"))
        if not files:
            failures.append(f"empty Flutter source discovery: {name}")
            continue
        for file in files:
            source = file.read_text()
            for imported in DART_SDK_IMPORT.findall(source):
                if name in {"catalog_api", "catalog_impl"} and imported.startswith(PLATFORM_DART_SDKS):
                    failures.append(f"Flutter {name} forbidden import {imported} in {file}")
            for imported in DART_IMPORT.findall(source):
                forbidden = (
                    (name in {"catalog_api", "catalog_impl"} and imported == "flutter")
                    or (name == "catalog_api" and imported in {"catalog_impl", "feature_catalog"})
                    or (name == "catalog_impl" and imported == "feature_catalog")
                    or (name == "feature_catalog" and imported == "catalog_impl")
                )
                if forbidden:
                    failures.append(f"Flutter {name} forbidden import {imported} in {file}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-log", type=Path, required=True)
    parser.add_argument("--flutter-json", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    args = parser.parse_args()
    for path in (args.android_log, args.flutter_json):
        if not path.is_file():
            parser.error(f"missing resolved graph: {path}")
    failures = android_graph(args.android_log) + flutter_graph(args.flutter_json) + source_imports(args.source_root)
    for failure in failures:
        print("FAIL:", failure)
    if failures:
        return 1
    print("PASS: resolved Android and Flutter product edges, nonempty source discovery and allowed imports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
