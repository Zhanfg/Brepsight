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
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Product-level facade for the 0.1 mobile viewer.
 *
 * CadEnginePlugin remains the stable renderer/importer bridge. This facade
 * keeps container preprocessing, asynchronous import orchestration,
 * cancellation semantics, progress, screen-to-model picking and section-plane
 * reloads outside that core so the original plugin path stays regression-safe.
 */
class CadEngineEntrypoint : FlutterPlugin, ActivityAware {
    private val core = CadEnginePlugin()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var context: Context
    private var channel: MethodChannel? = null

    private val fcStdSourceByHandle = ConcurrentHashMap<Long, String>()
    private val fcStdPreparedByHandle = ConcurrentHashMap<Long, FcStdPreparedArchive>()

    private val loadSequence = AtomicLong(1L)
    private val cancelRequested = AtomicBoolean(false)
    private val loadStateLock = Any()
    @Volatile private var activeLoadId = 0L
    @Volatile private var activeLoadPath = ""
    @Volatile private var activeLoadStage = "idle"
    @Volatile private var activeLoadProgress = 0

    private data class PreviousDocument(
        val handle: Long,
        val sourcePath: String,
        val formatId: String,
        val preparedFcStd: FcStdPreparedArchive?,
    )

    private data class LoadOutcome(
        val response: MutableMap<Any?, Any?>,
        val handle: Long? = null,
        val preparedFcStd: FcStdPreparedArchive? = null,
    )

    private class CaptureResult : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        var errorDetails: Any? = null
        var notImplemented = false

        override fun success(value: Any?) {
            this.value = value
        }

        override fun error(code: String, message: String?, details: Any?) {
            errorCode = code
            errorMessage = message
            errorDetails = details
        }

        override fun notImplemented() {
            notImplemented = true
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        core.onAttachedToEngine(binding)

        // CadEnginePlugin registers this channel first. Re-registering the same
        // channel installs the facade as the final handler. Calls outside the
        // 0.1 orchestration surface are delegated unchanged to core.
        channel = MethodChannel(binding.binaryMessenger, "cad_engine/methods").also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "loadModel" -> loadModelAsync(call.argument<String>("path").orEmpty(), result)
                    "getImportProgress" -> result.success(importProgressSnapshot())
                    "cancelImport" -> result.success(requestImportCancellation())
                    "getDocumentSummary" -> getDocumentSummaryWithSourceOverride(call, result)
                    "pickModelPoint" -> pickModelPoint(call, result)
                    "setSectionPlane" -> setSectionPlane(call, result)
                    else -> core.onMethodCall(call, result)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        cancelRequested.set(true)
        releaseAllFcStdLeases()
        core.onDetachedFromEngine(binding)
    }

    private fun invokeCore(method: String, arguments: Any?): Any? {
        val capture = CaptureResult()
        core.onMethodCall(MethodCall(method, arguments), capture)
        capture.errorCode?.let { code ->
            throw IllegalStateException("$code: ${capture.errorMessage ?: "native call failed"}")
        }
        if (capture.notImplemented) {
            throw UnsupportedOperationException("Core method is not implemented: $method")
        }
        return capture.value
    }

    private fun isFcStdPath(path: String): Boolean =
        File(path).extension.equals("fcstd", ignoreCase = true)

    private fun updateLoadState(stage: String, progress: Int) {
        activeLoadStage = stage
        activeLoadProgress = progress.coerceIn(0, 100)
    }

    private fun importProgressSnapshot(): Map<String, Any?> = synchronized(loadStateLock) {
        mapOf(
            "active" to (activeLoadId != 0L),
            "taskId" to activeLoadId,
            "path" to activeLoadPath,
            "stage" to activeLoadStage,
            "progress" to activeLoadProgress,
            "cancelRequested" to cancelRequested.get(),
        )
    }

    private fun requestImportCancellation(): Boolean = synchronized(loadStateLock) {
        if (activeLoadId == 0L) return@synchronized false
        cancelRequested.set(true)
        activeLoadStage = "cancelling"
        true
    }

