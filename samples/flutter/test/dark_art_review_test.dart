// Renders dark/light art review sheets into evidence/r2/art-review/ for visual
// review. Opt in: FIELD_GUIDE_ART_REVIEW=1 flutter test test/dark_art_review_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:catalog_api/catalog_api.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _order = [ArtKey.pine, ArtKey.glasshouse, ArtKey.canal, ArtKey.ridge];
const _gap = 16.0;

Future<List<int>> _sheet(
  ArtPalette palette,
  Color background,
  Size cell,
  double radius,
) async {
  final w = _gap * 3 + cell.width * 2;
  final h = _gap * 3 + cell.height * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = background);
  for (var i = 0; i < _order.length; i++) {
    final origin = Offset(
      _gap + (i % 2) * (cell.width + _gap),
      _gap + (i ~/ 2) * (cell.height + _gap),
    );
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final rect = Offset.zero & cell;
    canvas.clipRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      ),
    );
    paintScene(canvas, cell, _order[i], palette);
    canvas.restore();
  }
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  test(
    'renders dark and light art review sheets',
    () async {
      final dir = Directory('evidence/r2/art-review')
        ..createSync(recursive: true);
      const hero = Size(786, 440);
      const card = Size(706, 320);
      final jobs = <String, Future<List<int>> Function()>{
        'art-light-hero.png': () =>
            _sheet(ArtPalette.light, const Color(0xFFF8F5EC), hero, 0),
        'art-light-card.png': () =>
            _sheet(ArtPalette.light, const Color(0xFFF8F5EC), card, 22),
        'art-dark-hero.png': () =>
            _sheet(ArtPalette.dark, const Color(0xFF17251D), hero, 0),
        'art-dark-card.png': () =>
            _sheet(ArtPalette.dark, const Color(0xFF17251D), card, 22),
      };
      for (final e in jobs.entries) {
        File('${dir.path}/${e.key}').writeAsBytesSync(await e.value());
      }
      for (final name in jobs.keys) {
        final f = File('${dir.path}/$name');
        expect(f.existsSync(), isTrue);
        expect(f.lengthSync(), greaterThan(0));
      }
    },
    skip: Platform.environment.containsKey('FIELD_GUIDE_ART_REVIEW')
        ? false
        : 'Set FIELD_GUIDE_ART_REVIEW=1 to render the art review sheets.',
  );
}
