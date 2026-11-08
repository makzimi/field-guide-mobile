#!/usr/bin/env python3
"""Deterministic, narrowly scoped Field Guide Kotlin source rules."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
LOG_PATTERN = re.compile(r"\b(?:import\s+android\.util\.Log\b|android\.util\.Log\s*\.|Log\s*\.\s*(?:d|e|i|v|w|wtf)\s*\()")
COLOR_PATTERN = re.compile(r"\bColor\s*\(\s*0x[0-9A-Fa-f]{8}\s*\)")
UI_FUNCTION = re.compile(r"\bfun\s+(?:WalkList|WalkDetail)\s*\(")


def code_only(source: str) -> str:
    """Blank Kotlin comments and literals while retaining offsets and newlines."""
    output = list(source)
    state = "code"
    i = 0
    while i < len(source):
        pair = source[i:i + 2]
        triple = source[i:i + 3]
        if state == "code":
            if pair == "//":
                state = "line"
                width = 2
            elif pair == "/*":
                state = "block"
                width = 2
            elif triple == '"""':
                state = "triple"
                width = 3
            elif source[i] == '"':
                state = "string"
                width = 1
            elif source[i] == "'":
                state = "char"
                width = 1
            else:
                i += 1
                continue
            for j in range(i, i + width):
                output[j] = " "
            i += width
            continue
        if state == "line" and source[i] == "\n":
            state = "code"
            i += 1
            continue
        if state == "block" and pair == "*/":
            output[i:i + 2] = [" ", " "]
            i += 2
            state = "code"
            continue
        if state == "triple" and triple == '"""':
            output[i:i + 3] = [" ", " ", " "]
            i += 3
            state = "code"
            continue
        if state in {"string", "char"} and source[i] == "\\":
            output[i] = " "
            if i + 1 < len(source):
                output[i + 1] = " "
            i += 2
            continue
        if (state == "string" and source[i] == '"') or (state == "char" and source[i] == "'"):
            output[i] = " "
            state = "code"
            i += 1
            continue
        if source[i] != "\n":
            output[i] = " "
        i += 1
    return "".join(output)


def line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def ui_body_span(code: str, after_open_paren: int) -> tuple[int, int] | None:
    """Find the narrow block or expression body of a named Compose function."""
    depth = 1
    index = after_open_paren
    while index < len(code) and depth:
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1
        index += 1
    if depth:
        return None
    while index < len(code):
        if code.startswith("fun ", index):
            return None
        if code[index] == "{":
            start = index + 1
            depth = 1
            index += 1
            while index < len(code) and depth:
                if code[index] == "{":
                    depth += 1
                elif code[index] == "}":
                    depth -= 1
                index += 1
            return start, index - 1
        if code[index] == "=":
            start = index + 1
            index += 1
            nesting = 0
            saw_code = False
            while index < len(code):
                char = code[index]
                if char == "\n" and nesting == 0 and saw_code:
                    break
                if char in "([{":
                    nesting += 1
                elif char in ")]}":
                    nesting -= 1
                saw_code = saw_code or not char.isspace()
                index += 1
            return start, index
        index += 1
    return None


def inspect(path: Path) -> list[str]:
    source = path.read_text(encoding="utf-8")
    code = code_only(source)
    findings: list[str] = []
    for match in LOG_PATTERN.finditer(code):
        findings.append(
            f"{path}:{line_number(source, match.start())}: FG001: "
            "android.util.Log in product source can expose data and hide state failures. "
            "Remove android.util.Log; represent the failure in Feature state and assert it in a test."
        )
    for function in UI_FUNCTION.finditer(code):
        span = ui_body_span(code, function.end())
        if span is None:
            continue
        start, end = span
        for match in COLOR_PATTERN.finditer(code, start, end):
            findings.append(
                f"{path}:{line_number(source, match.start())}: FG002: "
                "A raw UI color bypasses the active light/dark theme. "
                "Replace Color(0x...) with MaterialTheme.colorScheme.primary "
                "or the appropriate semantic theme token."
            )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--all", action="store_true", help="Inspect production Kotlin source")
    args = parser.parse_args()
    paths = list(args.paths)
    if args.all:
        paths.extend(sorted((ROOT / "samples/android").glob("*/src/main/**/*.kt")))
    if not paths:
        parser.error("pass Kotlin paths or --all")
    findings: list[str] = []
    for path in paths:
        if not path.is_file() or path.suffix != ".kt":
            parser.error(f"not a Kotlin source file: {path}")
        findings.extend(inspect(path))
    for finding in findings:
        print(finding)
    if findings:
        print(f"FAIL {len(findings)} source rule violation(s)")
        return 1
    print(f"PASS {len(paths)} Kotlin source file(s) checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
