package dev.brepsight.cad_engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class FcStdArchivePreparerTest {
    @Test
    fun preparesOnlyDocumentReferencedBrep() {
        withTempDirectory { root ->
            val archive = File(root, "clean.FCStd")
            writeZip(
                archive,
                linkedMapOf(
                    "Document.xml" to documentXml("Box", "PartShape.brp").toByteArray(StandardCharsets.UTF_8),
                    "GuiDocument.xml" to "<GuiDocument/>".toByteArray(StandardCharsets.UTF_8),
                    "PartShape.brp" to "clean-room-placeholder-brep".toByteArray(StandardCharsets.US_ASCII),
                    "Macro.py" to "raise RuntimeError('must never execute')".toByteArray(StandardCharsets.UTF_8),
                ),
            )

            val prepared = FcStdArchivePreparer.prepare(archive, root)
            try {
                assertEquals(1, prepared.referencedShapeCount)
                assertEquals(1, prepared.documentObjectCount)
                assertEquals(4, prepared.archiveEntryCount)
                assertTrue(prepared.totalUncompressedBytes > 0)

                val extracted = File(prepared.workDir, "shapes").listFiles().orEmpty()
                assertEquals(1, extracted.size)
                assertEquals("brp", extracted.single().extension.lowercase())
                assertFalse(
                    prepared.workDir.walkTopDown().any {
                        it.isFile && it.name.equals("Macro.py", ignoreCase = true)
                    },
                )

                val manifest = prepared.manifestFile.readText(StandardCharsets.UTF_8)
                assertTrue(manifest.startsWith("BREPSIGHT_FCSTD_V1\n"))
                assertTrue(manifest.contains("objects\t1\n"))
                assertTrue(manifest.contains("shape\tBox\t"))
            } finally {
                prepared.workDir.deleteRecursively()
            }
        }
    }

    @Test
    fun rejectsZipPathTraversalBeforeExtraction() {
        withTempDirectory { root ->
            val archive = File(root, "traversal.FCStd")
            writeZip(
                archive,
                linkedMapOf(
                    "Document.xml" to documentXml("Box", "../escape.brp").toByteArray(StandardCharsets.UTF_8),
                    "../escape.brp" to byteArrayOf(1, 2, 3),
                ),
            )

            val error = assertThrows(FcStdRejectedException::class.java) {
                FcStdArchivePreparer.prepare(archive, root)
            }
            assertTrue(error.message.orEmpty().contains("unsafe", ignoreCase = true) ||
                error.message.orEmpty().contains("traversal", ignoreCase = true))
            assertFalse(File(root.parentFile, "escape.brp").exists())
        }
    }

    @Test
    fun rejectsDtdAndExternalEntityDeclarations() {
        withTempDirectory { root ->
            val archive = File(root, "xxe.FCStd")
            val xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE Document [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
                <Document>
                  <ObjectData Count="1">
                    <Object name="Box">
                      <Properties Count="1">
                        <Property name="Shape" type="Part::PropertyPartShape">
                          <Part file="PartShape.brp"/>
                        </Property>
                      </Properties>
                    </Object>
                  </ObjectData>
                </Document>
            """.trimIndent()
            writeZip(
                archive,
                linkedMapOf(
                    "Document.xml" to xml.toByteArray(StandardCharsets.UTF_8),
                    "PartShape.brp" to byteArrayOf(1, 2, 3),
                ),
            )

            val error = assertThrows(FcStdRejectedException::class.java) {
                FcStdArchivePreparer.prepare(archive, root)
            }
            assertTrue(error.message.orEmpty().contains("DTD", ignoreCase = true) ||
                error.message.orEmpty().contains("entity", ignoreCase = true))
        }
    }

    @Test
    fun rejectsMissingReferencedSavedShape() {
        withTempDirectory { root ->
            val archive = File(root, "missing-shape.FCStd")
            writeZip(
                archive,
                linkedMapOf(
                    "Document.xml" to documentXml("Body", "BodyShape.brp").toByteArray(StandardCharsets.UTF_8),
                ),
            )

            val error = assertThrows(FcStdRejectedException::class.java) {
                FcStdArchivePreparer.prepare(archive, root)
            }
            assertTrue(error.message.orEmpty().contains("missing saved shape", ignoreCase = true))
        }
    }

    @Test
    fun rejectsDocumentsWithoutSavedBrepGeometry() {
        withTempDirectory { root ->
            val archive = File(root, "no-shape.FCStd")
            val xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <Document>
                  <ObjectData Count="1">
                    <Object name="Spreadsheet">
                      <Properties Count="0"/>
                    </Object>
                  </ObjectData>
                </Document>
            """.trimIndent()
            writeZip(
                archive,
                linkedMapOf("Document.xml" to xml.toByteArray(StandardCharsets.UTF_8)),
            )

            val error = assertThrows(FcStdRejectedException::class.java) {
                FcStdArchivePreparer.prepare(archive, root)
            }
            assertTrue(error.message.orEmpty().contains("no saved BREP", ignoreCase = true))
        }
    }

    private fun documentXml(objectName: String, shapePath: String): String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document>
          <ObjectData Count="1">
            <Object name="$objectName">
              <Properties Count="1">
                <Property name="Shape" type="Part::PropertyPartShape">
                  <Part file="$shapePath"/>
                </Property>
              </Properties>
            </Object>
          </ObjectData>
        </Document>
    """.trimIndent()

    private fun writeZip(target: File, entries: LinkedHashMap<String, ByteArray>) {
        ZipOutputStream(target.outputStream().buffered()).use { zip ->
            entries.forEach { (name, bytes) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
    }

    private fun withTempDirectory(block: (File) -> Unit) {
        val root = Files.createTempDirectory("brepsight-fcstd-test-").toFile()
        try {
            block(root)
        } finally {
            root.deleteRecursively()
        }
    }
}
