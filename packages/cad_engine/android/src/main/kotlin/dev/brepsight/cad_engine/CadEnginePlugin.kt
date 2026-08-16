package dev.brepsight.cad_engine

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.io.File

class CadEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val OPEN_DOCUMENT_REQUEST = 8217
        private const val NOTIFICATION_PERMISSION_REQUEST = 8218
        init { System.loadLibrary("cad_engine") }
    }

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingOpenResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var surfaceWidth = 1
    private var surfaceHeight = 1

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "cad_engine/methods")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeViewport()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createViewport" -> {
                surfaceWidth = call.argument<Int>("width")?.coerceAtLeast(1) ?: 1
                surfaceHeight = call.argument<Int>("height")?.coerceAtLeast(1) ?: 1
                disposeViewport()
                val newProducer = textureRegistry.createSurfaceProducer()
                producer = newProducer
                newProducer.setSize(surfaceWidth, surfaceHeight)
                newProducer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                    override fun onSurfaceAvailable() {
                        attachCurrentSurface()
                    }

                    override fun onSurfaceCleanup() {
                        nativeDetachSurface()
                    }
                })
                attachCurrentSurface()
                result.success(newProducer.id())
            }
            "resizeViewport" -> {
                surfaceWidth = call.argument<Int>("width")?.coerceAtLeast(1) ?: surfaceWidth
                surfaceHeight = call.argument<Int>("height")?.coerceAtLeast(1) ?: surfaceHeight
                producer?.setSize(surfaceWidth, surfaceHeight)
                nativeResize(surfaceWidth, surfaceHeight)
                attachCurrentSurface()
                result.success(null)
            }
            "disposeViewport" -> {
                disposeViewport()
                result.success(null)
            }
            "openDocument" -> openDocument(result)
            "requestBackgroundProcessingPermission" -> requestBackgroundProcessingPermission(result)
            "canShowTaskNotifications" -> result.success(canShowTaskNotifications())
            "promoteBackgroundTask" -> {
                val taskId = call.argument<String>("taskId").orEmpty()
                if (taskId.isBlank()) {
                    result.error("INVALID_TASK", "Task id is empty.", null)
                } else {
                    startModelTaskService(
                        ModelTaskService.ACTION_START,
                        taskId,
                        call.argument<String>("title") ?: "BrepSight model task",
                        call.argument<String>("stage") ?: "Preparing",
                        call.argument<Number>("progress")?.toInt() ?: 0,
                        call.argument<String>("message") ?: "",
                        true,
                    )
                    result.success(null)
                }
            }
            "updateBackgroundTask" -> {
                startModelTaskService(
                    ModelTaskService.ACTION_UPDATE,
                    call.argument<String>("taskId").orEmpty(),
                    call.argument<String>("title") ?: "BrepSight model task",
                    call.argument<String>("stage") ?: "Working",
                    call.argument<Number>("progress")?.toInt() ?: 0,
                    call.argument<String>("message") ?: "",
                    true,
                )
                result.success(null)
            }
            "finishBackgroundTask" -> {
                startModelTaskService(
                    ModelTaskService.ACTION_FINISH,
                    call.argument<String>("taskId").orEmpty(),
                    call.argument<String>("title") ?: "BrepSight model task",
                    call.argument<String>("stage") ?: "Finalizing",
                    call.argument<Number>("progress")?.toInt() ?: 100,
                    call.argument<String>("message") ?: "",
                    call.argument<Boolean>("success") ?: true,
                )
                result.success(null)
            }
            "beginDocumentTransaction" -> {
                val path = call.argument<String>("path") ?: ""
                val formatId = call.argument<String>("formatId") ?: "unknown"
                if (path.isBlank()) {
                    result.error("INVALID_PATH", "Document path is empty.", null)
                } else {
                    result.success(nativeBeginDocumentTransaction(path, formatId))
                }
            }
            "commitDocumentTransaction" -> {
                val handle = call.argument<Number>("handle")?.toLong() ?: 0L
                val previous = nativeCommitDocumentTransaction(handle)
                if (previous < 0L) {
                    result.error("INVALID_HANDLE", "Unknown document handle: $handle", null)
                } else {
                    result.success(if (previous == 0L) null else previous)
                }
            }
            "discardDocumentTransaction" -> {
                val handle = call.argument<Number>("handle")?.toLong() ?: 0L
                result.success(nativeDiscardDocumentTransaction(handle))
            }
            "getCurrentDocumentHandle" -> {
                val handle = nativeCurrentDocumentHandle()
                result.success(if (handle == 0L) null else handle)
            }
            "getDocumentSummary" -> {
                val handle = call.argument<Number>("handle")?.toLong() ?: 0L
                val path = nativeDocumentSourcePath(handle)
                val formatId = nativeDocumentFormatId(handle)
                if (path == null || formatId == null) {
                    result.success(null)
                } else {
                    result.success(
                        mapOf(
                            "handle" to handle,
                            "sourcePath" to path,
                            "formatId" to formatId,
                            "committed" to nativeDocumentCommitted(handle),
                            "current" to (nativeCurrentDocumentHandle() == handle)
                        )
                    )
                }
            }
            "loadModel" -> {
                val path = call.argument<String>("path") ?: ""
                val code = nativeLoadModel(path)
                val file = File(path)
                result.success(
                    mapOf(
                        "ok" to (code == 0),
                        "displayName" to file.name,
                        "message" to if (code == 0) "OK" else "OCCT adapter is not linked yet (code=$code)"
                    )
                )
            }
            "fitAll" -> { nativeCommand("fit_all", 0.0, 0.0); result.success(null) }
            "setProjection" -> { nativeCommand(call.argument<String>("projection") ?: "perspective", 0.0, 0.0); result.success(null) }
            "setDisplayMode" -> { nativeCommand(call.argument<String>("mode") ?: "shaded_edges", 0.0, 0.0); result.success(null) }
            "orbit" -> { nativeCommand("orbit", call.argument<Double>("dx") ?: 0.0, call.argument<Double>("dy") ?: 0.0); result.success(null) }
            "pan" -> { nativeCommand("pan", call.argument<Double>("dx") ?: 0.0, call.argument<Double>("dy") ?: 0.0); result.success(null) }
            "zoom" -> { nativeCommand("zoom", call.argument<Double>("factor") ?: 1.0, 0.0); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun requestBackgroundProcessingPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || canShowTaskNotifications()) {
            result.success(true)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Notification permission must be requested while the app is visible.", null)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("BUSY", "Notification permission request is already active.", null)
            return
        }
        pendingNotificationPermissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun canShowTaskNotifications(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun startModelTaskService(
        action: String,
        taskId: String,
        title: String,
        stage: String,
        progress: Int,
        message: String,
        success: Boolean,
    ) {
        val intent = ModelTaskService.intent(
            context,
            action,
            taskId,
            title,
            stage,
            progress,
            message,
            success,
        )
        if (action == ModelTaskService.ACTION_START && Build.VERSION.SDK_INT >= 26) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun attachCurrentSurface() {
        val current = producer ?: return
        val surface: Surface = current.surface
        if (surface.isValid) {
            nativeAttachSurface(surface, surfaceWidth, surfaceHeight)
        }
    }

    private fun disposeViewport() {
        nativeDetachSurface()
        producer?.setCallback(null)
        producer?.release()
        producer = null
    }

    private fun openDocument(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "No Android Activity is attached.", null)
            return
        }
        if (pendingOpenResult != null) {
            result.error("BUSY", "A file picker is already open.", null)
            return
        }
        pendingOpenResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, OPEN_DOCUMENT_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != OPEN_DOCUMENT_REQUEST) return false
        val result = pendingOpenResult ?: return true
        pendingOpenResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }
        runCatching { importToCache(data.data!!) }
            .onSuccess { result.success(it.absolutePath) }
            .onFailure { result.error("IMPORT_FAILED", it.message, null) }
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false
        val result = pendingNotificationPermissionResult ?: return true
        pendingNotificationPermissionResult = null
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        return true
    }

    private fun importToCache(uri: Uri): File {
        val displayName = queryDisplayName(uri).ifBlank { "model_${System.currentTimeMillis()}" }
        val safeName = displayName.replace(Regex("[\\/:*?\"<>|\u0000-\u001F]"), "_")
        val dir = File(context.cacheDir, "cad_imports").apply { mkdirs() }
        val out = File(dir, safeName)
        context.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Unable to open selected document." }
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out
    }

    private fun queryDisplayName(uri: Uri): String {
        val cursor: Cursor? = context.contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
        )
        cursor.use {
            if (it != null && it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return it.getString(index) ?: ""
            }
        }
        return uri.lastPathSegment ?: ""
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    private external fun nativeAttachSurface(surface: Surface, width: Int, height: Int)
    private external fun nativeDetachSurface()
    private external fun nativeResize(width: Int, height: Int)
    private external fun nativeBeginDocumentTransaction(path: String, formatId: String): Long
    private external fun nativeCommitDocumentTransaction(handle: Long): Long
    private external fun nativeDiscardDocumentTransaction(handle: Long): Boolean
    private external fun nativeCurrentDocumentHandle(): Long
    private external fun nativeDocumentSourcePath(handle: Long): String?
    private external fun nativeDocumentFormatId(handle: Long): String?
    private external fun nativeDocumentCommitted(handle: Long): Boolean
    private external fun nativeLoadModel(path: String): Int
    private external fun nativeCommand(command: String, a: Double, b: Double)
}
