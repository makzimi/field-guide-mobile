package dev.fieldguide.catalog.impl

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import dev.fieldguide.catalog.api.*
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.CompletableFuture
import org.junit.Assert.*
import org.junit.Test

/** Exercises production code with the shared walks arrays and literal R1 expectations. */
class DomainDataBehaviorTest {
    private val root = Path.of(checkNotNull(System.getProperty("fieldGuide.contractDirectory")))
    private fun fixture(name: String): JsonObject = Files.newBufferedReader(root.resolve("$name.json")).use {
        JsonParser.parseReader(it).asJsonObject
    }
    private fun walks(name: String): String = fixture(name)["walks"].toString()
    private fun oracle(scenario: String, step: String): JsonObject {
        val cases = fixture("scenarios")["scenarios"].asJsonArray
        return cases.single { it.asJsonObject["id"].asString == scenario }.asJsonObject["steps"].asJsonArray
            .single { it.asJsonObject["id"].asString == step }.asJsonObject["expect"].asJsonObject
    }
    private fun assertIds(expected: List<String>, actual: List<Walk>, scenario: String, step: String) {
        assertEquals(expected, oracle(scenario, step)["listIds"].asJsonArray.map { it.asString })
        assertEquals(expected, actual.map { it.id })
    }
    private class Clock(var now: Long = 1_000_000) : MonotonicClock { override fun nowMs() = now }
    private class Source : CatalogSource {
        val requests = mutableListOf<CompletableFuture<String>>()
        override fun loadWalks(): CompletableFuture<String> = CompletableFuture<String>().also(requests::add)
        fun success(index: Int, walks: String) = requests[index].complete(walks)
        fun fail(index: Int) = requests[index].completeExceptionally(IllegalStateException("offline"))
    }
    private class Storage(initial: Set<String> = emptySet()) : BookmarkStorage {
        var durable = initial
        var deferLoads = false
        val loads = mutableListOf<Pair<Set<String>, CompletableFuture<Set<String>>>>()
        val writes = mutableListOf<Pair<Set<String>, CompletableFuture<Unit>>>()
        override fun loadIds(): CompletableFuture<Set<String>> = if (!deferLoads) CompletableFuture.completedFuture(durable)
            else CompletableFuture<Set<String>>().also { loads += durable to it }
        override fun writeIds(ids: Set<String>): CompletableFuture<Unit> = CompletableFuture<Unit>().also { writes += ids to it }
        fun succeed(index: Int) { durable = writes[index].first; writes[index].second.complete(Unit) }
        fun fail(index: Int) { writes[index].second.completeExceptionally(IllegalStateException("disk")) }
    }
    private data class Rig(val clock: Clock, val source: Source, val storage: Storage, val repo: FieldGuideRepository)
    private fun rig(saved: Set<String> = emptySet()): Rig {
        val clock = Clock(); val source = Source(); val storage = Storage(saved)
        return Rig(clock, source, storage, FieldGuideRepository(source, storage, clock, CatalogMapper()))
    }
    private fun loaded(name: String = "catalog-valid", saved: Set<String> = emptySet()): Rig = rig(saved).also {
        it.repo.loadBookmarks().join(); it.repo.refresh(); it.source.success(0, walks(name))
    }

    @Test fun boundaryAndSearchAndSortCallRealUseCase() {
        val mapper = CatalogMapper()
        val boundary = mapper.mapWalks(walks("catalog-boundary"))
        val boundaryQuery: WalkQuery = QueryWalks()
        assertIds(listOf("exact-hour"), boundaryQuery.run(boundary, "", 60), "CAT-02", "sixty")
        assertIds(listOf("exact-hour", "over-hour"), QueryWalks().run(boundary, "", 90), "CAT-02", "ninety")
        val valid = mapper.mapWalks(walks("catalog-valid"))
        val query = QueryWalks()
        assertIds(listOf("canal-gardens"), query.run(valid, "  CANAL  ", 60), "CAT-03", "spaced")
        assertEquals("pine loop", query.normalize("  PINE   LOOP "))
        assertIds(listOf("pine-loop"), query.run(valid, "  PINE   LOOP ", 60), "CAT-03", "internal")
        assertIds(emptyList(), query.run(valid, "gentle", 60), "CAT-03", "descriptionOnly")
        assertIds(listOf("pine-loop", "glasshouse-loop", "canal-gardens"), query.run(valid, " \t ", 60), "CAT-03", "whitespace")
        assertIds(listOf("short", "later", "alpha", "zeta"), query.run(mapper.mapWalks(walks("catalog-sort-ties")), "", 60), "CAT-03", "ties")
        assertIds(emptyList(), query.run(valid, "", 15), "CAT-04", "empty")
        assertThrows(IllegalArgumentException::class.java) { query.run(valid, "", 45) }
    }

