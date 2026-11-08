import 'dart:convert';

import 'package:catalog_impl/catalog_impl.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_fixture_loader.dart';
import 'controller_widget_test.dart' show ManualScheduler;
import 'repository_test.dart'
    show FakeClock, DeferredSource, MemoryStorage, fixture;

void main() {
  final loader = ContractFixtureLoader.fromWorkspace();
  final scenarios = (loader.readObject('scenarios.json')['scenarios'] as List)
      .cast<Map<String, dynamic>>();
  Map<String, dynamic> scenario(String id) =>
      scenarios.singleWhere((s) => s['id'] == id);
  final mapper = CatalogMapper();
  final query = QueryWalksImpl();
  test('CAT-02 shared hand-authored oracle is exercised by implementation', () {
    final definition = scenario('CAT-02');
    final initial = definition['initial'] as Map<String, dynamic>;
    final walks = mapper.mapJson(
      jsonEncode(
        loader.readObject('${initial['catalogFixture']}.json')['walks'],
      ),
    );
    final steps = (definition['steps'] as List).cast<Map<String, dynamic>>();
    for (final step in steps.take(2)) {
      final expected = step['expect'] as Map<String, dynamic>;
      final budget = step['minutes'] as int? ?? initial['budgetMinutes'] as int;
      expect(
        query(walks, budgetMinutes: budget).map((w) => w.id).toList(),
        expected['listIds'],
        reason: 'CAT-02/${step['id']}',
      );
    }
  });
  test('CAT-03 shared search oracle is exercised by implementation', () {
    final definition = scenario('CAT-03');
    final walks = mapper.mapJson(
      jsonEncode(loader.readObject('catalog-valid.json')['walks']),
    );
    for (final step
        in (definition['steps'] as List).cast<Map<String, dynamic>>().where(
          (s) => s['action'] == 'setQuery',
        )) {
      final expected = step['expect'] as Map<String, dynamic>;
      final text = step['text'] as String;
      expect(query.normalize(text), expected['normalizedQuery']);
      expect(
        query(walks, query: text).map((w) => w.id).toList(),
        expected['listIds'],
        reason: 'CAT-03/${step['id']}',
      );
    }
  });
  test('CLOCK-01 shared before/at TTL oracles observe real controller and use case', () async {
    final definition = scenario('CLOCK-01');
    final initial = definition['initial'] as Map<String, dynamic>;
    final clock = FakeClock()..value = initial['fetchedAtMs'] as int;
    final source = DeferredSource();
    final storage = MemoryStorage();
    final repo = CatalogRepositoryImpl(
      source: source,
      storage: storage,
      clock: clock,
    );
    final scheduler = ManualScheduler(clock);
    final controller = CatalogController(
      repository: repo,
      queryWalks: query,
      bookmarks: ChangeBookmarkImpl(repo),
      clock: clock,
      scheduler: scheduler,
    );
    addTearDown(() {
      controller.dispose();
      repo.dispose();
    });
    final pending = controller.start();
    source.requests.single.complete(
      fixture(initial['catalogFixture'] as String),
    );
    await pending;
    await controller.dispatch(const OpenDetail('canal-gardens'));
    for (final step
        in (definition['steps'] as List).cast<Map<String, dynamic>>().where(
          (s) => s['action'] == 'setClock',
        )) {
      clock.value = step['clockMs'] as int;
      scheduler.flush();
      final expected = step['expect'] as Map<String, dynamic>;
      final state = controller.state;
      final actual = <String, dynamic>{
        'ageMs': clock.nowMs - repo.state.snapshot!.fetchedAtMs,
        'fresh': state.fresh,
        'addEnabled': state.addEnabled,
        'staleWarning': state.stale,
        if (expected.containsKey('disabledReason'))
          'disabledReason': state.disabledReason,
      };
      expect(actual, expected, reason: 'CLOCK-01/${step['id']}');
    }
    final expectedResult =
        (((definition['steps'] as List)
                .cast<Map<String, dynamic>>()
                .singleWhere((s) => s['id'] == 'useCaseBypass'))['expect']
            as Map<String, dynamic>)['result'];
    final result = await ChangeBookmarkImpl(repo)('canal-gardens', save: true);
    expect(result.name, 'rejectedStale');
    expect(expectedResult, 'rejected-stale');
    expect(storage.ids, isEmpty);
  });
}
