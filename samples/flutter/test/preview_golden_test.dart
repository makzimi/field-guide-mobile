import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_golden_test/widgetbook_golden_test.dart';

import 'previews/widgetbook.directories.g.dart';
import 'visual_golden_test.dart' show sdkFontDirectory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = sdkFontDirectory();
    final loader = FontLoader('Roboto');
    for (final name in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            await File('${fonts.path}/Roboto-$name.ttf').readAsBytes(),
          ),
        ),
      );
    }
    await loader.load();
  });

  // Fail visibly if discovery stops working instead of reporting zero goldens.
  test('preview discovery contains use cases', () {
    expect(countPreviews(directories), greaterThan(0));
  });

  runWidgetbookGoldenTests(
    nodes: directories,
    goldenSnapshotsOutputPath: 'goldens/previews',
    properties: previewProperties,
  );
}

int countPreviews(List<WidgetbookNode> nodes) => nodes.fold(
  0,
  (count, node) =>
      count +
      (node is WidgetbookUseCase ? 1 : countPreviews(node.children ?? [])),
);

final previewProperties = WidgetbookGoldenTestsProperties(
  addons: [
    ViewportAddon([
      ViewportData(
        name: 'Component',
        width: 320,
        height: 240,
        pixelRatio: 1,
        platform: TargetPlatform.android,
      ),
    ]),
  ],
);
