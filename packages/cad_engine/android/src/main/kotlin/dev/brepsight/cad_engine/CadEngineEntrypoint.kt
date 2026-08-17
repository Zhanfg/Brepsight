package dev.brepsight.cad_engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Thin plugin facade that keeps container preprocessing separate from the core
 * renderer/importer bridge. CadEnginePlugin remains responsible for the normal
 * cad_engine/methods channel and Android activity lifecycle.
 */
class CadEngineEntrypoint : FlutterPlugin, ActivityAware {
    private val core = CadEnginePlugin()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var context: Context
    private var fcStdChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        core.onAttachedToEngine(binding)
        fcStdChannel = MethodChannel(binding.binaryMessenger, "cad_engine/fcstd").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        val path = call.argument<String>("path").orEmpty()
                        if (path.isBlank()) {
                            result.error("INVALID_PATH", "FCStd source path is empty.", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val prepared = FcStdArchivePreparer.prepare(File(path), context.cacheDir)
                                val payload = mapOf(
                                    "manifestPath" to prepared.manifestFile.absolutePath,
                                    "workDir" to prepared.workDir.absolutePath,
                                    "sourcePath" to prepared.sourceFile.absolutePath,
                                    "referencedShapeCount" to prepared.referencedShapeCount,
                                    "documentObjectCount" to prepared.documentObjectCount,
                                    "archiveEntryCount" to prepared.archiveEntryCount,
                                    "totalUncompressedBytes" to prepared.totalUncompressedBytes,
                                    "readOnly" to true,
                                    "recomputed" to false,
                                )
                                mainHandler.post { result.success(payload) }
                            } catch (error: FcStdRejectedException) {
                                mainHandler.post {
                                    result.error(
                                        "FCSTD_REJECTED",
                                        error.message ?: "FCStd was rejected by the safe reader.",
                                        null,
                                    )
                                }
                            } catch (error: Throwable) {
                                mainHandler.post {
                                    result.error(
                                        "FCSTD_PREPARE_FAILED",
                                        error.message ?: "Unable to prepare FCStd document.",
                                        null,
                                    )
                                }
                            }
                        }.start()
                    }
                    "cleanup" -> {
                        val path = call.argument<String>("workDir").orEmpty()
                        result.success(cleanupPreparedDirectory(path))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        fcStdChannel?.setMethodCallHandler(null)
        fcStdChannel = null
        core.onDetachedFromEngine(binding)
    }

    private fun cleanupPreparedDirectory(path: String): Boolean {
        if (path.isBlank()) return false
        return try {
            val root = File(context.cacheDir, "brepsight-fcstd").canonicalFile
            val candidate = File(path).canonicalFile
            if (candidate == root || !candidate.path.startsWith(root.path + File.separator)) {
                false
            } else {
                candidate.deleteRecursively()
            }
        } catch (_: Throwable) {
            false
        }
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