    private fun loadModelAsync(path: String, result: MethodChannel.Result) {
        if (path.isBlank()) {
            result.success(failure(File(path), "Document path is empty.", "unknown", 1490))
            return
        }

        val taskId = synchronized(loadStateLock) {
            if (activeLoadId != 0L) {
                result.error("IMPORT_BUSY", "Another model import is already active.", null)
                return
            }
            val id = loadSequence.getAndIncrement()
            activeLoadId = id
            activeLoadPath = path
            activeLoadStage = "queued"
            activeLoadProgress = 2
            cancelRequested.set(false)
            id
        }

        val previous = capturePreviousDocument()
        Thread {
            var outcome: LoadOutcome? = null
            try {
                updateLoadState("preparing", 8)
                if (cancelRequested.get()) {
                    mainHandler.post { result.success(cancelled(File(path), previous != null)) }
                    return@Thread
                }

                updateLoadState("importing", 20)
                outcome = loadPathBlocking(path)

                if (cancelRequested.get()) {
                    updateLoadState("restoring", 92)
                    if (outcome.response["ok"] == true) {
                        restorePreviousDocument(previous)
                        outcome.handle?.let(::releaseFcStdHandle)
                    }
                    nativeInvalidatePickCache()
                    mainHandler.post { result.success(cancelled(File(path), previous != null)) }
                    return@Thread
                }

                if (outcome.response["ok"] == true) {
                    updateLoadState("finalizing", 94)
                    previous?.let { old ->
                        if (old.handle != outcome.handle) releaseFcStdHandle(old.handle)
                    }
                    nativeInvalidatePickCache()
                }
                updateLoadState("complete", 100)
                mainHandler.post { result.success(outcome.response) }
            } catch (error: Throwable) {
                // A failed provider load never replaces the current native
                // document. If an FCStd preprocessing lease was created before
                // failure, drop only that new lease.
                outcome?.handle?.let { handle ->
                    if (outcome?.response?.get("ok") != true) releaseFcStdHandle(handle)
                }
                mainHandler.post {
                    result.success(
                        failure(
                            File(path),
                            error.message ?: "Unable to import model.",
                            File(path).extension.lowercase().ifBlank { "unknown" },
                            1491,
                        )
                    )
                }
            } finally {
                synchronized(loadStateLock) {
                    if (activeLoadId == taskId) {
                        activeLoadId = 0L
                        activeLoadPath = ""
                        if (activeLoadStage != "complete") activeLoadStage = "idle"
                        cancelRequested.set(false)
                    }
                }
            }
        }.start()
    }

    private fun loadPathBlocking(path: String): LoadOutcome =
        if (isFcStdPath(path)) loadFcStdBlocking(File(path)) else loadOrdinaryBlocking(path)

    private fun loadOrdinaryBlocking(path: String): LoadOutcome {
        val raw = invokeCore("loadModel", mapOf("path" to path))
        val response = mutableMapOf<Any?, Any?>()
        if (raw is Map<*, *>) response.putAll(raw)
        val handle = if (response["ok"] == true) captureCurrentHandle() else null
        return LoadOutcome(response = response, handle = handle)
    }

    private fun loadFcStdBlocking(source: File): LoadOutcome {
        var prepared: FcStdPreparedArchive? = null
        try {
            prepared = FcStdArchivePreparer.prepare(source, context.cacheDir)
            if (cancelRequested.get()) {
                prepared.workDir.deleteRecursively()
                return LoadOutcome(cancelled(source, capturePreviousDocument() != null).toMutableMap())
            }

            val raw = invokeCore("loadModel", mapOf("path" to prepared.manifestFile.absolutePath))
            val response = mutableMapOf<Any?, Any?>()
            if (raw is Map<*, *>) response.putAll(raw)
            response["displayName"] = source.name
            response["formatId"] = "fcstd"
            response["readOnly"] = true
            response["recomputed"] = false
            response["preparedShapeCount"] = prepared.referencedShapeCount
            response["documentObjectCount"] = prepared.documentObjectCount

            if (response["ok"] == true) {
                response["message"] =
                    "OK (read-only FreeCAD saved geometry; parametric recompute disabled)"
                val handle = captureCurrentHandle()
                    ?: throw IllegalStateException("FCStd load succeeded without a current document handle.")
                fcStdSourceByHandle[handle] = source.absolutePath
                fcStdPreparedByHandle[handle] = prepared
                return LoadOutcome(response, handle, prepared)
            }

            prepared.workDir.deleteRecursively()
            return LoadOutcome(response)
        } catch (error: FcStdRejectedException) {
            prepared?.workDir?.deleteRecursively()
            return LoadOutcome(
                fcStdFailure(source, error.message, 1401).toMutableMap()
            )
        } catch (error: Throwable) {
            prepared?.workDir?.deleteRecursively()
            return LoadOutcome(
                fcStdFailure(source, error.message, 1402).toMutableMap()
            )
        }
    }

