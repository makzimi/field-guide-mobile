package dev.fieldguide.feature.catalog

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import dev.fieldguide.catalog.api.*
import dev.fieldguide.catalog.impl.*
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.CompletableFuture
import org.junit.Assert.*
import org.junit.Test

/** In-process journeys. The mapper, repository, use cases, Feature and presentation are real. */
class CatalogIntegrationTest {
    private val contractRoot = Path.of(checkNotNull(System.getProperty("fieldGuide.contractDirectory")))
    private val scenarios = readJson("scenarios")["scenarios"].asJsonArray
    private val gson = Gson()

    private fun readJson(name: String): JsonObject = Files.newBufferedReader(contractRoot.resolve("$name.json")).use {
        JsonParser.parseReader(it).asJsonObject
    }
    private fun scenario(id: String) = scenarios.single { it.asJsonObject["id"].asString == id }.asJsonObject
    private fun step(id: String, name: String) = scenario(id)["steps"].asJsonArray
        .single { it.asJsonObject["id"].asString == name }.asJsonObject
    private fun walks(fixture: String) = readJson(fixture)["walks"].toString()

    private class Source : CatalogSource {
        val requests = mutableListOf<CompletableFuture<String>>()
        override fun loadWalks() = CompletableFuture<String>().also(requests::add)
        fun fail(index: Int) { requests[index].completeExceptionally(IllegalStateException("source unavailable")) }
    }
    private class Storage(var durableIds: Set<String>) : BookmarkStorage {
        data class Write(val ids: Set<String>, val completion: CompletableFuture<Unit>)
        val writes = mutableListOf<Write>()
        override fun loadIds() = CompletableFuture.completedFuture(durableIds.toSet())
        override fun writeIds(ids: Set<String>) = CompletableFuture<Unit>().also { writes += Write(ids.toSet(), it) }
        fun commit(index: Int) {
            durableIds = writes[index].ids
            writes[index].completion.complete(Unit)
        }
        fun fail(index: Int) { writes[index].completion.completeExceptionally(IllegalStateException("atomic write failed")) }
    }
    /** One controlled monotonic-time boundary, including its expiry callbacks. */
    private class Time(var now: Long) : MonotonicClock, ExpiryScheduler {
        data class Alarm(val at: Long, val callback: () -> Unit, var canceled: Boolean = false)
        private val alarms = mutableListOf<Alarm>()
        override fun nowMs() = now
        override fun schedule(delayMs: Long, task: () -> Unit): CancelExpiry {
            val alarm = Alarm(now + delayMs, task)
            alarms += alarm
            return CancelExpiry { alarm.canceled = true }
        }
        fun advance(to: Long) {
            now = to
            alarms.filter { !it.canceled && it.at <= to }.toList().forEach {
                it.canceled = true
                it.callback()
            }
        }
    }
    private class Rig(initial: JsonObject) : AutoCloseable {
        val time = Time(initial["fetchedAtMs"]?.asLong ?: initial["clockMs"].asLong)
        val source = Source()
        val storage = Storage(initial["savedIds"].asJsonArray.map { it.asString }.toSet())
        val repository = FieldGuideRepository(source, storage, time, CatalogMapper())
        val feature = CatalogFeature(repository, QueryWalks(), AddBookmark(repository), RemoveBookmark(repository),
            time, time) { callback -> callback() }
        // Observe published output. Assertions never call the mapper to manufacture expected views.
        val published = mutableListOf<FeatureView>()
        val view: FeatureView get() = published.last()
        init { feature.observe(published::add) }
        fun act(action: FeatureAction) { feature.dispatch(action) }
        override fun close() { feature.close() }
    }
    private fun rig(id: String) = Rig(scenario(id)["initial"].asJsonObject)
    private fun load(r: Rig, fixture: String = "catalog-valid") {
        r.feature.start()
        assertEquals(CatalogViewKind.Loading, r.view.catalogKind)
        r.source.requests[0].complete(walks(fixture))
    }

