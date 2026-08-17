package dev.brepsight.cad_engine

import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import javax.xml.parsers.SAXParserFactory

internal data class FcStdPreparedArchive(
    val sourceFile: File,
    val workDir: File,
    val manifestFile: File,
    val referencedShapeCount: Int,
    val documentObjectCount: Int,
    val archiveEntryCount: Int,
    val totalUncompressedBytes: Long,
)

internal class FcStdRejectedException(message: String) : IOException(message)

/**
 * Converts an untrusted FreeCAD FCStd ZIP into a tiny BrepSight-owned manifest.
 *
 * The preparer deliberately does not execute or restore document code. It only:
 *  - validates the entire ZIP central directory against conservative limits;
 *  - parses Document.xml as data with DTD/entities/network resolution disabled;
 *  - extracts BREP/BRP members explicitly referenced by Part::PropertyPartShape;
 *  - emits a generated manifest consumed by the native OCCT provider.
 */
internal object FcStdArchivePreparer {
    private const val MAX_ARCHIVE_BYTES = 512L * 1024L * 1024L
    private const val MAX_ENTRY_COUNT = 4096
    private const val MAX_TOTAL_UNCOMPRESSED_BYTES = 1024L * 1024L * 1024L
    private const val MAX_SINGLE_ENTRY_BYTES = 256L * 1024L * 1024L
    private const val MAX_XML_BYTES = 16L * 1024L * 1024L
    private const val MAX_REFERENCED_SHAPES = 10000
    private const val MAX_COMPRESSION_RATIO = 250.0
    private const val MANIFEST_HEADER = "BREPSIGHT_FCSTD_V1"

    private data class ShapeRef(val objectName: String, val archivePath: String)

    private data class DocumentIndex(
        val objectNames: LinkedHashSet<String>,
        val shapeRefs: List<ShapeRef>,
    )