    @Test fun invalidSnapshotsAreRejectedAsWholeAndNeverReplaceCache() {
        val r = loaded(saved = setOf("canal-gardens"))
        val expected = listOf("pine-loop", "glasshouse-loop", "canal-gardens")
        val names = listOf("duplicate", "enum", "fields", "art", "blank-id", "missing-id", "missing-title", "blank-title", "zero-duration", "zero-distance", "terrain")
        names.forEachIndexed { offset, name ->
            r.repo.refresh(); r.source.success(offset + 1, walks("catalog-invalid-$name"))
            assertIds(expected, QueryWalks().run(r.repo.snapshot!!.walks, "", 60), "CAT-08", name)
            assertEquals(CatalogError.InvalidCatalog, r.repo.error)
            assertEquals(1_000_000L, r.repo.fetchedAtMs)
            assertFalse(r.repo.snapshot!!.walks.any { it.id == "new-valid" })
            assertEquals(setOf("canal-gardens"), r.repo.savedIds)
        }
    }

    @Test fun exactTtlAndFreshFailureRetainTimestampAndSaveEligibility() {
        val r = loaded()
        r.clock.now = 1_299_999
        assertTrue(r.repo.isFresh())
        assertEquals(299_999L, r.repo.ageMs())
        assertEquals(true, oracle("CLOCK-01", "beforeTtl")["fresh"].asBoolean)
        r.clock.now = 1_300_000
        assertFalse(r.repo.isFresh())
        assertEquals(300_000L, r.repo.ageMs())
        assertEquals(false, oracle("CLOCK-01", "atTtl")["fresh"].asBoolean)
        assertEquals(BookmarkResult.RejectedStale, AddBookmark(r.repo).run("canal-gardens").join())
        assertEquals(emptySet<String>(), r.storage.durable)
        r.repo.refresh(); r.source.fail(1)
        assertEquals(CatalogError.SourceUnavailable, r.repo.error)
        assertEquals(1_000_000L, r.repo.fetchedAtMs)
        assertEquals(4, r.repo.snapshot!!.walks.size)
        val fresh = loaded()
        fresh.clock.now = 1_000_100
        fresh.repo.refresh(); fresh.source.fail(1)
        assertTrue(fresh.repo.isFresh())
        assertEquals(1_000_000L, fresh.repo.fetchedAtMs)
        assertEquals(BookmarkResult.RejectedClosed, AddBookmark(fresh.repo).run("glasshouse-loop").join())
    }

    @Test fun staleReturnStartsOneRefreshAndKeepsCacheAfterFailure() {
        val r = loaded()
        r.clock.now = 1_300_000
        r.repo.openList(); r.repo.openList()
        assertEquals(2, r.source.requests.size)
        assertTrue(r.repo.refreshing)
        r.source.fail(1)
        assertFalse(r.repo.refreshing)
        assertEquals(CatalogError.SourceUnavailable, r.repo.error)
        assertIds(listOf("pine-loop", "glasshouse-loop", "canal-gardens"), QueryWalks().run(r.repo.snapshot!!.walks, "", 60), "CAT-06", "failure")
    }

