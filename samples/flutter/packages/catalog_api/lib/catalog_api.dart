import 'dart:async';

enum Terrain { woodland, garden, waterside, ridge }

enum Availability { open, closed }

enum ArtKey { pine, glasshouse, canal, ridge }

enum CatalogFailure { sourceUnavailable, invalidCatalog }

enum StorageStatus { loading, loaded, failed }

enum BookmarkResult {
  saved,
  removed,
  rejectedClosed,
  rejectedStale,
  unavailable,
  storageNotReady,
  busy,
  failed,
}

final class Walk {
  const Walk({
    required this.id,
    required this.title,
    required this.description,
    required this.durationMinutes,
    required this.distanceMetres,
    required this.terrain,
    required this.availability,
    required this.artKey,
  });
  final String id, title, description;
  final int durationMinutes, distanceMetres;
  final Terrain terrain;
  final Availability availability;
  final ArtKey artKey;
}

abstract interface class MonotonicClock {
  int get nowMs;
}

abstract interface class CatalogSource {
  Future<String> load();
}

abstract interface class BookmarkStorage {
  Future<Set<String>> read();

  /// Completes only once the entire replacement set is durably committed.
  Future<void> write(Set<String> ids);
}

final class CatalogSnapshot {
  CatalogSnapshot(Iterable<Walk> walks, this.fetchedAtMs)
    : walks = List.unmodifiable(walks);
  final List<Walk> walks;
  final int fetchedAtMs;
  static const ttlMs = 300000;
  bool isFresh(int nowMs) => nowMs - fetchedAtMs < ttlMs;
  Walk? find(String id) {
    for (final walk in walks) {
      if (walk.id == id) return walk;
    }
    return null;
  }
}

final class CatalogState {
  CatalogState({
    this.snapshot,
    this.refreshing = false,
    this.catalogError,
    this.catalogFailure,
    this.storageStatus = StorageStatus.loading,
    Set<String> savedIds = const {},
    this.storageError,
    this.pendingId,
    this.bookmarkError,
    this.bookmarkErrorId,
    this.activeRequest = 0,
  }) : savedIds = Set.unmodifiable(savedIds);
  final CatalogSnapshot? snapshot;
  final bool refreshing;
  final CatalogFailure? catalogFailure;
  final String? catalogError,
      storageError,
      pendingId,
      bookmarkError,
      bookmarkErrorId;
  final StorageStatus storageStatus;
  final Set<String> savedIds;
  final int activeRequest;
}

abstract interface class CatalogRepository {
  CatalogState get state;
  Stream<CatalogState> get changes;
  Future<void> open();
  Future<void> refresh();
  Future<void> loadBookmarks();
  Future<BookmarkResult> add(String id);
  Future<BookmarkResult> remove(String id);
  void dispose();
}

abstract interface class QueryWalks {
  String normalize(String query);
  List<Walk> call(
    List<Walk> walks, {
    int budgetMinutes = 60,
    String query = '',
  });
}

abstract interface class ChangeBookmark {
  Future<BookmarkResult> call(String id, {required bool save});
}