    /** Shared hand-authored oracles are read directly, never generated from production behavior. */
    private fun expect(r: Rig, id: String, name: String, vararg fields: String) {
        val expected = step(id, name)["expect"].asJsonObject
        val v = r.view
        for (field in fields) {
            assertTrue("$id/$name must declare $field", expected.has(field))
            val actual: Any? = when (field) {
                "screen" -> when (v.screen) { ScreenKind.List -> "list"; ScreenKind.Detail -> "detail"; ScreenKind.Unavailable -> "unavailable" }
                "catalogState" -> when (v.catalogKind) {
                    CatalogViewKind.Loading -> "loading"; CatalogViewKind.FullError -> "full-error"
                    CatalogViewKind.Content -> "content"; CatalogViewKind.Empty -> "empty"
                    CatalogViewKind.RefreshingFresh -> "refreshing-fresh"; CatalogViewKind.RefreshingStale -> "refreshing-stale"
                    CatalogViewKind.ContentError -> "content-error"; CatalogViewKind.StaleError -> "stale-error"
                }
                "routeId" -> v.routeId
                "listIds" -> v.list.map { it.id }
                "savedBadgeIds" -> v.list.filter { it.saved }.map { it.id }
                "storedIds" -> r.storage.durableIds.toList()
                "savedIds" -> r.repository.savedIds.toList()
                "savedCount" -> v.savedCount
                "distanceLabel" -> v.detail?.distanceLabel
                "addEnabled" -> v.detail?.addEnabled
                "saved" -> v.detail?.saved
                "actionLabel" -> v.detail?.actionLabel
                "saveState" -> when (v.detail?.saveKind) { SaveViewKind.Idle -> "idle"; SaveViewKind.Saving -> "saving"; SaveViewKind.Error -> "error"; null -> null }
                "inlineRetryEnabled" -> v.detail?.inlineRetryEnabled
                "storageWriteCount" -> r.storage.writes.size
                "retryCatalogEnabled" -> v.retryCatalogEnabled
                "fetchedAtMs" -> r.feature.state.repository.fetchedAtMs
                "staleWarning" -> v.staleWarning
                "fresh" -> v.fresh
                "ageMs" -> v.ageMs
                "disabledReason" -> when (v.detail?.disabledReason) {
                    DisabledReason.Closed -> "closed"; DisabledReason.Stale -> "stale"
                    DisabledReason.StorageUnavailable -> "storage-unavailable"; DisabledReason.Saving -> "saving"; null -> null
                }
                "query" -> v.query
                "budgetMinutes" -> v.budgetMinutes
                else -> error("No real observation for $field")
            }
            assertEquals("$id/$name/$field", expected[field], gson.toJsonTree(actual))
        }
    }

    private fun loadedCatalog() = rig("SAVE-01").also(::load)

    @Test
    fun `save WHEN write is pending SHOULD stay unsaved`() =
        loadedCatalog().use { sut ->
            sut.act(FeatureAction.OpenDetail("canal-gardens"))

            sut.act(FeatureAction.Save)

            assertFalse(sut.view.detail!!.saved)
            assertEquals(0, sut.view.savedCount)
        }

    @Test
    fun `save WHEN write commits SHOULD publish saved state`() =
        loadedCatalog().use { sut ->
            sut.act(FeatureAction.OpenDetail("canal-gardens"))
            sut.act(FeatureAction.Save)

            sut.storage.commit(0)

            assertTrue(sut.view.detail!!.saved)
            assertEquals(1, sut.view.savedCount)
            assertEquals(setOf("canal-gardens"), sut.storage.durableIds)
        }

    // Catches a wrong Save use-case delegation or loss of the shared ID on Back.
    @Test fun loadDetailSaveBackPublishesTheSameCommittedId() = rig("SAVE-01").use { r ->
        load(r)
        assertEquals(listOf("pine-loop", "glasshouse-loop", "canal-gardens"), r.view.list.map { it.id })
        val id = step("SAVE-01", "detail")["routeId"].asString
        assertEquals("canal-gardens", id)
        r.act(FeatureAction.OpenDetail(id))
        expect(r, "SAVE-01", "detail", "screen", "routeId", "distanceLabel", "addEnabled", "saved")
        assertEquals("50 minutes", r.view.detail!!.durationLabel)
        assertEquals("Waterside", r.view.detail!!.terrainLabel)
        r.act(FeatureAction.Save)
        expect(r, "SAVE-01", "pending", "saveState", "addEnabled", "storedIds")
        assertFalse(r.view.detail!!.saved)
        assertEquals(0, r.view.savedCount)
        r.storage.commit(0)
        expect(r, "SAVE-01", "commit", "saveState", "saved", "storedIds", "actionLabel")
        assertEquals(BookmarkResult.Saved, r.feature.state.lastBookmarkResult)
        assertTrue(r.view.detail!!.removeEnabled)
        r.act(FeatureAction.BackToList)
        expect(r, "SAVE-01", "back", "screen", "savedCount", "savedBadgeIds", "listIds")
        assertNull(r.view.detail)
        assertEquals(1, r.source.requests.size) // Fresh Back reuses the actual repository cache.
        assertEquals(setOf("canal-gardens"), r.repository.savedIds)
        r.act(FeatureAction.OpenDetail(id))
        assertTrue(r.view.detail!!.saved)
        assertEquals("Remove saved walk", r.view.detail!!.actionLabel)
    }

