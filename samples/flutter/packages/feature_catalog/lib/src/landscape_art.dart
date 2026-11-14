import 'dart:math' as math;

import 'package:catalog_api/catalog_api.dart';
import 'package:flutter/material.dart';

// Original, locally drawn walk scenes. Geometry is ported from
// project/proposals/sample-app-design-r2-art.html in its 400x220 design box.
// Layout of this file: palette, fit, widget, helpers, shared shapes, scenes.

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

/// Named art colors. [cloud] and [ripple] style strokes are opaque white drawn
/// at [cloudAlpha] and [rippleAlpha]. [shadeAlpha] is the strength of the
/// black overlay on pine and peak faces.
final class ArtPalette {
  const ArtPalette({
    required this.skyPine,
    required this.skyGlasshouse,
    required this.skyCanal,
    required this.skyRidge,
    required this.skyHaze,
    required this.sun,
    required this.sunHalo,
    required this.cloud,
    required this.farRange,
    required this.farShade,
    required this.warmRange1,
    required this.warmShade1,
    required this.warmRange2,
    required this.warmShade2,
    required this.middleGround,
    required this.foliageLight,
    required this.foliageMid,
    required this.foliageDeep,
    required this.pineFar,
    required this.pineMid,
    required this.pineNear,
    required this.pineDeep,
    required this.ground,
    required this.groundDeep,
    required this.lawn,
    required this.path,
    required this.water,
    required this.waterDeep,
    required this.glass,
    required this.glassFrame,
    required this.stone,
    required this.stoneLine,
    required this.snow,
    required this.trunk,
    required this.accent,
    required this.bird,
    required this.flowerLight,
    required this.flowerWarm,
    required this.rock,
    required this.cairnLight,
    required this.cairnDark,
    required this.distantGround,
    required this.shadeAlpha,
    required this.cloudAlpha,
    required this.rippleAlpha,
  });

  final Color skyPine;
  final Color skyGlasshouse;
  final Color skyCanal;
  final Color skyRidge;

  /// Lower sky band behind the ridge scene.
  final Color skyHaze;
  final Color sun;
  final Color sunHalo;
  final Color cloud;
  final Color farRange;
  final Color farShade;
  final Color warmRange1;
  final Color warmShade1;
  final Color warmRange2;
  final Color warmShade2;
  final Color middleGround;
  final Color foliageLight;
  final Color foliageMid;
  final Color foliageDeep;
  final Color pineFar;
  final Color pineMid;
  final Color pineNear;
  final Color pineDeep;
  final Color ground;
  final Color groundDeep;
  final Color lawn;
  final Color path;
  final Color water;
  final Color waterDeep;
  final Color glass;
  final Color glassFrame;
  final Color stone;
  final Color stoneLine;
  final Color snow;
  final Color trunk;
  final Color accent;
  final Color bird;
  final Color flowerLight;
  final Color flowerWarm;
  final Color rock;
  final Color cairnLight;
  final Color cairnDark;
  final Color distantGround;
  final double shadeAlpha;
  final double cloudAlpha;
  final double rippleAlpha;

  static const light = ArtPalette(
    skyPine: Color(0xFFDCE8D6),
    skyGlasshouse: Color(0xFFEFE1CE),
    skyCanal: Color(0xFFD7E7E6),
    skyRidge: Color(0xFFF1E4D2),
    skyHaze: Color(0xFFEBD3BF),
    sun: Color(0xFFF2BC74),
    sunHalo: Color(0xFFF3C88B),
    cloud: Color(0xFFFFFFFF),
    farRange: Color(0xFFBBD0BE),
    farShade: Color(0xFFA9C2AE),
    warmRange1: Color(0xFFDDBFA8),
    warmShade1: Color(0xFFCDA98F),
    warmRange2: Color(0xFFB98A6E),
    warmShade2: Color(0xFFA67859),
    middleGround: Color(0xFF8DAB8D),
    foliageLight: Color(0xFF86AC7C),
    foliageMid: Color(0xFF6E9468),
    foliageDeep: Color(0xFF5C8459),
    pineFar: Color(0xFF5E8A6B),
    pineMid: Color(0xFF2E6B52),
    pineNear: Color(0xFF245B45),
    pineDeep: Color(0xFF1D4A39),
    ground: Color(0xFF416C52),
    groundDeep: Color(0xFF2B5240),
    lawn: Color(0xFF7FA372),
    path: Color(0xFFE9E2CC),
    water: Color(0xFF8FC1C6),
    waterDeep: Color(0xFF6FA5AC),
    glass: Color(0xFFDCECE6),
    glassFrame: Color(0xFF4F6F60),
    stone: Color(0xFFCDBBA2),
    stoneLine: Color(0xFFA8957C),
    snow: Color(0xFFFBF4EA),
    trunk: Color(0xFF5B4332),
    accent: Color(0xFFA85E43),
    bird: Color(0xFF4C5A50),
    flowerLight: Color(0xFFF7EFE2),
    flowerWarm: Color(0xFFF3C88B),
    rock: Color(0xFF5D6F5F),
    cairnLight: Color(0xFFA3927F),
    cairnDark: Color(0xFF8A7A6A),
    distantGround: Color(0xFF6F7F62),
    shadeAlpha: 0.16,
    cloudAlpha: 0.75,
    rippleAlpha: 0.65,
  );

