package dev.fieldguide.feature.catalog

import dev.fieldguide.catalog.api.*
import java.util.concurrent.CompletableFuture

fun interface CancelExpiry { fun cancel() }
fun interface ExpiryScheduler { fun schedule(delayMs: Long, task: () -> Unit): CancelExpiry }

/** Single-screen-session state holder; callbacks are marshalled through dispatchOnUi. */
class CatalogFeature(
    private val repository: WalkRepository,
    queryWalks: WalkQuery,
    private val addBookmark: AddBookmarkUseCase,
    private val removeBookmark: RemoveBookmarkUseCase,
    private val clock: MonotonicClock,
    private val scheduler: ExpiryScheduler,
    private val dispatchOnUi: (() -> Unit) -> Unit,
) {
    private val mapper = FeaturePresentationMapper(queryWalks)
    private var observer: ((FeatureView) -> Unit)? = null
    private var expiry: CancelExpiry? = null
    private var closed = false
    var state: FeatureState = FeatureState(repository = RepositoryView.capture(repository))
        private set
    val view: FeatureView get() = mapper.map(state)

    fun observe(listener: (FeatureView) -> Unit) {
        if (closed) return
        observer = listener
        listener(view)
    }

    fun start() {
        if (closed) return
        track(repository.loadBookmarks())
        track(repository.openList())
        sync()
    }

    fun dispatch(action: FeatureAction) {
        if (closed) return
        state = FeatureReducer.reduce(state, FeatureEvent.Action(action))
        emit()
        when (action) {
            FeatureAction.OpenList, FeatureAction.BackToList -> track(repository.openList())
            FeatureAction.RefreshCatalog, FeatureAction.RetryCatalog -> track(repository.refresh())
            FeatureAction.RetrySavedWalks -> track(repository.loadBookmarks())
            FeatureAction.Save -> {
                val id = state.routeId ?: return
                val future = if (id in repository.savedIds) removeBookmark.run(id) else addBookmark.run(id)
                // A storage adapter may fail before run returns. Retain that route's retry intent.
                if (repository.bookmarkWriteState == BookmarkWriteState.Saving ||
                    (future.isDone && future.getNow(null) == BookmarkResult.WriteFailed)) {
                    state = FeatureReducer.reduce(state, FeatureEvent.SaveStarted(id))
                }
                trackBookmark(future)
            }
            FeatureAction.RetrySave -> if (state.routeId == state.saveTargetId) {
                trackBookmark(repository.retryBookmarkWrite())
            }
            FeatureAction.Foreground -> sync()
            else -> Unit
        }
    }

    private fun track(future: CompletableFuture<Unit>) {
        sync()
        future.whenComplete { _, _ -> dispatchOnUi { if (!closed) sync() } }
    }

    private fun trackBookmark(future: CompletableFuture<BookmarkResult>) {
        sync()
        future.whenComplete { result, _ -> dispatchOnUi {
            if (!closed) {
                state = FeatureReducer.reduce(state, FeatureEvent.BookmarkCompleted(result ?: BookmarkResult.WriteFailed))
                sync()
            }
        } }
    }

    private fun sync() {
        if (closed) return
        var captured = RepositoryView.capture(repository)
        var untilStale = captured.fetchedAtMs?.let { 300_000L - (clock.nowMs() - it) }
        if (captured.fresh && untilStale != null && untilStale <= 0) {
            captured = RepositoryView.capture(repository)
            untilStale = captured.fetchedAtMs?.let { 300_000L - (clock.nowMs() - it) }
        }
        state = FeatureReducer.reduce(state, FeatureEvent.RepositoryChanged(captured))
        expiry?.cancel()
        expiry = null
        if (captured.fresh && untilStale != null && untilStale > 0) {
            expiry = scheduler.schedule(untilStale) { dispatchOnUi { if (!closed) sync() } }
        }
        emit()
    }

    private fun emit() { if (!closed) observer?.invoke(view) }

    fun close() {
        closed = true
        expiry?.cancel()
        expiry = null
        observer = null
    }
}
