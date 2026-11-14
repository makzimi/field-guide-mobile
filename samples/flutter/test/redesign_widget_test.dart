import 'dart:ui' as ui;

import 'package:catalog_api/catalog_api.dart';
import 'package:catalog_impl/catalog_impl.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_widget_test.dart' show ManualScheduler;
import 'repository_test.dart'
    show FakeClock, DeferredSource, MemoryStorage, fixture;

Future<void> pumpFeature(
  WidgetTester tester, {
  ThemeData? ambient,
  Size size = const Size(393, 852),
  double textScale = 1.0,
  String catalog = 'catalog-valid',
  bool loaded = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final clock = FakeClock();
  final source = DeferredSource();
  final repo = CatalogRepositoryImpl(
    source: source,
    storage: MemoryStorage(),
    clock: clock,
  );
  final controller = CatalogController(
    repository: repo,
    queryWalks: QueryWalksImpl(),
    bookmarks: ChangeBookmarkImpl(repo),
    clock: clock,
    scheduler: ManualScheduler(clock),
  );
  addTearDown(() {
    controller.dispose();
    repo.dispose();
  });
  final started = controller.start();
  if (loaded) {
    source.requests.last.complete(fixture(catalog));
    await started;
  }
  final feature = MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: CatalogFeature(controller: controller),
  );
  await tester.pumpWidget(
    // The feature's screens need MaterialLocalizations, so a bare MaterialApp
    // with its default theme stands in for "no ambient theme".
    MaterialApp(theme: ambient, home: feature),
  );
  if (loaded) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> openDetail(WidgetTester tester, String id) async {
  final card = find.byKey(ValueKey('route-$id'));
  // Banner cards are tall, so later cards start below the first screenful.
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('feature renders approved tokens with no ambient theme', (
    tester,
  ) async {
    await pumpFeature(tester);
    final scheme = Theme.of(tester.element(find.text('Walks worth finding')))
        .colorScheme;
    expect(scheme.primary, const Color(0xFF245B45));
    expect(scheme.surface, const Color(0xFFF8F5EC));
  });

  testWidgets('feature follows a dark ambient theme', (tester) async {
    await pumpFeature(tester, ambient: ThemeData(brightness: Brightness.dark));
    final scheme = Theme.of(tester.element(find.text('Walks worth finding')))
        .colorScheme;
    expect(scheme.primary, const Color(0xFF9DCEAD));
    expect(scheme.surface, const Color(0xFF1C2B22));
  });

  testWidgets('list has no app bar and keeps its handles', (tester) async {
    await pumpFeature(tester);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('FIELD GUIDE'), findsOneWidget);
    expect(find.byTooltip('Refresh walks'), findsOneWidget);
    expect(find.byKey(const ValueKey('walk-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-canal-gardens')), findsOneWidget);
  });

  testWidgets('card and detail titles use the bundled serif', (tester) async {
    const expected = 'packages/$fieldGuideSerifPackage/$fieldGuideSerifFamily';
    await pumpFeature(tester);
    expect(
      tester.widget<Text>(find.text('Canal gardens')).style?.fontFamily,
      expected,
    );
    await openDetail(tester, 'canal-gardens');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('detail-title')))
          .style
          ?.fontFamily,
      expected,
    );
  });

  testWidgets('detail shows captioned facts with whole values', (tester) async {
    await pumpFeature(tester);
    await openDetail(tester, 'canal-gardens');
    for (final caption in ['Time', 'Distance', 'Terrain']) {
      expect(find.text(caption), findsOneWidget);
    }
    expect(find.text('3.2 km'), findsOneWidget);
    expect(find.byTooltip('Back to walks'), findsOneWidget);
    expect(find.byTooltip('Refresh walks'), findsOneWidget);
    expect(find.text('Walk details'), findsNothing);
  });

  testWidgets('facts row does not overflow at 320 wide, 1.6 scale', (
    tester,
  ) async {
    await pumpFeature(tester, size: const Size(320, 640), textScale: 1.6);
    await openDetail(tester, 'canal-gardens');
    expect(tester.takeException(), isNull);
  });

  testWidgets('long title wraps fully at 1.6 and description is reachable', (
    tester,
  ) async {
    await pumpFeature(tester, catalog: 'catalog-long-text', textScale: 1.6);
    await tester.tap(find.byType(LandscapeArt).first);
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('detail-title')),
    );
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bookmark-action')),
      200,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail back and refresh stay reachable when scrolled down', (
    tester,
  ) async {
    await pumpFeature(tester, catalog: 'catalog-long-text', textScale: 1.6);
    await tester.tap(find.byType(LandscapeArt).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bookmark-action')),
      200,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to walks').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Refresh walks').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Back to walks'));
    await tester.pumpAndSettle();
    expect(find.text('Walks worth finding'), findsOneWidget);
  });

  testWidgets('initial loading shows one spinner and two silent placeholders', (
    tester,
  ) async {
    await pumpFeature(tester, loaded: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(PlaceholderCard), findsNWidgets(2));
    expect(find.bySemanticsLabel('Loading walks'), findsOneWidget);
  });

  for (final key in ArtKey.values) {
    for (final size in const [
      Size(393, 220),
      Size(353, 160),
      Size(900, 220),
      Size(353, 0),
      Size.zero,
    ]) {
      test('paintScene ${key.name} at $size does not throw', () {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        paintScene(canvas, size, key, ArtPalette.light);
        paintScene(canvas, size, key, ArtPalette.dark);
        recorder.endRecording();
      });
    }
  }

  test('each art key paints a different picture', () async {
    Future<List<int>> rasterize(ArtKey key, Size size) async {
      final recorder = ui.PictureRecorder();
      paintScene(Canvas(recorder), size, key, ArtPalette.light);
      final image = await recorder.endRecording().toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    }

    final hashes = <int>{};
    for (final key in ArtKey.values) {
      hashes.add(Object.hashAll(await rasterize(key, const Size(400, 220))));
    }
    expect(hashes.length, ArtKey.values.length);
  });
}