  static const dark = ArtPalette(
    skyPine: Color(0xFF1E3A33),
    skyGlasshouse: Color(0xFF2E3340),
    skyCanal: Color(0xFF1C3540),
    skyRidge: Color(0xFF33303F),
    skyHaze: Color(0xFF3A3444),
    sun: Color(0xFFE9E4CF),
    sunHalo: Color(0xFFC9CDB8),
    cloud: Color(0xFFFFFFFF),
    farRange: Color(0xFF3C5A50),
    farShade: Color(0xFF34504A),
    warmRange1: Color(0xFF5C5566),
    warmShade1: Color(0xFF4E4858),
    warmRange2: Color(0xFF453F52),
    warmShade2: Color(0xFF3A3546),
    middleGround: Color(0xFF2F4D41),
    foliageLight: Color(0xFF4A6E58),
    foliageMid: Color(0xFF3B5C49),
    foliageDeep: Color(0xFF2F4D3D),
    pineFar: Color(0xFF2D5042),
    pineMid: Color(0xFF1F4034),
    pineNear: Color(0xFF18352B),
    pineDeep: Color(0xFF122A22),
    ground: Color(0xFF1B352B),
    groundDeep: Color(0xFF132720),
    lawn: Color(0xFF2C4A3A),
    path: Color(0xFF8E8A76),
    water: Color(0xFF2F5C68),
    waterDeep: Color(0xFF244B56),
    glass: Color(0xFFF0D9A0),
    glassFrame: Color(0xFF1D332B),
    stone: Color(0xFF6B6558),
    stoneLine: Color(0xFF514C42),
    snow: Color(0xFFC9CBD6),
    trunk: Color(0xFF2A211B),
    accent: Color(0xFFB26E54),
    bird: Color(0xFF9AA79E),
    flowerLight: Color(0xFFBFB9A8),
    flowerWarm: Color(0xFFB89A68),
    rock: Color(0xFF2A3A31),
    cairnLight: Color(0xFF5E574D),
    cairnDark: Color(0xFF4A443C),
    distantGround: Color(0xFF2B3D33),
    shadeAlpha: 0.22,
    cloudAlpha: 0.12,
    rippleAlpha: 0.22,
  );

  static ArtPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

// ---------------------------------------------------------------------------
// Fit
// ---------------------------------------------------------------------------

const double _artW = 400;
const double _artH = 220;

typedef ArtTransform = ({double scale, double dx, double dy});

/// Uniform cover scale of the 400x220 box, centered horizontally. Vertical
/// overflow is cropped evenly from the top and bottom.
/// Empty bounds give an empty transform.
ArtTransform artFit(Size size) {
  if (size.width <= 0 || size.height <= 0) {
    return (scale: 0, dx: 0, dy: 0);
  }
  final scale = math.max(size.width / _artW, size.height / _artH);
  final dx = (size.width - _artW * scale) / 2;
  final overflow = _artH * scale - size.height;
  return (scale: scale, dx: dx, dy: -overflow / 2);
}

// ---------------------------------------------------------------------------
// Widget and painter
// ---------------------------------------------------------------------------

/// Original vector landscape, rendered locally without network assets.
class LandscapeArt extends StatelessWidget {
  const LandscapeArt({required this.artKey, super.key});
  final ArtKey artKey;

