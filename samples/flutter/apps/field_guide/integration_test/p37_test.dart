import 'dart:ui' show SemanticsAction;

import 'dart:async';

import 'package:catalog_api/catalog_api.dart';
import 'package:catalog_impl/catalog_impl.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:field_guide/local_adapters.dart';
import 'package:field_guide/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final class DeviceTime implements MonotonicClock, ExpiryScheduler {
  @override
  int nowMs = 1000000;
  final tasks = <({int at, void Function() callback, List<bool> cancelled})>[];
  @override
  CancelExpiry schedule(int delayMs, void Function() callback) {
    final cancelled = [false];
    tasks.add((at: nowMs + delayMs, callback: callback, cancelled: cancelled));
    return () => cancelled[0] = true;
  }

  void advance(int value, {bool notify = true}) {
    nowMs = value;
    if (notify) {
      for (final task in tasks.toList()) {
        if (!task.cancelled[0] && task.at <= nowMs) {
          task.cancelled[0] = true;
          task.callback();
        }
      }
    }
  }
}

// Delays and failures replace only catalog I/O. Successful bytes come from the
// production bundled adapter, whose generated inputs match canonical fixtures.
final class DeviceSource implements CatalogSource {
  final requests = <Completer<String>>[];
  @override
  Future<String> load() {
    final request = Completer<String>();
    requests.add(request);
    return request.future;
  }

  Future<void> complete([String fixture = 'catalog-valid']) async {
    requests.last.complete(await BundledCatalogSource(fixture: fixture).load());
  }

  void fail() =>
      requests.last.completeError(StateError('Controlled source failure'));
}

