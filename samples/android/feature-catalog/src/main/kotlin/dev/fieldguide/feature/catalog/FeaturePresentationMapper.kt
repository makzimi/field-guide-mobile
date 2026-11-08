package dev.fieldguide.feature.catalog

import dev.fieldguide.catalog.api.*
import java.util.Locale

enum class ScreenKind { List, Detail, Unavailable }
enum class CatalogViewKind { Loading, FullError, Content, Empty, RefreshingFresh, RefreshingStale, ContentError, StaleError }
enum class SaveViewKind { Idle, Saving, Error }
enum class DisabledReason { Closed, Stale, StorageUnavailable, Saving }

data class WalkCardView(
    val id: String, val title: String, val durationLabel: String, val distanceLabel: String,
    val closed: Boolean, val saved: Boolean, val artKey: ArtKey,
)
data class DetailView(
    val id: String, val title: String, val description: String, val durationLabel: String,
    val distanceLabel: String, val terrainLabel: String, val closed: Boolean, val saved: Boolean,
    val artKey: ArtKey, val addEnabled: Boolean, val removeEnabled: Boolean,
    val disabledReason: DisabledReason?, val actionLabel: String, val saveKind: SaveViewKind,
    val inlineRetryEnabled: Boolean,
)
data class FeatureView(
    val screen: ScreenKind, val routeId: String?, val query: String, val normalizedQuery: String,
    val budgetMinutes: Int, val catalogKind: CatalogViewKind, val list: List<WalkCardView>,
    val detail: DetailView?, val savedCount: Int?, val retryCatalogEnabled: Boolean,
    val retrySavedWalksEnabled: Boolean, val staleWarning: Boolean, val fresh: Boolean,
    val ageMs: Long?,
)

class FeaturePresentationMapper(private val queryWalks: WalkQuery) {
    fun map(state: FeatureState): FeatureView {
        val r = state.repository
        val stale = r.snapshot != null && !r.fresh
        val kind = when {
            r.snapshot == null && r.refreshing -> CatalogViewKind.Loading
            r.snapshot == null -> CatalogViewKind.FullError
            r.refreshing && stale -> CatalogViewKind.RefreshingStale
            r.refreshing -> CatalogViewKind.RefreshingFresh
            r.error != null && stale -> CatalogViewKind.StaleError
            r.error != null -> CatalogViewKind.ContentError
            else -> {
                val visible = queryWalks.run(r.snapshot.walks, state.query, state.budgetMinutes)
                if (visible.isEmpty()) CatalogViewKind.Empty else CatalogViewKind.Content
            }
        }
        val visible = r.snapshot?.let { queryWalks.run(it.walks, state.query, state.budgetMinutes) }.orEmpty()
        val cards = visible.map { walk ->
            WalkCardView(walk.id, walk.title, minutes(walk.durationMinutes), distance(walk.distanceMetres),
                walk.availability == Availability.Closed, walk.id in r.savedIds, walk.artKey)
        }
        val route = state.routeId?.let { id -> r.snapshot?.walks?.find { it.id == id } }
        val screen = when {
            state.routeId == null -> ScreenKind.List
            route == null -> ScreenKind.Unavailable
            else -> ScreenKind.Detail
        }
        val detail = route?.let { walk ->
            val saved = walk.id in r.savedIds
            val reason = when {
                r.bookmarkLoadState != BookmarkLoadState.Loaded -> DisabledReason.StorageUnavailable
                r.bookmarkWriteState == BookmarkWriteState.Saving -> DisabledReason.Saving
                saved -> null
                walk.availability == Availability.Closed -> DisabledReason.Closed
                !r.fresh -> DisabledReason.Stale
                else -> null
            }
            DetailView(
                id = walk.id, title = walk.title, description = walk.description,
                durationLabel = minutes(walk.durationMinutes), distanceLabel = distance(walk.distanceMetres),
                terrainLabel = walk.terrain.name.lowercase(Locale.ROOT).replaceFirstChar { it.uppercase() },
                closed = walk.availability == Availability.Closed, saved = saved, artKey = walk.artKey,
                addEnabled = !saved && reason == null, removeEnabled = saved && reason == null,
                disabledReason = reason, actionLabel = if (saved) "Remove saved walk" else "Save walk",
                saveKind = when (r.bookmarkWriteState) {
                    BookmarkWriteState.Idle -> SaveViewKind.Idle
                    BookmarkWriteState.Saving -> SaveViewKind.Saving
                    BookmarkWriteState.Error -> if (state.saveTargetId == walk.id) SaveViewKind.Error else SaveViewKind.Idle
                },
                inlineRetryEnabled = state.saveTargetId == walk.id &&
                    r.bookmarkWriteState == BookmarkWriteState.Error &&
                    r.bookmarkLoadState == BookmarkLoadState.Loaded,
            )
        }
        return FeatureView(screen, state.routeId, state.query, queryWalks.normalize(state.query),
            state.budgetMinutes, kind, cards, detail, r.savedCount, r.error != null,
            r.bookmarkLoadState == BookmarkLoadState.Error, stale, r.fresh, r.ageMs)
    }

    private fun minutes(value: Int) = "$value ${if (value == 1) "minute" else "minutes"}"
    private fun distance(metres: Int) = if (metres < 1000) "$metres m"
        else String.format(Locale.ROOT, "%.1f km", metres / 1000.0)
}
