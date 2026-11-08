package dev.fieldguide.feature.catalog

import dev.fieldguide.catalog.api.*

sealed interface FeatureAction {
    data object OpenList : FeatureAction
    data class OpenDetail(val routeId: String) : FeatureAction
    data object BackToList : FeatureAction
    data class SetQuery(val text: String) : FeatureAction
    data class SetBudget(val minutes: Int) : FeatureAction
    data object ClearFilters : FeatureAction
    data object RefreshCatalog : FeatureAction
    data object RetryCatalog : FeatureAction
    data object RetrySavedWalks : FeatureAction
    data object Save : FeatureAction
    data object RetrySave : FeatureAction
    data object Foreground : FeatureAction
}

internal sealed interface FeatureEvent {
    data class Action(val value: FeatureAction) : FeatureEvent
    data class RepositoryChanged(val value: RepositoryView) : FeatureEvent
    data class BookmarkCompleted(val value: BookmarkResult) : FeatureEvent
    data class SaveStarted(val routeId: String) : FeatureEvent
}

data class RepositoryView(
    val snapshot: WalkSnapshot? = null,
    val fetchedAtMs: Long? = null,
    val error: CatalogError? = null,
    val refreshing: Boolean = false,
    val savedIds: Set<String> = emptySet(),
    val savedCount: Int? = null,
    val bookmarkLoadState: BookmarkLoadState = BookmarkLoadState.Loading,
    val bookmarkWriteState: BookmarkWriteState = BookmarkWriteState.Idle,
    val fresh: Boolean = false,
    val ageMs: Long? = null,
) {
    companion object {
        fun capture(repository: WalkRepository) = RepositoryView(
            snapshot = repository.snapshot,
            fetchedAtMs = repository.fetchedAtMs,
            error = repository.error,
            refreshing = repository.refreshing,
            savedIds = repository.savedIds.toSet(),
            savedCount = repository.savedCount,
            bookmarkLoadState = repository.bookmarkLoadState,
            bookmarkWriteState = repository.bookmarkWriteState,
            fresh = repository.isFresh(),
            ageMs = repository.ageMs(),
        )
    }
}

data class FeatureState(
    val routeId: String? = null,
    val query: String = "",
    val budgetMinutes: Int = 60,
    val repository: RepositoryView = RepositoryView(),
    val lastBookmarkResult: BookmarkResult? = null,
    val saveTargetId: String? = null,
)

/** Every state transition is pure. I/O and timers belong to CatalogFeature. */
internal object FeatureReducer {
    fun reduce(state: FeatureState, event: FeatureEvent): FeatureState = when (event) {
        is FeatureEvent.RepositoryChanged -> state.copy(repository = event.value)
        is FeatureEvent.SaveStarted -> state.copy(saveTargetId = event.routeId, lastBookmarkResult = null)
        is FeatureEvent.BookmarkCompleted -> state.copy(lastBookmarkResult = event.value,
            saveTargetId = if (event.value == BookmarkResult.Saved || event.value == BookmarkResult.Removed)
                null else state.saveTargetId)
        is FeatureEvent.Action -> when (val action = event.value) {
            FeatureAction.OpenList, FeatureAction.BackToList -> state.copy(routeId = null)
            is FeatureAction.OpenDetail -> state.copy(routeId = action.routeId, lastBookmarkResult = null)
            is FeatureAction.SetQuery -> state.copy(query = action.text)
            is FeatureAction.SetBudget -> state.copy(budgetMinutes = action.minutes.also {
                require(it in setOf(15, 30, 60, 90))
            })
            FeatureAction.ClearFilters -> state.copy(query = "", budgetMinutes = 60)
            FeatureAction.Save, FeatureAction.RetrySave -> state.copy(lastBookmarkResult = null)
            else -> state
        }
    }
}
