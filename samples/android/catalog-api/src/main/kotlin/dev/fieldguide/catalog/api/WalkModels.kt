package dev.fieldguide.catalog.api

import java.util.concurrent.CompletableFuture

enum class Terrain { Woodland, Garden, Waterside, Ridge }
enum class Availability { Open, Closed }
enum class ArtKey { Pine, Glasshouse, Canal, Ridge }

data class Walk(
    val id: String,
    val title: String,
    val description: String,
    val durationMinutes: Int,
    val distanceMetres: Int,
    val terrain: Terrain,
    val availability: Availability,
    val artKey: ArtKey,
)

data class WalkSnapshot(val walks: List<Walk>)

/** Elapsed time, never wall-clock time. */
fun interface MonotonicClock { fun nowMs(): Long }

/** Completes with a JSON walks array. Contract wrapper metadata stays outside production. */
fun interface CatalogSource { fun loadWalks(): CompletableFuture<String> }

/** writeIds must atomically replace the durable set or fail without changing it. */
interface BookmarkStorage {
    fun loadIds(): CompletableFuture<Set<String>>
    fun writeIds(ids: Set<String>): CompletableFuture<Unit>
}

enum class CatalogError { SourceUnavailable, InvalidCatalog }
enum class BookmarkLoadState { Loading, Loaded, Error }
enum class BookmarkWriteState { Idle, Saving, Error }
enum class BookmarkResult {
    Saved, Removed, AlreadySaved, NotSaved, Busy, WriteFailed,
    RejectedClosed, RejectedStale, RejectedMissing, RejectedStorageUnavailable,
}

interface WalkRepository {
    val snapshot: WalkSnapshot?
    val fetchedAtMs: Long?
    val error: CatalogError?
    val refreshing: Boolean
    val savedIds: Set<String>
    val savedCount: Int?
    val bookmarkLoadState: BookmarkLoadState
    val bookmarkWriteState: BookmarkWriteState
    fun ageMs(): Long?
    fun isFresh(): Boolean
    fun openList(): CompletableFuture<Unit>
    fun refresh(): CompletableFuture<Unit>
    fun loadBookmarks(): CompletableFuture<Unit>
    fun addBookmark(id: String): CompletableFuture<BookmarkResult>
    fun removeBookmark(id: String): CompletableFuture<BookmarkResult>
    fun retryBookmarkWrite(): CompletableFuture<BookmarkResult>
}

/** Contracts available to feature-catalog without a dependency on catalog-impl. */
interface WalkQuery {
    fun normalize(value: String): String
    fun run(walks: List<Walk>, query: String, budgetMinutes: Int): List<Walk>
}

fun interface AddBookmarkUseCase {
    fun run(id: String): CompletableFuture<BookmarkResult>
}

fun interface RemoveBookmarkUseCase {
    fun run(id: String): CompletableFuture<BookmarkResult>
}
