import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Open light', type: StatusPill)
Widget openLight(BuildContext context) =>
    previewSurface(const StatusPill(closed: false), Brightness.light);

@widgetbook.UseCase(name: 'Open dark', type: StatusPill)
Widget openDark(BuildContext context) =>
    previewSurface(const StatusPill(closed: false), Brightness.dark);

@widgetbook.UseCase(name: 'Closed light', type: StatusPill)
Widget closedLight(BuildContext context) =>
    previewSurface(const StatusPill(closed: true), Brightness.light);

@widgetbook.UseCase(name: 'Closed dark', type: StatusPill)
Widget closedDark(BuildContext context) =>
    previewSurface(const StatusPill(closed: true), Brightness.dark);

Widget previewSurface(Widget child, Brightness brightness) =>
    PreviewSurface(brightness: brightness, child: child);

// A unique root lets the golden runner capture this surface, not an outer Theme.
class PreviewSurface extends StatelessWidget {
  const PreviewSurface({
    required this.child,
    required this.brightness,
    super.key,
  });
  final Widget child;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Theme(
      data: fieldGuideTheme(brightness),
      child: Material(child: Center(child: child)),
    ),
  );
}
