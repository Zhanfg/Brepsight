package dev.brepsight.cad_engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Thin plugin facade that keeps untrusted container preprocessing outside the
 * core renderer/importer bridge. All ordinary calls are delegated unchanged to
 * CadEnginePlugin; only FCStd loading and its user-visible source path are
 * intercepted here.
 */
class CadEngineEntrypoint : FlutterPlugin, ActivityAware {
    private val core = CadEnginePlugin()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var context: Context
    private var channel: MethodChannel? = null
    private val fcStdSourceByHandle = ConcurrentHashMap<Long, String>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        core.onAttachedToEngine(binding)

        // CadEnginePlugin registers this channel first. Re-registering the same
        // channel here intentionally installs the facade as the final handler;
        // non-FCStd calls are delegated directly to core.onMethodCall().
        channel = MethodChannel(binding.binaryMessenger, "cad_engine/methods").also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when {
                    call.method == "loadModel" && isFcStdPath(call.argument<String>("path").orEmpty()) ->
                        loadFcStd(call.argument<String>("path").orEmpty(), result)
                    call.method == "getDocumentSummary" ->
                        getDocumentSummaryWithSourceOverride(call, result)
                    else -> core.onMethodCall(call, result)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        fcStdSourceByHandle.clear()
        core.onDetachedFromEngine(binding)
    }

    private fun isFcStdPath(path: String): Boolean =
        File(path).extension.equals("fcstd", ignoreCase = true)

    private fun loadFcStd(path: String, result: MethodChannel.Result) {
        val source = File(path)
        Thread {
            var preparedForCleanup: FcStdPreparedArchive? = null
            try {
                val preparedArchive = FcStdArchivePreparer.prepare(source, context.cacheDir)
                preparedForCleanup = preparedArchive
                val manifestPath = preparedArchive.manifestFile.absolutePath
                val proxy = object : MethodChannel.Result {
                    override fun success(value: Any?) {
                        val response = mutableMapOf<Any?, Any?>()
                        if (value is Map<*, *>) response.putAll(value)
                        response["displayName"] = source.name
                        response["formatId"] = "fcstd"
                        response["readOnly"] = true
                        response["recomputed"] = false
                        response["preparedShapeCount"] = preparedArchive.referencedShapeCount
                        response["documentObjectCount"] = preparedArchive.documentObjectCount
                        if (response["ok"] == true) {
                            response["message"] =
                                "OK (read-only FreeCAD saved geometry; parametric recompute disabled)"
                            captureCurrentHandle()?.let { handle ->
                                fcStdSourceByHandle.clear()
                                fcStdSourceByHandle[handle] = source.absolutePath
                            }
                        }
                        mainHandler.post { result.success(response) }
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        mainHandler.post { result.error(code, message, details) }
                    }

                    override fun notImplemented() {
                        mainHandler.post { result.notImplemented() }
                    }
                }

                // The core loadModel path is synchronous. Running it on this
                // worker keeps ZIP validation and exact BREP import off the UI
                // thread while the proxy marshals the Flutter result back.
                core.onMethodCall(MethodCall("loadModel", mapOf("path" to manifestPath)), proxy)
            } catch (error: FcStdRejectedException) {
                mainHandler.post { result.success(fcStdFailure(source, error.message, 1401)) }
            } catch (error: Throwable) {
                mainHandler.post { result.success(fcStdFailure(source, error.message, 1402)) }
            } finally {
                // BRepTools::Read has already materialized exact shapes and the
                // display mesh by the time core.loadModel returns. No document
                // code or extracted archive payload needs to persist on disk.
                preparedForCleanup?.workDir?.deleteRecursively()
            }
        }.start()
    }

    private fun fcStdFailure(source: File, message: String?, errorCode: Int): Map<String, Any> =
        mapOf(
            "ok" to false,
            "displayName" to source.name,
            "message" to (message ?: "Unable to open FCStd document safely."),
            "formatId" to "fcstd",
            "triangleCount" to 0L,
            "hasUv" to false,
            "hasNormals" to false,
            "exactGeometry" to false,
            "rootObjectCount" to 0L,
            "hierarchyNodeCount" to 0L,
            "readOnly" to true,
            "recomputed" to false,
            "errorCode" to errorCode,
        )

    private fun captureCurrentHandle(): Long? {
        var handle: Long? = null
        core.onMethodCall(
            MethodCall("getCurrentDocumentHandle", null),
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    handle = (value as? Number)?.toLong()
                }

                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() = Unit
            },
        )
        return handle
    }

    private fun getDocumentSummaryWithSourceOverride(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val requestedHandle = call.argument<Number>("handle")?.toLong()
        val overridePath = requestedHandle?.let(fcStdSourceByHandle::get)
        if (overridePath == null) {
            core.onMethodCall(call, result)
            return
        }

        core.onMethodCall(
            call,
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    if (value !is Map<*, *>) {
                        result.success(value)
                        return
                    }
                    val response = mutableMapOf<Any?, Any?>()
                    response.putAll(value)
                    if (response["formatId"] == "fcstd") {
                        response["sourcePath"] = overridePath
                    }
                    result.success(response)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    result.error(code, message, details)
                }

                override fun notImplemented() {
                    result.notImplemented()
                }
            },
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        core.onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        core.onDetachedFromActivityForConfigChanges()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        core.onReattachedToActivityForConfigChanges(binding)
    }

    override fun onDetachedFromActivity() {
        core.onDetachedFromActivity()
    }
}