    @Test fun emptyCacheFailureThenRetryPublishesFirstValidSnapshot() {
        val r = rig(saved = setOf("canal-gardens"))
        r.repo.loadBookmarks().join()
        r.repo.openList()
        assertNull(r.repo.snapshot)
        r.source.fail(0)
        assertEquals(CatalogError.SourceUnavailable, r.repo.error)
        assertNull(r.repo.fetchedAtMs)
        r.repo.refresh()
        r.source.success(1, walks("catalog-valid"))
        assertNull(r.repo.error)
        assertEquals(1_000_000L, r.repo.fetchedAtMs)
        assertIds(listOf("pine-loop", "glasshouse-loop", "canal-gardens"),
            QueryWalks().run(r.repo.snapshot!!.walks, "", 60), "CAT-05", "success")
        assertEquals(1, r.repo.savedCount)
    }

    @Test fun newerSuccessWinsWhenOlderCompletesLastIncludingTimestampAndError() {
        val r = loaded(saved = setOf("canal-gardens"))
        r.clock.now = 1_000_100; r.repo.refresh() // A
        r.repo.refresh() // B
        r.clock.now = 1_000_150; r.source.success(2, walks("catalog-changed"))
        assertIds(listOf("pine-loop", "glasshouse-loop", "river-walk"), QueryWalks().run(r.repo.snapshot!!.walks, "", 60), "CAT-07", "finishB")
        assertEquals(1_000_150L, r.repo.fetchedAtMs)
        assertNull(r.repo.error)
        assertEquals(0, r.repo.savedCount)
        assertEquals(setOf("canal-gardens"), r.repo.savedIds)
        r.clock.now = 1_000_200; r.source.success(1, walks("catalog-boundary"))
        assertIds(listOf("pine-loop", "glasshouse-loop", "river-walk"), QueryWalks().run(r.repo.snapshot!!.walks, "", 60), "CAT-07", "finishA")
        assertEquals(1_000_150L, r.repo.fetchedAtMs)
        assertNull(r.repo.error)
    }

    @Test fun olderFailureCannotSetErrorAndOlderSuccessCannotClearNewerError() {
        val a = loaded()
        a.repo.refresh(); a.repo.refresh(); a.clock.now = 1_000_350
        a.source.success(2, walks("catalog-changed")); a.source.fail(1)
        assertNull(a.repo.error); assertEquals(1_000_350L, a.repo.fetchedAtMs)
        val b = loaded()
        b.repo.refresh(); b.repo.refresh(); b.clock.now = 1_000_500
        b.source.fail(2); b.clock.now = 1_000_600; b.source.success(1, walks("catalog-changed"))
        assertEquals(CatalogError.SourceUnavailable, b.repo.error)
        assertEquals(1_000_000L, b.repo.fetchedAtMs)
        assertEquals("canal-gardens", b.repo.snapshot!!.walks[2].id)
    }

    @Test fun failedAtomicAddAndRemoveLeaveMemoryAndDurableIdsUntouchedUntilRetry() {
        val r = loaded(saved = setOf("glasshouse-loop"))
        val add: AddBookmarkUseCase = AddBookmark(r.repo)
        val first = add.run("canal-gardens")
        assertFalse(first.isDone); assertEquals(setOf("glasshouse-loop"), r.repo.savedIds)
        assertEquals(BookmarkResult.Busy, add.run("canal-gardens").join())
        assertEquals(1, r.storage.writes.size)
        r.storage.fail(0)
        assertEquals(BookmarkResult.WriteFailed, first.join())
        assertEquals(setOf("glasshouse-loop"), r.repo.savedIds)
        assertEquals(setOf("glasshouse-loop"), r.storage.durable)
        val retry = r.repo.retryBookmarkWrite(); r.storage.succeed(1)
        assertEquals(BookmarkResult.Saved, retry.join())
        assertEquals(setOf("glasshouse-loop", "canal-gardens"), r.repo.savedIds)
        r.clock.now = 1_300_000
        val remove: RemoveBookmarkUseCase = RemoveBookmark(r.repo)
        val removeAttempt = remove.run("glasshouse-loop")
        r.storage.fail(2)
        assertEquals(BookmarkResult.WriteFailed, removeAttempt.join())
        assertEquals(setOf("glasshouse-loop", "canal-gardens"), r.repo.savedIds)
        val removeRetry = r.repo.retryBookmarkWrite(); r.storage.succeed(3)
        assertEquals(BookmarkResult.Removed, removeRetry.join())
        assertEquals(setOf("canal-gardens"), r.repo.savedIds)
        assertEquals(r.storage.durable, r.repo.savedIds)
    }

