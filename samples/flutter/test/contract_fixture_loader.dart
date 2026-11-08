import 'dart:convert';
import 'dart:io';

/// Test-only access to the single hand-authored shared contract directory.
/// Invalid catalogs are deliberately decoded, without a production mapper.
class ContractFixtureLoader {
  ContractFixtureLoader(this.directory);

  final Directory directory;

  factory ContractFixtureLoader.fromWorkspace() {
    var ancestor = Directory.current.absolute;
    while (true) {
      final candidate = Directory('${ancestor.path}/samples/contract');
      if (File('${candidate.path}/scenarios.json').existsSync()) {
        return ContractFixtureLoader(candidate);
      }
      final parent = ancestor.parent;
      if (parent.path == ancestor.path) {
        throw StateError(
          'Cannot locate samples/contract from working directory',
        );
      }
      ancestor = parent;
    }
  }

  Map<String, dynamic> readObject(String fileName) {
    final value = jsonDecode(
      File('${directory.path}/$fileName').readAsStringSync(),
    );
    if (value is! Map<String, dynamic>) {
      throw FormatException('$fileName must contain a JSON object');
    }
    return value;
  }

  Map<String, Map<String, dynamic>> readCatalogs() {
    final files = directory.listSync().whereType<File>().where((file) {
      final name = file.uri.pathSegments.last;
      return name.startsWith('catalog-') && name.endsWith('.json');
    }).toList()..sort((a, b) => a.path.compareTo(b.path));
    final catalogs = <String, Map<String, dynamic>>{};
    for (final file in files) {
      final catalog = readObject(file.uri.pathSegments.last);
      final id = catalog['fixtureId'];
      if (id is! String || catalogs.containsKey(id)) {
        throw FormatException('Missing or duplicate fixtureId in ${file.path}');
      }
      if (catalog['kind'] != 'catalog' || catalog['walks'] is! List) {
        throw FormatException('Invalid catalog envelope in ${file.path}');
      }
      catalogs[id] = catalog;
    }
    return catalogs;
  }
}
