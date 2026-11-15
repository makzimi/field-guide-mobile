"""Resolved dependency graph boundaries, including deliberate violations."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CHECKER = Path(__file__).with_name("graph.py")
ANDROID_GOOD = ROOT / "samples/harness/fixtures/allowed-android-graph.log"
FLUTTER_GOOD = ROOT / "samples/harness/fixtures/allowed-flutter-deps.json"


def run_graph(android: Path, flutter: Path, source_root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), "--android-log", str(android),
         "--flutter-json", str(flutter), "--source-root", str(source_root)],
        capture_output=True, text=True, check=False,
    )


class GraphBoundaryTest(unittest.TestCase):
    def test_current_resolved_graph_and_sources_pass(self):
        result = run_graph(ANDROID_GOOD, FLUTTER_GOOD, ROOT / "samples")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_forbidden_android_feature_to_impl_edge_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            bad = Path(temporary) / "android.log"
            original = ANDROID_GOOD.read_text()
            bad.write_text(original.replace(
                ":feature-catalog [debugRuntimeClasspath] -> :catalog-api",
                ":feature-catalog [debugRuntimeClasspath] -> :catalog-api, :catalog-impl",
            ))
            result = run_graph(bad, FLUTTER_GOOD, ROOT / "samples")
            self.assertEqual(result.returncode, 1)
            self.assertIn("feature-catalog", result.stdout)
            self.assertIn("catalog-impl", result.stdout)

    def test_forbidden_flutter_feature_to_impl_edge_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            bad = Path(temporary) / "flutter.json"
            graph = json.loads(FLUTTER_GOOD.read_text())
            member = next(item for item in graph["packages"] if item["name"] == "feature_catalog")
            member["directDependencies"].append("catalog_impl")
            bad.write_text(json.dumps(graph))
            result = run_graph(ANDROID_GOOD, bad, ROOT / "samples")
            self.assertEqual(result.returncode, 1)
            self.assertIn("feature_catalog", result.stdout)
            self.assertIn("catalog_impl", result.stdout)

    def test_any_new_feature_to_any_new_impl_edge_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            bad = Path(temporary) / "android.log"
            bad.write_text(ANDROID_GOOD.read_text().replace(
                ":feature-catalog [debugRuntimeClasspath] -> :catalog-api",
                ":feature-catalog [debugRuntimeClasspath] -> :catalog-api\n"
                ":feature-map [debugRuntimeClasspath] -> :routes-api, :routes-impl",
            ))
            result = run_graph(bad, FLUTTER_GOOD, ROOT / "samples")
            self.assertEqual(result.returncode, 1)
            self.assertIn("feature :feature-map must not depend on impl :routes-impl", result.stdout)
            self.assertNotIn("routes-api", result.stdout)

    def test_any_new_feature_import_of_any_new_impl_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sources = {
                "android/routes-impl/src/main/Routes.kt": "package sample.routes.impl\nclass Routes\n",
                "android/feature-map/src/main/Map.kt": "package sample.feature.map\nimport sample.routes.impl.Routes\n",
                "flutter/packages/routes_impl/lib/routes.dart": "final routes = 1;\n",
                "flutter/packages/feature_map/lib/map.dart": "import 'package:routes_impl/routes.dart';\n",
            }
            for name, text in sources.items():
                (root / name).parent.mkdir(parents=True)
                (root / name).write_text(text)
            result = run_graph(ANDROID_GOOD, FLUTTER_GOOD, root)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Android feature feature-map forbidden import sample.routes.impl.Routes", result.stdout)
            self.assertIn("Flutter feature feature_map forbidden import routes_impl", result.stdout)

    def test_empty_source_discovery_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = run_graph(ANDROID_GOOD, FLUTTER_GOOD, Path(temporary))
            self.assertEqual(result.returncode, 1)
            self.assertIn("empty", result.stdout.lower())

    def test_duplicate_resolved_flutter_node_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            bad = Path(temporary) / "flutter.json"
            graph = json.loads(FLUTTER_GOOD.read_text())
            member = next(item for item in graph["packages"] if item["name"] == "catalog_api")
            graph["packages"].append(dict(member))
            bad.write_text(json.dumps(graph))
            result = run_graph(ANDROID_GOOD, bad, ROOT / "samples")
            self.assertEqual(result.returncode, 1)
            self.assertIn("duplicate resolved Flutter node", result.stdout)

    def test_forbidden_feature_source_import_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("catalog-api", "catalog-impl", "feature-catalog"):
                file = root / "android" / name / "src/main" / "Sample.kt"
                file.parent.mkdir(parents=True)
                file.write_text("package sample\n")
            for name in ("catalog_api", "catalog_impl", "feature_catalog"):
                file = root / "flutter/packages" / name / "lib" / "sample.dart"
                file.parent.mkdir(parents=True)
                file.write_text("final sample = 1;\n")
            target = root / "flutter/packages/feature_catalog/lib/sample.dart"
            target.write_text("import 'package:catalog_impl/catalog_impl.dart';\n")
            result = run_graph(ANDROID_GOOD, FLUTTER_GOOD, root)
            self.assertEqual(result.returncode, 1)
            self.assertIn("forbidden import catalog_impl", result.stdout)

    def test_platform_sdk_import_in_pure_dart_api_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("catalog-api", "catalog-impl", "feature-catalog"):
                file = root / "android" / name / "src/main" / "Sample.kt"
                file.parent.mkdir(parents=True)
                file.write_text("package sample\n")
            for name in ("catalog_api", "catalog_impl", "feature_catalog"):
                file = root / "flutter/packages" / name / "lib" / "sample.dart"
                file.parent.mkdir(parents=True)
                file.write_text("final sample = 1;\n")
            target = root / "flutter/packages/catalog_api/lib/sample.dart"
            target.write_text("import 'dart:ui';\n")
            result = run_graph(ANDROID_GOOD, FLUTTER_GOOD, root)
            self.assertEqual(result.returncode, 1)
            self.assertIn("forbidden import dart:ui", result.stdout)


if __name__ == "__main__":
    unittest.main()
