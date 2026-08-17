package dev.brepsight.cad_engine

import java.io.File

internal class MeshEditSession(
    val originalHandle: Long,
    val originalSourcePath: String,
    val originalFormatId: String,
    val directory: File,
) {
    private val history = mutableListOf<File>()
    private var cursor = -1
    private var sequence = 0L

    var currentHandle: Long = originalHandle
        private set

    val active: Boolean
        get() = history.isNotEmpty() && cursor in history.indices

    val currentFile: File?
        get() = if (active) history[cursor] else null

    val baselineFile: File?
        get() = history.firstOrNull()

    val canUndo: Boolean
        get() = cursor > 0

    val canRedo: Boolean
        get() = cursor >= 0 && cursor < history.lastIndex

    fun initialize(snapshot: File) {
        require(history.isEmpty()) { "Mesh edit session is already initialized." }
        require(snapshot.isFile) { "Initial mesh edit snapshot does not exist." }
        history += snapshot
        cursor = 0
    }

    fun allocateSnapshot(): File {
        directory.mkdirs()
        sequence += 1
        return File(directory, "edit_%04d.obj".format(sequence))
    }

    fun record(snapshot: File, handle: Long) {
        require(snapshot.isFile) { "Mesh edit snapshot does not exist." }
        while (history.lastIndex > cursor) {
            history.removeLast().delete()
        }
        history += snapshot
        cursor = history.lastIndex
        currentHandle = handle
    }

    fun undoCandidate(): File? =
        if (canUndo) history[cursor - 1] else null

    fun redoCandidate(): File? =
        if (canRedo) history[cursor + 1] else null

    fun resetCandidate(): File? =
        if (cursor > 0) baselineFile else null

    fun commitUndo(handle: Long) {
        check(canUndo) { "No mesh edit undo is available." }
        cursor -= 1
        currentHandle = handle
    }

    fun commitRedo(handle: Long) {
        check(canRedo) { "No mesh edit redo is available." }
        cursor += 1
        currentHandle = handle
    }

    fun commitReset(handle: Long) {
        check(history.isNotEmpty()) { "Mesh edit session has no baseline." }
        cursor = 0
        currentHandle = handle
    }

    fun stateMap(): Map<String, Any?> = mapOf(
        "active" to active,
        "canUndo" to canUndo,
        "canRedo" to canRedo,
        "cursor" to cursor,
        "revisionCount" to history.size,
        "currentHandle" to currentHandle,
        "sourcePath" to originalSourcePath,
        "sourceFormatId" to originalFormatId,
        "workingCopyPath" to (currentFile?.absolutePath ?: ""),
        "meshWorkingCopy" to true,
        "sourceOverwritten" to false,
    )

    fun dispose() {
        directory.deleteRecursively()
        history.clear()
        cursor = -1
    }
}
