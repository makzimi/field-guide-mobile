package dev.fieldguide.feature.catalog

import com.google.gson.JsonParser
import dev.fieldguide.catalog.api.*
import dev.fieldguide.catalog.impl.*
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.CompletableFuture
import org.junit.Assert.*
import org.junit.Test
import androidx.lifecycle.ViewModelStore

/** Real reducer, mapper, repository and use cases; only source, storage and time are controlled. */
class FeatureBehaviorTest {
    private val root = Path.of(checkNotNull(System.getProperty("fieldGuide.contractDirectory")))
    private fun walks(name: String) = Files.newBufferedReader(root.resolve("$name.json")).use {
        JsonParser.parseReader(it).asJsonObject["walks"].toString()
    }
    private fun oracle(scenario: String, step: String) = Files.newBufferedReader(root.resolve("scenarios.json")).use {
        JsonParser.parseReader(it).asJsonObject["scenarios"].asJsonArray
            .single { entry -> entry.asJsonObject["id"].asString == scenario }.asJsonObject["steps"].asJsonArray
            .single { entry -> entry.asJsonObject["id"].asString == step }.asJsonObject["expect"].asJsonObject
    }
    private open class Clock(var now: Long = 1_000_000L) : MonotonicClock { override fun nowMs() = now }
    private class Source : CatalogSource {
        val requests = mutableListOf<CompletableFuture<String>>()
        override fun loadWalks() = CompletableFuture<String>().also(requests::add)
        fun succeed(index: Int, body: String) { requests[index].complete(body) }
        fun fail(index: Int) { requests[index].completeExceptionally(IllegalStateException("source")) }
    }
    private class Storage(var durable: Set<String> = emptySet()) : BookmarkStorage {
        var failWriteImmediately = false
        var loadFailure = false
        var deferLoad = false
        val loads = mutableListOf<CompletableFuture<Set<String>>>()
        val writes = mutableListOf<Pair<Set<String>, CompletableFuture<Unit>>>()
        override fun loadIds(): CompletableFuture<Set<String>> = if (loadFailure)
            CompletableFuture.failedFuture(IllegalStateException("storage"))
            else if (deferLoad) CompletableFuture<Set<String>>().also(loads::add)
            else CompletableFuture.completedFuture(durable)
        override fun writeIds(ids: Set<String>) = CompletableFuture<Unit>().also {
            writes += ids to it
            if (failWriteImmediately) it.completeExceptionally(IllegalStateException("immediate write"))
        }
        fun succeed(index: Int) { durable = writes[index].first; writes[index].second.complete(Unit) }
        fun fail(index: Int) { writes[index].second.completeExceptionally(IllegalStateException("write")) }
    }
    private class Scheduler(private val clock: Clock) : ExpiryScheduler {
        data class Task(val at: Long, val run: () -> Unit, var canceled: Boolean = false)
        val tasks = mutableListOf<Task>()
        override fun schedule(delayMs: Long, task: () -> Unit): CancelExpiry {
            val entry = Task(clock.now + delayMs, task)
            tasks += entry
            return CancelExpiry { entry.canceled = true }
        }
        fun advance(to: Long) {
            clock.now = to
            tasks.filter { !it.canceled && it.at <= to }.toList().forEach { it.canceled = true; it.run() }
        }
    }
    private data class Rig(val clock: Clock, val source: Source, val storage: Storage,
        val repo: FieldGuideRepository, val scheduler: Scheduler, val feature: CatalogFeature)
    private fun rig(saved: Set<String> = emptySet(), clock: Clock = Clock()): Rig {
        val source = Source(); val storage = Storage(saved)
        val repo = FieldGuideRepository(source, storage, clock, CatalogMapper())
        val scheduler = Scheduler(clock)
        return Rig(clock, source, storage, repo, scheduler,
            CatalogFeature(repo, QueryWalks(), AddBookmark(repo), RemoveBookmark(repo), clock, scheduler) { it() })
    }
    private fun loaded(saved: Set<String> = emptySet()): Rig = rig(saved).also {
        it.feature.start(); it.source.succeed(0, walks("catalog-valid"))
    }

