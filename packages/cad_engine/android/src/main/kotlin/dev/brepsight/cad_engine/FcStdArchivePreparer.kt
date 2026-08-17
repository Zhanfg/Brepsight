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
 *  - parses Document.xml / GuiDocument.xml as data with DTD/entities/network disabled;
 *  - extracts BREP/BRP members explicitly referenced by Part::PropertyPartShape;
 *  - preserves a narrow, independently parsed hierarchy/placement/presentation subset;
 *  - emits a generated manifest consumed by the native OCCT provider.
 */
internal object FcStdArchivePreparer {
    private const val MAX_ARCHIVE_BYTES = 512L * 1024L * 1024L
    private const val MAX_ENTRY_COUNT = 4096
    private const val MAX_TOTAL_UNCOMPRESSED_BYTES = 1024L * 1024L * 1024L
    private const val MAX_SINGLE_ENTRY_BYTES = 256L * 1024L * 1024L
    private const val MAX_XML_BYTES = 16L * 1024L * 1024L
    private const val MAX_REFERENCED_SHAPES = 10000
    private const val MAX_GROUP_EDGES = 100000
    private const val MAX_COMPRESSION_RATIO = 250.0
    private const val MANIFEST_HEADER = "BREPSIGHT_FCSTD_V2"

    private data class Placement(
        var px: Double = 0.0,
        var py: Double = 0.0,
        var pz: Double = 0.0,
        var q0: Double = 0.0,
        var q1: Double = 0.0,
        var q2: Double = 0.0,
        var q3: Double = 1.0,
    )

    private data class ObjectRecord(
        val name: String,
        var type: String = "",
        var label: String = "",
        var placement: Placement = Placement(),
        var visibility: Boolean? = null,
        var shapeColor: Long? = null,
    )

    private data class ShapeRef(val objectName: String, val archivePath: String)
    private data class GroupEdge(val parent: String, val child: String)