    // Catches an optimistic save publication, duplicate write or lost retry target.
    @Test fun failedSaveRetryCommitsOnceAndBackRetainsFilters() = rig("SAVE-02").use { r ->
        load(r)
        r.act(FeatureAction.SetQuery("  CANAL  "))
        r.act(FeatureAction.SetBudget(90))
        r.act(FeatureAction.OpenDetail(step("SAVE-02", "detail")["routeId"].asString))
        expect(r, "SAVE-02", "detail", "saved", "addEnabled")
        r.act(FeatureAction.Save)
        expect(r, "SAVE-02", "pending", "saveState", "addEnabled")
        r.act(FeatureAction.Save)
        expect(r, "SAVE-02", "duplicateTap", "saveState", "storageWriteCount", "storedIds")
        r.storage.fail(0)
        expect(r, "SAVE-02", "failure", "saveState", "saved", "storedIds", "inlineRetryEnabled")
        assertEquals(BookmarkResult.WriteFailed, r.feature.state.lastBookmarkResult)
        assertEquals(emptySet<String>(), r.repository.savedIds)
        assertFalse(r.view.list.single().saved)
        r.act(FeatureAction.RetrySave)
        expect(r, "SAVE-02", "retry", "saveState", "storedIds")
        assertFalse(r.view.detail!!.saved)
        r.storage.commit(1)
        expect(r, "SAVE-02", "success", "saveState", "saved", "storedIds", "inlineRetryEnabled")
        r.act(FeatureAction.BackToList)
        assertEquals(ScreenKind.List, r.view.screen)
        assertEquals("  CANAL  ", r.view.query)
        assertEquals("canal", r.view.normalizedQuery)
        assertEquals(90, r.view.budgetMinutes)
        assertEquals(listOf("canal-gardens"), r.view.list.map { it.id })
        assertEquals(listOf("canal-gardens"), r.view.list.filter { it.saved }.map { it.id })
        assertEquals(1, r.view.savedCount)
    }

    // Catches an error that discards bookmarks or a Retry action that never reloads.
    @Test fun initialSourceErrorThenRetryRestoresListAndSavedBadge() = rig("CAT-05").use { r ->
        r.feature.start()
        expect(r, "CAT-05", "start", "catalogState", "listIds")
        r.source.fail(0)
        expect(r, "CAT-05", "failure", "catalogState", "listIds", "retryCatalogEnabled", "savedIds")
        assertEquals(CatalogError.SourceUnavailable, r.feature.state.repository.error)
        r.act(FeatureAction.RetryCatalog)
        expect(r, "CAT-05", "retry", "catalogState")
        r.source.requests[1].complete(walks(step("CAT-05", "success")["fixture"].asString))
        expect(r, "CAT-05", "success", "catalogState", "listIds", "savedCount", "fetchedAtMs")
        assertFalse(r.view.retryCatalogEnabled)
        assertEquals(listOf("canal-gardens"), r.view.list.filter { it.saved }.map { it.id })
        r.act(FeatureAction.OpenDetail("canal-gardens"))
        assertTrue(r.view.detail!!.saved)
        assertTrue(r.view.detail!!.removeEnabled)
    }

    // Catches loss of cached content/timestamp, duplicate stale fetches or stale Save bypass.
    @Test fun expiredBackRetainsCacheAcrossFailureThenRecoversOnRetry() = rig("CAT-06").use { r ->
        load(r)
        r.act(FeatureAction.OpenDetail("pine-loop"))
        r.time.advance(scenario("CAT-06")["initial"].asJsonObject["clockMs"].asLong)
        r.act(FeatureAction.BackToList)
        expect(r, "CAT-06", "return", "catalogState", "listIds", "staleWarning", "fetchedAtMs")
        r.act(FeatureAction.OpenList)
        expect(r, "CAT-06", "returnAgain", "catalogState", "listIds")
        assertEquals(2, r.source.requests.size) // One initial load and one stale refresh, not two refreshes.
        r.source.fail(1)
        expect(r, "CAT-06", "failure", "catalogState", "listIds", "staleWarning", "retryCatalogEnabled", "fetchedAtMs")
        r.act(FeatureAction.OpenDetail(step("CAT-06", "detail")["routeId"].asString))
        expect(r, "CAT-06", "detail", "screen", "routeId", "addEnabled", "disabledReason")
        r.act(FeatureAction.Save)
        assertEquals(BookmarkResult.RejectedStale, r.feature.state.lastBookmarkResult)
        assertEquals(0, r.storage.writes.size)
        r.act(FeatureAction.RetryCatalog)
        assertEquals(CatalogViewKind.RefreshingStale, r.view.catalogKind)
        r.source.requests[2].complete(walks("catalog-valid"))
        assertEquals(CatalogViewKind.Content, r.view.catalogKind)
        assertTrue(r.view.detail!!.addEnabled)
        assertFalse(r.view.staleWarning)
        assertFalse(r.view.retryCatalogEnabled)
        assertEquals(1_300_000L, r.feature.state.repository.fetchedAtMs)
    }

