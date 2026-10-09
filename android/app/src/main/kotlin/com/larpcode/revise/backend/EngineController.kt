package com.larpcode.revise.backend

import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors

/**
 * Native lifecycle boundary. Permission requests and Flutter delivery belong on the main thread;
 * callers supply the permission result. Loading, flushing and resource release happen here.
 */
class EngineController(
    private val prepareModels: () -> PreparedModels,
    private val speechFactory: SpeechBackendFactory,
    private val crm: GemmaCrmEngine,
    private val events: BackendEvents,
) {
    private enum class State { NEW, READY, LISTENING, PAUSED, STOPPED, ERROR, DISPOSED }
    private val lock = Any()
    private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "revise-control") }
    private var state = State.NEW
    private var operation = false
    private var generation = 0L
    private var acceptingCaptions = false
    private var closing: CompletableFuture<Unit>? = null
    private var models: PreparedModels? = null // Worker only.
    @Volatile private var speech: SpeechBackend? = null

    /** Delivery must also check this token on the main thread, to discard already queued stale events. */
    fun isCurrentGeneration(value: Long): Boolean = synchronized(lock) { generation == value && state != State.DISPOSED }
    fun canStart(): Boolean = synchronized(lock) { state in setOf(State.READY, State.STOPPED) && !operation }

    fun init(): CompletableFuture<Map<String, Boolean>> = control(setOf(State.NEW, State.READY, State.STOPPED, State.ERROR)) {
        crm.unload().join()
        closeSpeech()
        synchronized(lock) { ensureAlive(); state = State.NEW; generation++; acceptingCaptions = false }
        val prepared = prepareModels()
        models = prepared
        speech = speechFactory.open(prepared) // Loaded STT only; never initializes Gemma.
        transition(State.READY)
        mapOf("sttReady" to true, "llmReady" to (prepared.gemma != null))
    }

    fun start(permissionGranted: Boolean, language: String = "en"): CompletableFuture<Boolean> {
        if (language != "en") return failed(BackendFailure.invalidState("Only English is supported."))
        return control(setOf(State.READY, State.STOPPED)) {
            if (!permissionGranted) throw BackendFailure("permission_denied", "Microphone permission is required.")
            crm.unload().join() // Includes the busy-after-timeout guard.
            val prepared = models ?: throw BackendFailure.modelMissing("Initialize models before recording.")
            val engine = speech ?: speechFactory.open(prepared).also { speech = it }
            val token = synchronized(lock) { ensureAlive(); acceptingCaptions = true; ++generation }
            engine.start(listener(token))
            transition(State.LISTENING)
            true
        }
    }

    fun pause(): CompletableFuture<Boolean> = control(setOf(State.LISTENING)) {
        speech!!.pause()
        transition(State.PAUSED)
        true
    }
    fun resume(): CompletableFuture<Boolean> = control(setOf(State.PAUSED)) {
        synchronized(lock) { ensureAlive(); acceptingCaptions = true }
        speech!!.resume()
        transition(State.LISTENING)
        true
    }
    fun stop(): CompletableFuture<Boolean> = control(setOf(State.LISTENING, State.PAUSED, State.STOPPED)) {
        if (synchronized(lock) { state != State.STOPPED }) {
            speech!!.stop() // devJ's drain barrier: all finals enqueue before stopped.
            closeSpeech()
            transition(State.STOPPED)
        }
        true
    }

    fun generateCrm(prompt: String, maxTokens: Int = 512): CompletableFuture<Map<String, String>> {
        synchronized(lock) {
            if (state != State.STOPPED || operation) return failed(BackendFailure.invalidState("CRM requires an idle stopped session."))
            operation = true
        }
        val result = CompletableFuture<Map<String, String>>()
        val nativeResult = crm.generate(prompt, maxTokens)
        nativeResult.whenComplete { text, error ->
            synchronized(lock) {
                operation = false
                if (state == State.DISPOSED) result.completeExceptionally(BackendFailure.invalidState("Engine disposed."))
                else if (error != null) result.completeExceptionally(safeFailure(error))
                else result.complete(mapOf("json" to text))
            }
        }
        result.whenComplete { _, _ -> if (result.isCancelled) nativeResult.cancel(false) }
        return result
    }

    /** Call for engine detach, event-sink loss, or activity disposal. No stale event delivery. */
    fun closeAsync(): CompletableFuture<Unit> {
        val result: CompletableFuture<Unit>
        synchronized(lock) {
            closing?.let { return it }
            state = State.DISPOSED
            acceptingCaptions = false
            generation++
            result = CompletableFuture()
            closing = result
        }
        runCatching { speech?.requestStop() }
        val crmClosing = crm.closeAsync()
        worker.execute {
            var error: Throwable? = null
            try { closeSpeech() } catch (e: Throwable) { error = e }
            crmClosing.whenComplete { _, nativeError ->
                if (error != null || nativeError != null) result.completeExceptionally(BackendFailure.inferenceFailed("Native resources could not be released."))
                else result.complete(Unit)
            }
            worker.shutdown()
        }
        return result
    }

    /** Call when backgrounded/interrupted. Retains finals and reports error rather than successful Stop. */
    fun interrupt() {
        val token = synchronized(lock) {
            if (state !in setOf(State.LISTENING, State.PAUSED) && !acceptingCaptions) return
            generation
        }
        failSession(token, "capture_failed")
    }

    private fun listener(token: Long) = object : SpeechListener {
        override fun onCaption(caption: CaptionSnapshot) = synchronized(lock) {
            // start may produce a callback before it returns. Pause and stop keep this token alive
            // until their drain barriers have completed.
            if (generation == token && acceptingCaptions && state != State.DISPOSED && state != State.ERROR) {
                events.enqueue(token, caption.toWire())
            }
        }
        override fun onFailure(code: String) {
            synchronized(lock) {
                if (generation != token || (state !in setOf(State.LISTENING, State.PAUSED) && !acceptingCaptions)) return
                failSession(token, code)
            }
        }
    }

    private fun failSession(token: Long, code: String) {
        synchronized(lock) {
            if (generation != token || state == State.DISPOSED || state == State.ERROR) return
            val safeCode = if (code in setOf("permission_denied", "model_missing", "capture_failed", "inference_failed")) code else "capture_failed"
            state = State.ERROR
            acceptingCaptions = false
            events.enqueue(token, mapOf("type" to "state", "state" to "error", "message" to safeCode))
            runCatching { speech?.requestStop() }
            worker.execute { runCatching { closeSpeech() } }
        }
    }

    private fun transition(next: State) = synchronized(lock) {
        ensureAlive()
        if (state == State.ERROR) throw BackendFailure("capture_failed", "The recording was interrupted.")
        state = next
        acceptingCaptions = next == State.LISTENING
        events.enqueue(generation, mapOf("type" to "state", "state" to next.name.lowercase()))
    }

    private fun <T> control(allowed: Set<State>, action: () -> T): CompletableFuture<T> = synchronized(lock) {
        if (state !in allowed || operation) return@synchronized failed(BackendFailure.invalidState("Operation is not allowed in the current engine state."))
        operation = true
        val result = CompletableFuture<T>()
        worker.execute {
            var value: T? = null
            var failure: BackendFailure? = null
            try {
                synchronized(lock) { ensureAlive() }
                value = action()
            } catch (error: Throwable) {
                failure = safeFailure(error)
                if (failure.code != "invalid_state") failSession(synchronized(lock) { generation }, failure.code)
            }
            synchronized(lock) {
                operation = false
                if (state == State.DISPOSED) result.completeExceptionally(BackendFailure.invalidState("Engine disposed."))
                else if (failure != null) result.completeExceptionally(failure)
                else {
                    @Suppress("UNCHECKED_CAST") result.complete(value as T)
                }
            }
        }
        result
    }

    private fun ensureAlive() { if (state == State.DISPOSED) throw BackendFailure.invalidState("Engine disposed.") }
    private fun closeSpeech() { speech?.close(); speech = null }
    private fun safeFailure(error: Throwable): BackendFailure {
        var current = error
        while ((current is java.util.concurrent.CompletionException || current is java.util.concurrent.ExecutionException) && current.cause != null) current = current.cause!!
        return current as? BackendFailure ?: BackendFailure("capture_failed", "The native recording operation failed.")
    }
    private fun <T> failed(error: BackendFailure) = CompletableFuture<T>().also { it.completeExceptionally(error) }
}
