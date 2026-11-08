import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:catalog_api/catalog_api.dart';

/// Validates transport types before any domain object enters the cache.
final class WalkDto {
  const WalkDto(
    this.id,
    this.title,
    this.description,
    this.minutes,
    this.metres,
    this.terrain,
    this.availability,
    this.artKey,
  );
  final String id, title, description;
  final int minutes, metres;
  final Terrain terrain;
  final Availability availability;
  final ArtKey artKey;
  factory WalkDto.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Walk must be an object');
    }
    String text(String key) {
      final v = value[key];
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('Invalid $key');
      }
      return v;
    }

    int positive(String key) {
      final v = value[key];
      if (v is! int || v <= 0) throw FormatException('Invalid $key');
      return v;
    }

    T enumeration<T extends Enum>(String key, List<T> values) {
      final raw = text(key);
      for (final v in values) {
        if (v.name == raw) return v;
      }
      throw FormatException('Unknown $key');
    }

    final id = text('id');
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(id)) {
      throw const FormatException('Invalid ID');
    }
    return WalkDto(
      id,
      text('title'),
      text('description'),
      positive('durationMinutes'),
      positive('distanceMetres'),
      enumeration('terrain', Terrain.values),
      enumeration('availability', Availability.values),
      enumeration('artKey', ArtKey.values),
    );
  }
  Walk toDomain() => Walk(
    id: id,
    title: title,
    description: description,
    durationMinutes: minutes,
    distanceMetres: metres,
    terrain: terrain,
    availability: availability,
    artKey: artKey,
  );
}

final class CatalogMapper {
  List<Walk> mapJson(String text) {
    final raw = jsonDecode(text);
    if (raw is! List) throw const FormatException('Catalog must be a list');
    final ids = <String>{};
    final walks = <Walk>[];
    for (final value in raw) {
      final dto = WalkDto.fromJson(value);
      if (!ids.add(dto.id)) throw const FormatException('Duplicate ID');
      walks.add(dto.toDomain());
    }
    return List.unmodifiable(walks);
  }
}

final class QueryWalksImpl implements QueryWalks {
  @override
  String normalize(String query) => query
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase());
  @override
  List<Walk> call(
    List<Walk> walks, {
    int budgetMinutes = 60,
    String query = '',
  }) {
    if (![15, 30, 60, 90].contains(budgetMinutes)) {
      throw ArgumentError.value(budgetMinutes, 'budgetMinutes');
    }
    final normalized = normalize(query);
    final matches = walks
        .where(
          (w) =>
              w.durationMinutes <= budgetMinutes &&
              normalize(w.title).contains(normalized),
        )
        .toList();
    matches.sort((a, b) {
      final duration = a.durationMinutes.compareTo(b.durationMinutes);
      if (duration != 0) return duration;
      final title = normalize(a.title).compareTo(normalize(b.title));
      return title != 0 ? title : a.id.compareTo(b.id);
    });
    return List.unmodifiable(matches);
  }
}