    // Catches partial publication of an invalid source or freshness reset on failed refresh.
    @Test fun invalidRefreshPreservesRealMappedDetailAndExpiryStillDisablesSave() = rig("SAVE-01").use { r ->
        load(r)
        r.act(FeatureAction.OpenDetail("canal-gardens"))
        r.act(FeatureAction.RefreshCatalog)
        assertEquals(CatalogViewKind.RefreshingFresh, r.view.catalogKind)
        r.source.requests[1].complete(walks("catalog-invalid-duplicate"))
        expect(r, "CAT-08", "duplicate", "catalogState", "listIds", "fetchedAtMs")
        assertEquals(CatalogError.InvalidCatalog, r.feature.state.repository.error)
        assertTrue(r.view.detail!!.addEnabled)
        assertEquals("Canal gardens", r.view.detail!!.title)
        assertEquals("3.2 km", r.view.detail!!.distanceLabel)
        assertFalse(r.view.list.any { it.id == "new-valid" })
        r.time.advance(1_299_999L)
        assertTrue(r.view.detail!!.addEnabled)
        r.time.advance(step("CLOCK-01", "atTtl")["clockMs"].asLong)
        expect(r, "CLOCK-01", "atTtl", "ageMs", "fresh", "addEnabled", "disabledReason", "staleWarning")
        assertEquals(CatalogViewKind.StaleError, r.view.catalogKind)
        r.act(FeatureAction.Save)
        assertEquals(BookmarkResult.RejectedStale, r.feature.state.lastBookmarkResult)
        assertEquals(emptySet<String>(), r.repository.savedIds)
    }

    // Catches a detail copy detached from refresh or deletion of an absent saved ID.
    @Test fun removedSelectedIdBecomesUnavailableAndBackPreservesQueryThenBookmarkReappears() = rig("NAV-01").use { r ->
        load(r)
        val initial = scenario("NAV-01")["initial"].asJsonObject
        r.time.advance(initial["clockMs"].asLong)
        r.act(FeatureAction.SetQuery(initial["query"].asString))
        r.act(FeatureAction.SetBudget(initial["budgetMinutes"].asInt))
        r.act(FeatureAction.OpenDetail(step("NAV-01", "selected")["routeId"].asString))
        expect(r, "NAV-01", "selected", "screen", "routeId", "saved")
        r.act(FeatureAction.RefreshCatalog)
        r.source.requests[1].complete(walks(step("NAV-01", "removed")["fixture"].asString))
        expect(r, "NAV-01", "removed", "screen", "routeId", "storedIds", "savedCount")
        assertNull(r.view.detail)
        r.act(FeatureAction.BackToList) // Executed navigation, not an invented back-enabled flag.
        expect(r, "NAV-01", "back", "screen", "query", "budgetMinutes", "listIds", "storedIds", "savedCount")
        r.act(FeatureAction.OpenDetail(step("NAV-01", "unknown")["routeId"].asString))
        expect(r, "NAV-01", "unknown", "screen", "routeId", "storedIds")
        r.act(FeatureAction.BackToList)
        expect(r, "NAV-01", "unknownBack", "screen", "query", "budgetMinutes", "storedIds")
        r.act(FeatureAction.RefreshCatalog)
        r.source.requests[2].complete(walks("catalog-valid"))
        assertEquals(1, r.view.savedCount)
        assertEquals(listOf("canal-gardens"), r.view.list.filter { it.saved }.map { it.id })
        r.act(FeatureAction.OpenDetail("canal-gardens"))
        assertTrue(r.view.detail!!.saved)
        assertTrue(r.view.detail!!.removeEnabled)
    }
}
