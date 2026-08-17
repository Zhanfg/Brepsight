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
                assertTrue(manifest.startsWith("BREPSIGHT_FCSTD_V2\n"))
                assertTrue(manifest.contains("objects\t1\n"))
                assertTrue(manifest.contains("object\tBox\t\t\t0.0\t0.0\t0.0\t0.0\t0.0\t0.0\t1.0\n"))
                assertTrue(manifest.contains("shape\tBox\t"))
            } finally {
                prepared.workDir.deleteRecursively()
            }
        }
    }

    @Test
    fun preservesGroupPlacementAndGuiPresentationSubset() {
        withTempDirectory { root ->
            val archive = File(root, "hierarchy.FCStd")
            writeZip(
                archive,
                linkedMapOf(
                    "Document.xml" to hierarchyDocumentXml().toByteArray(StandardCharsets.UTF_8),
                    "GuiDocument.xml" to hierarchyGuiXml().toByteArray(StandardCharsets.UTF_8),
                    "BoxShape.brp" to "box-brep".toByteArray(StandardCharsets.US_ASCII),
                    "HiddenShape.brp" to "hidden-brep".toByteArray(StandardCharsets.US_ASCII),
                ),
            )

            val prepared = FcStdArchivePreparer.prepare(archive, root)
            try {
                assertEquals(3, prepared.documentObjectCount)
                assertEquals(2, prepared.referencedShapeCount)
                val manifest = prepared.manifestFile.readText(StandardCharsets.UTF_8)

                assertTrue(manifest.contains("object\tAssembly\tApp%3A%3APart\tMain%20Assembly\t10.0\t20.0\t30.0\t0.0\t0.0\t0.0\t1.0\n"))
                assertTrue(manifest.contains("object\tBox\tPart%3A%3AFeature\tVisible%20Box\t5.0\t0.0\t0.0\t0.0\t0.0\t0.0\t1.0\n"))
                assertTrue(manifest.contains("group\tAssembly\tBox\n"))
                assertTrue(manifest.contains("group\tAssembly\tHidden\n"))

                // A non-Group PropertyLinkList is dependency data, not tree ownership.
                assertFalse(manifest.contains("group\tBox\tHidden\n"))

                assertTrue(manifest.contains("presentation\tBox\t1\t287454207\n"))
                assertTrue(manifest.contains("presentation\tHidden\t0\t-\n"))
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
                <!DOCTYPE Document [<!ENTITY xxe SYSTEM="file:///etc/passwd">]>
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
    fun rejectsDtdInGuiDocumentToo() {
        withTempDirectory { root ->
            val archive = File(root, "gui-xxe.FCStd")
            val gui = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE GuiDocument [<!ENTITY xxe SYSTEM="file:///etc/passwd">]>
                <GuiDocument><ViewProvider name="Box"/></GuiDocument>
            """.trimIndent()
            writeZip(
                archive,
                linkedMapOf(
                    "Document.xml" to documentXml("Box", "PartShape.brp").toByteArray(StandardCharsets.UTF_8),
                    "GuiDocument.xml" to gui.toByteArray(StandardCharsets.UTF_8),
                    "PartShape.brp" to byteArrayOf(1, 2, 3),
                ),
            )

            val error = assertThrows(FcStdRejectedException::class.java) {
                FcStdArchivePreparer.prepare(archive, root)
            }
            assertTrue(error.message.orEmpty().contains("GuiDocument.xml"))
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

    private fun hierarchyDocumentXml(): String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document>
          <Objects Count="3">
            <Object type="App::Part" name="Assembly"/>
            <Object type="Part::Feature" name="Box"/>
            <Object type="Part::Feature" name="Hidden"/>
          </Objects>
          <ObjectData Count="3">
            <Object name="Assembly">
              <Properties Count="3">
                <Property name="Label" type="App::PropertyString"><String value="Main Assembly"/></Property>
                <Property name="Placement" type="App::PropertyPlacement">
                  <PropertyPlacement Px="10" Py="20" Pz="30" Q0="0" Q1="0" Q2="0" Q3="1"/>
                </Property>
                <Property name="Group" type="App::PropertyLinkList">
                  <LinkList count="2"><Link value="Box"/><Link value="Hidden"/></LinkList>
                </Property>
              </Properties>
            </Object>
            <Object name="Box">
              <Properties Count="4">
                <Property name="Label" type="App::PropertyString"><String value="Visible Box"/></Property>
                <Property name="Placement" type="App::PropertyPlacement">
                  <PropertyPlacement Px="5" Py="0" Pz="0" Q0="0" Q1="0" Q2="0" Q3="1"/>
                </Property>
                <Property name="Dependencies" type="App::PropertyLinkList">
                  <LinkList count="1"><Link value="Hidden"/></LinkList>
                </Property>
                <Property name="Shape" type="Part::PropertyPartShape"><Part file="BoxShape.brp"/></Property>
              </Properties>
            </Object>
            <Object name="Hidden">
              <Properties Count="1">
                <Property name="Shape" type="Part::PropertyPartShape"><Part file="HiddenShape.brp"/></Property>
              </Properties>
            </Object>
          </ObjectData>
        </Document>
    """.trimIndent()

    private fun hierarchyGuiXml(): String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <GuiDocument>
          <ViewProviderData Count="3">
            <ViewProvider name="Assembly"><Properties Count="0"/></ViewProvider>
            <ViewProvider name="Box">
              <Properties Count="2">
                <Property name="Visibility" type="App::PropertyBool"><Bool value="true"/></Property>
                <Property name="ShapeColor" type="App::PropertyColor"><PropertyColor value="287454207"/></Property>
              </Properties>
            </ViewProvider>
            <ViewProvider name="Hidden">
              <Properties Count="1">
                <Property name="Visibility" type="App::PropertyBool"><Bool value="false"/></Property>
              </Properties>
            </ViewProvider>
          </ViewProviderData>
        </GuiDocument>
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
