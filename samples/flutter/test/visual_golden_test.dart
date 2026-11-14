import 'dart:io';

import 'package:catalog_impl/catalog_impl.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_widget_test.dart' show ManualScheduler;
import 'repository_test.dart'
    show FakeClock, DeferredSource, MemoryStorage, fixture;

void main() {
  setUpAll(() async {
    // Font bytes come from the pinned SDK, not host fallback or Ahem glyphs.
    final fonts = sdkFontDirectory();
    final roboto = FontLoader('Roboto');
    for (final name in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]) {
      roboto.addFont(
        Future.value(
          ByteData.sublistView(await File('${fonts.path}/$name').readAsBytes()),
        ),
      );
    }
    await roboto.load();
    final serif = FontLoader('packages/feature_catalog/SourceSerif4')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              'packages/feature_catalog/fonts/SourceSerif4-Semibold.ttf',
            ).readAsBytes(),
          ),
        ),
      );
    await serif.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytes(),
          ),
        ),
      );
    await icons.load();
  });

  for (final brightness in Brightness.values) {
    for (final scenario in [
      'list',
      'detail',
      'saved',
      'loading',
      'empty',
      'initial-error',
      'stale-error',
      'closed',
      'unavailable',
      'save-error',
    ]) {
      testWidgets('P3.7 golden $scenario ${brightness.name} 1.0', (
        tester,
      ) async {
        await capture(tester, scenario, brightness, 1);
      });
    }
    for (final scale in [1.0, 1.6]) {
      for (final scenario in [
        'long-list',
        'long-detail-top',
        'long-detail-bottom',
      ]) {
        testWidgets('P3.7 golden $scenario ${brightness.name} $scale', (
          tester,
        ) async {
          await capture(tester, scenario, brightness, scale);
        });
      }
    }
  }
}

Directory sdkFontDirectory() {
  final selectedBinary = Platform.environment['FIELD_GUIDE_FLUTTER_BIN'];
  final selectedRoot = Platform.environment['FLUTTER_ROOT'];
  Directory root;
  if (selectedBinary != null && selectedBinary.isNotEmpty) {
    root = File(File(selectedBinary).resolveSymbolicLinksSync()).parent.parent;
  } else if (selectedRoot != null && selectedRoot.isNotEmpty) {
    root = Directory(selectedRoot);
  } else {
    // flutter_tester runs from this SDK's bin/cache/artifacts/engine directory.
    root = File(Platform.resolvedExecutable).parent;
    while (!Directory('${root.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      final parent = root.parent;
      if (parent.path == root.path) {
        throw StateError(
          'Cannot locate SDK fonts. Set FIELD_GUIDE_FLUTTER_BIN.',
        );
      }
      root = parent;
    }
  }
  return Directory('${root.path}/bin/cache/artifacts/material_fonts');
}

Future<void> capture(
  WidgetTester tester,
  String scenario,
  Brightness brightness,
  double scale,
) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final clock = FakeClock();
  final source = DeferredSource();
  final storage = MemoryStorage();
  final scheduler = ManualScheduler(clock);
  final repo = CatalogRepositoryImpl(
    source: source,
    storage: storage,
    clock: clock,
  );
  final controller = CatalogController(
    repository: repo,
    queryWalks: QueryWalksImpl(),
    bookmarks: ChangeBookmarkImpl(repo),
    clock: clock,
    scheduler: scheduler,
  );
  addTearDown(() {
    controller.dispose();
    repo.dispose();
  });
  final started = controller.start();
  if (scenario == 'initial-error') {
    source.requests.last.completeError(StateError('Controlled source failure'));
    await started;
  } else if (scenario != 'loading') {
    source.requests.last.complete(
      fixture(
        scenario.startsWith('long-') ? 'catalog-long-text' : 'catalog-valid',
      ),
    );
    await started;
  }
  if (['detail', 'saved', 'save-error'].contains(scenario)) {
    await controller.dispatch(const OpenDetail('canal-gardens'));
    if (scenario == 'saved') await controller.dispatch(const ToggleBookmark());
    if (scenario == 'save-error') {
      storage.failWrite = true;
      await controller.dispatch(const ToggleBookmark());
    }
  }
  if (scenario == 'closed') {
    await controller.dispatch(const OpenDetail('glasshouse-loop'));
  }
  if (scenario == 'unavailable') {
    await controller.dispatch(const OpenDetail('never-listed'));
  }
  if (scenario == 'empty') await controller.dispatch(const SetBudget(15));
  if (scenario == 'stale-error') {
    clock.value = 1300000;
    scheduler.flush();
    final refresh = controller.dispatch(const RefreshCatalog());
    source.requests.last.completeError(StateError('Controlled source failure'));
    await refresh;
  }
  if (scenario.startsWith('long-detail')) {
    await controller.dispatch(const OpenDetail('long-title'));
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('golden-surface'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Roboto',
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
          data: MediaQueryData(
            size: const Size(393, 852),
            textScaler: TextScaler.linear(scale),
          ),
          child: CatalogFeature(controller: controller),
        ),
      ),
    ),
  );
  if (scenario == 'loading') {
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    await tester.pumpAndSettle();
  }
  if (scenario == 'long-detail-bottom' ||
      scenario == 'save-error' ||
      scenario == 'closed') {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bookmark-action')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    if (scenario == 'save-error') {
      await tester.ensureVisible(find.text('Retry save'));
      await tester.pumpAndSettle();
    }
  }

  final surface = find.byKey(const ValueKey('golden-surface'));
  final golden = 'goldens/p37/$scenario-${brightness.name}-$scale.png';

  expect(tester.takeException(), isNull);
  await expectLater(surface, matchesGoldenFile(golden));

  if (scenario == 'loading') {
    source.requests.last.complete(fixture('catalog-valid'));
    await started;
  }
  await tester.pumpWidget(const SizedBox());
}
