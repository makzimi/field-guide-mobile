import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bundled Source Serif 4 Semibold, used by the three title styles.
const String fieldGuideSerifFamily = 'SourceSerif4';
const String fieldGuideSerifPackage = 'feature_catalog';

Color _c(int rgb) => Color(0xFF000000 | rgb);

/// The approved Field Guide color tokens for [brightness].
///
/// Flutter 3.47 deprecates `ColorScheme.background` and `surfaceVariant`, so
/// the spec's roles map as follows: "background" is
/// `ThemeData.scaffoldBackgroundColor` (see [fieldGuideTheme]), "surface" is
/// `ColorScheme.surface`, and "surfaceVariant" is
/// `ColorScheme.surfaceContainerHighest`. In light mode background and
/// surface are the same value.
ColorScheme fieldGuideColors(Brightness brightness) {
  final light = brightness == Brightness.light;
  return ColorScheme(
    brightness: brightness,
    surface: _c(light ? 0xF8F5EC : 0x1C2B22),
    surfaceContainerLowest: _c(light ? 0xFFFFFF : 0x22332A),
    surfaceContainerHighest: _c(light ? 0xEAE9DE : 0x304337),
    onSurface: _c(light ? 0x263A30 : 0xF3F0E8),
    onSurfaceVariant: _c(light ? 0x5C6B61 : 0xB9C4BB),
    outlineVariant: _c(light ? 0xDCDCCF : 0x3A4D41),
    primary: _c(light ? 0x245B45 : 0x9DCEAD),
    onPrimary: _c(light ? 0xFFFFFF : 0x12301F),
    primaryContainer: _c(light ? 0xD8E5D4 : 0x2E4A3A),
    onPrimaryContainer: _c(light ? 0x1D4A39 : 0xCFE8D6),
    secondary: _c(light ? 0xA35A40 : 0xE0A990),
    onSecondary: _c(light ? 0xFFFFFF : 0x3A2218),
    secondaryContainer: _c(light ? 0xF3E0D6 : 0x5A3A2C),
    onSecondaryContainer: _c(light ? 0x6E3A27 : 0xF5D9CB),
    error: _c(light ? 0xB3261E : 0xF2B8B5),
    onError: _c(light ? 0xFFFFFF : 0x601410),
    errorContainer: _c(light ? 0xF6DDD6 : 0x5C2B22),
    onErrorContainer: _c(light ? 0x7A2E1E : 0xF8D8D0),
  );
}

/// The Field Guide theme: Material 3, Roboto, spec background as scaffold.
ThemeData fieldGuideTheme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  colorScheme: fieldGuideColors(brightness),
  scaffoldBackgroundColor: _c(
    brightness == Brightness.light ? 0xF8F5EC : 0x17251D,
  ),
);

double _luminance(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

/// WCAG contrast ratio between [foreground] and [background].
double contrastRatio(Color foreground, Color background) {
  final a = _luminance(foreground);
  final b = _luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// Text styles from the spec's Typography table. Colors come from the theme.
abstract final class FieldGuideType {
  static TextStyle _serif(double size, double line) => TextStyle(
    fontFamily: fieldGuideSerifFamily,
    package: fieldGuideSerifPackage,
    fontSize: size,
    height: line / size,
    fontWeight: FontWeight.w600,
  );

  static TextStyle _sans(double size, double line, FontWeight weight) =>
      TextStyle(
        fontFamily: 'Roboto',
        fontSize: size,
        height: line / size,
        fontWeight: weight,
      );

  static TextStyle get pageTitle => _serif(30, 36);
  static TextStyle get detailTitle => _serif(28, 34);
  static TextStyle get cardTitle => _serif(20, 26);
  static TextStyle get eyebrow => TextStyle(
    fontFamily: 'Roboto',
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 12 * 0.08,
  );
  static TextStyle get body => _sans(16, 24, FontWeight.w400);
  static TextStyle get facts => _sans(14, 20, FontWeight.w400);
  static TextStyle get factValue => _sans(16, 22, FontWeight.w500);
  static TextStyle get button => _sans(14, 20, FontWeight.w500);
}