    private data class DocumentIndex(
        val objects: LinkedHashMap<String, ObjectRecord>,
        val shapeRefs: List<ShapeRef>,
        val groupEdges: List<GroupEdge>,
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
                val guiEntry = entries["GuiDocument.xml"]
                if (guiEntry != null && !guiEntry.isDirectory) {
                    if (guiEntry.size > MAX_XML_BYTES) {
                        throw FcStdRejectedException("FCStd GuiDocument.xml exceeds the XML safety limit.")
                    }
                    parseGuiDocumentXml(readEntryLimited(zip, guiEntry, MAX_XML_BYTES), index.objects)
                }

                if (index.shapeRefs.isEmpty()) {
                    throw FcStdRejectedException("FCStd contains no saved BREP/BRP shapes that BrepSight can open read-only.")
                }
                if (index.shapeRefs.size > MAX_REFERENCED_SHAPES) {
                    throw FcStdRejectedException("FCStd references too many saved shapes.")
                }
                if (index.groupEdges.size > MAX_GROUP_EDGES) {
                    throw FcStdRejectedException("FCStd contains too many group hierarchy edges.")
                }

                val manifest = File(workDir, "document.fcstdmanifest")
                manifest.bufferedWriter(StandardCharsets.UTF_8).use { writer ->
                    writer.appendLine(MANIFEST_HEADER)
                    writer.append("source\t").appendLine(percentEncode(sourceFile.absolutePath))
                    writer.append("objects\t").appendLine(index.objects.size.toString())

                    for (record in index.objects.values) {
                        val p = record.placement
                        writer.append("object\t")
                            .append(percentEncode(record.name)).append('\t')
                            .append(percentEncode(record.type)).append('\t')
                            .append(percentEncode(record.label)).append('\t')
                            .append(formatDouble(p.px)).append('\t')
                            .append(formatDouble(p.py)).append('\t')
                            .append(formatDouble(p.pz)).append('\t')
                            .append(formatDouble(p.q0)).append('\t')
                            .append(formatDouble(p.q1)).append('\t')
                            .append(formatDouble(p.q2)).append('\t')
                            .appendLine(formatDouble(p.q3))

                        val visibility = when (record.visibility) {
                            true -> "1"
                            false -> "0"
                            null -> "-"
                        }
                        val color = record.shapeColor?.toString() ?: "-"
                        writer.append("presentation\t")
                            .append(percentEncode(record.name)).append('\t')
                            .append(visibility).append('\t')
                            .appendLine(color)
                    }

                    index.groupEdges.forEach { edge ->
                        if (index.objects.containsKey(edge.parent) && index.objects.containsKey(edge.child)) {
                            writer.append("group\t")
                                .append(percentEncode(edge.parent)).append('\t')
                                .appendLine(percentEncode(edge.child))
                        }
                    }

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
                    documentObjectCount = index.objects.size,
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
        rejectUnsafeXml(bytes, "Document.xml")
        val objects = linkedMapOf<String, ObjectRecord>()
        val shapes = mutableListOf<ShapeRef>()
        val groups = mutableListOf<GroupEdge>()

        parseXml(bytes, "Document.xml", object : DefaultHandler() {
            private var currentObject: ObjectRecord? = null
            private var objectDataDepth = 0
            private var currentPropertyName = ""
            private var currentPropertyType = ""
            private var propertyDepth = 0
            private var groupPropertyDepth = 0
            private var shapePropertyDepth = 0
            private var depth = 0

            override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
                depth += 1
                if (depth > 512) throw SAXException("FCStd Document.xml nesting is too deep.")
                when (qName) {
                    "ObjectData" -> objectDataDepth = depth
                    "Object" -> {
                        val name = attributes.getValue("name").orEmpty()
                        if (name.isNotBlank()) {
                            val record = objects.getOrPut(name) { ObjectRecord(name) }
                            attributes.getValue("type")?.takeIf { it.isNotBlank() }?.let { record.type = it }
                            if (objectDataDepth > 0) currentObject = record
                        }
                    }
                    "Property" -> if (currentObject != null) {
                        currentPropertyName = attributes.getValue("name").orEmpty()
                        currentPropertyType = attributes.getValue("type").orEmpty()
                        propertyDepth = depth
                        if (currentPropertyName == "Group" && currentPropertyType == "App::PropertyLinkList") {
                            groupPropertyDepth = depth
                        }
                        if (currentPropertyName == "Shape" && currentPropertyType == "Part::PropertyPartShape") {
                            shapePropertyDepth = depth
                        }
                    }
                    "String" -> if (currentObject != null && currentPropertyName == "Label") {
                        currentObject?.label = attributes.getValue("value").orEmpty()
                    }
                    "PropertyPlacement" -> if (currentObject != null && currentPropertyName == "Placement" &&
                        currentPropertyType == "App::PropertyPlacement") {
                        currentObject?.placement = parsePlacement(attributes)
                    }
                    "Bool" -> if (currentObject != null && currentPropertyName == "Visibility") {
                        currentObject?.visibility = parseBoolean(attributes.getValue("value").orEmpty())
                    }
                    "Link" -> if (currentObject != null && groupPropertyDepth > 0) {
                        val child = attributes.getValue("value").orEmpty()
                        if (child.isNotBlank()) groups += GroupEdge(currentObject!!.name, child)
                    }
                    "Part" -> if (shapePropertyDepth > 0 && currentObject != null) {
                        val archivePath = validateEntryName(attributes.getValue("file").orEmpty())
                        shapes += ShapeRef(currentObject!!.name, archivePath)
                    }
                }
            }

            override fun endElement(uri: String?, localName: String?, qName: String) {
                if (qName == "Property" && propertyDepth == depth) {
                    currentPropertyName = ""
                    currentPropertyType = ""
                    propertyDepth = 0
                    if (groupPropertyDepth == depth) groupPropertyDepth = 0
                    if (shapePropertyDepth == depth) shapePropertyDepth = 0
                }
                if (qName == "Object" && objectDataDepth > 0) currentObject = null
                if (qName == "ObjectData" && objectDataDepth == depth) objectDataDepth = 0
                depth -= 1
            }
        })

        return DocumentIndex(
            objects = objects,
            shapeRefs = shapes,
            groupEdges = groups.distinct().filter { it.parent != it.child },
        )
    }

