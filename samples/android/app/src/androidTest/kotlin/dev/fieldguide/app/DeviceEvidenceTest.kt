package dev.fieldguide.app

import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import androidx.activity.compose.setContent
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.fieldguide.catalog.api.*
import dev.fieldguide.catalog.impl.*
import dev.fieldguide.feature.catalog.*
import org.junit.*
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CompletableFuture

/** Real emulator checks. Controlled source/clock states are explicitly distinguished from the launcher journey. */
@RunWith(AndroidJUnit4::class)
class DeviceEvidenceTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var scenario: ActivityScenario<MainActivity>

    @After fun closeActivity() { if (::scenario.isInitialized) scenario.close() }
    private fun launch(fixture: String? = null) {
        val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        fixture?.let { intent.putExtra("fieldguide.catalogFixture", it) }
        scenario = ActivityScenario.launch(intent)
    }
    private fun waitText(value: String) = compose.waitUntil(10_000) {
        compose.onAllNodesWithText(value, substring = true).fetchSemanticsNodes().isNotEmpty()
    }
    private fun open(id: String) {
        compose.onNodeWithTag("walk-list").performScrollToNode(hasTestTag("walk-$id"))
        compose.onNodeWithTag("walk-$id").performClick()
    }
    private fun text(value: String) = compose.onNodeWithText(value, substring = true)
    private fun shot(name: String) {
        compose.waitForIdle()
        val suffix = InstrumentationRegistry.getArguments().getString("captureSet") ?: "light-1.0"
        val file = File(context.filesDir, "device-evidence/$suffix/$name.png")
        file.parentFile!!.mkdirs()
        file.outputStream().use { compose.onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it) }
        println("CAPTURE ${file.absolutePath}")
    }

    @Test fun launcherSaveBackAndActivityRecreation() {
        context.deleteFile("saved-walks.json")
        launch()
        waitText("Pine loop")
        compose.onNode(hasTestTag("refresh-walks") and hasText("Refresh walks") and hasClickAction()).performClick()
        waitText("Pine loop")

        compose.onNodeWithTag("search-walks").performTextInput("  CANAL  ")
        open("canal-gardens")
        waitText("Canal gardens")
        text("50 minutes · 3.2 km").assertExists()

        compose.onNodeWithTag("save-walk")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()

        waitText("Remove saved walk")
        Assert.assertEquals("[\"canal-gardens\"]", File(context.filesDir, "saved-walks.json").readText())

        compose.onNodeWithTag("back-to-walks").performClick()

        text("1 saved walk").assertExists()
        compose.onNodeWithTag("search-walks").assertTextContains("  CANAL  ")
        compose.onNodeWithTag("walk-canal-gardens").performScrollTo().assertTextContains("Saved", substring = true)

        scenario.recreate()

        waitText("1 saved walk")
        open("canal-gardens")
        text("Remove saved walk").assertExists()
        shot("real-persisted-detail")
        println("REAL_STORAGE_ACTIVITY_RECREATION canal-gardens durable and removable")
    }

    /** Host force-stops the package between the previous test and this test. */
    @Test fun persistedAfterHostProcessRestart() {
        Assert.assertEquals("[\"canal-gardens\"]", File(context.filesDir, "saved-walks.json").readText())
        launch()
        waitText("1 saved walk")
        open("canal-gardens")
        text("Remove saved walk").assertExists()
        shot("real-process-restored-detail")
        println("REAL_STORAGE_PROCESS_RESTART canal-gardens loaded by launcher graph")
    }

    /** Inject only the controlled graph into the real Activity's lifecycle adapter. */
    @Test fun activityResumeRechecksExpiredControlledGraph() {
        launch()
        val source = DeferredSource()
        val clock = DeviceClock()
        val storageFile = File(context.filesDir, "foreground-test-saved.json")
        storageFile.delete()
        val storage = FileBookmarkStorage(storageFile)
        val repository = FieldGuideRepository(source, storage, clock, CatalogMapper())
        val feature = CatalogFeature(repository, QueryWalks(), AddBookmark(repository), RemoveBookmark(repository),
            clock, clock, { action -> Handler(Looper.getMainLooper()).post(action) })
        scenario.onActivity { activity ->
            val controlledModel = CatalogViewModel(feature)
            val modelField = MainActivity::class.java.getDeclaredField("model")
            modelField.isAccessible = true
            modelField.set(activity, controlledModel)
            activity.setContent { FieldGuideScreens(controlledModel.view, controlledModel::dispatch) }
        }
        waitText("Loading walks")
        complete(source, "catalog-valid")
        waitText("Pine loop")
        open("canal-gardens")
        compose.onNodeWithTag("save-walk").assertIsEnabled()
        compose.runOnIdle { clock.setWithoutDue(299999) }
        compose.onNodeWithTag("save-walk").assertIsEnabled()
        compose.runOnIdle { clock.setWithoutDue(300000) }
        // No due callback is fired here. Only MainActivity.onResume can forward
        // Foreground to the injected ViewModel and make this view stale.
        compose.onNodeWithTag("save-walk").assertIsEnabled()
        scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        waitText("Walks may be out of date.")
        compose.onNodeWithTag("save-walk").assertIsNotEnabled()
        Assert.assertEquals(300000L, feature.view.ageMs)
        shot("foreground-expiry")
        compose.runOnIdle { feature.close() }
        println("ACTIVITY_ON_RESUME_FOREGROUND expired at exactly 300000 ms without scheduler callback")
    }

    @Test fun controlledDeviceScenariosAndPreviewCaptures() {
        launch()
        val source = DeferredSource()
        val clock = DeviceClock()
        val storageFile = File(context.filesDir, "device-test-saved.json")
        storageFile.delete()
        val disk = FileBookmarkStorage(storageFile)
        var failWrite = false
        val storage = object : BookmarkStorage {
            override fun loadIds() = disk.loadIds()
            override fun writeIds(ids: Set<String>): CompletableFuture<Unit> = if (failWrite)
                CompletableFuture<Unit>().also { it.completeExceptionally(IllegalStateException("Controlled device write failure")) }
                else disk.writeIds(ids)
        }
        val repository = FieldGuideRepository(source, storage, clock, CatalogMapper())
        val feature = CatalogFeature(repository, QueryWalks(), AddBookmark(repository), RemoveBookmark(repository),
            clock, clock, { action -> Handler(Looper.getMainLooper()).post(action) })
        val state = mutableStateOf(feature.view)
        scenario.onActivity { activity ->
            feature.observe { state.value = it }
            activity.setContent {
                val rendered = if (InstrumentationRegistry.getArguments().getString("negativeVisibleValue") == "true")
                    state.value.copy(savedCount = 7) else state.value
                FieldGuideScreens(rendered, feature::dispatch)
            }
            feature.start()
        }
        waitText("Loading walks")
        compose.waitUntil(10_000) { repository.bookmarkLoadState == BookmarkLoadState.Loaded }
        shot("loading")
        fail(source)
        waitText("Walks could not be loaded.")
        shot("error")
        compose.onNodeWithTag("retry-walks").performClick()
        waitText("Loading walks")
        complete(source, "catalog-valid")
        waitText("Pine loop")
        shot("list")
        compose.onNodeWithTag("budget-30").performClick()
        compose.onNodeWithTag("walk-pine-loop").assertExists()
        compose.onNodeWithTag("walk-glasshouse-loop").assertDoesNotExist()
        compose.onNodeWithTag("budget-15").performClick()
        waitText("No walks match these filters.")
        shot("empty")
        compose.onNodeWithTag("clear-filters").performClick()
        open("glasshouse-loop")
        text("Closed walks cannot be saved.").assertExists()
        compose.onNodeWithTag("save-walk").assertIsNotEnabled()
        shot("closed")
        compose.onNodeWithTag("back-to-walks").performClick()
        compose.onNodeWithTag("search-walks").performTextInput("  CANAL  ")
        open("canal-gardens")
        compose.onNodeWithTag("save-walk").assertIsEnabled()
        shot("detail")
        // Failure is injected only at the write boundary; successful writes use the real adapter.
        failWrite = true
        compose.onNodeWithTag("save-walk").performScrollTo().performClick()
        waitText("Could not update saved walks.")
        Assert.assertFalse(storageFile.exists())
        shot("save-error")
        failWrite = false
        compose.onNodeWithTag("retry-save").performScrollTo().performClick()
        waitText("Remove saved walk")
        compose.onNodeWithTag("save-walk").performScrollTo().performClick()
        waitText("Save walk")
        // The real adapter persists and the real graph updates only after write completion.
        compose.onNodeWithTag("save-walk").performScrollTo().performClick()
        waitText("Remove saved walk")
        shot("saved")
        compose.onNodeWithTag("save-walk").performScrollTo().performClick()
        waitText("Save walk")
        compose.runOnIdle { clock.set(299999) }
        compose.onNodeWithTag("save-walk").assertIsEnabled()
        Assert.assertEquals(299999L, repository.ageMs())
        compose.onNodeWithTag("save-walk").performScrollTo().performClick()
        waitText("Remove saved walk")
        compose.runOnIdle { clock.set(300000) }
        waitText("Walks may be out of date.")
        compose.onNodeWithTag("save-walk").performScrollTo().assertIsEnabled().performClick()
        waitText("Refresh walks to save this walk.")
        compose.onNodeWithTag("save-walk").assertIsNotEnabled()
        Assert.assertEquals(300000L, feature.view.ageMs)
        Assert.assertEquals(BookmarkResult.RejectedStale, AddBookmark(repository).run("canal-gardens").get())
        shot("stale-detail")
        // Foreground checks the same exact boundary and cannot re-enable Save.
        scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        compose.runOnIdle { feature.dispatch(FeatureAction.Foreground) }
        compose.onNodeWithTag("save-walk").assertIsNotEnabled()
        compose.onNodeWithTag("back-to-walks").performClick()
        waitText("Refreshing walks")
        fail(source)
        waitText("Refresh failed.")
        shot("stale-list")
        compose.onNodeWithTag("retry-walks").performScrollTo().performClick()
        complete(source, "catalog-valid")
        waitText("Canal gardens")
        open("canal-gardens")
        compose.onNodeWithTag("save-walk").assertIsEnabled()
        compose.runOnIdle { feature.dispatch(FeatureAction.RefreshCatalog) }
        complete(source, "catalog-changed")
        waitText("Walk unavailable")
        shot("removed")
        compose.onNodeWithTag("back-to-walks").performClick()
        waitText("No walks match these filters.")
        compose.onNodeWithTag("search-walks").assertTextContains("  CANAL  ")
        compose.runOnIdle { feature.dispatch(FeatureAction.OpenDetail("unknown-id")) }
        waitText("Walk unavailable")
        compose.onNodeWithTag("back-to-walks").assertHasClickAction().performClick()
        // The long text fixture is canonical generated APK input, not copied test data.
        compose.runOnIdle { feature.dispatch(FeatureAction.ClearFilters); feature.dispatch(FeatureAction.RefreshCatalog) }
        complete(source, "catalog-long-text")
        waitText("The very long woodland")
        shot("long-list")
        open("long-title")
        shot("long-detail-top")
        compose.onNodeWithTag("save-walk").performScrollTo().assertIsDisplayed().assertIsEnabled()
        text("returning to the start.").assertIsDisplayed()
        shot("long-detail-bottom")
        compose.runOnIdle { feature.close() }
        println("DEVICE_SCENARIOS CAT-01 CAT-03 CAT-04 CAT-05 CAT-06 SAVE-01 SAVE-03 NAV-01 CLOCK-01 VIEW-01 passed")
    }

    private fun complete(source: DeferredSource, fixture: String) {
        val raw = context.assets.open("catalog/$fixture.json").bufferedReader().use { it.readText() }
        source.pending.removeAt(0).complete(org.json.JSONObject(raw).getJSONArray("walks").toString())
        compose.waitForIdle()
    }
    private fun fail(source: DeferredSource) {
        source.pending.removeAt(0).completeExceptionally(IllegalStateException("Controlled device source failure"))
        compose.waitForIdle()
    }
    private class DeferredSource : CatalogSource {
        val pending = mutableListOf<CompletableFuture<String>>()
        override fun loadWalks() = CompletableFuture<String>().also { pending.add(it) }
    }
    private class DeviceClock : MonotonicClock, ExpiryScheduler {
        private var time = 0L
        private val due = mutableListOf<Pair<Long, () -> Unit>>()
        override fun nowMs() = time
        override fun schedule(delayMs: Long, task: () -> Unit): CancelExpiry {
            val entry = (time + delayMs) to task
            due.add(entry)
            return CancelExpiry { due.remove(entry) }
        }
        fun set(value: Long) {
            time = value
            val ready = due.filter { it.first <= time }; due.removeAll(ready.toSet())
            ready.forEach { it.second() }
        }
        fun setWithoutDue(value: Long) { time = value }
    }
}
