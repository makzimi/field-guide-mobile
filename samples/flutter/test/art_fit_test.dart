import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void expectFit(
    double width,
    double height,
    double scale,
    double dx,
    double dy,
  ) {
    final t = artFit(Size(width, height));
    expect(t.scale, closeTo(scale, 0.001), reason: 'scale');
    expect(t.dx, closeTo(dx, 0.01), reason: 'dx');
    expect(t.dy, closeTo(dy, 0.01), reason: 'dy');
  }

  test('detail hero 393x220 is height bound with centered crop', () {
    expectFit(393, 220, 1, -3.5, 0);
  });

  test('card banner 353x160 crops evenly top and bottom', () {
    expectFit(353, 160, 0.8825, 0, -17.075);
  });

  test('wide 900x220 scales by width and crops vertically', () {
    expectFit(900, 220, 2.25, 0, -137.5);
  });

  test('design size 400x220 is identity', () {
    expectFit(400, 220, 1, 0, 0);
  });

  test('zero height gives an empty transform', () {
    expectFit(353, 0, 0, 0, 0);
  });

  test('zero width gives an empty transform', () {
    expectFit(0, 160, 0, 0, 0);
  });
}
