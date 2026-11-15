import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('features SHOULD NOT depend on any _impl package', () {
    final features = Directory('packages')
        .listSync()
        .whereType<Directory>()
        .where((package) => package.uri.pathSegments
            .lastWhere((segment) => segment.isNotEmpty)
            .startsWith('feature_'));
    expect(features, isNotEmpty);

    for (final feature in features) {
      final file = File('${feature.path}/pubspec.yaml');
      final manifest = loadYaml(file.readAsStringSync()) as YamlMap;
      final dependencies = manifest['dependencies'] as YamlMap;

      expect(
        dependencies.keys.where((name) => '$name'.endsWith('_impl')),
        isEmpty,
        reason: '${feature.path} must depend on _api packages',
      );
    }
  });
}
