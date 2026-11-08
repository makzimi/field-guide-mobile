#!/usr/bin/env python3
"""Static integrity check for the hand-authored P3.2 fixtures and oracles."""

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
EXPECTED_IDS = [
    *(f"CAT-{n:02d}" for n in range(1, 9)),
    *(f"SAVE-{n:02d}" for n in range(1, 7)),
    "NAV-01", "CLOCK-01", "VIEW-01",
]
TERRAINS = {"woodland", "garden", "waterside", "ridge"}
AVAILABILITIES = {"open", "closed"}
ART_KEYS = {"pine", "glasshouse", "canal", "ridge"}
WALK_KEYS = {"id", "title", "description", "durationMinutes", "distanceMetres", "terrain", "availability", "artKey"}
ACTIONS = {
    "openList", "completeCatalog", "setBudget", "setQuery", "clearFilters",
    "failCatalog", "retryCatalog", "openDetail", "startRefresh",
    "refreshWithFixture", "backToList", "startSave", "completeSave",
    "retrySave", "addBookmark", "removeBookmark", "recreateProcess",
    "completeStorageLoad", "failStorageLoad", "retryStorageLoad", "setClock",
    "resetHarness", "startRemove", "foreground", "invokeAddUseCase",
}
ROUTE_ASSERTIONS = {"listIds", "closedIds", "savedBadgeIds", "includedId", "excludedId", "routeId"}
ACTION_REQUIRED = {
    "setQuery": ("text",), "setBudget": ("minutes",), "openDetail": ("routeId",),
    "startSave": ("routeId",), "startRemove": ("routeId",),
    "addBookmark": ("routeId",), "removeBookmark": ("routeId",),
    "invokeAddUseCase": ("routeId",), "completeSave": ("result",),
    "failCatalog": ("error",), "setClock": ("clockMs",),
}


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def read_json(path, errors):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"{path.name}: cannot read JSON: {exc}")
        return None


def validate_catalog(path, data, errors):
    name = path.name
    if not isinstance(data, dict) or data.get("fixtureId") != path.stem or data.get("kind") != "catalog":
        errors.append(f"{name}: fixtureId must match filename and kind must be catalog")
        return set()
    walks = data.get("walks")
    if not isinstance(walks, list) or not walks:
        errors.append(f"{name}: walks must be a nonempty array")
        return set()
    invalid = name.startswith("catalog-invalid-")
    if invalid != ("invalidBecause" in data):
        errors.append(f"{name}: invalidBecause must appear exactly on invalid fixtures")
    ids = []
    defects = set()
    for index, walk in enumerate(walks):
        label = f"{name} walks[{index}]"
        if not isinstance(walk, dict):
            errors.append(f"{label}: expected an object")
            continue
        for key in WALK_KEYS - set(walk):
            defects.add(f"missing-{key}")
        for key in set(walk) - WALK_KEYS:
            errors.append(f"{label}: unexpected field {key}")
        for key in ("id", "title", "description"):
            if key in walk and (not isinstance(walk[key], str) or not walk[key].strip()):
                defects.add(f"blank-{key}")
        if isinstance(walk.get("id"), str):
            ids.append(walk["id"])
            if walk["id"].strip() and not all(c.isascii() and (c.islower() or c.isdigit() or c == "-") for c in walk["id"]):
                defects.add("malformed-id")
        for key in ("durationMinutes", "distanceMetres"):
            if key in walk and (not is_int(walk[key]) or walk[key] <= 0):
                defects.add(f"nonpositive-{key}")
        if "terrain" in walk and walk["terrain"] not in TERRAINS:
            defects.add("unknown-terrain")
        if "availability" in walk and walk["availability"] not in AVAILABILITIES:
            defects.add("unknown-availability")
        if "artKey" in walk and walk["artKey"] not in ART_KEYS:
            defects.add("unknown-art-key")
    if len(ids) != len(set(ids)):
        defects.add("duplicate-id")
    if invalid:
        declared = set(data.get("invalidBecause", "").split("-and-"))
        aliases = {
            "nonpositive-duration": "nonpositive-durationMinutes",
            "nonpositive-distance": "nonpositive-distanceMetres",
            "unknown-art-key": "unknown-art-key",
        }
        declared = {aliases.get(d, d) for d in declared}
        if not defects or declared != defects:
            errors.append(f"{name}: declared defects {sorted(declared)} differ from actual {sorted(defects)}")
    elif defects:
        errors.append(f"{name}: valid catalog has defects {sorted(defects)}")
    return set(ids)


def require(condition, message, errors):
    if not condition:
        errors.append(message)