  @override
  Widget build(BuildContext context) {
    final palette = ArtPalette.of(Theme.of(context).brightness);
    return ExcludeSemantics(
      child: ClipRect(
        child: CustomPaint(
          painter: _LandscapePainter(artKey, palette),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter(this.artKey, this.palette);
  final ArtKey artKey;
  final ArtPalette palette;

  @override
  void paint(Canvas canvas, Size size) =>
      paintScene(canvas, size, artKey, palette);

  @override
  bool shouldRepaint(_LandscapePainter oldDelegate) =>
      oldDelegate.artKey != artKey || oldDelegate.palette != palette;
}

/// Paints [key] fitted to [size] with [palette]. Empty bounds paint nothing.
@visibleForTesting
void paintScene(Canvas canvas, Size size, ArtKey key, ArtPalette palette) {
  final t = artFit(size);
  if (t.scale <= 0) return;
  canvas.save();
  canvas.translate(t.dx, t.dy);
  canvas.scale(t.scale);
  final g = _Pen(canvas, palette);
  switch (key) {
    case ArtKey.pine:
      _pineScene(g);
    case ArtKey.glasshouse:
      _glasshouseScene(g);
    case ArtKey.canal:
      _canalScene(g);
    case ArtKey.ridge:
      _ridgeScene(g);
  }
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Drawing helpers
// ---------------------------------------------------------------------------

Path _poly(List<double> v) => _addPoly(Path(), v);

/// Adds one closed polygon subpath to [p].
Path _addPoly(Path p, List<double> v) {
  p.moveTo(v[0], v[1]);
  for (var i = 2; i < v.length; i += 2) {
    p.lineTo(v[i], v[i + 1]);
  }
  p.close();
  return p;
}

Path _polyline(List<double> v) {
  final p = Path()..moveTo(v[0], v[1]);
  for (var i = 2; i < v.length; i += 2) {
    p.lineTo(v[i], v[i + 1]);
  }
  return p;
}

/// Open segments given as x0, y0, x1, y1 quadruples.
Path _segments(List<double> v) {
  final p = Path();
  for (var i = 0; i < v.length; i += 4) {
    p
      ..moveTo(v[i], v[i + 1])
      ..lineTo(v[i + 2], v[i + 3]);
  }
  return p;
}

class _Pen {
  _Pen(this.canvas, this.p);
  final Canvas canvas;
  final ArtPalette p;

  void fill(Path path, Color c) => canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.fill
      ..color = c,
  );

  void line(
    Path path,
    Color c,
    double w, {
    StrokeCap cap = StrokeCap.butt,
    StrokeJoin join = StrokeJoin.miter,
  }) => canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..color = c
      ..strokeWidth = w
      ..strokeCap = cap
      ..strokeJoin = join,
  );

  void rect(double x, double y, double w, double h, Color c) =>
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = c);

  void rrect(double x, double y, double w, double h, double r, Color c) =>
      canvas.drawRRect(
        RRect.fromRectXY(Rect.fromLTWH(x, y, w, h), r, r),
        Paint()..color = c,
      );

  void disc(double cx, double cy, double r, Color c) =>
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = c);

  void oval(double cx, double cy, double rx, double ry, Color c) =>
      canvas.drawOval(
        Rect.fromLTRB(cx - rx, cy - ry, cx + rx, cy + ry),
        Paint()..color = c,
      );

  /// Places a symbol of viewBox vw x vh in the x, y, w, h box (xMidYMid meet).
  void place(
    double x,
    double y,
    double w,
    double h,
    double vw,
    double vh,
    void Function() draw,
  ) {
    final s = math.min(w / vw, h / vh);
    canvas.save();
    canvas.translate(x + (w - vw * s) / 2, y + (h - vh * s) / 2);
    canvas.scale(s);
    draw();
    canvas.restore();
  }

  // Shared shapes: pine (40x80), cloud (80x24), bird (16x6).

  void pine(double x, double y, double w, double h, Color color) =>
      place(x, y, w, h, 40, 80, () {
        rect(18, 60, 4, 20, p.trunk);
        final tiers = _poly([20, 4, 32, 30, 8, 30]);
        _addPoly(tiers, [20, 18, 35, 48, 5, 48]);
        _addPoly(tiers, [20, 34, 38, 68, 2, 68]);
        fill(tiers, color);
        final shade = _poly([20, 4, 32, 30, 20, 30]);
        _addPoly(shade, [20, 18, 35, 48, 20, 48]);
        _addPoly(shade, [20, 34, 38, 68, 20, 68]);
        fill(shade, const Color(0xFF000000).withValues(alpha: p.shadeAlpha));
      });

  void cloud(double x, double y, double w, double h) =>
      place(x, y, w, h, 80, 24, () {
        const clockwise = true;
        final path = Path()
          ..moveTo(8, 20)
          ..arcToPoint(
            const Offset(14, 6),
            radius: const Radius.circular(8),
            clockwise: clockwise,
          )
          ..arcToPoint(
            const Offset(36, 3),
            radius: const Radius.circular(12),
            clockwise: clockwise,
          )
          ..arcToPoint(
            const Offset(54, 8),
            radius: const Radius.circular(10),
            clockwise: clockwise,
          )
          ..arcToPoint(
            const Offset(66, 20),
            radius: const Radius.circular(7),
            clockwise: clockwise,
          )
          ..close();
        fill(path, p.cloud.withValues(alpha: p.cloudAlpha));
      });

  void bird(double x, double y, double w, double h) =>
      place(x, y, w, h, 16, 6, () {
        final path = Path()
          ..moveTo(1, 5)
          ..quadraticBezierTo(4.5, 0, 8, 5)
          ..quadraticBezierTo(11.5, 0, 15, 5);
        line(path, p.bird, 1.2, cap: StrokeCap.round);
      });

  /// Sun disc with two halo rings.
  void sun(
    double cx,
    double cy,
    double r1,
    double r2,
    double r3,
    double a1,
    double a2,
  ) {
    disc(cx, cy, r1, p.sunHalo.withValues(alpha: a1));
    disc(cx, cy, r2, p.sunHalo.withValues(alpha: a2));
    disc(cx, cy, r3, p.sun);
  }

  void tuft(double x, double y, Color c) => line(
    _segments([x, y, x - 3, y - 8, x, y, x + 1, y - 10, x, y, x + 5, y - 7]),
    c,
    1.5,
    cap: StrokeCap.round,
  );
}

// ---------------------------------------------------------------------------
// Scene: pine
// ---------------------------------------------------------------------------

void _pineScene(_Pen g) {
  final p = g.p;
  g.rect(0, 0, _artW, _artH, p.skyPine);
  g.sun(310, 58, 42, 29, 18, 0.25, 0.45);
  g.cloud(36, 28, 90, 27);
  g.cloud(196, 20, 56, 17);
  g.bird(150, 52, 16, 6);
  g.bird(176, 64, 12, 5);
  g.fill(
    _poly([
      0, 130, 50, 92, 85, 112, 140, 70, 185, 108, 230, 84, 290, 118, //
      340, 96, 400, 124, 400, 220, 0, 220,
    ]),
    p.farRange,
  );
  final farShade = _poly([140, 70, 185, 108, 160, 112, 150, 94]);
  _addPoly(farShade, [230, 84, 290, 118, 258, 118, 240, 100]);
  _addPoly(farShade, [50, 92, 85, 112, 64, 114]);
  g.fill(farShade, p.farShade);
  g.fill(
    Path()
      ..moveTo(0, 150)
      ..quadraticBezierTo(80, 118, 160, 140)
      ..quadraticBezierTo(240, 162, 320, 132)
      ..quadraticBezierTo(400, 102, 400, 140)
      ..lineTo(400, 220)
      ..lineTo(0, 220)
      ..close(),
    p.middleGround,
  );
  for (final b in const [
    [8.0, 106.0, 18.0, 36.0],
    [26.0, 100.0, 20.0, 40.0],
    [46.0, 98.0, 18.0, 36.0],
    [112.0, 102.0, 20.0, 40.0],
    [132.0, 106.0, 18.0, 36.0],
    [196.0, 108.0, 18.0, 36.0],
    [216.0, 104.0, 20.0, 40.0],
    [238.0, 102.0, 18.0, 36.0],
    [372.0, 100.0, 20.0, 40.0],
  ]) {
    g.pine(b[0], b[1], b[2], b[3], p.pineFar);
  }
  g.fill(
    Path()
      ..moveTo(0, 176)
      ..quadraticBezierTo(110, 148, 220, 170)
      ..quadraticBezierTo(330, 192, 400, 160)
      ..lineTo(400, 220)
      ..lineTo(0, 220)
      ..close(),
    p.ground,
  );
  g.fill(
    Path()
      ..moveTo(0, 206)
      ..quadraticBezierTo(200, 192, 400, 208)
      ..lineTo(400, 220)
      ..lineTo(0, 220)
      ..close(),
    p.groundDeep,
  );
  g.fill(
    Path()
      ..moveTo(146, 220)
      ..cubicTo(180, 196, 238, 198, 226, 180)
      ..cubicTo(218, 168, 196, 170, 204, 158)
      ..lineTo(210, 158)
      ..cubicTo(205, 170, 234, 168, 244, 180)
      ..cubicTo(258, 200, 222, 204, 222, 220)
      ..close(),
    p.path,
  );
  g.pine(246, 124, 36, 72, p.pineMid);
  g.pine(124, 130, 30, 60, p.pineMid);
  g.pine(14, 92, 58, 116, p.pineNear);
  g.pine(284, 84, 64, 128, p.pineNear);
  g.pine(62, 118, 44, 88, p.pineDeep);
  g.pine(338, 114, 48, 96, p.pineDeep);
  g.rect(263, 188, 3, 16, p.trunk);
  g.rrect(258, 186, 13, 7, 1, p.accent);
  g.tuft(116, 200, p.middleGround);
  g.tuft(186, 208, p.middleGround);
  g.tuft(300, 212, p.middleGround);
}

// ---------------------------------------------------------------------------
// Scene: glasshouse
// ---------------------------------------------------------------------------

void _glasshouseScene(_Pen g) {
  final p = g.p;
  g.rect(0, 0, _artW, _artH, p.skyGlasshouse);
  g.sun(78, 54, 40, 27, 17, 0.25, 0.45);
  g.cloud(250, 26, 84, 25);
  g.cloud(150, 18, 50, 15);
  g.bird(320, 70, 16, 6);
  g.fill(
    Path()
      ..moveTo(0, 128)
      ..quadraticBezierTo(100, 96, 200, 120)
      ..quadraticBezierTo(300, 144, 400, 110)
      ..lineTo(400, 220)
      ..lineTo(0, 220)
      ..close(),
    p.farRange,
  );
  g.fill(
    Path()
      ..moveTo(0, 146)
      ..quadraticBezierTo(120, 126, 240, 142)
      ..quadraticBezierTo(360, 158, 400, 136)
      ..lineTo(400, 220)
      ..lineTo(0, 220)
      ..close(),
    p.middleGround,
  );
  g.rect(98, 128, 4, 30, p.trunk);
  g.rect(296, 128, 4, 30, p.trunk);
  g.rect(330, 134, 3, 24, p.trunk);
  g.rect(60, 136, 3, 22, p.trunk);
  g.disc(100, 114, 22, p.foliageMid);
  g.disc(92, 106, 10, p.foliageLight);
  g.disc(298, 112, 24, p.foliageMid);
  g.disc(290, 103, 11, p.foliageLight);
  g.disc(332, 126, 15, p.foliageDeep);
  g.disc(61, 128, 14, p.foliageDeep);
  g.fill(
    Path()
      ..moveTo(0, 162)
      ..quadraticBezierTo(200, 152, 400, 162)
      ..lineTo(400, 220)
      ..lineTo(0, 220)
      ..close(),
    p.lawn,
  );
  // Glasshouse: dome, apex, body, inner plants, ribs, outline, plinth, door.
  g.fill(
    Path()
      ..moveTo(126, 108)
      ..quadraticBezierTo(200, 50, 274, 108)
      ..close(),
    p.glass,
  );
  final apex = _poly([188, 64, 200, 52, 212, 64]);
  g.fill(apex, p.glass);
  g.line(apex, p.glassFrame, 2, join: StrokeJoin.round);
  g.rect(130, 108, 140, 44, p.glass);
  g.disc(146, 142, 9, p.foliageMid.withValues(alpha: 0.6));
  g.disc(166, 137, 12, p.foliageDeep.withValues(alpha: 0.55));
  g.disc(238, 138, 12, p.foliageMid.withValues(alpha: 0.6));
  g.disc(258, 143, 8, p.foliageDeep.withValues(alpha: 0.55));
  g.line(
    Path()
      ..moveTo(178, 150)
      ..quadraticBezierTo(172, 128, 182, 120)
      ..moveTo(224, 150)
      ..quadraticBezierTo(232, 130, 222, 118),
    p.foliageDeep.withValues(alpha: 0.6),
    3,
  );
  g.line(
    _segments([
      150, 108, 150, 152, 170, 108, 170, 152, 230, 108, 230, 152, //
      250, 108, 250, 152, 130, 124, 270, 124,
    ]),
    p.glassFrame,
    1.5,
  );
  g.line(
    Path()
      ..moveTo(150, 108)
      ..quadraticBezierTo(160, 84, 180, 70)
      ..moveTo(250, 108)
      ..quadraticBezierTo(240, 84, 220, 70)
      ..moveTo(175, 108)
      ..quadraticBezierTo(180, 84, 192, 68)
      ..moveTo(225, 108)
      ..quadraticBezierTo(220, 84, 208, 68)
      ..moveTo(200, 108)
      ..lineTo(200, 64),
    p.glassFrame,
    1.5,
  );
  g.line(
    Path()
      ..moveTo(126, 108)
      ..quadraticBezierTo(200, 50, 274, 108),
    p.glassFrame,
    2.5,
  );
  g.line(_poly([130, 108, 270, 108, 270, 152, 130, 152]), p.glassFrame, 2.5);
  g.rect(126, 150, 148, 12, p.stone);
  g.line(
    _segments([
      126, 156, 274, 156, 150, 150, 150, 156, 186, 150, 186, 156, //
      222, 150, 222, 156, 258, 150, 258, 156, 168, 156, 168, 162, //
      240, 156, 240, 162,
    ]),
    p.stoneLine,
    1,
  );
  g.rect(190, 126, 20, 36, p.flowerLight);
  g.line(_poly([190, 126, 210, 126, 210, 162, 190, 162]), p.glassFrame, 2);
  g.line(_segments([200, 126, 200, 162]), p.glassFrame, 1.5);
  g.fill(_poly([190, 162, 210, 162, 252, 220, 148, 220]), p.path);
  g.oval(84, 188, 56, 13, p.foliageDeep);
  g.oval(316, 188, 56, 13, p.foliageDeep);
  for (final c in const [
    [48.0, 186.0],
    [76.0, 182.0],
    [108.0, 190.0],
    [284.0, 184.0],
    [318.0, 192.0],
    [350.0, 186.0],
  ]) {
    g.disc(c[0], c[1], 3, p.accent);
  }
  for (final c in const [
    [62.0, 192.0],
    [92.0, 186.0],
    [124.0, 184.0],
    [300.0, 188.0],
    [334.0, 183.0],
    [362.0, 191.0],
  ]) {
    g.disc(c[0], c[1], 3, p.flowerWarm);
  }
  for (final c in const [
    [38.0, 191.0],
    [100.0, 194.0],
    [270.0, 190.0],
    [340.0, 194.0],
  ]) {
    g.disc(c[0], c[1], 2.5, p.flowerLight);
  }
  g.rect(156, 170, 3, 14, p.trunk);
  g.rect(241, 170, 3, 14, p.trunk);
  g.disc(157.5, 164, 10, p.pineMid);
  g.disc(242.5, 164, 10, p.pineMid);
  final pots = _poly([150, 184, 165, 184, 162, 194, 153, 194]);
  _addPoly(pots, [235, 184, 250, 184, 247, 194, 238, 194]);
  g.fill(pots, p.accent);
  g.fill(
    Path()
      ..moveTo(0, 208)
      ..quadraticBezierTo(70, 198, 148, 210)
      ..lineTo(148, 220)
      ..lineTo(0, 220)
      ..close()
      ..moveTo(252, 210)
      ..quadraticBezierTo(330, 198, 400, 208)
      ..lineTo(400, 220)
      ..lineTo(252, 220)
      ..close(),
    p.ground,
  );
}

// ---------------------------------------------------------------------------
// Scene: canal
// ---------------------------------------------------------------------------

void _canalScene(_Pen g) {
  final p = g.p;
  g.rect(0, 0, _artW, _artH, p.skyCanal);
  g.sun(300, 50, 38, 25, 16, 0.35, 0.6);
  g.cloud(60, 24, 96, 29);
  g.cloud(200, 60, 50, 15);
  g.bird(170, 40, 16, 6);
  g.bird(192, 50, 12, 5);
  g.fill(
    Path()
      ..moveTo(0, 112)
      ..quadraticBezierTo(20, 96, 40, 108)
      ..quadraticBezierTo(60, 90, 85, 106)
      ..quadraticBezierTo(110, 92, 130, 108)
      ..quadraticBezierTo(160, 94, 185, 108)
      ..quadraticBezierTo(215, 96, 240, 108)
      ..quadraticBezierTo(270, 92, 300, 108)
      ..quadraticBezierTo(330, 96, 360, 108)
      ..quadraticBezierTo(385, 98, 400, 108)
      ..lineTo(400, 140)
      ..lineTo(0, 140)
      ..close(),
    p.farShade,
  );
  g.rect(0, 120, _artW, 100, p.middleGround);
  g.fill(
    Path()
      ..moveTo(0, 150)
      ..quadraticBezierTo(60, 140, 124, 150)
      ..lineTo(60, 220)
      ..lineTo(0, 220)
      ..close(),
    p.foliageMid,
  );
  g.fill(_poly([184, 122, 216, 122, 332, 220, 68, 220]), p.water);
  g.fill(_poly([184, 122, 191, 122, 112, 220, 68, 220]), p.waterDeep);
  g.fill(
    Path()
      ..moveTo(174, 124)
      ..quadraticBezierTo(200, 146, 226, 124)
      ..close(),
    p.waterDeep.withValues(alpha: 0.55),
  );
  g.fill(
    Path()
      ..moveTo(154, 126)
      ..lineTo(154, 114)
      ..quadraticBezierTo(200, 94, 246, 114)
      ..lineTo(246, 126)
      ..lineTo(226, 126)
      ..quadraticBezierTo(200, 104, 174, 126)
      ..close(),
    p.stone,
  );
  g.line(
    Path()
      ..moveTo(154, 114)
      ..quadraticBezierTo(200, 94, 246, 114),
    p.stoneLine,
    2.5,
  );
  g.line(
    _segments([
      166, 113, 166, 119, 182, 108, 182, 113, 200, 106, 200, 111, //
      218, 108, 218, 113, 234, 113, 234, 119,
    ]),
    p.stoneLine,
    1.2,
  );
  g.fill(_poly([222, 124, 234, 124, 400, 196, 400, 220, 346, 220]), p.path);
  g.line(
    _segments([
      192, 140, 208, 140, 176, 158, 198, 158, 214, 168, 240, 168, //
      150, 190, 180, 190, 226, 198, 260, 198, 176, 210, 200, 210,
    ]),
    p.cloud.withValues(alpha: p.rippleAlpha),
    1.6,
    cap: StrokeCap.round,
  );
  final hull = Path()
    ..moveTo(146, 178)
    ..quadraticBezierTo(172, 190, 200, 178);
  g.fill(
    Path()
      ..moveTo(146, 178)
      ..quadraticBezierTo(172, 190, 200, 178)
      ..lineTo(195, 186)
      ..quadraticBezierTo(172, 194, 152, 186)
      ..close(),
    p.accent,
  );
  g.rrect(164, 172, 18, 8, 1.5, p.flowerLight);
  g.line(hull, p.trunk, 1.5);
  // Willow.
  g.line(
    Path()
      ..moveTo(72, 176)
      ..quadraticBezierTo(74, 146, 84, 122),
    p.trunk,
    6,
    cap: StrokeCap.round,
  );
  g.line(
    Path()
      ..moveTo(56, 110)
      ..quadraticBezierTo(48, 140, 54, 162)
      ..moveTo(70, 120)
      ..quadraticBezierTo(64, 150, 70, 170)
      ..moveTo(98, 122)
      ..quadraticBezierTo(104, 150, 98, 168)
      ..moveTo(112, 110)
      ..quadraticBezierTo(120, 136, 114, 158),
    p.foliageDeep,
    7,
    cap: StrokeCap.round,
  );
  g.disc(84, 106, 34, p.foliageMid);
  g.disc(74, 96, 16, p.foliageLight);
  g.line(
    Path()
      ..moveTo(62, 124)
      ..quadraticBezierTo(58, 146, 62, 158)
      ..moveTo(84, 132)
      ..quadraticBezierTo(84, 152, 82, 164)
      ..moveTo(106, 124)
      ..quadraticBezierTo(110, 144, 106, 156),
    p.pineFar,
    5,
    cap: StrokeCap.round,
  );
  // Poplars.
  g.rect(328, 108, 3, 26, p.trunk);
  g.rect(354, 112, 3, 24, p.trunk);
  g.rect(378, 118, 3, 22, p.trunk);
  g.oval(329.5, 92, 12, 30, p.foliageDeep);
  g.oval(355.5, 100, 10, 25, p.foliageMid);
  g.oval(379.5, 106, 9, 22, p.foliageDeep);
  for (final c in const [
    [286.0, 138.0],
    [310.0, 146.0],
    [346.0, 152.0],
  ]) {
    g.disc(c[0], c[1], 2.5, p.accent);
  }
  for (final c in const [
    [298.0, 142.0],
    [330.0, 148.0],
    [366.0, 158.0],
  ]) {
    g.disc(c[0], c[1], 2.5, p.flowerLight);
  }
  // Reeds.
  g.line(
    _segments([
      96, 220, 94, 194, 104, 220, 107, 190, 112, 220, 111, 198, //
      40, 220, 42, 196, 30, 220, 27, 200,
    ]),
    p.ground,
    2,
    cap: StrokeCap.round,
  );
  g.oval(94, 191, 2.5, 6, p.trunk);
  g.oval(107, 187, 2.5, 6, p.trunk);
  g.oval(42, 193, 2.5, 6, p.trunk);
}

// ---------------------------------------------------------------------------
// Scene: ridge
// ---------------------------------------------------------------------------

void _ridgeScene(_Pen g) {
  final p = g.p;
  g.rect(0, 0, _artW, _artH, p.skyRidge);
  g.rect(0, 92, _artW, 60, p.skyHaze);
  g.sun(118, 68, 46, 32, 20, 0.25, 0.45);
  g.cloud(290, 22, 84, 25);
  g.cloud(16, 22, 52, 16);
  g.bird(196, 40, 16, 6);
  g.bird(218, 30, 12, 5);
  g.bird(330, 64, 12, 5);
  g.fill(
    _poly([
      0, 120, 40, 96, 80, 112, 130, 66, 170, 100, 210, 78, 262, 40, //
      310, 92, 350, 74, 400, 104, 400, 220, 0, 220,
    ]),
    p.warmRange1,
  );
  final shade1 = _poly([262, 40, 310, 92, 282, 98, 266, 70]);
  _addPoly(shade1, [130, 66, 170, 100, 146, 104, 134, 84]);
  _addPoly(shade1, [350, 74, 400, 104, 372, 106, 354, 90]);
  g.fill(shade1, p.warmShade1);
  final caps = _poly([262, 40, 278, 57, 270, 54, 263, 63, 255, 53, 246, 52]);
  _addPoly(caps, [130, 66, 140, 75, 134, 73, 129, 80, 125, 73, 120, 75]);
  g.fill(caps, p.snow);
  g.fill(
    _poly([
      0, 150, 60, 118, 110, 140, 170, 104, 230, 138, 290, 112, 350, 136, //
      400, 118, 400, 220, 0, 220,
    ]),
    p.warmRange2,
  );
  final shade2 = _poly([170, 104, 230, 138, 196, 142, 176, 122]);
  _addPoly(shade2, [290, 112, 350, 136, 316, 140, 296, 124]);
  _addPoly(shade2, [60, 118, 110, 140, 82, 144, 66, 130]);
  g.fill(shade2, p.warmShade2);
  g.fill(
    Path()
      ..moveTo(0, 176)
      ..quadraticBezierTo(60, 150, 120, 164)
      ..quadraticBezierTo(180, 178, 250, 150)
      ..quadraticBezierTo(320, 122, 400, 160)
      ..lineTo(400, 220)
      ..lineTo(0, 220)
      ..close(),
    p.distantGround,
  );
  g.fill(
    _poly([0, 220, 0, 196, 120, 180, 250, 150, 300, 158, 400, 190, 400, 220]),
    p.ground,
  );
  g.fill(
    _poly([250, 150, 300, 158, 400, 190, 400, 220, 290, 220]),
    p.groundDeep,
  );
  g.line(
    _polyline([56, 220, 132, 200, 88, 192, 192, 175, 160, 169, 246, 152]),
    p.path,
    3.5,
    cap: StrokeCap.round,
    join: StrokeJoin.round,
  );
  g.oval(252, 148, 8, 3.5, p.cairnDark);
  g.oval(252, 143, 6, 3, p.cairnLight);
  g.oval(252, 138.5, 4, 2.5, p.cairnDark);
  g.oval(252, 135, 2.5, 2, p.cairnLight);
  g.pine(316, 138, 28, 56, p.pineDeep);
  g.pine(344, 156, 24, 48, p.pineDeep);
  g.pine(14, 158, 26, 52, p.pineDeep);
  final rocks = _poly([150, 206, 160, 198, 172, 202, 176, 210]);
  _addPoly(rocks, [216, 188, 224, 182, 234, 185, 236, 191]);
  _addPoly(rocks, [374, 208, 382, 201, 392, 205, 392, 210]);
  g.fill(rocks, p.rock);
  g.tuft(100, 212, p.distantGround);
  g.tuft(270, 200, p.distantGround);
}