    private fun capturePreviousDocument(): PreviousDocument? {
        val handle = captureCurrentHandle() ?: return null
        val raw = runCatching {
            invokeCore("getDocumentSummary", mapOf("handle" to handle))
        }.getOrNull() as? Map<*, *> ?: return null
        val format = raw["formatId"] as? String ?: return null
        val corePath = raw["sourcePath"] as? String ?: return null
        val sourcePath = fcStdSourceByHandle[handle] ?: corePath
        return PreviousDocument(
            handle = handle,
            sourcePath = sourcePath,
            formatId = format,
            preparedFcStd = fcStdPreparedByHandle[handle],
        )
    }

    private fun restorePreviousDocument(previous: PreviousDocument?) {
        if (previous == null) {
            clearCurrentDocumentAfterCancellation()
            return
        }

        val prepared = previous.preparedFcStd
        if (prepared != null && prepared.manifestFile.isFile) {
            val raw = invokeCore("loadModel", mapOf("path" to prepared.manifestFile.absolutePath))
            val response = raw as? Map<*, *>
            if (response?.get("ok") != true) {
                throw IllegalStateException("Unable to restore the previous FCStd document after cancellation.")
            }
            val restoredHandle = captureCurrentHandle()
                ?: throw IllegalStateException("Restored FCStd document has no native handle.")
            fcStdSourceByHandle.remove(previous.handle)
            fcStdPreparedByHandle.remove(previous.handle)
            fcStdSourceByHandle[restoredHandle] = previous.sourcePath
            fcStdPreparedByHandle[restoredHandle] = prepared
            return
        }

        val raw = invokeCore("loadModel", mapOf("path" to previous.sourcePath))
        val response = raw as? Map<*, *>
        if (response?.get("ok") != true) {
            throw IllegalStateException("Unable to restore the previous document after cancellation.")
        }
    }

    private fun clearCurrentDocumentAfterCancellation() {
        val loadedHandle = captureCurrentHandle() ?: return
        val blank = invokeCore(
            "beginDocumentTransaction",
            mapOf("path" to "__brepsight_cancelled__", "formatId" to "empty"),
        ) as? Number ?: return
        invokeCore("commitDocumentTransaction", mapOf("handle" to blank.toLong()))
        invokeCore("discardDocumentTransaction", mapOf("handle" to loadedHandle))
    }

    private fun cancelled(source: File, preservedPrevious: Boolean): Map<String, Any?> =
        mapOf(
            "ok" to false,
            "cancelled" to true,
            "displayName" to source.name,
            "message" to if (preservedPrevious) {
                "Import cancelled; the previous visible document was preserved."
            } else {
                "Import cancelled."
            },
            "formatId" to source.extension.lowercase().ifBlank { "unknown" },
            "triangleCount" to 0L,
            "hasUv" to false,
            "hasNormals" to false,
            "exactGeometry" to false,
            "rootObjectCount" to 0L,
            "hierarchyNodeCount" to 0L,
            "errorCode" to 1499,
        )

    private fun failure(
        source: File,
        message: String,
        formatId: String,
        errorCode: Int,
    ): Map<String, Any?> =
        mapOf(
            "ok" to false,
            "displayName" to source.name,
            "message" to message,
            "formatId" to formatId,
            "triangleCount" to 0L,
            "hasUv" to false,
            "hasNormals" to false,
            "exactGeometry" to false,
            "rootObjectCount" to 0L,
            "hierarchyNodeCount" to 0L,
            "errorCode" to errorCode,
        )

    private fun fcStdFailure(source: File, message: String?, errorCode: Int): Map<String, Any?> =
        failure(
            source,
            message ?: "Unable to open FCStd document safely.",
            "fcstd",
            errorCode,
        ) + mapOf(
            "readOnly" to true,
            "recomputed" to false,
        )

    private fun captureCurrentHandle(): Long? {
        val value = runCatching { invokeCore("getCurrentDocumentHandle", null) }.getOrNull()
        return (value as? Number)?.toLong()?.takeIf { it > 0L }
    }

    private fun releaseFcStdHandle(handle: Long) {
        fcStdSourceByHandle.remove(handle)
        fcStdPreparedByHandle.remove(handle)?.workDir?.deleteRecursively()
    }

