package com.larpcode.revise.backend

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.security.MessageDigest
import java.util.UUID

data class ModelEntry(val group: String, val path: String, val sizeBytes: Long, val sha256: String)

/** The application accepts only the agreed 8 STT, 2 diarization and 1 Gemma files. */
class ModelInventory(files: List<ModelEntry>) {
    val files: List<ModelEntry> = files.toList()
    init {
        require(files.size == REQUIRED_PATHS.size && files.map { it.path }.toSet() == REQUIRED_PATHS)
        files.forEach {
            require(it.path.split('/')[1] == it.group && it.sizeBytes > 0 && it.sha256.matches(Regex("[0-9a-f]{64}")))
        }
    }

    // Any inventory/hash change produces a new directory; SDKs never read a mixed asset set.
    val version: String = sha256(files.sortedBy { it.path }.joinToString("\n") {
        "${it.path}:${it.sizeBytes}:${it.sha256}"
    }.toByteArray(Charsets.UTF_8)).take(24)

    companion object {
        const val GEMMA_PATH = "models/llm/gemma3-1b-it-int4.litertlm"
        val REQUIRED_PATHS: Set<String> = setOf(
            "models/stt/adapter.ort", "models/stt/cross_kv.ort", "models/stt/decoder_kv.ort",
            "models/stt/encoder.ort", "models/stt/frontend.model.ort", "models/stt/frontend.weights.ort",
            "models/stt/streaming_config.json", "models/stt/tokenizer.bin",
            "models/diarization/segmentation.ort", "models/diarization/embedding.ort", GEMMA_PATH,
        )
    }
}

fun interface PackagedModels { fun open(path: String): InputStream }
data class PreparedModels(val speechDirectory: File, val diarizationDirectory: File, val gemma: File?)

/**
 * Call off the main thread. The root must be Context.noBackupFilesDir/revise-models.
 * No download/cache workers and no audio/transcript storage are involved.
 */
class ModelAssets(
    private val inventory: ModelInventory,
    private val packaged: PackagedModels,
    private val privateRoot: File,
    private val availableBytes: (File) -> Long = { it.usableSpace },
) {
    @Synchronized
    fun prepare(): PreparedModels {
        inventory.files.filter { it.group != "llm" }.forEach { extract(it) }
        val gemma = try { requireGemma() } catch (_: BackendFailure) { null }
        val root = versionRoot()
        return PreparedModels(File(root, "models/stt"), File(root, "models/diarization"), gemma)
    }

    /** Extract/check Gemma only. init must not instantiate an LLM just to report readiness. */
    @Synchronized
    fun requireGemma(): File = extract(inventory.files.single { it.path == ModelInventory.GEMMA_PATH })

    private fun versionRoot() = File(privateRoot, inventory.version)

    private fun extract(entry: ModelEntry): File {
        var temporary: File? = null
        try {
            val destination = File(versionRoot(), entry.path)
            assertNoLinks(destination)
            if (matches(destination, entry)) return destination
            val parent = destination.parentFile!!
            if (!parent.isDirectory && !parent.mkdirs()) throw BackendFailure.modelMissing("Model storage is unavailable.")
            if (availableBytes(parent) < entry.sizeBytes + STORAGE_RESERVE_BYTES) {
                throw BackendFailure.modelMissing("Not enough private storage to extract the model assets.")
            }
            temporary = File(parent, ".${destination.name}.${UUID.randomUUID()}.partial")
            val digest = MessageDigest.getInstance("SHA-256")
            var size = 0L
            packaged.open("revise/${entry.path}").use { input ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        size += count
                        if (size > entry.sizeBytes) throw BackendFailure.modelMissing("Packaged model length is invalid.")
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            if (size != entry.sizeBytes || hex(digest.digest()) != entry.sha256) {
                throw BackendFailure.modelMissing("Packaged model checksum is invalid.")
            }
            // Same-directory atomic publication. If the filesystem cannot support it, fail safely.
            Files.move(temporary.toPath(), destination.toPath(), ATOMIC_MOVE, REPLACE_EXISTING)
            return destination
        } catch (error: BackendFailure) {
            throw error
        } catch (_: Exception) {
            throw BackendFailure.modelMissing("A required packaged model is missing, corrupt, or inaccessible.")
        } finally {
            // Cleanup failure must not replace the stable error already selected above.
            temporary?.let { runCatching { Files.deleteIfExists(it.toPath()) } }
        }
    }

    private fun matches(file: File, entry: ModelEntry): Boolean {
        if (!Files.isRegularFile(file.toPath(), NOFOLLOW_LINKS) || file.length() != entry.sizeBytes) return false
        return file.inputStream().use { input ->
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
            hex(digest.digest()) == entry.sha256
        }
    }

    private fun assertNoLinks(file: File) {
        var current: File? = file.absoluteFile
        while (current != null) {
            if (Files.isSymbolicLink(current.toPath())) throw BackendFailure.modelMissing("Linked model paths are unsupported.")
            current = current.parentFile
        }
    }

    companion object { private const val STORAGE_RESERVE_BYTES = 4L * 1024 * 1024 }
}

private fun sha256(bytes: ByteArray) = hex(MessageDigest.getInstance("SHA-256").digest(bytes))
private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
