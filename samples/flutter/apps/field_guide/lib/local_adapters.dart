import 'dart:convert';

import 'package:catalog_api/catalog_api.dart';
import 'package:flutter/services.dart';

final class ProcessMonotonicClock implements MonotonicClock {
  final _watch = Stopwatch()..start();
  @override
  int get nowMs => _watch.elapsedMilliseconds;
}

final class BundledCatalogSource implements CatalogSource {
  BundledCatalogSource({
    this.fixture = 'catalog-valid',
    this.failFirst = false,
    AssetBundle? bundle,
  }) : bundle = bundle ?? rootBundle;
  final String fixture;
  final bool failFirst;
  final AssetBundle bundle;
  bool _attempted = false;
  @override
  Future<String> load() async {
    if (failFirst && !_attempted) {
      _attempted = true;
      throw StateError('Demonstration source failure');
    }
    _attempted = true;
    if (!RegExp(r'^catalog-[a-z-]+$').hasMatch(fixture)) {
      throw ArgumentError.value(fixture, 'fixture');
    }
    final envelope = jsonDecode(
      await bundle.loadString('assets/generated/$fixture.json'),
    );
    if (envelope is! Map<String, dynamic> || envelope['walks'] is! List) {
      throw const FormatException('Invalid catalog asset');
    }
    return jsonEncode(envelope['walks']);
  }
}

final class LocalBookmarkStorage implements BookmarkStorage {
  LocalBookmarkStorage({
    this.channel = const MethodChannel('field_guide/bookmarks'),
  });
  final MethodChannel channel;
  @override
  Future<Set<String>> read() async {
    final raw = await channel.invokeMethod<Object?>('read');
    if (raw is! List || raw.any((id) => id is! String || id.trim().isEmpty)) {
      throw const FormatException('Invalid saved walks');
    }
    return Set<String>.unmodifiable(raw.cast<String>());
  }

  @override
  Future<void> write(Set<String> ids) async {
    final values = ids.toList()..sort();
    await channel.invokeMethod<void>('write', values);
  }
}