final class DeviceGraph {
  final time = DeviceTime();
  final source = DeviceSource();
  // This is the actual MethodChannel and Android private-file adapter.
  final storage = LocalBookmarkStorage();
  late final repository = CatalogRepositoryImpl(
    source: source,
    storage: storage,
    clock: time,
  );
  late final controller = CatalogController(
    repository: repository,
    queryWalks: QueryWalksImpl(),
    bookmarks: ChangeBookmarkImpl(repository),
    clock: time,
    scheduler: time,
  );
  void dispose() {
    controller.dispose();
    repository.dispose();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  bool surfaceConverted = false;
  setUp(() => surfaceConverted = false);
  Future<void> tap(WidgetTester tester, String label) async {
    final finder = label == 'Back to walks' || label == 'Refresh walks'
        ? find.byTooltip(label)
        : find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}(?:\\n|\$)'));
    expect(finder, findsOneWidget, reason: 'Semantic action: $label');
    debugPrint('P37 ACTION: $label');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!surfaceConverted) {
      debugPrint('P37 screenshot surface convert begin');
      await binding.convertFlutterSurfaceToImage();
      debugPrint('P37 screenshot surface convert complete');
      surfaceConverted = true;
    }
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('P37 CAPTURE: $name');
    await binding.takeScreenshot(name);
  }

  Future<void> mount(
    WidgetTester tester,
    DeviceGraph graph, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff285244),
            brightness: brightness,
          ),
          scaffoldBackgroundColor: brightness == Brightness.light
              ? const Color(0xfffff9ee)
              : null,
          useMaterial3: true,
        ),
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: CatalogFeature(controller: graph.controller),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'P3.7 launcher graph saves through real channel and new adapter restores',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        debugPrint('P37 real storage reset begin');
        await LocalBookmarkStorage().write({});
        debugPrint('P37 real storage reset complete');
        app.main();
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        expect(find.text('0 saved walks'), findsOneWidget);
        await shot(tester, 'launcher-list');

        await tap(tester, 'Canal gardens');
        expect(find.text('3.2 km'), findsOneWidget);

        await tap(tester, 'Save walk');
        await tester.pumpAndSettle();

        expect(find.text('Remove saved walk'), findsOneWidget);
        expect(await LocalBookmarkStorage().read(), {'canal-gardens'});
        await shot(tester, 'launcher-saved-detail');

        await tap(tester, 'Back to walks');
        await tester.pumpAndSettle();

        expect(find.text('1 saved walk'), findsOneWidget);
        await tester.enterText(
          find.bySemanticsLabel('Search walks'),
          '  CANAL  ',
        );
        await tester.pumpAndSettle();
        expect(find.text('Canal gardens'), findsOneWidget);
        expect(find.text('Pine loop'), findsNothing);
        await tap(tester, 'Canal gardens');
        await tap(tester, 'Back to walks');
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '  CANAL  ',
        );
        await tap(tester, '15 min');
        await tester.pumpAndSettle();
        expect(find.text('No walks match your filters.'), findsOneWidget);
        await shot(tester, 'launcher-empty');
        await tap(tester, 'Clear filters');
        await tester.pumpAndSettle();
        expect(find.text('Pine loop'), findsOneWidget);
        await tap(tester, 'Refresh walks');
        await tester.pumpAndSettle();
        expect(find.text('1 saved walk'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        // Recreate the actual app repository/controller, with a fresh storage adapter.
        app.main();
        await tester.pumpAndSettle();
        expect(find.text('1 saved walk'), findsOneWidget);
        await shot(tester, 'launcher-adapter-recreated');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'P3.7 device controlled source loading error retry clock closed removed foreground',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await LocalBookmarkStorage().write({'canal-gardens'});
        final graph = DeviceGraph();
        addTearDown(graph.dispose);
        final start = graph.controller.start();
        await mount(tester, graph);
        expect(find.bySemanticsLabel('Loading walks'), findsOneWidget);
        await shot(tester, 'controlled-loading');
        graph.source.fail();
        await start;
        await tester.pumpAndSettle();
        expect(find.text('Walks are unavailable right now.'), findsOneWidget);
        await shot(tester, 'controlled-initial-error');
        await tap(tester, 'Retry walks');
        await graph.source.complete();
        await tester.pumpAndSettle();
        expect(find.text('1 saved walk'), findsOneWidget);
        await tap(tester, 'Glasshouse loop');
        await tester.ensureVisible(find.text('Save walk'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(find.text('Save walk'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          false,
        );
        expect(
          find.text('This walk is closed. You can save it when it reopens.'),
          findsOneWidget,
        );
        await shot(tester, 'controlled-closed');
        await tap(tester, 'Back to walks');
        await tester.pumpAndSettle();
        await tap(tester, 'Pine loop');
        graph.time.advance(1299999);
        await tester.pump();
        expect(graph.controller.state.addEnabled, true);
        expect(
          tester
              .getSemantics(find.text('Save walk'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          true,
        );
        graph.time.advance(1300000);
        await tester.pump();
        expect(graph.controller.state.addEnabled, false);
        expect(
          tester
              .getSemantics(find.text('Save walk'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          false,
        );
        expect(
          await ChangeBookmarkImpl(graph.repository)('pine-loop', save: true),
          BookmarkResult.rejectedStale,
        );
        await shot(tester, 'controlled-stale-detail');
        await tap(tester, 'Refresh walks');
        graph.source.fail();
        await tester.pumpAndSettle();
        expect(find.text('Retry walks'), findsOneWidget);
        await shot(tester, 'controlled-stale-error');
        await graph.controller.dispatch(const OpenDetail('canal-gardens'));
        await tester.pumpAndSettle();
        expect(graph.controller.state.removeEnabled, true);
        await tap(tester, 'Remove saved walk');
        await tester.pumpAndSettle();
        expect(await LocalBookmarkStorage().read(), isEmpty);
        await tap(tester, 'Retry walks');
        await graph.source.complete();
        await tester.pumpAndSettle();
        expect(graph.controller.state.addEnabled, true);
        await tap(tester, 'Save walk');
        await tester.pumpAndSettle();
        expect(await LocalBookmarkStorage().read(), {'canal-gardens'});
        await tap(tester, 'Back to walks');
        await tester.pumpAndSettle();
        await tap(tester, 'Canal gardens');
        await tap(tester, 'Refresh walks');
        await graph.source.complete('catalog-changed');
        await tester.pumpAndSettle();
        expect(find.text('This walk is unavailable.'), findsOneWidget);
        expect(await LocalBookmarkStorage().read(), {'canal-gardens'});
        expect(graph.controller.state.savedCount, 0);
        await shot(tester, 'controlled-removed');
        await tap(tester, 'Back to walks');
        await tester.pumpAndSettle();
        await graph.controller.dispatch(const OpenDetail('never-listed'));
        await tester.pumpAndSettle();
        expect(find.text('This walk is unavailable.'), findsOneWidget);
        await tap(tester, 'Back to walks');
        await tester.pumpAndSettle();
        await tap(tester, 'Pine loop');
        expect(graph.controller.state.disabledReason, 'closed');
        // Persist a closed route, recreate graph/storage, and prove removal remains allowed.
        await LocalBookmarkStorage().write({'pine-loop', 'canal-gardens'});
        await graph.repository.loadBookmarks();
        await tester.pumpAndSettle();
        await tap(tester, 'Remove saved walk');
        await tester.pumpAndSettle();
        expect(await LocalBookmarkStorage().read(), {'canal-gardens'});
        // A real WidgetsBinding resumed notification calls the production observer;
        // fake time jumps without flushing timers to isolate foreground rechecking.
        graph.time.advance(1600000, notify: false);
        final before = graph.source.requests.length;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(graph.source.requests.length, before + 1);
        expect(graph.controller.state.stale, true);
        await graph.source.complete();
        await tester.pumpAndSettle();
        expect(graph.controller.state.stale, false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'P3.7 device long text light dark scale 1.0 and 1.6 actions reachable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final graph = DeviceGraph();
        addTearDown(graph.dispose);
        final start = graph.controller.start();
        await graph.source.complete('catalog-long-text');
        await start;
        for (final brightness in Brightness.values) {
          for (final scale in [1.0, 1.6]) {
            await graph.controller.dispatch(const BackToList());
            await mount(tester, graph, brightness: brightness, scale: scale);
            await tester.pumpAndSettle();
            final title = graph.repository.state.snapshot!.walks.single.title;
            await shot(tester, 'long-${brightness.name}-$scale-list');
            await tap(tester, title);
            await tester.pumpAndSettle();
            await shot(tester, 'long-${brightness.name}-$scale-detail-top');
            await tester.scrollUntilVisible(
              find.text('Save walk'),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .getSemantics(find.text('Save walk'))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              true,
            );
            expect(
              find.text(
                graph.repository.state.snapshot!.walks.single.description,
              ),
              findsOneWidget,
            );
            await shot(tester, 'long-${brightness.name}-$scale-detail-bottom');
            expect(tester.takeException(), isNull);
            await tap(tester, 'Back to walks');
            await tester.pumpWidget(const SizedBox());
          }
        }
        // Leave canonical saved ID for external force-stop/launcher recreation.
        await LocalBookmarkStorage().write({'canal-gardens'});
      } finally {
        semantics.dispose();
      }
    },
  );
}
