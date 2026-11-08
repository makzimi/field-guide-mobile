import 'dart:convert';

import 'package:catalog_impl/catalog_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_fixture_loader.dart';

void main() {
  final loader = ContractFixtureLoader.fromWorkspace();
  List<dynamic> rows(String id) =>
      loader.readObject('$id.json')['walks'] as List;
  final mapper = CatalogMapper();
  final query = QueryWalksImpl();
  final contract = loader.readObject('scenarios.json');
  test('CAT-01 real mapper and query return ordered default routes', () {
    final walks = mapper.mapJson(jsonEncode(rows('catalog-valid')));
    expect(query(walks).map((w) => w.id), [
      'pine-loop',
      'glasshouse-loop',
      'canal-gardens',
    ]);
    expect(
      walks.singleWhere((w) => w.id == 'canal-gardens').distanceMetres,
      3200,
    );
    expect(contract['scenarioIds'], contains('CAT-01'));
  });
  test('CAT-02 includes 60 and excludes 61 at budget 60', () {
    final walks = mapper.mapJson(jsonEncode(rows('catalog-boundary')));
    expect(query(walks).map((w) => w.id), ['exact-hour']);
    expect(query(walks, budgetMinutes: 90).map((w) => w.id), [
      'exact-hour',
      'over-hour',
    ]);
  });
  test('CAT-03 ASCII normalization and title-only filtering', () {
    final walks = mapper.mapJson(jsonEncode(rows('catalog-valid')));
    expect(query.normalize('  PINE \t LOOP '), 'pine loop');
    expect(query(walks, query: '  CANAL  ').map((w) => w.id), [
      'canal-gardens',
    ]);
    expect(query(walks, query: 'gentle'), isEmpty);
    expect(query(walks, query: ' \t ').map((w) => w.id), [
      'pine-loop',
      'glasshouse-loop',
      'canal-gardens',
    ]);
    expect(
      query(mapper.mapJson(jsonEncode(rows('catalog-sort-ties'))))
          .map((w) => w.id),
      ['short', 'later', 'alpha', 'zeta'],
    );
    expect(() => query(walks, budgetMinutes: 61), throwsArgumentError);
  });
  for (final entry in loader.readCatalogs().entries.where(
    (e) => e.key.startsWith('catalog-invalid-'),
  )) {
    test('CAT-08 rejects whole snapshot ${entry.key}', () {
      expect(
        () => mapper.mapJson(jsonEncode(entry.value['walks'])),
        throwsFormatException,
      );
    });
  }
  test('DTO rejects malformed envelopes and types without coercion', () {
    expect(() => mapper.mapJson('{}'), throwsFormatException);
    final row = Map<String, dynamic>.from(rows('catalog-valid').first as Map);
    row['durationMinutes'] = 25.0;
    expect(() => mapper.mapJson(jsonEncode([row])), throwsFormatException);
  });
}
