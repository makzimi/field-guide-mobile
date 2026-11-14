import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contrast of black on white is 21', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21.0, 0.01),
    );
  });

  for (final brightness in Brightness.values) {
    test('${brightness.name} text pairings reach 4.5:1', () {
      final c = fieldGuideColors(brightness);
      final page = fieldGuideTheme(brightness).scaffoldBackgroundColor;
      final pairs = <String, (Color, Color)>{
        'onSurface/background': (c.onSurface, page),
        'onSurface/surfaceContainerLowest': (
          c.onSurface,
          c.surfaceContainerLowest,
        ),
        'onSurfaceVariant/background': (c.onSurfaceVariant, page),
        'onSurfaceVariant/surfaceContainerLowest': (
          c.onSurfaceVariant,
          c.surfaceContainerLowest,
        ),
        'onSurfaceVariant/surfaceVariant': (
          c.onSurfaceVariant,
          c.surfaceContainerHighest,
        ),
        'onPrimary/primary': (c.onPrimary, c.primary),
        'onPrimaryContainer/primaryContainer': (
          c.onPrimaryContainer,
          c.primaryContainer,
        ),
        'secondary/background': (c.secondary, page),
        'secondary/surfaceContainerLowest': (
          c.secondary,
          c.surfaceContainerLowest,
        ),
        'onSecondaryContainer/secondaryContainer': (
          c.onSecondaryContainer,
          c.secondaryContainer,
        ),
        'onErrorContainer/errorContainer': (
          c.onErrorContainer,
          c.errorContainer,
        ),
      };
      pairs.forEach((name, pair) {
        expect(
          contrastRatio(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: name,
        );
      });
    });
  }

  test('pinned token values', () {
    final light = fieldGuideColors(Brightness.light);
    final dark = fieldGuideColors(Brightness.dark);
    expect(light.primary, const Color(0xFF245B45));
    expect(light.secondary, const Color(0xFFA35A40));
    expect(light.surface, const Color(0xFFF8F5EC));
    expect(dark.surface, const Color(0xFF1C2B22));
    expect(
      fieldGuideTheme(Brightness.dark).scaffoldBackgroundColor,
      const Color(0xFF17251D),
    );
  });

  test('light art palette matches the board', () {
    final light = ArtPalette.light;
    expect(light.skyPine, const Color(0xFFDCE8D6));
    expect(light.pineNear, const Color(0xFF245B45));
    expect(light.water, const Color(0xFF8FC1C6));
    expect(light.snow, const Color(0xFFFBF4EA));
  });

  test('dark art keeps foreground darker than sky', () {
    final dark = ArtPalette.dark;
    const black = Color(0xFF000000);
    expect(
      contrastRatio(dark.groundDeep, black),
      lessThan(contrastRatio(dark.skyPine, black)),
    );
    expect(
      contrastRatio(dark.sun, black),
      greaterThan(contrastRatio(dark.skyRidge, black)),
    );
  });
}
