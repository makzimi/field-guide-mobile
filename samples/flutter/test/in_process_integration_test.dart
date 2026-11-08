import 'dart:async';
import 'dart:convert';

import 'package:catalog_api/catalog_api.dart';
import 'package:catalog_impl/catalog_impl.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_fixture_loader.dart';

// Every double below replaces an I/O or time edge. No business layer is mocked.
final class SourceIo implements CatalogSource {
  final requests = <Completer<String>>[];
  @override
  Future<String> load() {
    final request = Completer<String>();
    requests.add(request);
    return request.future;
  }
}

final class StorageIo implements BookmarkStorage {
  StorageIo(Iterable<String> initial) : ids = Set.of(initial);
  Set<String> ids;
  final reads = <Completer<Set<String>>>[];
  final writes = <({Set<String> ids, Completer<void> done})>[];
  @override
  Future<Set<String>> read() {
    final request = Completer<Set<String>>();
    reads.add(request);
    return request.future;
  }

  @override
  Future<void> write(Set<String> next) async {
    final done = Completer<void>();
    writes.add((ids: Set.of(next), done: done));
    await done.future;
    ids = Set.of(next);
  }
}

final class TestTime implements MonotonicClock, ExpiryScheduler {
  TestTime(this.nowMs);
  @override
  int nowMs;
  final entries =
      <({int at, void Function() callback, List<bool> cancelled})>[];
  @override
  CancelExpiry schedule(int delayMs, void Function() callback) {
    final cancelled = [false];
    entries.add((
      at: nowMs + delayMs,
      callback: callback,
      cancelled: cancelled,
    ));
    return () => cancelled[0] = true;
  }

  void advanceTo(int value) {
    nowMs = value;
    for (final entry in entries.toList()) {
      if (!entry.cancelled[0] && entry.at <= nowMs) {
        entry.cancelled[0] = true;
        entry.callback();
      }
    }
  }
}

final class IntegrationGraph {
  IntegrationGraph(this.loader, {Iterable<String> savedIds = const []}) {
    storage = StorageIo(savedIds);
    repository = CatalogRepositoryImpl(
      source: source,
      storage: storage,
      clock: time,
      mapper: CatalogMapper(),
    );
    controller = CatalogController(
      repository: repository,
      queryWalks: QueryWalksImpl(),
      bookmarks: ChangeBookmarkImpl(repository),
      clock: time,
      scheduler: time,
    );
    controller.addListener(() => published.add(controller.state));
  }
  final ContractFixtureLoader loader;
  final source = SourceIo();
  final time = TestTime(1000000);
  late final StorageIo storage;
  late final CatalogRepositoryImpl repository;
  late final CatalogController controller;
  final published = <FeatureState>[];

  String payload(String fixture) =>
      jsonEncode(loader.readObject('$fixture.json')['walks']);
  Future<void> load() async {
    final pending = controller.start();
    source.requests.single.complete(payload('catalog-valid'));
    storage.reads.single.complete(Set.of(storage.ids));
    await pending;
  }

  void dispose() {
    controller.dispose();
    repository.dispose();
  }
}