    @Test fun initialLoadingErrorRetryAndFiltersUseSharedContract() {
        val r = rig(saved = setOf("canal-gardens")); r.feature.start()
        assertEquals(CatalogViewKind.Loading, r.feature.view.catalogKind)
        r.source.fail(0)
        assertEquals(CatalogViewKind.FullError, r.feature.view.catalogKind)
        assertTrue(r.feature.view.retryCatalogEnabled)
        r.feature.dispatch(FeatureAction.RetryCatalog); r.source.succeed(1, walks("catalog-valid"))
        assertEquals(listOf("pine-loop", "glasshouse-loop", "canal-gardens"), r.feature.view.list.map { it.id })
        assertEquals(oracle("CAT-05", "success")["listIds"].asJsonArray.map { it.asString }, r.feature.view.list.map { it.id })
        assertEquals(1, r.feature.view.savedCount)
        r.feature.dispatch(FeatureAction.SetBudget(15))
        assertEquals(CatalogViewKind.Empty, r.feature.view.catalogKind)
        r.feature.dispatch(FeatureAction.SetQuery("canal"))
        r.feature.dispatch(FeatureAction.ClearFilters)
        assertEquals(60, r.feature.view.budgetMinutes)
        assertEquals("", r.feature.view.query)
        assertEquals(listOf("pine-loop", "glasshouse-loop", "canal-gardens"), r.feature.view.list.map { it.id })
    }

    @Test fun failedSaveRetainsOldStateAndInlineRetryCommitsOnlyAfterWrite() {
        val r = loaded(); r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        assertEquals("3.2 km", r.feature.view.detail!!.distanceLabel)
        r.feature.dispatch(FeatureAction.Save)
        assertEquals(SaveViewKind.Saving, r.feature.view.detail!!.saveKind)
        r.feature.dispatch(FeatureAction.Save)
        assertEquals(1, r.storage.writes.size)
        assertFalse(r.feature.view.detail!!.saved)
        r.storage.fail(0)
        assertEquals(SaveViewKind.Error, r.feature.view.detail!!.saveKind)
        assertTrue(r.feature.view.detail!!.inlineRetryEnabled)
        assertEquals(emptySet<String>(), r.storage.durable)
        r.feature.dispatch(FeatureAction.RetrySave)
        assertEquals(SaveViewKind.Saving, r.feature.view.detail!!.saveKind)
        r.storage.succeed(1)
        assertEquals(SaveViewKind.Idle, r.feature.view.detail!!.saveKind)
        assertTrue(r.feature.view.detail!!.saved)
        assertEquals(setOf("canal-gardens"), r.storage.durable)
        r.feature.dispatch(FeatureAction.BackToList)
        assertEquals(1, r.feature.view.savedCount)
    }

    @Test fun immediateWriteFailureStillIdentifiesRouteAndOffersInlineRetry() {
        val r = loaded(); r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        r.storage.failWriteImmediately = true
        r.feature.dispatch(FeatureAction.Save)
        assertEquals(BookmarkResult.WriteFailed, r.feature.state.lastBookmarkResult)
        assertEquals(SaveViewKind.Error, r.feature.view.detail!!.saveKind)
        assertTrue(r.feature.view.detail!!.inlineRetryEnabled)
        assertEquals(emptySet<String>(), r.storage.durable)
        r.storage.failWriteImmediately = false
        r.feature.dispatch(FeatureAction.RetrySave)
        r.storage.succeed(1)
        assertTrue(r.feature.view.detail!!.saved)
        assertEquals(setOf("canal-gardens"), r.storage.durable)
    }

    @Test fun storageFailureLeavesCatalogReadableAndRetryRestoresActions() {
        val r = rig(saved = setOf("canal-gardens")); r.storage.loadFailure = true
        r.feature.start(); r.source.succeed(0, walks("catalog-valid"))
        assertEquals(3, r.feature.view.list.size)
        assertNull(r.feature.view.savedCount)
        assertTrue(r.feature.view.retrySavedWalksEnabled)
        r.feature.dispatch(FeatureAction.OpenDetail("pine-loop"))
        assertEquals(DisabledReason.StorageUnavailable, r.feature.view.detail!!.disabledReason)
        r.storage.loadFailure = false
        r.feature.dispatch(FeatureAction.RetrySavedWalks)
        assertEquals(1, r.feature.view.savedCount)
        assertTrue(r.feature.view.detail!!.addEnabled)
    }

