package dev.brepsight.cad_engine

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshEditSessionTest {
    private fun snapshot(directory: File, name: String): File =
        File(directory, name).apply { writeText("v 0 0 0\n") }

    @Test
    fun undoRedoAndBranchingHistoryAreDeterministic() {
        val directory = Files.createTempDirectory("brepsight-edit-history").toFile()
        try {
            val session = MeshEditSession(
                originalHandle = 7L,
                originalSourcePath = "/source/model.step",
                originalFormatId = "step",
                directory = directory,
            )
            val baseline = snapshot(directory, "edit_0000.obj")
            val first = snapshot(directory, "edit_0001.obj")
            val second = snapshot(directory, "edit_0002.obj")
            session.initialize(baseline)
            session.record(first, 8L)
            session.record(second, 9L)

            assertTrue(session.canUndo)
            assertFalse(session.canRedo)
            assertEquals(first, session.undoCandidate())

            session.commitUndo(10L)
            assertEquals(10L, session.currentHandle)
            assertTrue(session.canUndo)
            assertTrue(session.canRedo)
            assertEquals(second, session.redoCandidate())

            val branch = snapshot(directory, "edit_branch.obj")
            session.record(branch, 11L)
            assertFalse(second.exists())
            assertFalse(session.canRedo)
            assertEquals(branch, session.currentFile)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun resetKeepsBaselineAndHistoryIsBounded() {
        val directory = Files.createTempDirectory("brepsight-edit-cap").toFile()
        try {
            val session = MeshEditSession(
                originalHandle = 1L,
                originalSourcePath = "/source/model.iges",
                originalFormatId = "iges",
                directory = directory,
            )
            val baseline = snapshot(directory, "edit_0000.obj")
            session.initialize(baseline)

            repeat(40) { index ->
                session.record(snapshot(directory, "edit_${index + 1}.obj"), (index + 2).toLong())
            }

            val state = session.stateMap()
            assertEquals(33, state["revisionCount"])
            assertEquals(32, state["cursor"])
            assertTrue(baseline.exists())
            assertEquals(baseline, session.resetCandidate())

            session.commitReset(99L)
            assertEquals(99L, session.currentHandle)
            assertEquals(baseline, session.currentFile)
            assertFalse(session.canUndo)
            assertTrue(session.canRedo)
        } finally {
            directory.deleteRecursively()
        }
    }
}
