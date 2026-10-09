package com.larpcode.revise.backend

import android.content.Context
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

/** Android binding; the testable extractor itself has no Android or JSON dependencies. */
object AndroidModelAssets {
    fun create(context: Context): ModelAssets {
        val app = context.applicationContext
        try {
            val bytes = ByteArrayOutputStream()
            app.assets.open("revise/model-manifest.json").use { input ->
                val buffer = ByteArray(4096)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (bytes.size() + count > 65_536) throw IllegalArgumentException()
                    bytes.write(buffer, 0, count)
                }
            }
            val manifest = JSONObject(bytes.toString("UTF-8"))
            require(manifest.getInt("schemaVersion") == 1)
            val files = manifest.getJSONArray("files")
            val entries = (0 until files.length()).map { i ->
                val entry = files.getJSONObject(i)
                ModelEntry(entry.getString("group"), entry.getString("path"), entry.getLong("sizeBytes"), entry.getString("sha256"))
            }
            return ModelAssets(ModelInventory(entries), PackagedModels { app.assets.open(it) }, File(app.noBackupFilesDir, "revise-models"))
        } catch (_: Exception) {
            throw BackendFailure.modelMissing("The packaged model inventory is missing or invalid.")
        }
    }
}