    @Test fun storageLoadingDisablesSaveUntilLoaded() {
        val r = rig(); r.storage.deferLoad = true; r.feature.start()
        r.source.succeed(0, walks("catalog-valid"))
        r.feature.dispatch(FeatureAction.OpenDetail("pine-loop"))
        assertNull(r.feature.view.savedCount)
        assertFalse(r.feature.view.detail!!.addEnabled)
        assertEquals(DisabledReason.StorageUnavailable, r.feature.view.detail!!.disabledReason)
        r.feature.dispatch(FeatureAction.Save)
        assertEquals(BookmarkResult.RejectedStorageUnavailable, r.feature.state.lastBookmarkResult)
        assertEquals(0, r.storage.writes.size)
        r.storage.loads[0].complete(emptySet())
        assertEquals(0, r.feature.view.savedCount)
        assertTrue(r.feature.view.detail!!.addEnabled)
    }

    @Test fun staleRefreshRetainsCardsAndShowsRetryWhileClosedOrSavedActionsStayCorrect() {
        val r = loaded(saved = setOf("canal-gardens"))
        r.scheduler.advance(1_300_000)
        r.feature.dispatch(FeatureAction.OpenDetail("glasshouse-loop"))
        assertEquals(DisabledReason.Closed, r.feature.view.detail!!.disabledReason)
        r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        assertTrue(r.feature.view.detail!!.removeEnabled)
        r.feature.dispatch(FeatureAction.BackToList)
        assertEquals(CatalogViewKind.RefreshingStale, r.feature.view.catalogKind)
        assertEquals(listOf("pine-loop", "glasshouse-loop", "canal-gardens"), r.feature.view.list.map { it.id })
        r.source.fail(1)
        assertEquals(CatalogViewKind.StaleError, r.feature.view.catalogKind)
        assertTrue(r.feature.view.retryCatalogEnabled)
        r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        r.feature.dispatch(FeatureAction.Save); r.storage.succeed(0)
        assertFalse(r.feature.view.detail!!.saved)
        assertEquals(emptySet<String>(), r.storage.durable)
    }

    @Test fun closedStaleAndRemovedIdsResolveWithBackAndPreserveFilters() {
        val r = loaded(saved = setOf("canal-gardens"))
        r.feature.dispatch(FeatureAction.SetBudget(90)); r.feature.dispatch(FeatureAction.SetQuery("canal"))
        r.feature.dispatch(FeatureAction.OpenDetail("glasshouse-loop"))
        assertEquals(DisabledReason.Closed, r.feature.view.detail!!.disabledReason)
        r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        r.feature.dispatch(FeatureAction.RefreshCatalog); r.source.succeed(1, walks("catalog-changed"))
        assertEquals(ScreenKind.Unavailable, r.feature.view.screen)
        assertEquals("canal-gardens", r.feature.view.routeId)
        assertEquals(0, r.feature.view.savedCount)
        assertEquals(setOf("canal-gardens"), r.storage.durable)
        r.feature.dispatch(FeatureAction.BackToList)
        assertEquals(90, r.feature.view.budgetMinutes)
        assertEquals("canal", r.feature.view.query)
        assertEquals(emptyList<String>(), r.feature.view.list.map { it.id })
        r.feature.dispatch(FeatureAction.OpenDetail("never-listed"))
        assertEquals(ScreenKind.Unavailable, r.feature.view.screen)
    }