    @Test fun staleClosedReasonPrecedesStaleAndSavedStaleRemovalStillWorks() {
        val r = loaded(saved = setOf("canal-gardens"))
        r.clock.now = 1_300_000
        assertEquals("closed", oracle("SAVE-03", "closed")["disabledReason"].asString)
        assertEquals(BookmarkResult.RejectedClosed, AddBookmark(r.repo).run("glasshouse-loop").join())
        assertEquals("stale", oracle("SAVE-03", "openStale")["disabledReason"].asString)
        assertEquals(BookmarkResult.RejectedStale, AddBookmark(r.repo).run("pine-loop").join())
        val removal = RemoveBookmark(r.repo).run("canal-gardens")
        assertEquals(1, r.storage.writes.size)
        r.storage.succeed(0)
        assertEquals(BookmarkResult.Removed, removal.join())
        assertEquals(emptySet<String>(), r.storage.durable)
    }

    @Test fun obsoleteBookmarkLoadCannotOverwriteCommittedWrite() {
        val r = loaded()
        val write = AddBookmark(r.repo).run("pine-loop")
        r.storage.deferLoads = true
        val reload = r.repo.loadBookmarks()
        r.storage.succeed(0)
        assertEquals(BookmarkResult.Saved, write.join())
        r.storage.loads.forEach { (captured, future) -> future.complete(captured) }
        reload.join()
        assertEquals(setOf("pine-loop"), r.repo.savedIds)
        assertEquals(setOf("pine-loop"), r.storage.durable)
    }

    @Test fun failedRemoveRetryWaitsForStorageReadiness() {
        val r = loaded(saved = setOf("glasshouse-loop"))
        val first = RemoveBookmark(r.repo).run("glasshouse-loop")
        r.storage.fail(0)
        assertEquals(BookmarkResult.WriteFailed, first.join())
        r.storage.deferLoads = true
        val reload = r.repo.loadBookmarks()
        val blocked = r.repo.retryBookmarkWrite()
        assertTrue("Retry must reject immediately while storage is loading", blocked.isDone)
        assertEquals(BookmarkResult.RejectedStorageUnavailable, blocked.join())
        assertEquals(1, r.storage.writes.size)
        r.storage.loads.forEach { (captured, future) -> future.complete(captured) }
        reload.join()
        val retry = r.repo.retryBookmarkWrite()
        r.storage.succeed(1)
        assertEquals(BookmarkResult.Removed, retry.join())
        assertEquals(emptySet<String>(), r.repo.savedIds)
    }

    @Test fun missingSavedIdSurvivesCatalogChangeAndStorageLoadFailureDisablesAdd() {
        val r = loaded(saved = setOf("canal-gardens", "retired-walk"))
        assertEquals(1, r.repo.savedCount)
        r.repo.refresh(); r.source.success(1, walks("catalog-changed"))
        assertEquals(0, r.repo.savedCount)
        assertEquals(setOf("canal-gardens", "retired-walk"), r.repo.savedIds)
        assertEquals(BookmarkResult.RejectedMissing, AddBookmark(r.repo).run("canal-gardens").join())
        val source = Source(); val storage = object : BookmarkStorage {
            var fail = true
            override fun loadIds(): CompletableFuture<Set<String>> = if (fail) CompletableFuture.failedFuture(IllegalStateException("disk")) else CompletableFuture.completedFuture(setOf("canal-gardens"))
            override fun writeIds(ids: Set<String>) = CompletableFuture.completedFuture(Unit)
        }
        val repo = FieldGuideRepository(source, storage, Clock(), CatalogMapper())
        repo.refresh(); source.success(0, walks("catalog-valid")); repo.loadBookmarks().join()
        assertEquals(BookmarkLoadState.Error, repo.bookmarkLoadState)
        assertNull(repo.savedCount)
        assertEquals(BookmarkResult.RejectedStorageUnavailable, AddBookmark(repo).run("pine-loop").join())
        storage.fail = false; repo.loadBookmarks().join()
        assertEquals(BookmarkLoadState.Loaded, repo.bookmarkLoadState)
        assertEquals(1, repo.savedCount)
    }
}