/// Process-only catalog cache; bookmark I/O has a separate readiness policy.
final class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl({
    required this.source,
    required this.storage,
    required this.clock,
    CatalogMapper? mapper,
  }) : mapper = mapper ?? CatalogMapper();
  final CatalogSource source;
  final BookmarkStorage storage;
  final MonotonicClock clock;
  final CatalogMapper mapper;
  final _changes = StreamController<CatalogState>.broadcast(sync: true);
  CatalogState _state = CatalogState();
  final _notifications = Queue<CatalogState>();
  bool _emitting = false;
  CatalogSnapshot? _snapshot;
  bool _refreshing = false, _disposed = false;
  String? _catalogError, _storageError, _pendingId, _bookmarkError;
  CatalogFailure? _catalogFailure;
  String? _bookmarkErrorId;
  Set<String> _savedIds = {};
  StorageStatus _storageStatus = StorageStatus.loading;
  int _request = 0, _storageRequest = 0;
  Future<void>? _inflight;
  @override
  CatalogState get state => _state;
  @override
  Stream<CatalogState> get changes => _changes.stream;
  void _publish() {
    if (_disposed) return;
    _state = CatalogState(
      snapshot: _snapshot,
      refreshing: _refreshing,
      catalogError: _catalogError,
      catalogFailure: _catalogFailure,
      storageStatus: _storageStatus,
      savedIds: _savedIds,
      storageError: _storageError,
      pendingId: _pendingId,
      bookmarkError: _bookmarkError,
      bookmarkErrorId: _bookmarkErrorId,
      activeRequest: _request,
    );
    _notifications.add(_state);
    if (_emitting) return;
    _emitting = true;
    try {
      while (!_disposed && _notifications.isNotEmpty) {
        _changes.add(_notifications.removeFirst());
      }
    } finally {
      _emitting = false;
      if (_disposed) {
        _notifications.clear();
        unawaited(_changes.close());
      }
    }
  }

  @override
  Future<void> open() {
    if (_disposed) return Future.value();
    if (_refreshing) return _inflight ?? Future.value();
    if (_snapshot?.isFresh(clock.nowMs) ?? false) return Future.value();
    return refresh();
  }

  @override
  Future<void> refresh() {
    if (_disposed) return Future.value();
    final request = ++_request;
    _refreshing = true;
    _catalogError = null;
    _catalogFailure = null;
    _publish();
    // A synchronous observer can start a newer request or dispose us.
    if (_disposed || request != _request) return Future.value();
    return _inflight = _fetch(request);
  }

  Future<void> _fetch(int request) async {
    try {
      final json = await source.load();
      if (_disposed || request != _request) return;
      final walks = mapper.mapJson(json);
      _snapshot = CatalogSnapshot(walks, clock.nowMs);
      _catalogError = null;
    } on FormatException {
      if (_disposed || request != _request) return;
      _catalogFailure = CatalogFailure.invalidCatalog;
      _catalogError = 'The walk catalog is invalid. Try again.';
    } catch (_) {
      if (_disposed || request != _request) return;
      _catalogFailure = CatalogFailure.sourceUnavailable;
      _catalogError = 'Could not refresh walks. Try again.';
    }
    if (_disposed || request != _request) return;
    _refreshing = false;
    _publish();
  }

  @override
  Future<void> loadBookmarks() async {
    if (_disposed || _pendingId != null) return;
    final request = ++_storageRequest;
    _storageStatus = StorageStatus.loading;
    _storageError = null;
    _publish();
    try {
      final ids = await storage.read();
      if (_disposed || request != _storageRequest) return;
      _savedIds = Set.of(ids);
      _storageStatus = StorageStatus.loaded;
    } catch (_) {
      if (_disposed || request != _storageRequest) return;
      _storageStatus = StorageStatus.failed;
      _storageError = 'Could not load saved walks.';
    }
    _publish();
  }

  @override
  Future<BookmarkResult> add(String id) => _change(id, true);
  @override
  Future<BookmarkResult> remove(String id) => _change(id, false);
  Future<BookmarkResult> _change(String id, bool save) async {
    if (_disposed || _storageStatus != StorageStatus.loaded) {
      return BookmarkResult.storageNotReady;
    }
    if (_pendingId != null) return BookmarkResult.busy;
    final walk = _snapshot?.find(id);
    if (save) {
      if (walk == null) return BookmarkResult.unavailable;
      if (walk.availability == Availability.closed) {
        return BookmarkResult.rejectedClosed;
      }
      if (!_snapshot!.isFresh(clock.nowMs)) return BookmarkResult.rejectedStale;
      if (_savedIds.contains(id)) return BookmarkResult.saved;
    } else if (!_savedIds.contains(id)) {
      return BookmarkResult.removed;
    }
    final next = Set<String>.of(_savedIds);
    if (save) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _pendingId = id;
    _bookmarkError = null;
    _bookmarkErrorId = null;
    _publish();
    try {
      await storage.write(Set.unmodifiable(next));
      if (_disposed) {
        return save ? BookmarkResult.saved : BookmarkResult.removed;
      }
      _savedIds = next;
      _pendingId = null;
      _publish();
      return save ? BookmarkResult.saved : BookmarkResult.removed;
    } catch (_) {
      if (!_disposed) {
        _pendingId = null;
        _bookmarkError = 'Could not update saved walks. Try again.';
        _bookmarkErrorId = id;
        _publish();
      }
      return BookmarkResult.failed;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _notifications.clear();
    // Closing a synchronous controller inside its listener is forbidden.
    if (!_emitting) unawaited(_changes.close());
  }
}

final class ChangeBookmarkImpl implements ChangeBookmark {
  ChangeBookmarkImpl(this.repository);
  final CatalogRepository repository;
  @override
  Future<BookmarkResult> call(String id, {required bool save}) =>
      save ? repository.add(id) : repository.remove(id);
}
