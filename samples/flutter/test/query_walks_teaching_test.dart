import 'package:catalog_api/catalog_api.dart';
import 'package:catalog_impl/catalog_impl.dart';
import 'package:flutter_test/flutter_test.dart';

// Pure query examples: no mapper, repository, storage or widget is involved.
Walk walk({required int minutes}) => Walk(
  id: 'walk-$minutes',
  title: '$minutes minute walk',
  description: 'An open route',
  durationMinutes: minutes,
  distanceMetres: 1000,
  terrain: Terrain.garden,
  availability: Availability.open,
  artKey: ArtKey.glasshouse,
);

void main() {
  test('query WHEN budget is 60 SHOULD keep only 60', () {
    final oneHour = walk(minutes: 60);
    final tooLong = walk(minutes: 61);
    final sut = QueryWalksImpl();

    final visible = sut([oneHour, tooLong], budgetMinutes: 60);

    expect(visible, [oneHour]);
  });
}
