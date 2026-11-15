#!/usr/bin/env python3
"""Verify resolved product edges and source imports for both Field Guide apps."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


# Naming conventions decide every rule. No module or package is listed by name,
# so a new feature or implementation is covered as soon as it exists.
ALLOWED_ROLES = {
    "api": {"api"},
    "impl": {"api"},
    "feature": {"api"},
    "app": {"api", "impl", "feature"},
}
PURE_ROLES = {"api", "impl"}
ANDROID_EDGE = re.compile(r"^(:[\w-]+) \[(debugRuntimeClasspath|runtimeClasspath)\] -> (.*)$")
KOTLIN_PACKAGE = re.compile(r"^\s*package\s+([\w.]+)", re.MULTILINE)
KOTLIN_IMPORT = re.compile(r"^\s*import\s+([\w.]+)", re.MULTILINE)
DART_IMPORT = re.compile(r"^\s*import\s+['\"]package:([^/'\"]+)", re.MULTILINE)
DART_SDK_IMPORT = re.compile(r"^\s*import\s+['\"](dart:[^'\"]+)", re.MULTILINE)
PLATFORM_DART_SDKS = ("dart:ui", "dart:io", "dart:html", "dart:js", "dart:ffi", "dart:mirrors")


def role(name: str) -> str:
    """feature-* is a feature, *-api an API, *-impl an implementation, the rest an app."""
    plain = name.lstrip(":").replace("_", "-")
    if plain.startswith("feature-"):
        return "feature"
    if plain.endswith("-api"):
        return "api"
    if plain.endswith("-impl"):
        return "impl"
    return "app"


def forbidden_edges(platform: str, graph: dict[str, set[str]]) -> list[str]:
    failures: list[str] = []
    roles = {role(name) for name in graph}
    for required in ("feature", "impl"):
        if required not in roles:
            failures.append(f"empty {platform} discovery: no {required} in {sorted(graph)}")
    for name, edges in sorted(graph.items()):
        for edge in sorted(edges):
            if edge in graph and role(edge) not in ALLOWED_ROLES[role(name)]:
                failures.append(f"{platform} {role(name)} {name} must not depend on {role(edge)} {edge}")
    return failures


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
    for edges in list(found.values()):
        for edge in edges:
            found.setdefault(edge, set())
    return failures + forbidden_edges("Android resolved", found)


def flutter_graph(path: Path) -> list[str]:
    data = json.loads(path.read_text())
    failures: list[str] = []
    found: dict[str, set[str]] = {}
    for item in data.get("packages", []):
        name = item.get("name")
        if item.get("source") != "root" or name == data.get("root"):
            continue
        if name in found:
            failures.append(f"duplicate resolved Flutter node {name}")
        found[name] = set(item.get("directDependencies", []))
    for name, edges in sorted(found.items()):
        if role(name) in PURE_ROLES and "flutter" in edges:
            failures.append(f"Flutter resolved {role(name)} {name} must not depend on flutter")
    return failures + forbidden_edges("Flutter resolved", found)


def source_imports(root: Path) -> list[str]:
    failures: list[str] = []

    android = {path.name: sorted((path / "src/main").rglob("*.kt"))
               for path in sorted((root / "android").glob("*")) if (path / "src/main").is_dir()}
    if not android or not all(android.values()):
        failures.append(f"empty Android source discovery: {sorted(n for n, f in android.items() if not f) or 'no modules'}")
    owners = {package: name for name, files in android.items()
              for file in files for package in KOTLIN_PACKAGE.findall(file.read_text())}
    for name, files in android.items():
        for file in files:
            for imported in KOTLIN_IMPORT.findall(file.read_text()):
                owner = owners.get(imported.rpartition(".")[0])
                forbidden = (
                    (role(name) in PURE_ROLES and imported.startswith(("android.", "androidx.")))
                    or (owner is not None and owner != name and role(owner) not in ALLOWED_ROLES[role(name)])
                )
                if forbidden:
                    failures.append(f"Android {role(name)} {name} forbidden import {imported} in {file}")

    flutter = {path.name: sorted((path / "lib").rglob("*.dart"))
               for path in sorted((root / "flutter/packages").glob("*")) if (path / "lib").is_dir()}
    if not flutter or not all(flutter.values()):
        failures.append(f"empty Flutter source discovery: {sorted(n for n, f in flutter.items() if not f) or 'no packages'}")
    for name, files in flutter.items():
        for file in files:
            source = file.read_text()
            for imported in DART_SDK_IMPORT.findall(source):
                if role(name) in PURE_ROLES and imported.startswith(PLATFORM_DART_SDKS):
                    failures.append(f"Flutter {role(name)} {name} forbidden import {imported} in {file}")
            for imported in DART_IMPORT.findall(source):
                forbidden = (
                    (role(name) in PURE_ROLES and imported == "flutter")
                    or (imported in flutter and imported != name and role(imported) not in ALLOWED_ROLES[role(name)])
                )
                if forbidden:
                    failures.append(f"Flutter {role(name)} {name} forbidden import {imported} in {file}")
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