    private fun releaseAllFcStdLeases() {
        val unique = fcStdPreparedByHandle.values.toSet()
        fcStdPreparedByHandle.clear()
        fcStdSourceByHandle.clear()
        unique.forEach { it.workDir.deleteRecursively() }
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
                    if (response["formatId"] == "fcstd") response["sourcePath"] = overridePath
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

    private fun pickModelPoint(call: MethodCall, result: MethodChannel.Result) {
        val requestedHandle = call.argument<Number>("handle")?.toLong()
        val handle = requestedHandle?.takeIf { it > 0L } ?: captureCurrentHandle()
        if (handle == null) {
            result.success(null)
            return
        }

        val prepared = fcStdPreparedByHandle[handle]
        val path = if (prepared != null && prepared.manifestFile.isFile) {
            prepared.manifestFile.absolutePath
        } else {
            val raw = runCatching {
                invokeCore("getDocumentSummary", mapOf("handle" to handle))
            }.getOrNull() as? Map<*, *>
            raw?.get("sourcePath") as? String
        }
        if (path.isNullOrBlank()) {
            result.success(null)
            return
        }

        val hit = nativePickModelPoint(
            path,
            call.argument<Number>("width")?.toInt() ?: 1,
            call.argument<Number>("height")?.toInt() ?: 1,
            call.argument<Number>("orbitX")?.toDouble() ?: 0.55,
            call.argument<Number>("orbitY")?.toDouble() ?: -0.35,
            call.argument<Number>("panX")?.toDouble() ?: 0.0,
            call.argument<Number>("panY")?.toDouble() ?: 0.0,
            call.argument<Number>("zoom")?.toDouble() ?: 1.0,
            call.argument<Boolean>("orthographic") ?: false,
            call.argument<Number>("screenX")?.toDouble() ?: 0.0,
            call.argument<Number>("screenY")?.toDouble() ?: 0.0,
        )
        result.success(hit?.toList())
    }

    private fun setSectionPlane(call: MethodCall, result: MethodChannel.Result) {
        synchronized(loadStateLock) {
            if (activeLoadId != 0L) {
                result.error("IMPORT_BUSY", "Section plane cannot change during an active import.", null)
                return
            }
        }

        val enabled = call.argument<Boolean>("enabled") ?: false
        val ok = nativeSetSectionPlane(
            enabled,
            call.argument<Number>("nx")?.toDouble() ?: 0.0,
            call.argument<Number>("ny")?.toDouble() ?: 0.0,
            call.argument<Number>("nz")?.toDouble() ?: 1.0,
            call.argument<Number>("offset")?.toDouble() ?: 0.0,
        )
        if (!ok) {
            result.error(
                "SECTION_INVALID",
                nativeSectionPlaneError().ifBlank { "Invalid section plane." },
                null,
            )
            return
        }

        val current = capturePreviousDocument()
        if (current == null) {
            nativeInvalidatePickCache()
            result.success(true)
            return
        }

        Thread {
            try {
                val oldHandle = current.handle
                val prepared = current.preparedFcStd
                val response = if (prepared != null && prepared.manifestFile.isFile) {
                    invokeCore("loadModel", mapOf("path" to prepared.manifestFile.absolutePath)) as? Map<*, *>
                } else {
                    invokeCore("loadModel", mapOf("path" to current.sourcePath)) as? Map<*, *>
                }
                if (response?.get("ok") != true) {
                    throw IllegalStateException("Unable to rebuild the display mesh for the section plane.")
                }
                if (prepared != null) {
                    val newHandle = captureCurrentHandle()
                        ?: throw IllegalStateException("Sectioned FCStd document has no native handle.")
                    fcStdSourceByHandle.remove(oldHandle)
                    fcStdPreparedByHandle.remove(oldHandle)
                    fcStdSourceByHandle[newHandle] = current.sourcePath
                    fcStdPreparedByHandle[newHandle] = prepared
                }
                nativeInvalidatePickCache()
                mainHandler.post { result.success(true) }
            } catch (error: Throwable) {
                mainHandler.post { result.error("SECTION_RELOAD_FAILED", error.message, null) }
            }
        }.start()
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

    private external fun nativeSetSectionPlane(
        enabled: Boolean,
        nx: Double,
        ny: Double,
        nz: Double,
        offset: Double,
    ): Boolean

    private external fun nativeSectionPlaneError(): String
    private external fun nativeInvalidatePickCache()
    private external fun nativePickModelPoint(
        path: String,
        width: Int,
        height: Int,
        orbitX: Double,
        orbitY: Double,
        panX: Double,
        panY: Double,
        zoom: Double,
        orthographic: Boolean,
        screenX: Double,
        screenY: Double,
    ): DoubleArray?
}
