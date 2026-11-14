import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import 'widgetbook.directories.g.dart';

void main() => runApp(const PreviewCatalog());

@widgetbook.App()
class PreviewCatalog extends StatelessWidget {
  const PreviewCatalog({super.key});

  @override
  Widget build(BuildContext context) =>
      Widgetbook.material(directories: directories);
}
