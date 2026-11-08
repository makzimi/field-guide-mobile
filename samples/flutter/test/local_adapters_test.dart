import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_guide/local_adapters.dart';

import 'contract_fixture_loader.dart';

final class FixtureBundle extends CachingAssetBundle {
  String? requested;
  @override
  Future<ByteData> load(String key) async {
    requested = key;
    final bytes = utf8.encode(
      jsonEncode(
        ContractFixtureLoader.fromWorkspace().readObject(key.split('/').last),
      ),
    );
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('field_guide/bookmarks');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'bundled source unwraps only walk payload; explicit fail-first retries',
    () async {
      final bundle = FixtureBundle();
      final source = BundledCatalogSource(bundle: bundle, failFirst: true);
      await expectLater(source.load(), throwsStateError);
      final payload = jsonDecode(await source.load()) as List;
      expect(payload.map((w) => w['id']), [
        'pine-loop',
        'glasshouse-loop',
        'canal-gardens',
        'ridge-path',
      ]);
      expect(bundle.requested, 'assets/generated/catalog-valid.json');
    },
  );
  test(
    'storage adapter loads canonical IDs and commits a sorted entire set',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'read') return ['canal-gardens', 'pine-loop'];
            return null;
          });
      final adapter = LocalBookmarkStorage();
      expect(await adapter.read(), {'canal-gardens', 'pine-loop'});
      await adapter.write({'pine-loop', 'canal-gardens'});
      expect(calls.map((c) => c.method), ['read', 'write']);
      expect(calls.last.arguments, ['canal-gardens', 'pine-loop']);
    },
  );
  test('storage adapter rejects malformed read and propagates durable-write failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') return ['canal-gardens', 9];
          throw PlatformException(code: 'storage-write');
        });
    final adapter = LocalBookmarkStorage();
    await expectLater(adapter.read(), throwsFormatException);
    await expectLater(
      adapter.write({'pine-loop'}),
      throwsA(isA<PlatformException>()),
    );
  });
}
