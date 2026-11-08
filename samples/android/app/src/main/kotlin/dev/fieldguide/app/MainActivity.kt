package dev.fieldguide.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.content.res.AssetManager
import android.util.AtomicFile
import androidx.activity.compose.BackHandler
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import dev.fieldguide.catalog.api.*
import dev.fieldguide.catalog.impl.*
import dev.fieldguide.feature.catalog.*
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.CompletableFuture
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : ComponentActivity() {
    private lateinit var model: CatalogViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        model = ViewModelProvider(this, object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                val clock = MonotonicClock { SystemClock.elapsedRealtime() }
                val handler = Handler(Looper.getMainLooper())
                val repository = FieldGuideRepository(
                    AssetCatalogSource(applicationContext.assets, intent.getStringExtra("fieldguide.catalogFixture")),
                    FileBookmarkStorage(File(filesDir, "saved-walks.json")), clock, CatalogMapper(),
                )
                val scheduler = ExpiryScheduler { delay, task ->
                    val callback = Runnable(task)
                    handler.postDelayed(callback, delay)
                    CancelExpiry { handler.removeCallbacks(callback) }
                }
                val feature = CatalogFeature(repository, QueryWalks(), AddBookmark(repository),
                    RemoveBookmark(repository), clock, scheduler) { action -> handler.post(action) }
                @Suppress("UNCHECKED_CAST")
                return CatalogViewModel(feature) as T
            }
        })[CatalogViewModel::class.java]
        setContent {
            val view = model.view
            BackHandler(enabled = view.screen != ScreenKind.List) { model.dispatch(FeatureAction.BackToList) }
            FieldGuideScreens(view, model::dispatch)
        }
    }

    override fun onResume() {
        super.onResume()
        if (::model.isInitialized) model.onForeground()
    }
}

/** Launch with fieldguide.catalogFixture=source-error, catalog-changed, or a catalog fixture name. */
internal class AssetCatalogSource(private val assets: AssetManager, selection: String?) : CatalogSource {
    private val fixture = selection?.takeIf {
        it == "source-error" || it.matches(Regex("catalog-[a-z-]+"))
    } ?: "catalog-valid"

    override fun loadWalks(): CompletableFuture<String> = CompletableFuture.supplyAsync {
        if (fixture == "source-error") error("Demo source failure")
        val raw = assets.open("catalog/$fixture.json").bufferedReader().use { it.readText() }
        JSONObject(raw).getJSONArray("walks").toString()
    }
}

/** AtomicFile replaces the whole saved-ID set or keeps the previous file on failure. */
internal class FileBookmarkStorage(file: File) : BookmarkStorage {
    private val atomic = AtomicFile(file)
    private val lock = Any()

    override fun loadIds(): CompletableFuture<Set<String>> = CompletableFuture.supplyAsync {
        synchronized(lock) {
            val raw = try { atomic.openRead().bufferedReader().use { it.readText() } }
                catch (_: FileNotFoundException) { return@synchronized emptySet() }
            val array = JSONArray(raw)
            (0 until array.length()).map { array.getString(it) }.toSet()
        }
    }

    override fun writeIds(ids: Set<String>): CompletableFuture<Unit> = CompletableFuture.supplyAsync {
        synchronized(lock) {
            val output = atomic.startWrite()
            try {
                output.write(JSONArray(ids.sorted()).toString().toByteArray(Charsets.UTF_8))
                atomic.finishWrite(output)
            } catch (failure: Exception) {
                atomic.failWrite(output)
                throw failure
            }
            Unit
        }
    }
}
