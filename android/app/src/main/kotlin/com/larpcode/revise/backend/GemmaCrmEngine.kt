package com.larpcode.revise.backend

import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Sequential CRM inference, with a fresh conversation for every card. The controller must
 * release STT before calling generate and await unload before loading STT again.
 *
 * A timeout completes the caller but keeps this engine busy until native work acknowledges
 * cancellation. This deliberately prevents a second inference stack from starting too early.
 */
class GemmaCrmEngine(
    private val factory: CrmRuntimeFactory,
    private val timeoutMs: Long = 120_000,
) {
    private val lock = Any()
    private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "revise-crm") }
    private val timer = Executors.newSingleThreadScheduledExecutor { task -> Thread(task, "revise-crm-timeout") }
    private var runtime: CrmRuntime? = null // Worker only.
    private var active: Request? = null // Guarded by lock.
    private var unloading = false
    private var disposed = false
    private var closing: CompletableFuture<Unit>? = null

    init { require(timeoutMs > 0) }

    fun generate(prompt: String, maxTokens: Int = OUTPUT_TOKENS): CompletableFuture<String> {
        if (prompt.isBlank() || prompt.length > MAX_PROMPT_CHARS || maxTokens != OUTPUT_TOKENS) {
            return failed(BackendFailure.invalidState("Supply a nonempty prompt and maxTokens=512 within the input limit."))
        }
        val request = Request()
        synchronized(lock) {
            if (disposed || unloading || active != null) {
                return failed(BackendFailure.invalidState("CRM is busy or disposed."))
            }
            active = request
            val deadline = timer.schedule({
                request.cancel(BackendFailure.inferenceFailed("Local CRM inference timed out."))
            }, timeoutMs, TimeUnit.MILLISECONDS)
            request.result.whenComplete { _, _ ->
                if (request.result.isCancelled) request.cancel(BackendFailure.inferenceFailed("CRM request cancelled."))
            }
            worker.execute {
                var output: String? = null
                var failure: BackendFailure? = null
                try {
                    request.checkRunning()
                    val current = runtime ?: factory.open().also { runtime = it }
                    request.checkRunning()
                    val conversation = current.newConversation(OUTPUT_TOKENS)
                    try {
                        request.attach(conversation)
                        val generated = conversation.generate(prompt)
                        request.checkRunning()
                        // Conservatively reject a response that reached the decode budget. Dart
                        // owns JSON/schema validation and the single permitted card retry.
                        if (generated.decodeTokens <= 0 || generated.decodeTokens >= OUTPUT_TOKENS ||
                            generated.text.isBlank() || generated.text.length > MAX_OUTPUT_CHARS) {
                            throw BackendFailure.inferenceFailed("CRM output was empty, oversized, or reached its token limit.")
                        }
                        output = generated.text
                    } finally {
                        request.detachAndClose(conversation)
                    }
                } catch (error: Throwable) {
                    failure = error as? BackendFailure ?: BackendFailure.inferenceFailed()
                    try { closeRuntime() } catch (_: Throwable) {
                        // Unknown native cleanup state: prevent reopening another engine.
                        synchronized(lock) { disposed = true }
                    }
                } finally {
                    deadline.cancel(false)
                    synchronized(lock) { active = null }
                }
                if (failure == null) request.result.complete(output!!)
                else request.result.completeExceptionally(failure)
            }
        }
        return request.result
    }

    /** Fails while inference is active, including after a caller timeout/cancellation. */
    fun unload(): CompletableFuture<Unit> = synchronized(lock) {
        if (disposed || unloading || active != null) {
            return@synchronized failed(BackendFailure.invalidState("CRM has not finished releasing its active request."))
        }
        unloading = true
        val result = CompletableFuture<Unit>()
        worker.execute {
            var failure: BackendFailure? = null
            try { closeRuntime() } catch (_: Throwable) {
                synchronized(lock) { disposed = true }
                failure = BackendFailure.inferenceFailed("CRM resources could not be released.")
            } finally { synchronized(lock) { unloading = false } }
            if (failure == null) result.complete(Unit) else result.completeExceptionally(failure)
        }
        result
    }

    /** Idempotent asynchronous disposal; does not delete native handles during an active call. */
    fun closeAsync(): CompletableFuture<Unit> {
        val request: Request?
        val result: CompletableFuture<Unit>
        synchronized(lock) {
            closing?.let { return it }
            disposed = true
            request = active
            result = CompletableFuture()
            closing = result
            worker.execute {
                try {
                    closeRuntime()
                    result.complete(Unit)
                } catch (_: Throwable) {
                    result.completeExceptionally(BackendFailure.inferenceFailed("CRM resources could not be released."))
                } finally {
                    timer.shutdownNow()
                    worker.shutdown()
                }
            }
        }
        request?.cancel(BackendFailure.inferenceFailed("CRM engine disposed."))
        return result
    }

    private fun closeRuntime() {
        runtime?.close()
        runtime = null
    }

    private class Request {
        val result = CompletableFuture<String>()
        private val guard = Any()
        private var reason: BackendFailure? = null
        private var conversation: CrmConversation? = null

        fun checkRunning() = synchronized(guard) { reason?.let { throw it } }
        fun attach(value: CrmConversation) = synchronized(guard) {
            reason?.let { throw it }
            conversation = value
        }
        fun cancel(failure: BackendFailure) {
            synchronized(guard) {
                if (reason != null) return
                reason = failure
                // Never expose cancellation exceptions or diagnostics from the native runtime.
                try { conversation?.cancel() } catch (_: Throwable) { /* Await its terminal callback. */ }
            }
            result.completeExceptionally(failure)
        }
        fun detachAndClose(value: CrmConversation) = synchronized(guard) {
            conversation = null
            value.close()
        }
    }

    companion object {
        const val OUTPUT_TOKENS = 512
        const val MAX_PROMPT_CHARS = 65_536
        const val MAX_OUTPUT_CHARS = 32_768
        private fun <T> failed(error: BackendFailure) = CompletableFuture<T>().also { it.completeExceptionally(error) }
    }
}
