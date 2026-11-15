import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('features SHOULD NOT depend on any _impl package', () {
    final manifests = Glob('packages/feature_*/pubspec.yaml').listSync();
    expect(manifests, isNotEmpty);

    for (final file in manifests) {
      final manifest = loadYaml(File(file.path).readAsStringSync()) as YamlMap;
      final deps = manifest['dependencies'] as YamlMap;
      final impls = deps.keys.where((name) => '$name'.endsWith('_impl'));
      expect(impls, isEmpty, reason: file.path);
    }
  });
}