    @Test fun visibleSaveExpiresExactlyAtTtlAndForegroundRechecks() {
        val r = loaded(); r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        assertTrue(r.feature.view.detail!!.addEnabled)
        r.scheduler.advance(1_299_999)
        assertTrue(r.feature.view.detail!!.addEnabled)
        assertEquals(299_999L, r.repo.ageMs())
        assertEquals(oracle("CLOCK-01", "beforeTtl")["fresh"].asBoolean, r.feature.view.fresh)
        r.scheduler.advance(1_300_000)
        assertFalse(r.feature.view.detail!!.addEnabled)
        assertEquals(DisabledReason.Stale, r.feature.view.detail!!.disabledReason)
        assertEquals(300_000L, r.feature.view.ageMs)
        assertEquals(oracle("CLOCK-01", "atTtl")["fresh"].asBoolean, r.feature.view.fresh)
        r.feature.dispatch(FeatureAction.Foreground)
        assertFalse(r.feature.view.detail!!.addEnabled)
        assertEquals(BookmarkResult.RejectedStale, AddBookmark(r.repo).run("canal-gardens").join())
        assertEquals(emptySet<String>(), r.storage.durable)

        val resumed = loaded(); resumed.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        resumed.clock.now = 1_300_000 // delayed timer while the app was away
        assertTrue(resumed.feature.view.detail!!.addEnabled)
        resumed.feature.dispatch(FeatureAction.Foreground)
        assertFalse(resumed.feature.view.detail!!.addEnabled)
    }

    @Test fun useCaseRejectsAtExecutionEvenWhenUiStillShowsFresh() {
        val r = loaded(); r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        assertTrue(r.feature.view.detail!!.addEnabled)
        r.clock.now = 1_300_000 // timer has not dispatched; deliberately old visible state
        assertEquals(BookmarkResult.RejectedStale, AddBookmark(r.repo).run("canal-gardens").join())
        r.feature.dispatch(FeatureAction.Save)
        assertEquals(BookmarkResult.RejectedStale, r.feature.state.lastBookmarkResult)
        assertEquals(emptyList<Any>(), r.storage.writes)
    }

    @Test fun failedSaveRetryIsOnlyOfferedOnItsOwnRoute() {
        val r = loaded(); r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        r.feature.dispatch(FeatureAction.Save); r.storage.fail(0)
        assertTrue(r.feature.view.detail!!.inlineRetryEnabled)
        r.feature.dispatch(FeatureAction.OpenDetail("pine-loop"))
        assertFalse(r.feature.view.detail!!.inlineRetryEnabled)
        assertEquals(SaveViewKind.Idle, r.feature.view.detail!!.saveKind)
        r.feature.dispatch(FeatureAction.RetrySave)
        assertEquals(1, r.storage.writes.size)
        r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        assertTrue(r.feature.view.detail!!.inlineRetryEnabled)
    }

    @Test fun expiryCannotBeLostWhenClockCrossesBoundaryBetweenReads() {
        class CrossingClock : Clock() {
            var cross = false
            override fun nowMs(): Long {
                val value = now
                if (cross && now == 1_299_999L) now = 1_300_000L
                return value
            }
        }
        val clock = CrossingClock(); val r = rig(clock = clock)
        r.feature.start(); r.source.succeed(0, walks("catalog-valid"))
        r.feature.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        clock.now = 1_299_999L; clock.cross = true
        r.feature.dispatch(FeatureAction.Foreground)
        assertFalse(r.feature.view.detail!!.addEnabled)
        assertEquals(DisabledReason.Stale, r.feature.view.detail!!.disabledReason)
    }

    @Test fun disposedFeatureDoesNotPublishLateCompletion() {
        val r = rig(); var notifications = 0
        r.feature.observe { notifications++ }; r.feature.start()
        val beforeClose = notifications
        r.feature.close(); r.source.succeed(0, walks("catalog-valid"))
        assertEquals(beforeClose, notifications)
    }

    @Test fun viewModelPublishesThenDetachesOnStoreClear() {
        val r = rig(); val model = CatalogViewModel(r.feature)
        val store = ViewModelStore(); store.put("field-guide", model)
        assertEquals(CatalogViewKind.Loading, model.view.catalogKind)
        r.source.succeed(0, walks("catalog-valid"))
        assertEquals(3, model.view.list.size)
        model.dispatch(FeatureAction.OpenDetail("canal-gardens"))
        r.clock.now = 1_300_000
        model.onForeground()
        assertFalse(model.view.detail!!.addEnabled)
        store.clear()
        val before = model.view
        r.feature.dispatch(FeatureAction.SetQuery("pine"))
        assertEquals(before, model.view)
    }
}
