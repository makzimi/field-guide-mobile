import 'package:catalog_api/catalog_api.dart';
import 'package:catalog_impl/catalog_impl.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test.dart'
    show FakeClock, DeferredSource, MemoryStorage, fixture;

final class ManualScheduler implements ExpiryScheduler {
  final entries =
      <({int at, void Function() callback, List<bool> cancelled})>[];
  ManualScheduler(this.clock);
  final FakeClock clock;
  @override
  CancelExpiry schedule(int delayMs, void Function() callback) {
    final cancelled = [false];
    entries.add((
      at: clock.nowMs + delayMs,
      callback: callback,
      cancelled: cancelled,
    ));
    return () => cancelled[0] = true;
  }

  void flush() {
    final due = entries
        .where((e) => !e.cancelled[0] && e.at <= clock.nowMs)
        .toList();
    for (final e in due) {
      e.cancelled[0] = true;
      e.callback();
    }
  }
}

void main() {
  late FakeClock clock;
  late DeferredSource source;
  late MemoryStorage storage;
  late CatalogRepositoryImpl repo;
  late CatalogController controller;
  late ManualScheduler scheduler;
  setUp(() {
    clock = FakeClock();
    source = DeferredSource();
    storage = MemoryStorage();
    scheduler = ManualScheduler(clock);
    repo = CatalogRepositoryImpl(
      source: source,
      storage: storage,
      clock: clock,
    );
    controller = CatalogController(
      repository: repo,
      queryWalks: QueryWalksImpl(),
      bookmarks: ChangeBookmarkImpl(repo),
      clock: clock,
      scheduler: scheduler,
    );
  });
  tearDown(() {
    controller.dispose();
    repo.dispose();
  });
  Future<void> load([String id = 'catalog-valid']) async {
    final started = controller.start();
    expect(source.requests, isNotEmpty);
    source.requests.last.complete(fixture(id));
    await started;
  }

  test('loaded routes reach the controller through the real repository',
      () async {
    final loading = controller.start();
    expect(controller.state.catalogStatus, 'loading');
    source.requests.single.complete(fixture('catalog-valid'));
    await loading;
    expect(controller.state.walks.map((item) => item.walk.title), [
      'Pine loop', 'Glasshouse loop', 'Canal gardens',
    ]);
  });

  test('CAT-01, CAT-04 list loading, query, empty and reset states', () async {
    final pending = controller.start();
    expect(controller.state.catalogStatus, 'loading');
    expect(source.requests, hasLength(1));
    source.requests.single.complete(fixture('catalog-valid'));
    await pending;
    expect(controller.state.walks.map((w) => w.walk.id), [
      'pine-loop',
      'glasshouse-loop',
      'canal-gardens',
    ]);
    await controller.dispatch(const SetBudget(15));
    await controller.dispatch(const SetQuery('canal'));
    expect(controller.state.catalogStatus, 'empty');
    await controller.dispatch(const ClearFilters());
    expect(controller.state.query, '');
    expect(controller.state.budgetMinutes, 60);
    expect(controller.state.walks, hasLength(3));
  });
  test(
    'SAVE-01, NAV-01 filters survive navigation; removed detail keeps bookmark',
    () async {
      await load();
      await controller.dispatch(const SetQuery('canal'));
      await controller.dispatch(const SetBudget(90));
      await controller.dispatch(const OpenDetail('canal-gardens'));
      expect(controller.state.detail?.distance, '3.2 km');
      expect(controller.state.detail?.duration, '50 minutes');
      await controller.dispatch(const ToggleBookmark());
      expect(controller.state.detail?.saved, true);
      expect(controller.state.savedCount, 1);
      await controller.dispatch(const BackToList());
      expect(controller.state.query, 'canal');
      expect(controller.state.budgetMinutes, 90);
      expect(controller.state.walks.single.saved, true);
      await controller.dispatch(const OpenDetail('canal-gardens'));
      final refresh = controller.dispatch(const RefreshCatalog());
      source.requests.last.complete(fixture('catalog-changed'));
      await refresh;
      expect(controller.state.selectedId, 'canal-gardens');
      expect(controller.state.detail, null);
      expect(controller.state.savedCount, 0);
      expect(storage.ids, {'canal-gardens'});
      await controller.dispatch(const BackToList());
      expect(controller.state.walks, isEmpty);
      await controller.dispatch(const OpenDetail('unknown'));
      expect(controller.state.detail, null);
    },
  );
  test('CLOCK-01 scheduled visible expiry at 300000; foreground reschedules and refreshes', () async {
    await load();
    await controller.dispatch(const OpenDetail('canal-gardens'));
    clock.value = 1299999;
    scheduler.flush();
    expect(controller.state.addEnabled, true);
    expect(controller.state.stale, false);
    clock.value = 1300000;
    scheduler.flush();
    expect(controller.state.addEnabled, false);
    expect(controller.state.disabledReason, 'stale');
    expect(controller.state.stale, true);
    expect(
      await ChangeBookmarkImpl(repo)('canal-gardens', save: true),
      BookmarkResult.rejectedStale,
    );
    final resumed = controller.dispatch(const Foreground());
    expect(controller.state.addEnabled, false);
    expect(source.requests, hasLength(2));
    source.requests.last.complete(fixture('catalog-valid'));
    await resumed;
    expect(controller.state.addEnabled, true);
  });
  test(
    'SAVE-02 controller retries same failed intent and suppresses duplicates',
    () async {
      await load();
      await controller.dispatch(const OpenDetail('canal-gardens'));
      storage.failWrite = true;
      await controller.dispatch(const ToggleBookmark());
      expect(controller.state.detail?.saved, false);
      expect(controller.state.catalog.bookmarkError, isNotNull);
      storage.failWrite = false;
      await controller.dispatch(const RetryBookmark());
      expect(controller.state.detail?.saved, true);
    },
  );
  test('SAVE-03/04 presentation reason priority and allowed removal', () async {
    storage.ids = {'glasshouse-loop'};
    await load();
    clock.value = 1300000;
    scheduler.flush();
    await controller.dispatch(const OpenDetail('glasshouse-loop'));
    expect(controller.state.removeEnabled, true);
    await controller.dispatch(const ToggleBookmark());
    expect(controller.state.detail?.saved, false);
    expect(controller.state.disabledReason, 'closed');
    await controller.dispatch(const OpenDetail('pine-loop'));
    expect(controller.state.disabledReason, 'stale');
  });
  test(
    'SAVE-06 storage failure keeps list readable and count unavailable',
    () async {
      storage.failRead = true;
      await load();
      expect(controller.state.savedCount, null);
      expect(controller.state.walks, hasLength(3));
      await controller.dispatch(const OpenDetail('canal-gardens'));
      expect(controller.state.disabledReason, 'storage-unavailable');
      storage.failRead = false;
      await controller.dispatch(const RetrySavedWalks());
      expect(controller.state.addEnabled, true);
    },
  );
  test(
    'late completions and expiry emit no notifications after disposal',
    () async {
      int notifications = 0;
      controller.addListener(() => notifications++);
      final start = controller.start();
      expect(source.requests, hasLength(1));
      controller.dispose();
      final before = notifications;
      source.requests.single.complete(fixture('catalog-valid'));
      await start;
      clock.value = 1300000;
      scheduler.flush();
      expect(notifications, before);
    },
  );
  testWidgets('VIEW-01 widgets navigate save and back with visible labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await load();
    await tester.pumpWidget(
      MaterialApp(home: CatalogFeature(controller: controller)),
    );
    expect(find.text('Search walks'), findsOneWidget);
    expect(find.text('Pine loop'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('route-canal-gardens')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('route-canal-gardens')));
    await tester.pump();
    expect(find.text('3.2 km'), findsOneWidget);
    expect(find.text('Save walk'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bookmark-action')));
    await tester.pump();
    expect(find.text('Remove saved walk'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to walks'));
    await tester.pump();
    expect(find.text('1 saved walk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('CLOCK-01 visible Save disables at exact expiry', (tester) async {
    await load();
    await controller.dispatch(const OpenDetail('canal-gardens'));
    await tester.pumpWidget(
      MaterialApp(home: CatalogFeature(controller: controller)),
    );
    clock.value = 1299999;
    scheduler.flush();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('bookmark-action')))
          .onPressed,
      isNotNull,
    );
    clock.value = 1300000;
    scheduler.flush();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('bookmark-action')))
          .onPressed,
      null,
    );
    expect(find.text('Refresh walks before saving.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'VIEW-01 long text at 393x852 scale 1.6 in light and dark scrolls without overflow',
    (tester) async {
      await load('catalog-long-text');
      await controller.dispatch(
        OpenDetail(repo.state.snapshot!.walks.first.id),
      );
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(393, 852),
                textScaler: TextScaler.linear(1.6),
              ),
              child: CatalogFeature(controller: controller),
            ),
          ),
        );
        expect(tester.takeException(), null);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('bookmark-action')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Save walk'), findsOneWidget);
        expect(tester.takeException(), null);
        expect(
          find.text(repo.state.snapshot!.walks.first.description),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'CAT-05 loading then source error renders Retry and restores content',
    (tester) async {
      final started = controller.start();
      await tester.pumpWidget(
        MaterialApp(home: CatalogFeature(controller: controller)),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      source.requests.single.completeError(StateError('unavailable'));
      await started;
      await tester.pump();
      expect(find.text('Walks are unavailable right now.'), findsOneWidget);
      await tester.tap(find.text('Retry walks'));
      await tester.pump();
      expect(source.requests, hasLength(2));
      source.requests.last.complete(fixture('catalog-valid'));
      await tester.pump();
      expect(find.text('Pine loop'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('NAV-01 unavailable detail provides a functional Back action', (
    tester,
  ) async {
    await load();
    await controller.dispatch(const OpenDetail('unknown'));
    await tester.pumpWidget(
      MaterialApp(home: CatalogFeature(controller: controller)),
    );
    expect(find.text('This walk is unavailable.'), findsOneWidget);
    await tester.tap(find.text('Back to walks'));
    await tester.pump();
    expect(find.text('Search walks'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'SAVE-02 failed save remains inline until explicit successful retry',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await load();
      await controller.dispatch(const OpenDetail('canal-gardens'));
      await tester.pumpWidget(
        MaterialApp(home: CatalogFeature(controller: controller)),
      );
      storage.failWrite = true;
      await tester.tap(find.byKey(const ValueKey('bookmark-action')));
      await tester.pump();
      expect(
        find.text('Could not update saved walks. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Save walk'), findsOneWidget);
      expect(storage.ids, isEmpty);
      await tester.ensureVisible(find.text('Retry save'));
      await tester.pumpAndSettle();
      storage.failWrite = false;
      await tester.tap(find.text('Retry save'));
      await tester.pump();
      expect(find.text('Remove saved walk'), findsOneWidget);
      expect(storage.ids, {'canal-gardens'});
      expect(find.text('Retry save'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('bookmark retry belongs to the failed route across navigation', (
    tester,
  ) async {
    await load();
    await controller.dispatch(const OpenDetail('canal-gardens'));
    storage.failWrite = true;
    await controller.dispatch(const ToggleBookmark());
    await controller.dispatch(const OpenDetail('pine-loop'));
    await tester.pumpWidget(
      MaterialApp(home: CatalogFeature(controller: controller)),
    );
    expect(find.text('Retry save'), findsNothing);
    await controller.dispatch(const OpenDetail('canal-gardens'));
    await tester.pump();
    expect(find.text('Retry save'), findsOneWidget);
    storage.failWrite = false;
    await controller.dispatch(const RetryBookmark());
    await tester.pump();
    expect(controller.state.detail?.saved, true);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'failed Save retry rejected at TTL keeps intent until valid refresh',
    () async {
      await load();
      await controller.dispatch(const OpenDetail('canal-gardens'));
      storage.failWrite = true;
      await controller.dispatch(const ToggleBookmark());
      expect(controller.state.catalog.bookmarkError, isNotNull);
      clock.value = 1300000;
      scheduler.flush();
      storage.failWrite = false;
      await controller.dispatch(const RetryBookmark());
      expect(storage.writes, 1);
      expect(controller.state.detail?.saved, false);
      final refreshing = controller.dispatch(const RefreshCatalog());
      source.requests.last.complete(fixture('catalog-valid'));
      await refreshing;
      expect(controller.state.addEnabled, true);
      await controller.dispatch(const RetryBookmark());
      expect(controller.state.detail?.saved, true);
      expect(controller.state.catalog.bookmarkError, null);
      expect(storage.ids, {'canal-gardens'});
      expect(storage.writes, 2);
    },
  );
}
