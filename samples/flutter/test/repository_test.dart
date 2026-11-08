import 'dart:async';
import 'dart:convert';

import 'package:catalog_api/catalog_api.dart';
import 'package:catalog_impl/catalog_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_fixture_loader.dart';

final class FakeClock implements MonotonicClock {
  int value = 1000000;
  @override
  int get nowMs => value;
}

final class DeferredSource implements CatalogSource {
  final requests = <Completer<String>>[];
  @override
  Future<String> load() {
    final c = Completer<String>();
    requests.add(c);
    return c.future;
  }
}

final class MemoryStorage implements BookmarkStorage {
  Set<String> ids = {};
  bool failRead = false, failWrite = false;
  Completer<void>? pending;
  int writes = 0;
  @override
  Future<Set<String>> read() async {
    if (failRead) throw StateError('read');
    return Set.of(ids);
  }

  @override
  Future<void> write(Set<String> ids) async {
    writes++;
    if (pending != null) await pending!.future;
    if (failWrite) throw StateError('write');
    this.ids = Set.of(ids);
  }
}

String fixture(String id) => jsonEncode(
  ContractFixtureLoader.fromWorkspace().readObject('$id.json')['walks'],
);

void main() {
  late FakeClock clock;
  late DeferredSource source;
  late MemoryStorage storage;
  late CatalogRepositoryImpl repo;
  setUp(() {
    clock = FakeClock();
    source = DeferredSource();
    storage = MemoryStorage();
    repo = CatalogRepositoryImpl(
      source: source,
      storage: storage,
      clock: clock,
    );
  });
  tearDown(() => repo.dispose());
  Future<void> load([String id = 'catalog-valid']) async {
    final future = repo.open();
    if (source.requests.isNotEmpty) source.requests.last.complete(fixture(id));
    await future;
    await repo.loadBookmarks();
  }

  test('CAT-01 loading starts, winning valid load sets timestamp and immutable snapshot', () async {
    final pending = repo.open();
    expect(repo.state.refreshing, true);
    source.requests.single.complete(fixture('catalog-valid'));
    await pending;
    expect(repo.state.snapshot?.fetchedAtMs, 1000000);
    expect(repo.state.snapshot?.walks.map((w) => w.id), [
      'pine-loop',
      'glasshouse-loop',
      'canal-gardens',
      'ridge-path',
    ]);
    expect(() => repo.state.snapshot!.walks.clear(), throwsUnsupportedError);
  });
  test(
    'CAT-05 initial error and retry; CAT-06 cache retention and TTL boundary',
    () async {
      final first = repo.open();
      expect(source.requests, hasLength(1));
      source.requests.last.completeError(StateError('source'));
      await first;
      expect(repo.state.snapshot, null);
      expect(repo.state.catalogError, isNotNull);
      expect(repo.state.catalogFailure, CatalogFailure.sourceUnavailable);
      await load();
      final snapshot = repo.state.snapshot!;
      clock.value = 1299999;
      await repo.open();
      expect(source.requests, hasLength(2));
      expect(snapshot.isFresh(clock.nowMs), true);
      clock.value = 1300000;
      final refresh = repo.open();
      final repeated = repo.open();
      expect(source.requests, hasLength(3));
      source.requests.last.completeError(StateError('source'));
      await refresh;
      await repeated;
      expect(identical(repo.state.snapshot, snapshot), true);
      expect(repo.state.snapshot!.fetchedAtMs, 1000000);
      expect(snapshot.isFresh(clock.nowMs), false);
    },
  );
  test(
    'CAT-07 newest initiated refresh alone commits data, time or error',
    () async {
      await load();
      storage.ids = {'canal-gardens'};
      await repo.loadBookmarks();
      final a = repo.refresh(), b = repo.refresh();
      expect(source.requests, hasLength(3));
      clock.value = 1000150;
      source.requests[2].complete(fixture('catalog-changed'));
      await b;
      clock.value = 1000200;
      source.requests[1].complete(fixture('catalog-boundary'));
      await a;
      expect(repo.state.snapshot?.walks.map((w) => w.id), [
        'pine-loop',
        'glasshouse-loop',
        'river-walk',
        'ridge-path',
      ]);
      expect(repo.state.snapshot?.fetchedAtMs, 1000150);
      expect(repo.state.savedIds, {'canal-gardens'});
      final old = repo.refresh(), latest = repo.refresh();
      source.requests.last.complete(fixture('catalog-valid'));
      await latest;
      source.requests[source.requests.length - 2].completeError(
        StateError('old'),
      );
      await old;
      expect(repo.state.catalogError, null);
      expect(repo.state.snapshot?.find('canal-gardens'), isNotNull);
    },
  );
  test(
    'CAT-08 rejects all invalid refreshes and retains the exact good snapshot',
    () async {
      await load();
      final snapshot = repo.state.snapshot;
      for (final name
          in ContractFixtureLoader.fromWorkspace().readCatalogs().keys.where(
            (k) => k.startsWith('catalog-invalid-'),
          )) {
        final pending = repo.refresh();
        source.requests.last.complete(fixture(name));
        await pending;
        expect(identical(repo.state.snapshot, snapshot), true, reason: name);
        expect(repo.state.catalogError, isNotNull, reason: name);
        expect(
          repo.state.catalogFailure,
          CatalogFailure.invalidCatalog,
          reason: name,
        );
        expect(repo.state.snapshot?.find('new-valid'), null, reason: name);
      }
    },
  );
  test('SAVE-01, SAVE-02 atomic persist then commit, duplicate tap and failed retry', () async {
    await load();
    storage.pending = Completer<void>();
    final pending = ChangeBookmarkImpl(repo)('canal-gardens', save: true);
    expect(repo.state.pendingId, 'canal-gardens');
    expect(repo.state.savedIds, isEmpty);
    expect(await repo.add('canal-gardens'), BookmarkResult.busy);
    expect(storage.writes, 1);
    storage.pending!.complete();
    expect(await pending, BookmarkResult.saved);
    expect(repo.state.savedIds, {'canal-gardens'});
    expect(storage.ids, {'canal-gardens'});
    storage.pending = null;
    storage.failWrite = true;
    expect(await repo.remove('canal-gardens'), BookmarkResult.failed);
    expect(repo.state.savedIds, {'canal-gardens'});
    expect(repo.state.bookmarkError, isNotNull);
    storage.failWrite = false;
    expect(await repo.remove('canal-gardens'), BookmarkResult.removed);
    expect(storage.ids, isEmpty);
  });
  test('SAVE-03, SAVE-04 and CLOCK-01 direct execution checks closed then stale; removal allowed', () async {
    await load();
    expect(await repo.add('glasshouse-loop'), BookmarkResult.rejectedClosed);
    clock.value = 1299999;
    expect(await repo.add('canal-gardens'), BookmarkResult.saved);
    clock.value = 1300000;
    expect(await repo.add('pine-loop'), BookmarkResult.rejectedStale);
    expect(await repo.add('glasshouse-loop'), BookmarkResult.rejectedClosed);
    expect(await repo.remove('canal-gardens'), BookmarkResult.removed);
    expect(await repo.add('unknown'), BookmarkResult.unavailable);
  });
  test(
    'SAVE-05 storage adapter recreation reloads IDs but catalog starts empty',
    () async {
      await load();
      await repo.add('canal-gardens');
      repo.dispose();
      repo = CatalogRepositoryImpl(
        source: source,
        storage: storage,
        clock: clock,
      );
      expect(repo.state.snapshot, null);
      await repo.loadBookmarks();
      expect(repo.state.savedIds, {'canal-gardens'});
    },
  );
  test(
    'SAVE-06 storage failure gates additions and removals until retry',
    () async {
      await load();
      storage.failRead = true;
      await repo.loadBookmarks();
      expect(repo.state.storageStatus, StorageStatus.failed);
      expect(await repo.add('canal-gardens'), BookmarkResult.storageNotReady);
      expect(
        await repo.remove('canal-gardens'),
        BookmarkResult.storageNotReady,
      );
      expect(repo.state.snapshot?.walks, hasLength(4));
      storage.failRead = false;
      await repo.loadBookmarks();
      expect(await repo.add('canal-gardens'), BookmarkResult.saved);
    },
  );
  test('dispose suppresses late repository publication', () async {
    final events = <CatalogState>[];
    final sub = repo.changes.listen(events.add);
    final request = repo.open();
    final count = events.length;
    repo.dispose();
    if (source.requests.isNotEmpty) {
      source.requests.last.complete(fixture('catalog-valid'));
    }
    await request;
    expect(events, hasLength(count));
    await sub.cancel();
  });
  test('refresh initiated by an observer queues safely and latest request finishes', () async {
    final listenerErrors = <Object>[];
    Future<void>? nested;
    bool initiated = false;
    final subscription = repo.changes.listen((state) {
      if (state.refreshing && !initiated) {
        initiated = true;
        try {
          nested = repo.refresh();
        } catch (error) {
          listenerErrors.add(error);
        }
      }
    });
    final outer = repo.refresh();
    for (final request in source.requests) {
      request.complete(fixture('catalog-valid'));
    }
    await outer;
    if (nested != null) await nested;
    expect(listenerErrors, isEmpty);
    expect(repo.state.refreshing, false);
    expect(repo.state.snapshot?.find('canal-gardens'), isNotNull);
    expect(repo.state.activeRequest, 2);
    await subscription.cancel();
  });
  test(
    'an observer can dispose its repository without synchronous close error',
    () async {
      final listenerErrors = <Object>[];
      int notifications = 0;
      final subscription = repo.changes.listen((_) {
        notifications++;
        try {
          repo.dispose();
        } catch (error) {
          listenerErrors.add(error);
        }
      });
      final request = repo.refresh();
      for (final pending in source.requests) {
        pending.complete(fixture('catalog-valid'));
      }
      await request;
      expect(listenerErrors, isEmpty);
      expect(notifications, 1);
      await subscription.cancel();
    },
  );
}
