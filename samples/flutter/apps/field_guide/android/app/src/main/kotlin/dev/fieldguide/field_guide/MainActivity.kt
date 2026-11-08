package dev.fieldguide.field_guide

import android.os.Handler
import android.os.Looper
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import org.json.JSONArray

/** Original local I/O adapter. Replacement is atomic in the app's private directory. */
class MainActivity : FlutterActivity() {
    private val storageExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val file = File(applicationContext.filesDir, "field-guide-bookmarks.json")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "field_guide/bookmarks")
            .setMethodCallHandler { call, result ->
                if (call.method != "read" && call.method != "write") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                storageExecutor.execute {
                    try {
                        val response: Any? = if (call.method == "read") {
                            if (!file.exists()) emptyList<String>() else {
                                val array = JSONArray(file.readText(Charsets.UTF_8))
                                (0 until array.length()).map { index ->
                                    val id = array.get(index)
                                    require(id is String && id.isNotBlank()) { "Invalid bookmark ID" }
                                    id
                                }.distinct().sorted()
                            }
                        } else {
                            val arguments = call.arguments as? List<*>
                                ?: throw IllegalArgumentException("Expected bookmark list")
                            val ids = arguments.map {
                                require(it is String && it.isNotBlank()) { "Invalid bookmark ID" }
                                it
                            }.distinct().sorted()
                            val temporary = File(file.parentFile, "${file.name}.tmp")
                            try {
                                FileOutputStream(temporary).use { output ->
                                    output.write(JSONArray(ids).toString().toByteArray(Charsets.UTF_8))
                                    output.fd.sync()
                                }
                                Os.rename(temporary.absolutePath, file.absolutePath)
                            } finally {
                                temporary.delete()
                            }
                            null
                        }
                        mainHandler.post { result.success(response) }
                    } catch (error: Exception) {
                        mainHandler.post { result.error("storage-${call.method}", "Saved walks storage failed", null) }
                    }
                }
            }
    }

    override fun onDestroy() {
        storageExecutor.shutdown()
        super.onDestroy()
    }
}