def validate_scenarios(data, fixture_routes, errors):
    fixture_ids = set(fixture_routes)
    if not isinstance(data, dict):
        errors.append("scenarios.json: top level must be an object")
        return
    require(data.get("schemaVersion") == 1, "scenarios.json: schemaVersion must be 1", errors)
    require(data.get("clockUnit") == "monotonic-ms", "scenarios.json: clockUnit must be monotonic-ms", errors)
    require(data.get("ttlMs") == 300000, "scenarios.json: ttlMs must be exactly 300000", errors)
    require(data.get("defaultBudgetMinutes") == 60, "scenarios.json: default budget must be 60", errors)
    require(data.get("scenarioIds") == EXPECTED_IDS, "scenarios.json: scenarioIds must list the 17 approved IDs in order", errors)
    scenarios = data.get("scenarios")
    if not isinstance(scenarios, list):
        errors.append("scenarios.json: scenarios must be an array")
        return
    ids = [s.get("id") for s in scenarios if isinstance(s, dict)]
    require(ids == EXPECTED_IDS, "scenarios.json: scenario entries must contain each approved ID once in order", errors)
    require(len(ids) == len(set(ids)), "scenarios.json: duplicate scenario ID", errors)
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            errors.append("scenarios.json: scenario must be an object")
            continue
        sid = scenario.get("id", "<missing>")
        initial = scenario.get("initial")
        if not isinstance(initial, dict):
            errors.append(f"{sid}: initial must be an object")
            continue
        required_initial = {"clockMs", "catalogFixture", "savedIds", "storage", "budgetMinutes", "query"}
        require(required_initial <= set(initial), f"{sid}: missing initial fields", errors)
        require(is_int(initial.get("clockMs")) and initial["clockMs"] >= 0, f"{sid}: invalid initial clock", errors)
        require(initial.get("budgetMinutes") in (15, 30, 60, 90), f"{sid}: invalid budget", errors)
        require(initial.get("storage") in ("loaded", "loading"), f"{sid}: invalid storage state", errors)
        require(isinstance(initial.get("query"), str), f"{sid}: query must be string", errors)
        saved = initial.get("savedIds")
        require(isinstance(saved, list) and len(saved) == len(set(saved)) and all(isinstance(x, str) and x for x in saved), f"{sid}: savedIds must be unique nonempty strings", errors)
        refs = []
        route_assertions = []
        pending_requests = set()
        current_clock = initial.get("clockMs")
        fixture = initial.get("catalogFixture")
        if fixture is not None:
            refs.append(fixture)
            require(fixture in fixture_ids, f"{sid}: unknown initial fixture {fixture}", errors)
            require(is_int(initial.get("fetchedAtMs")) and initial["fetchedAtMs"] <= initial["clockMs"], f"{sid}: invalid fetchedAtMs", errors)
        else:
            require("fetchedAtMs" not in initial, f"{sid}: empty cache must not have fetchedAtMs", errors)
        steps = scenario.get("steps")
        if not isinstance(steps, list) or not steps:
            errors.append(f"{sid}: steps must be a nonempty array")
            continue
        step_ids = []
        for step in steps:
            if not isinstance(step, dict):
                errors.append(f"{sid}: step must be an object")
                continue
            step_id = step.get("id")
            step_ids.append(step_id)
            label = f"{sid}/{step_id}"
            require(isinstance(step_id, str) and bool(step_id), f"{sid}: step ID missing", errors)
            require(step.get("action") in ACTIONS, f"{label}: unknown action", errors)
            for field in ACTION_REQUIRED.get(step.get("action"), ()):
                require(field in step, f"{label}: {step.get('action')} requires {field}", errors)
            expect = step.get("expect")
            require(isinstance(expect, dict) and bool(expect), f"{label}: expect must be a nonempty object", errors)
            if "fixture" in step:
                ref = step["fixture"]
                refs.append(ref)
                require(ref in fixture_ids, f"{label}: unknown fixture {ref}", errors)
            if step.get("action") == "resetHarness":
                reset = step.get("initial")
                require(isinstance(reset, dict) and reset.get("catalogFixture") in fixture_ids, f"{label}: resetHarness needs a valid catalog fixture", errors)
                if isinstance(reset, dict):
                    refs.append(reset.get("catalogFixture"))
                    current_clock = reset.get("clockMs")
                pending_requests.clear()
            if step.get("action") == "startRefresh":
                request_id = step.get("requestId")
                require(isinstance(request_id, str) and bool(request_id) and request_id not in pending_requests, f"{label}: requestId must be unique among pending requests", errors)
                pending_requests.add(request_id)
            if step.get("action") in ("completeCatalog", "failCatalog") and "requestId" in step:
                require(step["requestId"] in pending_requests, f"{label}: completion has no matching request", errors)
                pending_requests.discard(step["requestId"])
            if step.get("action") in ("completeCatalog", "refreshWithFixture"):
                require("fixture" in step, f"{label}: catalog completion needs fixture", errors)
            if step.get("action") == "setClock":
                require(is_int(step.get("clockMs")), f"{label}: setClock needs integer clockMs", errors)
                if is_int(step.get("clockMs")) and is_int(current_clock):
                    require(step["clockMs"] >= current_clock, f"{label}: monotonic clock moved backward", errors)
                    current_clock = step["clockMs"]
            if step.get("action") == "setBudget":
                require(step.get("minutes") in (15, 30, 60, 90), f"{label}: unsupported budget", errors)
            if isinstance(expect, dict):
                for key in ROUTE_ASSERTIONS & set(expect):
                    values = expect[key] if isinstance(expect[key], list) else [expect[key]]
                    route_assertions.append((label, key, values))
                    require(len(values) == len(set(values)), f"{label}: {key} repeats a route ID", errors)
        require(len(step_ids) == len(set(step_ids)), f"{sid}: duplicate step ID", errors)
        require(all(ref in fixture_ids for ref in refs), f"{sid}: unresolved fixture reference", errors)
        allowed_routes = set().union(*(fixture_routes.get(ref, set()) for ref in refs))
        if sid == "NAV-01":
            allowed_routes.add("never-listed")
        for label, key, values in route_assertions:
            require(all(isinstance(v, str) and v in allowed_routes for v in values), f"{label}: {key} references a route outside this scenario's fixtures", errors)

    by_id = {s["id"]: s for s in scenarios if isinstance(s, dict) and "id" in s}
    if "CAT-02" in by_id:
        cat = by_id["CAT-02"]
        boundary = by_id["CAT-02"]["initial"].get("catalogFixture")
        require(boundary == "catalog-boundary", "CAT-02: must use boundary catalog", errors)
        require(cat["initial"].get("budgetMinutes") == 60, "CAT-02: initial budget must be 60", errors)
        steps = {s["id"]: s for s in cat["steps"]}
        require(steps.get("sixty", {}).get("expect", {}).get("listIds") == ["exact-hour"], "CAT-02: 60-minute oracle must include only exact-hour", errors)
        require(steps.get("sixty", {}).get("expect", {}).get("excludedId") == "over-hour", "CAT-02: 61-minute route must be excluded", errors)
    if "CLOCK-01" in by_id:
        require(by_id["CLOCK-01"]["initial"].get("clockMs") == 1000000 and by_id["CLOCK-01"]["initial"].get("fetchedAtMs") == 1000000, "CLOCK-01: initial clock and fetch time must be 1000000", errors)
        steps = {s["id"]: s for s in by_id["CLOCK-01"]["steps"]}
        before, at = steps.get("beforeTtl", {}), steps.get("atTtl", {})
        require(before.get("clockMs") == 1299999 and before.get("expect", {}).get("ageMs") == 299999 and before.get("expect", {}).get("fresh") is True and before.get("expect", {}).get("addEnabled") is True, "CLOCK-01: 299999-ms fresh boundary must be exact", errors)
        require(at.get("clockMs") == 1300000 and at.get("expect", {}).get("ageMs") == 300000 and at.get("expect", {}).get("fresh") is False and at.get("expect", {}).get("addEnabled") is False, "CLOCK-01: 300000-ms stale boundary must be exact", errors)
    if "CAT-07" in by_id:
        steps = {s["id"]: s for s in by_id["CAT-07"]["steps"]}
        require(steps.get("clockB", {}).get("clockMs") == 1000150 and steps.get("clockA", {}).get("clockMs") == 1000200, "CAT-07: older completion must occur later in fake time", errors)
        require(steps.get("finishA", {}).get("expect", {}).get("fetchedAtMs") == 1000150, "CAT-07: older completion must not change timestamp", errors)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    errors = []
    fixtures = {}
    fixture_routes = {}
    paths = sorted(ROOT.glob("catalog-*.json"))
    for path in paths:
        data = read_json(path, errors)
        if data is not None:
            fixture_id = data.get("fixtureId") if isinstance(data, dict) else None
            if fixture_id in fixtures:
                errors.append(f"duplicate fixture ID: {fixture_id}")
            fixtures[fixture_id] = path
            fixture_routes[fixture_id] = validate_catalog(path, data, errors)
    require(len(paths) == 16, "expected exactly sixteen catalog fixtures", errors)
    boundary = read_json(ROOT / "catalog-boundary.json", errors)
    if isinstance(boundary, dict):
        durations = {w.get("id"): w.get("durationMinutes") for w in boundary.get("walks", []) if isinstance(w, dict)}
        require(durations == {"exact-hour": 60, "over-hour": 61}, "catalog-boundary: IDs and 60/61-minute durations must be exact", errors)
    scenarios = read_json(ROOT / "scenarios.json", errors)
    if scenarios is not None:
        validate_scenarios(scenarios, fixture_routes, errors)
    lines = ["P3.2 shared contract validation", f"Catalog fixtures: {len(paths)}", f"Scenarios: {len(scenarios.get('scenarios', [])) if isinstance(scenarios, dict) else 0}"]
    for path in [*paths, ROOT / "scenarios.json"]:
        if path.exists():
            lines.append(f"SHA-256 {path.name}: {hashlib.sha256(path.read_bytes()).hexdigest()}")
    lines.extend([f"Result: {'FAIL' if errors else 'PASS'}", *[f"ERROR: {e}" for e in errors]])
    output = "\n".join(lines) + "\n"
    print(output, end="")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output, encoding="utf-8")
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