final class SharedOracle {
  SharedOracle(this.loader)
    : scenarios = (loader.readObject('scenarios.json')['scenarios'] as List)
          .cast<Map<String, dynamic>>();
  final ContractFixtureLoader loader;
  final List<Map<String, dynamic>> scenarios;
  Map<String, dynamic> step(String scenario, String stepId) =>
      (scenarios.singleWhere((s) => s['id'] == scenario)['steps'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((s) => s['id'] == stepId);
  Map<String, dynamic> expected(String scenario, String stepId) =>
      step(scenario, stepId)['expect'] as Map<String, dynamic>;

  // This adapter exposes observations only. It never calculates expected IDs,
  // sort order, freshness, policy, or labels with production helpers.
  void check(
    IntegrationGraph graph,
    String scenario,
    String stepId, {
    Iterable<String> omit = const [],
  }) {
    final state = graph.controller.state;
    final catalog = state.catalog;
    final failure = switch (catalog.catalogFailure) {
      CatalogFailure.sourceUnavailable => 'source-unavailable',
      CatalogFailure.invalidCatalog => 'invalid-catalog',
      null => null,
    };
    final observed = <String, dynamic>{
      'screen': state.selectedId == null
          ? 'list'
          : state.detail == null
          ? 'unavailable'
          : 'detail',
      'catalogState': state.catalogStatus,
      'listIds': state.walks.map((w) => w.walk.id).toList(),
      'closedIds': state.walks
          .where((w) => w.walk.availability == Availability.closed)
          .map((w) => w.walk.id)
          .toList(),
      'savedBadgeIds': state.walks
          .where((w) => w.saved)
          .map((w) => w.walk.id)
          .toList(),
      'savedIds': catalog.savedIds.toList()..sort(),
      'storedIds': graph.storage.ids.toList()..sort(),
      'savedCount': state.savedCount,
      'fetchedAtMs': catalog.snapshot?.fetchedAtMs,
      'routeId': state.selectedId,
      'query': state.query,
      'budgetMinutes': state.budgetMinutes,
      'distanceLabel': state.detail?.distance,
      'saved': state.detail?.saved,
      'addEnabled': state.addEnabled,
      'removeEnabled': state.removeEnabled,
      'saveEnabled': state.addEnabled || state.removeEnabled,
      'disabledReason': state.disabledReason,
      'fresh': state.fresh,
      'staleWarning': state.stale,
      'ageMs': catalog.snapshot == null
          ? null
          : graph.time.nowMs - catalog.snapshot!.fetchedAtMs,
      'clockMs': graph.time.nowMs,
      'error': failure,
      'newValidVisible': state.walks.any((w) => w.walk.id == 'new-valid'),
      'storageWriteCount': graph.storage.writes.length,
      'storageState': catalog.storageStatus.name,
      'saveState': catalog.pendingId != null
          ? 'saving'
          : catalog.bookmarkError != null
          ? 'error'
          : 'idle',
      'inlineRetryEnabled':
          catalog.bookmarkErrorId == state.selectedId &&
          catalog.bookmarkError != null &&
          (state.addEnabled || state.removeEnabled),
    };
    for (final entry in expected(scenario, stepId).entries) {
      if (omit.contains(entry.key)) continue;
      if (!observed.containsKey(entry.key)) {
        fail('Unhandled oracle field $scenario/$stepId/${entry.key}');
      }
      expect(
        observed[entry.key],
        entry.value,
        reason: '$scenario/$stepId/${entry.key}',
      );
    }
  }
}

void main() {
  final loader = ContractFixtureLoader.fromWorkspace();
  final oracle = SharedOracle(loader);
  late IntegrationGraph graph;
  setUp(() => graph = IntegrationGraph(loader));
  tearDown(() => graph.dispose());

  Future<CatalogController> openCanalDetails() async {
    await graph.load();
    await graph.controller.dispatch(const OpenDetail('canal-gardens'));
    return graph.controller;
  }

  Future<void> commitSave(Future<void> saving) async {
    graph.storage.writes.single.done.complete();
    await saving;
  }

  test('save WHEN write is pending SHOULD stay unsaved', () async {
    final sut = await openCanalDetails();

    final saving = sut.dispatch(const ToggleBookmark());
    addTearDown(() => commitSave(saving));

    expect(sut.state.detail?.saved, false);
    expect(sut.state.savedCount, 0);
    expect(graph.storage.ids, isEmpty);
  });

  test('save WHEN write commits SHOULD publish saved state', () async {
    final sut = await openCanalDetails();
    final saving = sut.dispatch(const ToggleBookmark());

    await commitSave(saving);

    expect(sut.state.detail?.saved, true);
    expect(sut.state.savedCount, 1);
    expect(graph.storage.ids, {'canal-gardens'});
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CatalogFeature(controller: graph.controller)),
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    // Pending I/O can leave an indeterminate progress indicator. Do not settle
    // that animation; only publish the action and its immediate state.
    await tester.pump();
  }

  testWidgets('P3.6 CAT-01 SAVE-01 real graph load detail save back', (
    tester,
  ) async {
    final loading = graph.controller.start();
    await mount(tester);
    oracle.check(graph, 'CAT-01', 'start');
    expect(find.bySemanticsLabel('Loading walks'), findsOneWidget);
    graph.source.requests.single.complete(graph.payload('catalog-valid'));
    graph.storage.reads.single.complete({});
    await loading;
    await tester.pumpAndSettle();
    oracle.check(graph, 'CAT-01', 'finish');
    final detail = oracle.step('SAVE-01', 'detail');
    await tap(tester, find.byKey(ValueKey('route-${detail['routeId']}')));
    oracle.check(graph, 'SAVE-01', 'detail');
    expect(
      find.text(
        oracle.expected('SAVE-01', 'detail')['distanceLabel'] as String,
      ),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const ValueKey('bookmark-action')));
    oracle.check(graph, 'SAVE-01', 'pending');
    expect(find.text('Saving…'), findsOneWidget);
    expect(graph.repository.state.savedIds, isEmpty);
    graph.storage.writes.single.done.complete();
    await tester.pumpAndSettle();
    oracle.check(graph, 'SAVE-01', 'commit', omit: ['actionLabel']);
    expect(
      find.text(oracle.expected('SAVE-01', 'commit')['actionLabel'] as String),
      findsOneWidget,
    );
    await tap(tester, find.byTooltip('Back to walks'));
    oracle.check(graph, 'SAVE-01', 'back');
    expect(find.text('1 saved walk'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('route-canal-gardens')),
        matching: find.text('Saved'),
      ),
      findsOneWidget,
    );
    expect(graph.source.requests, hasLength(1));
    expect(
      graph.published.any((s) => s.catalog.pendingId == 'canal-gardens'),
      true,
    );
    expect(graph.published.last, same(graph.controller.state));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'P3.6 SAVE-02 atomic failure duplicate suppression and widget retry',
    (tester) async {
      await graph.load();
      await graph.controller.dispatch(const OpenDetail('canal-gardens'));
      await mount(tester);
      oracle.check(graph, 'SAVE-02', 'detail');
      await tap(tester, find.byKey(const ValueKey('bookmark-action')));
      oracle.check(
        graph,
        'SAVE-02',
        'pending',
        omit: ['duplicateSubmissionAccepted'],
      );
      await graph.controller.dispatch(const ToggleBookmark());
      oracle.check(graph, 'SAVE-02', 'duplicateTap');
      graph.storage.writes.single.done.completeError(
        StateError('write failure'),
      );
      await tester.pumpAndSettle();
      oracle.check(graph, 'SAVE-02', 'failure');
      expect(
        find.text('Could not update saved walks. Try again.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Retry save'));
      oracle.check(graph, 'SAVE-02', 'retry');
      graph.storage.writes.last.done.complete();
      await tester.pumpAndSettle();
      oracle.check(graph, 'SAVE-02', 'success');
      expect(find.text('Retry save'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P3.6 CAT-05 initial failure and widget retry preserve saved IDs',
    (tester) async {
      graph.dispose();
      graph = IntegrationGraph(loader, savedIds: ['canal-gardens']);
      final loading = graph.controller.start();
      await mount(tester);
      oracle.check(graph, 'CAT-05', 'start');
      graph.storage.reads.single.complete({'canal-gardens'});
      graph.source.requests.single.completeError(
        StateError('source unavailable'),
      );
      await loading;
      await tester.pumpAndSettle();
      oracle.check(graph, 'CAT-05', 'failure', omit: ['retryCatalogEnabled']);
      expect(find.text('Walks are unavailable right now.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Retry walks'))
            .onPressed,
        isNotNull,
      );
      await tap(tester, find.text('Retry walks'));
      oracle.check(graph, 'CAT-05', 'retry');
      graph.source.requests.last.complete(graph.payload('catalog-valid'));
      await tester.pumpAndSettle();
      oracle.check(graph, 'CAT-05', 'success');
      expect(find.text('1 saved walk'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('P3.6 CAT-06 fresh failure expires and stale opens coalesce', () async {
    await graph.load();
    oracle.check(graph, 'CAT-06', 'freshReset');
    final manual = graph.controller.dispatch(const RefreshCatalog());
    oracle.check(graph, 'CAT-06', 'manual', omit: ['sourceRequestCount']);
    expect(
      graph.source.requests.length - 1,
      oracle.expected('CAT-06', 'manual')['sourceRequestCount'],
    );
    graph.source.requests.last.completeError(StateError('source unavailable'));
    await manual;
    oracle.check(graph, 'CAT-06', 'manualFailure');
    await graph.controller.dispatch(const OpenDetail('canal-gardens'));
    oracle.check(graph, 'CAT-06', 'freshDetail');
    graph.time.advanceTo(1300000);
    oracle.check(graph, 'CAT-06', 'laterExpiry');
    final priorRequests = graph.source.requests.length;
    final returning = graph.controller.dispatch(const OpenList());
    oracle.check(graph, 'CAT-06', 'return');
    final repeated = graph.controller.dispatch(const OpenList());
    oracle.check(graph, 'CAT-06', 'returnAgain', omit: ['sourceRequestCount']);
    expect(
      graph.source.requests.length - priorRequests,
      oracle.expected('CAT-06', 'returnAgain')['sourceRequestCount'],
    );
    graph.source.requests.last.completeError(StateError('source unavailable'));
    await Future.wait([returning, repeated]);
    oracle.check(graph, 'CAT-06', 'failure', omit: ['retryCatalogEnabled']);
    await graph.controller.dispatch(const OpenDetail('canal-gardens'));
    oracle.check(graph, 'CAT-06', 'detail');
    expect(
      await ChangeBookmarkImpl(graph.repository)('canal-gardens', save: true),
      BookmarkResult.rejectedStale,
    );
    expect(graph.storage.writes, isEmpty);
  });

  test(
    'P3.6 CAT-08 all invalid snapshots retain shared saved cache and timestamp',
    () async {
      graph.dispose();
      graph = IntegrationGraph(loader, savedIds: ['canal-gardens']);
      await graph.load();
      final snapshot = graph.repository.state.snapshot;
      graph.time.advanceTo(1000100);
      final steps =
          (oracle.scenarios.singleWhere((s) => s['id'] == 'CAT-08')['steps']
                  as List)
              .cast<Map<String, dynamic>>();
      for (final step in steps) {
        final refreshing = graph.controller.dispatch(const RefreshCatalog());
        graph.source.requests.last.complete(
          graph.payload(step['fixture'] as String),
        );
        await refreshing;
        oracle.check(graph, 'CAT-08', step['id'] as String);
        expect(graph.repository.state.snapshot, same(snapshot));
      }
    },
  );

  testWidgets(
    'P3.6 NAV-01 changed catalog unavailable route and filtered Back',
    (tester) async {
      graph.dispose();
      graph = IntegrationGraph(loader, savedIds: ['canal-gardens']);
      await graph.load();
      graph.time.advanceTo(1000100);
      await graph.controller.dispatch(const SetQuery('canal'));
      await graph.controller.dispatch(const SetBudget(90));
      await mount(tester);
      await tap(tester, find.byKey(const ValueKey('route-canal-gardens')));
      oracle.check(graph, 'NAV-01', 'selected');
      await tap(tester, find.byTooltip('Refresh walks'));
      graph.source.requests.last.complete(graph.payload('catalog-changed'));
      await tester.pumpAndSettle();
      oracle.check(graph, 'NAV-01', 'removed', omit: ['backEnabled']);
      expect(find.text('This walk is unavailable.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Back to walks'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tap(tester, find.byTooltip('Back to walks'));
      oracle.check(graph, 'NAV-01', 'back');
      expect(find.text('No walks match your filters.'), findsOneWidget);
      await graph.controller.dispatch(const OpenDetail('never-listed'));
      await tester.pump();
      oracle.check(graph, 'NAV-01', 'unknown', omit: ['backEnabled']);
      await tap(tester, find.byTooltip('Back to walks'));
      oracle.check(graph, 'NAV-01', 'unknownBack');
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'P3.6 SAVE-06 storage retry keeps readable catalog and gates use case',
    () async {
      graph.dispose();
      graph = IntegrationGraph(loader, savedIds: ['canal-gardens']);
      final loading = graph.controller.start();
      graph.source.requests.single.complete(graph.payload('catalog-valid'));
      graph.storage.reads.single.completeError(StateError('read failure'));
      await loading;
      oracle.check(
        graph,
        'SAVE-06',
        'failure',
        omit: ['retrySavedWalksEnabled'],
      );
      await graph.controller.dispatch(const OpenDetail('pine-loop'));
      oracle.check(graph, 'SAVE-06', 'pendingDetail');
      expect(
        await ChangeBookmarkImpl(graph.repository)('pine-loop', save: true),
        BookmarkResult.storageNotReady,
      );
      expect(graph.storage.writes, isEmpty);
      final retry = graph.controller.dispatch(const RetrySavedWalks());
      oracle.check(graph, 'SAVE-06', 'retry');
      graph.storage.reads.last.complete({'canal-gardens'});
      await retry;
      oracle.check(
        graph,
        'SAVE-06',
        'success',
        omit: ['retrySavedWalksEnabled'],
      );
      expect(graph.controller.state.catalog.storageError, isNull);
      await graph.controller.dispatch(const OpenDetail('pine-loop'));
      oracle.check(graph, 'SAVE-06', 'restoredAdd');
      await graph.controller.dispatch(const OpenDetail('canal-gardens'));
      oracle.check(graph, 'SAVE-06', 'restoredRemove');
    },
  );

  for (final olderResult in ['success', 'failure', 'newer-failure']) {
    test(
      'P3.6 CAT-07 winning refresh controls published state: $olderResult',
      () async {
        graph.dispose();
        graph = IntegrationGraph(loader, savedIds: ['canal-gardens']);
        await graph.load();
        graph.time.advanceTo(1000100);
        final first = graph.controller.dispatch(const RefreshCatalog());
        final requestA = graph.source.requests.last;
        final second = graph.controller.dispatch(const RefreshCatalog());
        final requestB = graph.source.requests.last;
        if (olderResult == 'newer-failure') {
          graph.time.advanceTo(1000500);
          requestB.completeError(StateError('newer failure'));
        } else {
          graph.time.advanceTo(olderResult == 'success' ? 1000150 : 1000350);
          requestB.complete(graph.payload('catalog-changed'));
        }
        await second;
        final finishStep = olderResult == 'success'
            ? 'finishB'
            : olderResult == 'failure'
            ? 'finishB2'
            : 'failB3';
        oracle.check(graph, 'CAT-07', finishStep);
        final publishedCount = graph.published.length;
        graph.time.advanceTo(
          olderResult == 'success'
              ? 1000200
              : olderResult == 'failure'
              ? 1000400
              : 1000600,
        );
        if (olderResult == 'failure') {
          requestA.completeError(StateError('older failure'));
        } else {
          requestA.complete(
            graph.payload(
              olderResult == 'success' ? 'catalog-boundary' : 'catalog-changed',
            ),
          );
        }
        await first;
        final ignoredStep = olderResult == 'success'
            ? 'finishA'
            : olderResult == 'failure'
            ? 'failA2'
            : 'finishA3';
        oracle.check(graph, 'CAT-07', ignoredStep, omit: ['ignoredRequestId']);
        expect(
          graph.published.length,
          publishedCount,
          reason: 'An obsolete completion must not publish a state or error',
        );
      },
    );
  }
}
