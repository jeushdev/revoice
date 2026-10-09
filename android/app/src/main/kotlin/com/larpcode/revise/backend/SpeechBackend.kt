package com.larpcode.revise.backend

/** Implemented by devJ. All methods except requestStop run on the controller's worker. */
fun interface SpeechBackendFactory { fun open(models: PreparedModels): SpeechBackend }

interface SpeechBackend : AutoCloseable {
    fun start(listener: SpeechListener)
    /** Return only after capture has stopped and accepted audio/final callbacks have drained. */
    fun pause()
    fun resume()
    /** Return only after final callbacks have been processed. Idempotent. */
    fun stop()
    /** Thread-safe interruption: stop accepting mic input promptly; do not emit successful Stop. */
    fun requestStop()
}

interface SpeechListener {
    fun onCaption(caption: CaptionSnapshot)
    fun onFailure(code: String)
}

data class CaptionSnapshot(
    val segmentId: String,
    val text: String,
    val speakerId: Int,
    val isFinal: Boolean,
    val tStartMs: Long,
    val tEndMs: Long,
) {
    init {
        require(segmentId.isNotBlank() && speakerId in 0..4 && tStartMs >= 0 && tEndMs >= tStartMs)
    }
    fun toWire(): Map<String, Any> = mapOf(
        "type" to "caption", "segmentId" to segmentId, "text" to text,
        "speakerId" to speakerId, "isFinal" to isFinal, "tStartMs" to tStartMs, "tEndMs" to tEndMs,
    )
}

/** enqueue must preserve FIFO order and return after scheduling main-thread channel delivery. */
fun interface BackendEvents { fun enqueue(generation: Long, event: Map<String, Any>) }