    private fun parseGuiDocumentXml(bytes: ByteArray, objects: LinkedHashMap<String, ObjectRecord>) {
        rejectUnsafeXml(bytes, "GuiDocument.xml")
        parseXml(bytes, "GuiDocument.xml", object : DefaultHandler() {
            private var currentObject: ObjectRecord? = null
            private var currentPropertyName = ""
            private var currentPropertyType = ""
            private var propertyDepth = 0
            private var depth = 0

            override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
                depth += 1
                if (depth > 512) throw SAXException("FCStd GuiDocument.xml nesting is too deep.")
                when (qName) {
                    "ViewProvider" -> {
                        val name = attributes.getValue("name").orEmpty()
                        currentObject = objects[name]
                    }
                    "Property" -> if (currentObject != null) {
                        currentPropertyName = attributes.getValue("name").orEmpty()
                        currentPropertyType = attributes.getValue("type").orEmpty()
                        propertyDepth = depth
                    }
                    "Bool" -> if (currentObject != null && currentPropertyName == "Visibility") {
                        currentObject?.visibility = parseBoolean(attributes.getValue("value").orEmpty())
                    }
                    "PropertyColor" -> if (currentObject != null && currentPropertyName == "ShapeColor" &&
                        currentPropertyType == "App::PropertyColor") {
                        currentObject?.shapeColor = parsePackedColor(attributes.getValue("value").orEmpty())
                    }
                }
            }

            override fun endElement(uri: String?, localName: String?, qName: String) {
                if (qName == "Property" && propertyDepth == depth) {
                    currentPropertyName = ""
                    currentPropertyType = ""
                    propertyDepth = 0
                }
                if (qName == "ViewProvider") currentObject = null
                depth -= 1
            }
        })
    }

    private fun parsePlacement(attributes: Attributes): Placement = Placement(
        px = parseFiniteDouble(attributes.getValue("Px"), "Placement Px"),
        py = parseFiniteDouble(attributes.getValue("Py"), "Placement Py"),
        pz = parseFiniteDouble(attributes.getValue("Pz"), "Placement Pz"),
        q0 = parseFiniteDouble(attributes.getValue("Q0"), "Placement Q0"),
        q1 = parseFiniteDouble(attributes.getValue("Q1"), "Placement Q1"),
        q2 = parseFiniteDouble(attributes.getValue("Q2"), "Placement Q2"),
        q3 = parseFiniteDouble(attributes.getValue("Q3"), "Placement Q3"),
    )

    private fun parseFiniteDouble(raw: String?, label: String): Double {
        val value = raw?.toDoubleOrNull()
        if (value == null || !value.isFinite()) throw FcStdRejectedException("FCStd $label is invalid.")
        return value
    }

    private fun parseBoolean(raw: String): Boolean = when (raw.lowercase(Locale.ROOT)) {
        "true", "1" -> true
        "false", "0" -> false
        else -> throw FcStdRejectedException("FCStd boolean property is invalid.")
    }

    private fun parsePackedColor(raw: String): Long {
        val value = raw.toLongOrNull()
            ?: throw FcStdRejectedException("FCStd ShapeColor value is invalid.")
        if (value < 0L || value > 0xFFFF_FFFFL) {
            throw FcStdRejectedException("FCStd ShapeColor value is outside the 32-bit range.")
        }
        return value
    }

    private fun rejectUnsafeXml(bytes: ByteArray, label: String) {
        val text = bytes.toString(StandardCharsets.UTF_8)
        if (text.indexOf('\uFFFD') >= 0) throw FcStdRejectedException("FCStd $label is not valid UTF-8.")
        if (text.contains("<!DOCTYPE", ignoreCase = true) || text.contains("<!ENTITY", ignoreCase = true)) {
            throw FcStdRejectedException("FCStd $label contains a prohibited DTD/entity declaration.")
        }
    }

    private fun parseXml(bytes: ByteArray, label: String, handler: DefaultHandler) {
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
        reader.contentHandler = handler
        try {
            reader.parse(InputSource(ByteArrayInputStream(bytes)))
        } catch (error: FcStdRejectedException) {
            throw error
        } catch (error: Exception) {
            throw FcStdRejectedException("FCStd $label could not be parsed safely: ${error.message ?: error.javaClass.simpleName}")
        }
    }

    private fun setSaxFeature(factory: SAXParserFactory, feature: String, value: Boolean) {
        try {
            factory.setFeature(feature, value)
        } catch (_: Exception) {
            // Defense in depth: declarations are rejected before SAX and the reader resolver rejects every external lookup.
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

    private fun formatDouble(value: Double): String {
        if (!value.isFinite()) throw FcStdRejectedException("FCStd manifest contains a non-finite transform.")
        return java.lang.Double.toString(value)
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
