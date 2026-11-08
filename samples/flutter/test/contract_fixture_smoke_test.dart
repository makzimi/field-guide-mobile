import 'dart:io';

import 'contract_fixture_loader.dart';

// Standalone SDK-only test: no application model, policy or widget is invoked.
void expectEqual(Object? actual, Object? expected, String field) {
  if (!jsonEquals(actual, expected)) {
    throw StateError('$field: expected $expected, got $actual');
  }
}

bool jsonEquals(Object? actual, Object? expected) {
  if (actual is Map && expected is Map) {
    return actual.length == expected.length &&
        expected.keys.every(
          (key) =>
              actual.containsKey(key) && jsonEquals(actual[key], expected[key]),
        );
  }
  if (actual is List && expected is List) {
    return actual.length == expected.length &&
        List.generate(
          actual.length,
          (index) => index,
        ).every((index) => jsonEquals(actual[index], expected[index]));
  }
  return actual == expected;
}

Map<String, dynamic> object(Object? value) => value as Map<String, dynamic>;

Map<String, dynamic> step(Map<String, dynamic> scenario, String id) =>
    (scenario['steps'] as List).cast<Map<String, dynamic>>().singleWhere(
      (value) => value['id'] == id,
    );

void main() {
  final loader = ContractFixtureLoader.fromWorkspace();
  final catalogs = loader.readCatalogs();
  final contract = loader.readObject('scenarios.json');
  expectEqual(catalogs.length, 16, 'catalog file count');
  expectEqual(contract['schemaVersion'], 1, 'schemaVersion');
  expectEqual(contract['ttlMs'], 300000, 'ttlMs');
  expectEqual(contract['clockUnit'], 'monotonic-ms', 'clockUnit');
  const ids = [
    'CAT-01',
    'CAT-02',
    'CAT-03',
    'CAT-04',
    'CAT-05',
    'CAT-06',
    'CAT-07',
    'CAT-08',
    'SAVE-01',
    'SAVE-02',
    'SAVE-03',
    'SAVE-04',
    'SAVE-05',
    'SAVE-06',
    'NAV-01',
    'CLOCK-01',
    'VIEW-01',
  ];
  final scenarios = (contract['scenarios'] as List)
      .cast<Map<String, dynamic>>();
  final loadedIds = scenarios.map((scenario) => scenario['id']).toList();
  expectEqual(contract['scenarioIds'], ids, 'declared scenario IDs');
  expectEqual(loadedIds, ids, 'loaded scenario IDs');
  expectEqual(loadedIds.toSet().length, 17, 'unique scenario IDs');

  final boundary = catalogs['catalog-boundary']!;
  final walks = (boundary['walks'] as List).cast<Map<String, dynamic>>();
  expectEqual(walks.length, 2, 'duration boundary fixture rows');
  expectEqual(
    walks.singleWhere((walk) => walk['id'] == 'exact-hour')['durationMinutes'],
    60,
    'exact-hour duration',
  );
  expectEqual(
    walks.singleWhere((walk) => walk['id'] == 'over-hour')['durationMinutes'],
    61,
    'over-hour duration',
  );
  final durationScenario = scenarios.singleWhere(
    (scenario) => scenario['id'] == 'CAT-02',
  );
  expectEqual(
    object(durationScenario['initial'])['catalogFixture'],
    'catalog-boundary',
    'CAT-02 fixture reference',
  );
  expectEqual(
    object(durationScenario['initial'])['budgetMinutes'],
    60,
    'CAT-02 initial budget',
  );
  final sixty = object(step(durationScenario, 'sixty')['expect']);
  expectEqual(sixty['listIds'], ['exact-hour'], 'CAT-02 sixty oracle');
  expectEqual(sixty['includedId'], 'exact-hour', 'CAT-02 included ID');
  expectEqual(sixty['excludedId'], 'over-hour', 'CAT-02 excluded ID');
  final ninety = step(durationScenario, 'ninety');
  expectEqual(ninety['minutes'], 90, 'CAT-02 ninety budget');
  expectEqual(object(ninety['expect'])['listIds'], [
    'exact-hour',
    'over-hour',
  ], 'CAT-02 ninety oracle');

  final clockScenario = scenarios.singleWhere(
    (scenario) => scenario['id'] == 'CLOCK-01',
  );
  expectEqual(
    object(clockScenario['initial'])['fetchedAtMs'],
    1000000,
    'CLOCK-01 fetch time',
  );
  final before = step(clockScenario, 'beforeTtl');
  expectEqual(before['clockMs'], 1299999, 'CLOCK-01 before input');
  expectEqual(object(before['expect']), {
    'ageMs': 299999,
    'fresh': true,
    'addEnabled': true,
    'staleWarning': false,
  }, 'CLOCK-01 before oracle');
  final expiry = step(clockScenario, 'atTtl');
  expectEqual(expiry['clockMs'], 1300000, 'CLOCK-01 expiry input');
  expectEqual(object(expiry['expect']), {
    'ageMs': 300000,
    'fresh': false,
    'addEnabled': false,
    'disabledReason': 'stale',
    'staleWarning': true,
  }, 'CLOCK-01 expiry oracle');
  expectEqual(
    object(step(clockScenario, 'useCaseBypass')['expect'])['result'],
    'rejected-stale',
    'CLOCK-01 direct policy oracle',
  );

  stdout.writeln('PASS: Flutter/Dart shared contract reading smoke');
  stdout.writeln('Source: ${loader.directory.path}');
  stdout.writeln(
    'Parsed 16 catalog JSON files and 17 scenarios from the shared source.',
  );
  stdout.writeln(
    'Verified CAT-02 60/61-minute data/oracles and CLOCK-01 299999/300000-ms data/oracles.',
  );
  stdout.writeln(
    'Scope: JSON reading and contract constants only. No app behavior, mapper rejection, widgets or devices were exercised.',
  );
}
