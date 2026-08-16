package dev.brepsight.cad_engine

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
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
        private const val EXPORT_DOCUMENT_REQUEST = 8219
        private const val SPLIT_DOCUMENT_REQUEST = 8220
        private const val MERGE_DOCUMENT_REQUEST = 8221
        init { System.loadLibrary("cad_engine") }
    }

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingOpenResult: MethodChannel.Result? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportFormat: String? = null
    private var pendingExportName: String? = null
    private var pendingSplitResult: MethodChannel.Result? = null
    private var pendingSplitFormat: String? = null
    private var pendingSplitSourcePath: String? = null
    private var pendingSplitSourceFormat: String? = null
    private var pendingMergeResult: MethodChannel.Result? = null
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
                result.success(null)
            }
            "disposeViewport" -> {
                disposeViewport()
                result.success(null)
            }
            "openDocument" -> openDocument(result)
            "mergeDocuments" -> mergeDocuments(result)
            "exportCurrentModel" -> exportCurrentModel(call.argument<String>("formatId").orEmpty(), result)
            "splitCurrentModel" -> splitCurrentModel(call.argument<String>("formatId").orEmpty(), result)
            "analyzeCurrentModel" -> analyzeCurrentModel(result)
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
                            "triangleCount" to nativeDocumentTriangleCount(handle),
                            "hasUv" to nativeDocumentHasUv(handle),
                            "hasNormals" to nativeDocumentHasNormals(handle),
                            "exactGeometry" to nativeDocumentHasExactGeometry(handle),
                            "rootObjectCount" to nativeDocumentRootObjectCount(handle),
                            "hierarchyNodeCount" to nativeDocumentHierarchyNodeCount(handle),
                            "committed" to nativeDocumentCommitted(handle),
                            "current" to (nativeCurrentDocumentHandle() == handle),
                        )
                    )
                }
            }
            "loadModel" -> {
                val path = call.argument<String>("path") ?: ""
                val code = nativeLoadModel(path)
                val file = File(path)
                val handle = if (code == 0) nativeCurrentDocumentHandle() else 0L
                val formatId = if (handle != 0L) nativeDocumentFormatId(handle) ?: "unknown" else file.extension.lowercase()
                val triangleCount = if (handle != 0L) nativeDocumentTriangleCount(handle) else 0L
                val hasUv = handle != 0L && nativeDocumentHasUv(handle)
                val hasNormals = handle != 0L && nativeDocumentHasNormals(handle)
                val exactGeometry = handle != 0L && nativeDocumentHasExactGeometry(handle)
                val rootObjectCount = if (handle != 0L) nativeDocumentRootObjectCount(handle) else 0L
                val hierarchyNodeCount = if (handle != 0L) nativeDocumentHierarchyNodeCount(handle) else 0L
                val message = if (code == 0) {
                    "OK"
                } else {
                    nativeLastError().ifBlank { "Native importer failed (code=$code)" }
                }
                result.success(
                    mapOf(
                        "ok" to (code == 0),
                        "displayName" to file.name,
                        "message" to message,
                        "formatId" to formatId,
                        "triangleCount" to triangleCount,
                        "hasUv" to hasUv,
                        "hasNormals" to hasNormals,
                        "exactGeometry" to exactGeometry,
                        "rootObjectCount" to rootObjectCount,
                        "hierarchyNodeCount" to hierarchyNodeCount,
                        "errorCode" to code,
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

    private fun pickerBusy(): Boolean =
        pendingOpenResult != null || pendingExportResult != null || pendingSplitResult != null || pendingMergeResult != null

    private fun mergeDocuments(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Merging requires a visible Android Activity.", null)
            return
        }
        if (pickerBusy()) {
            result.error("BUSY", "A document picker is already active.", null)
            return
        }

        pendingMergeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, MERGE_DOCUMENT_REQUEST)
    }

    private fun analyzeCurrentModel(result: MethodChannel.Result) {
        val handle = nativeCurrentDocumentHandle()
        if (handle == 0L) {
            result.error("NO_DOCUMENT", "No model is currently loaded.", null)
            return
        }
        val path = nativeDocumentSourcePath(handle)
        val format = nativeDocumentFormatId(handle)
        if (path.isNullOrBlank() || format.isNullOrBlank()) {
            result.error("NO_DOCUMENT", "Current model metadata is incomplete.", null)
            return
        }

        Thread {
            val json = nativeAnalyzeModelFile(path, format)
            mainHandler.post {
                if (json.isBlank()) {
                    result.error("ANALYSIS_FAILED", "Native mesh inspection could not analyze this document.", null)
                } else {
                    result.success(json)
                }
            }
        }.start()
    }

    private fun splitCurrentModel(formatId: String, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Splitting requires a visible Android Activity.", null)
            return
        }
        val normalized = formatId.lowercase()
        if (normalized != "stl" && normalized != "obj") {
            result.error("UNSUPPORTED_FORMAT", "Connected components can currently be written as STL or OBJ.", null)
            return
        }
        val handle = nativeCurrentDocumentHandle()
        if (handle == 0L) {
            result.error("NO_DOCUMENT", "No model is currently loaded.", null)
            return
        }
        if (pickerBusy()) {
            result.error("BUSY", "A document picker is already active.", null)
            return
        }
        val sourcePath = nativeDocumentSourcePath(handle)
        val sourceFormat = nativeDocumentFormatId(handle)
        if (sourcePath.isNullOrBlank() || sourceFormat.isNullOrBlank()) {
            result.error("NO_DOCUMENT", "Current model metadata is incomplete.", null)
            return
        }

        pendingSplitResult = result
        pendingSplitFormat = normalized
        pendingSplitSourcePath = sourcePath
        pendingSplitSourceFormat = sourceFormat
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        activity.startActivityForResult(intent, SPLIT_DOCUMENT_REQUEST)
    }

    private fun exportCurrentModel(formatId: String, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Export requires a visible Android Activity.", null)
            return
        }
        val normalized = formatId.lowercase()
        if (normalized != "stl" && normalized != "obj") {
            result.error("UNSUPPORTED_FORMAT", "Only STL and OBJ writers are connected right now.", null)
            return
        }
        if (nativeCurrentDocumentHandle() == 0L) {
            result.error("NO_DOCUMENT", "No model is currently loaded.", null)
            return
        }
        if (pickerBusy()) {
            result.error("BUSY", "A document picker is already active.", null)
            return
        }

        val sourcePath = nativeDocumentSourcePath(nativeCurrentDocumentHandle()).orEmpty()
        val sourceName = File(sourcePath).nameWithoutExtension.ifBlank { "brepsight-model" }
        val suggestedName = "$sourceName.$normalized"
        pendingExportResult = result
        pendingExportFormat = normalized
        pendingExportName = suggestedName

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeTypeFor(normalized)
            putExtra(Intent.EXTRA_TITLE, suggestedName)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, EXPORT_DOCUMENT_REQUEST)
    }

    private fun mimeTypeFor(format: String): String = when (format) {
        "stl" -> "model/stl"
        "obj" -> "model/obj"
        else -> "application/octet-stream"
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
        if (pickerBusy()) {
            result.error("BUSY", "A document picker is already open.", null)
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

    private fun collectSelectedUris(data: Intent?): List<Uri> {
        if (data == null) return emptyList()
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(uris::add)
            }
        } else {
            data.data?.let(uris::add)
        }
        return uris.distinct()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == OPEN_DOCUMENT_REQUEST) {
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

        if (requestCode == MERGE_DOCUMENT_REQUEST) {
            val result = pendingMergeResult ?: return true
            pendingMergeResult = null
            if (resultCode != Activity.RESULT_OK) {
                result.success(null)
                return true
            }
            val uris = collectSelectedUris(data)
            if (uris.size < 2) {
                result.error("MERGE_NEEDS_MULTIPLE", "Select at least two STL/OBJ files to merge.", null)
                return true
            }

            Thread {
                val sessionId = System.nanoTime()
                val inputDir = File(context.cacheDir, "cad_merges/input_$sessionId")
                val outputDir = File(context.cacheDir, "cad_merges/output").apply { mkdirs() }
                val output = File(outputDir, "merged_$sessionId.obj")
                try {
                    inputDir.mkdirs()
                    val inputs = uris.mapIndexed { index, uri ->
                        val displayName = queryDisplayName(uri).ifBlank { "model_$index" }
                        val extension = displayName.substringAfterLast('.', "").lowercase()
                        if (extension != "stl" && extension != "obj") {
                            throw IllegalArgumentException("Only STL and OBJ can be merged in the current native path: $displayName")
                        }
                        val safeName = displayName.replace(Regex("[\\/:*?\"<>|\u0000-\u001F]"), "_")
                        val cached = File(inputDir, "%03d_%s".format(index + 1, safeName))
                        context.contentResolver.openInputStream(uri).use { input ->
                            requireNotNull(input) { "Unable to open $displayName." }
                            cached.outputStream().use { outputStream -> input.copyTo(outputStream) }
                        }
                        cached.absolutePath
                    }

                    val count = nativeMergeModelFiles(inputs.toTypedArray(), output.absolutePath, "obj")
                    if (count < 2) {
                        throw IllegalStateException("Native mesh merge failed (code=$count).")
                    }
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "ok" to true,
                                "sourceCount" to count,
                                "outputPath" to output.absolutePath,
                                "formatId" to "obj",
                            )
                        )
                    }
                } catch (error: Throwable) {
                    output.delete()
                    mainHandler.post { result.error("MERGE_FAILED", error.message, null) }
                } finally {
                    inputDir.deleteRecursively()
                }
            }.start()
            return true
        }

        if (requestCode == EXPORT_DOCUMENT_REQUEST) {
            val result = pendingExportResult ?: return true
            val format = pendingExportFormat.orEmpty()
            val displayName = pendingExportName.orEmpty()
            pendingExportResult = null
            pendingExportFormat = null
            pendingExportName = null

            val destination = data?.data
            if (resultCode != Activity.RESULT_OK || destination == null) {
                result.success(null)
                return true
            }

            Thread {
                val exportDir = File(context.cacheDir, "cad_exports").apply { mkdirs() }
                val temp = File(exportDir, "export_${System.nanoTime()}.$format")
                try {
                    val code = nativeExportCurrentModel(temp.absolutePath, format)
                    if (code != 0) {
                        val message = nativeLastError().ifBlank { "Native writer failed (code=$code)" }
                        mainHandler.post { result.error("EXPORT_FAILED", message, code) }
                        return@Thread
                    }
                    context.contentResolver.openOutputStream(destination, "w").use { output ->
                        requireNotNull(output) { "Unable to open export destination." }
                        temp.inputStream().use { input -> input.copyTo(output) }
                    }
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "ok" to true,
                                "displayName" to displayName,
                                "formatId" to format,
                                "destinationUri" to destination.toString(),
                            )
                        )
                    }
                } catch (error: Throwable) {
                    mainHandler.post { result.error("EXPORT_FAILED", error.message, null) }
                } finally {
                    temp.delete()
                }
            }.start()
            return true
        }

        if (requestCode == SPLIT_DOCUMENT_REQUEST) {
            val result = pendingSplitResult ?: return true
            val outputFormat = pendingSplitFormat.orEmpty()
            val sourcePath = pendingSplitSourcePath.orEmpty()
            val sourceFormat = pendingSplitSourceFormat.orEmpty()
            pendingSplitResult = null
            pendingSplitFormat = null
            pendingSplitSourcePath = null
            pendingSplitSourceFormat = null

            val treeUri = data?.data
            if (resultCode != Activity.RESULT_OK || treeUri == null) {
                result.success(null)
                return true
            }

            val grantedFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            runCatching {
                context.contentResolver.takePersistableUriPermission(treeUri, grantedFlags)
            }

            Thread {
                val tempDir = File(context.cacheDir, "cad_split/split_${System.nanoTime()}")
                try {
                    tempDir.mkdirs()
                    val count = nativeSplitModelFile(
                        sourcePath,
                        sourceFormat,
                        tempDir.absolutePath,
                        outputFormat,
                    )
                    if (count <= 0) {
                        mainHandler.post {
                            result.error(
                                "SPLIT_FAILED",
                                if (count == 0) "No connected components were produced." else "Native split failed (code=$count)",
                                count,
                            )
                        }
                        return@Thread
                    }

                    val rootDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        DocumentsContract.getTreeDocumentId(treeUri),
                    )
                    val sourceBase = File(sourcePath).nameWithoutExtension.ifBlank { "brepsight-model" }
                    val parts = tempDir.listFiles()?.filter { it.isFile }?.sortedBy { it.name }.orEmpty()
                    if (parts.size != count) {
                        throw IllegalStateException("Expected $count split files, found ${parts.size}.")
                    }

                    parts.forEachIndexed { index, part ->
                        val displayName = "%s_part_%03d.%s".format(sourceBase, index + 1, outputFormat)
                        val destination = DocumentsContract.createDocument(
                            context.contentResolver,
                            rootDocumentUri,
                            mimeTypeFor(outputFormat),
                            displayName,
                        ) ?: throw IllegalStateException("Unable to create $displayName in the selected folder.")
                        context.contentResolver.openOutputStream(destination, "w").use { output ->
                            requireNotNull(output) { "Unable to open $displayName for writing." }
                            part.inputStream().use { input -> input.copyTo(output) }
                        }
                    }

                    mainHandler.post {
                        result.success(
                            mapOf(
                                "ok" to true,
                                "partCount" to count,
                                "formatId" to outputFormat,
                                "destinationUri" to treeUri.toString(),
                            )
                        )
                    }
                } catch (error: Throwable) {
                    mainHandler.post { result.error("SPLIT_FAILED", error.message, null) }
                } finally {
                    tempDir.deleteRecursively()
                }
            }.start()
            return true
        }

        return false
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
    private external fun nativeDocumentTriangleCount(handle: Long): Long
    private external fun nativeDocumentHasUv(handle: Long): Boolean
    private external fun nativeDocumentHasNormals(handle: Long): Boolean
    private external fun nativeDocumentHasExactGeometry(handle: Long): Boolean
    private external fun nativeDocumentRootObjectCount(handle: Long): Long
    private external fun nativeDocumentHierarchyNodeCount(handle: Long): Long
    private external fun nativeLastError(): String
    private external fun nativeLoadModel(path: String): Int
    private external fun nativeExportCurrentModel(path: String, formatId: String): Int
    private external fun nativeAnalyzeModelFile(path: String, formatId: String): String
    private external fun nativeSplitModelFile(
        path: String,
        sourceFormatId: String,
        outputDirectory: String,
        outputFormatId: String,
    ): Int
    private external fun nativeMergeModelFiles(
        paths: Array<String>,
        outputPath: String,
        outputFormatId: String,
    ): Int
    private external fun nativeCommand(command: String, a: Double, b: Double)
}