    fun prepare(sourceFile: File, cacheDir: File): FcStdPreparedArchive {
        if (!sourceFile.isFile) throw FcStdRejectedException("FCStd source is not a readable file.")
        if (sourceFile.length() <= 0L || sourceFile.length() > MAX_ARCHIVE_BYTES) {
            throw FcStdRejectedException("FCStd archive size is outside the supported safety limit.")
        }

        val workDir = File(cacheDir, "brepsight-fcstd/${UUID.randomUUID()}")
        val shapeDir = File(workDir, "shapes")
        if (!shapeDir.mkdirs()) throw IOException("Unable to create FCStd cache directory.")

        try {
            ZipFile(sourceFile).use { zip ->
                val entries = linkedMapOf<String, ZipEntry>()
                var totalUncompressed = 0L
                var entryCount = 0

                val enumeration = zip.entries()
                while (enumeration.hasMoreElements()) {
                    val entry = enumeration.nextElement()
                    entryCount += 1
                    if (entryCount > MAX_ENTRY_COUNT) {
                        throw FcStdRejectedException("FCStd contains too many ZIP entries.")
                    }

                    val normalized = validateEntryName(entry.name)
                    if (entries.put(normalized, entry) != null) {
                        throw FcStdRejectedException("FCStd contains duplicate ZIP entry names.")
                    }
                    if (entry.isDirectory) continue
                    if (entry.method != ZipEntry.STORED && entry.method != ZipEntry.DEFLATED) {
                        throw FcStdRejectedException("FCStd uses an unsupported ZIP compression method.")
                    }

                    val size = entry.size
                    val compressedSize = entry.compressedSize
                    if (size < 0L || compressedSize < 0L) {
                        throw FcStdRejectedException("FCStd ZIP entry has unknown size metadata.")
                    }
                    if (size > MAX_SINGLE_ENTRY_BYTES) {
                        throw FcStdRejectedException("FCStd ZIP entry exceeds the per-entry safety limit.")
                    }
                    totalUncompressed = safeAdd(totalUncompressed, size)
                    if (totalUncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES) {
                        throw FcStdRejectedException("FCStd expanded size exceeds the archive safety limit.")
                    }
                    if (size > 0L) {
                        if (compressedSize == 0L || size.toDouble() / compressedSize.toDouble() > MAX_COMPRESSION_RATIO) {
                            throw FcStdRejectedException("FCStd ZIP entry exceeds the compression-ratio safety limit.")
                        }
                    }
                }

                val documentEntry = entries["Document.xml"]
                    ?: throw FcStdRejectedException("FCStd is missing Document.xml.")
                if (documentEntry.isDirectory || documentEntry.size > MAX_XML_BYTES) {
                    throw FcStdRejectedException("FCStd Document.xml exceeds the XML safety limit.")
                }

                val documentBytes = readEntryLimited(zip, documentEntry, MAX_XML_BYTES)
                val index = parseDocumentXml(documentBytes)
                if (index.shapeRefs.isEmpty()) {
                    throw FcStdRejectedException("FCStd contains no saved BREP/BRP shapes that BrepSight can open read-only.")
                }
                if (index.shapeRefs.size > MAX_REFERENCED_SHAPES) {
                    throw FcStdRejectedException("FCStd references too many saved shapes.")
                }

                val manifest = File(workDir, "document.fcstdmanifest")
                manifest.bufferedWriter(StandardCharsets.UTF_8).use { writer ->
                    writer.appendLine(MANIFEST_HEADER)
                    writer.append("source\t").appendLine(percentEncode(sourceFile.absolutePath))
                    writer.append("objects\t").appendLine(index.objectNames.size.toString())

                    index.shapeRefs.forEachIndexed { indexValue, shapeRef ->
                        val entry = entries[shapeRef.archivePath]
                            ?: throw FcStdRejectedException("FCStd references a missing saved shape: ${shapeRef.archivePath}")
                        if (entry.isDirectory) {
                            throw FcStdRejectedException("FCStd saved-shape reference points to a directory.")
                        }
                        val extension = shapeRef.archivePath.substringAfterLast('.', "").lowercase(Locale.ROOT)
                        if (extension != "brep" && extension != "brp") {
                            throw FcStdRejectedException("FCStd saved-shape reference is not BREP/BRP data.")
                        }

                        val extracted = File(shapeDir, "shape-${indexValue.toString().padStart(5, '0')}.$extension")
                        zip.getInputStream(entry).use { input ->
                            extracted.outputStream().use { output ->
                                copyLimited(input, output, MAX_SINGLE_ENTRY_BYTES)
                            }
                        }
                        if (extracted.length() != entry.size) {
                            throw FcStdRejectedException("FCStd saved-shape extraction size mismatch.")
                        }

                        writer.append("shape\t")
                            .append(percentEncode(shapeRef.objectName))
                            .append('\t')
                            .append(percentEncode(extracted.absolutePath))
                            .appendLine()
                    }
                }

                return FcStdPreparedArchive(
                    sourceFile = sourceFile,
                    workDir = workDir,
                    manifestFile = manifest,
                    referencedShapeCount = index.shapeRefs.size,
                    documentObjectCount = index.objectNames.size,
                    archiveEntryCount = entryCount,
                    totalUncompressedBytes = totalUncompressed,
                )
            }
        } catch (error: Exception) {
            workDir.deleteRecursively()
            throw error
        }
    }

    private fun validateEntryName(rawName: String): String {
        if (rawName.isBlank() || rawName.indexOf('\u0000') >= 0 || rawName.contains('\\')) {
            throw FcStdRejectedException("FCStd contains an unsafe ZIP entry path.")
        }
        if (rawName.startsWith('/') || rawName.startsWith('~')) {
            throw FcStdRejectedException("FCStd contains an absolute ZIP entry path.")
        }
        val normalized = rawName.removeSuffix("/")
        if (normalized.isBlank()) throw FcStdRejectedException("FCStd contains an invalid ZIP entry path.")
        val segments = normalized.split('/')
        if (segments.any { it.isBlank() || it == "." || it == ".." || it.contains(':') }) {
            throw FcStdRejectedException("FCStd contains ZIP path traversal or an unsafe path segment.")
        }
        return normalized
    }

