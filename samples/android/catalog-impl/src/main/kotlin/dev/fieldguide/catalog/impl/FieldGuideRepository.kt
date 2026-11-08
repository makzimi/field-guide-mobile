package dev.fieldguide.catalog.impl

import dev.fieldguide.catalog.api.*
import java.util.concurrent.CompletableFuture

/** Process-local catalog and bookmark policy. I/O is confined to two injected ports. */
class FieldGuideRepository(
    private val source: CatalogSource,
    private val storage: BookmarkStorage,
    private val clock: MonotonicClock,
    private val mapper: CatalogMapper,
) : WalkRepository {
    private val lock = Any()
    private var currentSnapshot: WalkSnapshot? = null
    private var currentFetchedAt: Long? = null
    private var currentError: CatalogError? = null
    private var currentRefresh: CompletableFuture<Unit>? = null
    private var refreshVersion = 0L
    private var saved = emptySet<String>()
    private var loadState = BookmarkLoadState.Loading
    private var writeState = BookmarkWriteState.Idle
    private var currentWrite: CompletableFuture<BookmarkResult>? = null
    private var pendingWrite: WriteIntent? = null
    private var loadVersion = 0L

    override val snapshot: WalkSnapshot? get() = synchronized(lock) { currentSnapshot }
    override val fetchedAtMs: Long? get() = synchronized(lock) { currentFetchedAt }
    override val error: CatalogError? get() = synchronized(lock) { currentError }
    override val refreshing: Boolean get() = synchronized(lock) { currentRefresh != null }
    override val savedIds: Set<String> get() = synchronized(lock) { saved }
    override val savedCount: Int? get() = synchronized(lock) {
        if (loadState != BookmarkLoadState.Loaded) null
        else currentSnapshot?.walks?.count { it.id in saved }
    }
    override val bookmarkLoadState: BookmarkLoadState get() = synchronized(lock) { loadState }
    override val bookmarkWriteState: BookmarkWriteState get() = synchronized(lock) { writeState }

    override fun ageMs(): Long? = synchronized(lock) {
        currentFetchedAt?.let { (clock.nowMs() - it).coerceAtLeast(0) }
    }

    override fun isFresh(): Boolean = synchronized(lock) {
        val at = currentFetchedAt ?: return@synchronized false
        val age = clock.nowMs() - at
        currentSnapshot != null && age >= 0 && age < TTL_MS
    }

    override fun openList(): CompletableFuture<Unit> = synchronized(lock) {
        if (isFresh()) CompletableFuture.completedFuture(Unit)
        else currentRefresh ?: refresh()
    }

    override fun refresh(): CompletableFuture<Unit> {
        val version: Long
        val completion = CompletableFuture<Unit>()
        synchronized(lock) {
            version = ++refreshVersion
            currentRefresh = completion
            currentError = null
        }
        val request = try { source.loadWalks() } catch (e: RuntimeException) { CompletableFuture.failedFuture(e) }
        request.whenComplete { body, failure ->
            var mapped: WalkSnapshot? = null
            var outcome: CatalogError? = null
            if (failure != null) outcome = CatalogError.SourceUnavailable
            else try { mapped = WalkSnapshot(mapper.mapWalks(body)) }
            catch (e: RuntimeException) { outcome = CatalogError.InvalidCatalog }
            synchronized(lock) {
                if (version == refreshVersion) {
                    if (mapped != null) {
                        currentSnapshot = mapped
                        currentFetchedAt = clock.nowMs()
                        currentError = null
                    } else currentError = outcome
                    currentRefresh = null
                }
            }
            completion.complete(Unit)
        }
        return completion
    }

    override fun loadBookmarks(): CompletableFuture<Unit> {
        val version: Long
        synchronized(lock) {
            // Do not read a pre-commit set and later publish it over a successful write.
            if (writeState == BookmarkWriteState.Saving) {
                return checkNotNull(currentWrite).thenCompose { loadBookmarks() }
            }
            version = ++loadVersion
            loadState = BookmarkLoadState.Loading
        }
        val request = try { storage.loadIds() } catch (e: RuntimeException) { CompletableFuture.failedFuture(e) }
        return request.handle { ids, failure ->
            synchronized(lock) {
                if (version == loadVersion) {
                    if (failure == null && ids != null) {
                        saved = ids.toSet()
                        loadState = BookmarkLoadState.Loaded
                    } else loadState = BookmarkLoadState.Error
                }
            }
            Unit
        }
    }

    override fun addBookmark(id: String): CompletableFuture<BookmarkResult> = synchronized(lock) {
        if (writeState == BookmarkWriteState.Saving) return@synchronized done(BookmarkResult.Busy)
        val decision = addDecision(id)
        if (decision != null) done(decision) else startWrite(WriteIntent(id, add = true))
    }

    override fun removeBookmark(id: String): CompletableFuture<BookmarkResult> = synchronized(lock) {
        when {
            writeState == BookmarkWriteState.Saving -> done(BookmarkResult.Busy)
            loadState != BookmarkLoadState.Loaded -> done(BookmarkResult.RejectedStorageUnavailable)
            id !in saved -> done(BookmarkResult.NotSaved)
            else -> startWrite(WriteIntent(id, add = false))
        }
    }

    override fun retryBookmarkWrite(): CompletableFuture<BookmarkResult> = synchronized(lock) {
        if (writeState == BookmarkWriteState.Saving) return@synchronized done(BookmarkResult.Busy)
        if (loadState != BookmarkLoadState.Loaded) return@synchronized done(BookmarkResult.RejectedStorageUnavailable)
        val intent = pendingWrite ?: return@synchronized done(BookmarkResult.NotSaved)
        if (intent.add) {
            val decision = addDecision(intent.id)
            if (decision != null) return@synchronized done(decision)
        }
        startWrite(intent)
    }

    /** Closed takes priority over stale; executed again when the user invokes Save. */
    private fun addDecision(id: String): BookmarkResult? {
        if (loadState != BookmarkLoadState.Loaded) return BookmarkResult.RejectedStorageUnavailable
        val route = currentSnapshot?.walks?.find { it.id == id } ?: return BookmarkResult.RejectedMissing
        if (id in saved) return BookmarkResult.AlreadySaved
        if (route.availability == Availability.Closed) return BookmarkResult.RejectedClosed
        if (!isFresh()) return BookmarkResult.RejectedStale
        return null
    }

    private fun startWrite(intent: WriteIntent): CompletableFuture<BookmarkResult> {
        val next = if (intent.add) saved + intent.id else saved - intent.id
        pendingWrite = intent
        writeState = BookmarkWriteState.Saving
        val completion = CompletableFuture<BookmarkResult>()
        currentWrite = completion
        val request = try { storage.writeIds(next) } catch (e: RuntimeException) { CompletableFuture.failedFuture(e) }
        request.whenComplete { _, failure ->
            synchronized(lock) {
                if (failure == null) {
                    saved = next
                    pendingWrite = null
                    writeState = BookmarkWriteState.Idle
                    currentWrite = null
                    completion.complete(if (intent.add) BookmarkResult.Saved else BookmarkResult.Removed)
                } else {
                    writeState = BookmarkWriteState.Error
                    currentWrite = null
                    completion.complete(BookmarkResult.WriteFailed)
                }
            }
        }
        return completion
    }

    private fun done(result: BookmarkResult) = CompletableFuture.completedFuture(result)
    private data class WriteIntent(val id: String, val add: Boolean)

    companion object { const val TTL_MS = 300_000L }
}