    private fun parseDocumentXml(bytes: ByteArray): DocumentIndex {
        val text = bytes.toString(StandardCharsets.UTF_8)
        if (text.indexOf('\uFFFD') >= 0) {
            throw FcStdRejectedException("FCStd Document.xml is not valid UTF-8.")
        }
        if (text.contains("<!DOCTYPE") || text.contains("<!ENTITY")) {
            throw FcStdRejectedException("FCStd Document.xml contains a prohibited DTD/entity declaration.")
        }

        val objects = linkedSetOf<String>()
        val shapes = mutableListOf<ShapeRef>()
        val factory = SAXParserFactory.newInstance().apply {
            isNamespaceAware = false
            isValidating = false
        }
        setSaxFeature(factory, "http://xml.org/sax/features/external-general-entities", false)
        setSaxFeature(factory, "http://xml.org/sax/features/external-parameter-entities", false)
        setSaxFeature(factory, "http://apache.org/xml/features/nonvalidating/load-external-dtd", false)

        val reader = factory.newSAXParser().xmlReader
        reader.entityResolver = org.xml.sax.EntityResolver { _, _ ->
            throw SAXException("External XML entity resolution is prohibited for FCStd.")
        }
        reader.contentHandler = object : DefaultHandler() {
            private var currentObject = ""
            private var shapePropertyDepth = 0
            private var depth = 0

            override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
                depth += 1
                if (depth > 512) throw SAXException("FCStd Document.xml nesting is too deep.")
                when (qName) {
                    "Object" -> {
                        val name = attributes.getValue("name").orEmpty()
                        if (name.isNotBlank()) {
                            currentObject = name
                            objects += name
                        }
                    }
                    "Property" -> {
                        val propertyName = attributes.getValue("name").orEmpty()
                        val propertyType = attributes.getValue("type").orEmpty()
                        if (propertyName == "Shape" && propertyType == "Part::PropertyPartShape") {
                            shapePropertyDepth = depth
                        }
                    }
                    "Part" -> if (shapePropertyDepth > 0 && currentObject.isNotBlank()) {
                        val archivePath = validateEntryName(attributes.getValue("file").orEmpty())
                        shapes += ShapeRef(currentObject, archivePath)
                    }
                }
            }

            override fun endElement(uri: String?, localName: String?, qName: String) {
                if (shapePropertyDepth == depth && qName == "Property") shapePropertyDepth = 0
                if (qName == "Object") currentObject = ""
                depth -= 1
            }
        }

        try {
            reader.parse(InputSource(ByteArrayInputStream(bytes)))
        } catch (error: FcStdRejectedException) {
            throw error
        } catch (error: Exception) {
            throw FcStdRejectedException("FCStd Document.xml could not be parsed safely: ${error.message ?: error.javaClass.simpleName}")
        }
        return DocumentIndex(objects, shapes)
    }

    private fun setSaxFeature(factory: SAXParserFactory, feature: String, value: Boolean) {
        try {
            factory.setFeature(feature, value)
        } catch (_: Exception) {
            // Defense in depth: DTD/entity declarations are rejected before SAX,
            // and the XMLReader EntityResolver below rejects every external lookup.
        }
    }

    private fun readEntryLimited(zip: ZipFile, entry: ZipEntry, limit: Long): ByteArray {
        zip.getInputStream(entry).use { input ->
            val output = ByteArrayOutputStream(minOf(entry.size.coerceAtLeast(0L), 1024L * 1024L).toInt())
            copyLimited(input, output, limit)
            return output.toByteArray()
        }
    }

    private fun copyLimited(input: java.io.InputStream, output: java.io.OutputStream, limit: Long) {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total = safeAdd(total, read.toLong())
            if (total > limit) throw FcStdRejectedException("FCStd entry expanded beyond its safety limit while reading.")
            output.write(buffer, 0, read)
        }
    }

    private fun safeAdd(left: Long, right: Long): Long {
        if (right > Long.MAX_VALUE - left) throw FcStdRejectedException("FCStd size accounting overflow.")
        return left + right
    }

    private fun percentEncode(value: String): String {
        val bytes = value.toByteArray(StandardCharsets.UTF_8)
        val out = StringBuilder(bytes.size)
        for (byte in bytes) {
            val unsigned = byte.toInt() and 0xFF
            if ((unsigned in 'a'.code..'z'.code) ||
                (unsigned in 'A'.code..'Z'.code) ||
                (unsigned in '0'.code..'9'.code) ||
                unsigned == '-'.code || unsigned == '_'.code || unsigned == '.'.code || unsigned == '/'.code
            ) {
                out.append(unsigned.toChar())
            } else {
                out.append('%')
                out.append("0123456789ABCDEF"[unsigned ushr 4])
                out.append("0123456789ABCDEF"[unsigned and 0x0F])
            }
        }
        return out.toString()
    }
}
