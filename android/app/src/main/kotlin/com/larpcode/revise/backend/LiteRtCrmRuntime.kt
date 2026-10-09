package com.larpcode.revise.backend

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.ExperimentalFlags
import com.google.ai.edge.litertlm.LogSeverity
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import java.io.File
import java.util.concurrent.CompletableFuture

/** Adapter for the pinned litertlm-android:0.18.0 API. No network, tools, or prompt rewriting. */
@OptIn(ExperimentalApi::class)
class LiteRtCrmRuntime private constructor(private val engine: Engine) : CrmRuntime {
    override fun newConversation(maxOutputTokens: Int): CrmConversation = LiteRtConversation(
        engine.createConversation(ConversationConfig(
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.2),
            automaticToolCalling = false,
            channels = emptyList(),
            maxOutputToken = maxOutputTokens,
            enableSpeculativeDecoding = false,
        )), maxOutputTokens,
    )

    override fun close() = engine.close()

    companion object {
        /** Called by the CRM worker after ModelAssets has verified/extracted the model. */
        fun open(model: File): LiteRtCrmRuntime {
            if (!model.isFile) throw BackendFailure.modelMissing("The local Gemma model is missing.")
            // Suppress SDK diagnostics entirely; even native error messages may contain text.
            Engine.setNativeMinLogSeverity(LogSeverity.INFINITY)
            ExperimentalFlags.enableBenchmark = true // Decode-token aggregate only, never logged.
            ExperimentalFlags.enableSpeculativeDecoding = false
            val engine = Engine(EngineConfig(
                modelPath = model.absolutePath,
                backend = Backend.CPU(),
                maxNumTokens = 4096,
                cacheDir = ":nocache",
            ))
            try {
                engine.initialize()
                return LiteRtCrmRuntime(engine)
            } catch (_: Throwable) {
                if (engine.isInitialized()) runCatching { engine.close() }
                throw BackendFailure.inferenceFailed("The local Gemma runtime could not initialize.")
            }
        }
    }
}

@OptIn(ExperimentalApi::class)
private class LiteRtConversation(
    private val conversation: Conversation,
    private val maxTokens: Int,
) : CrmConversation {
    private val lifecycle = Any()
    private var cancelled = false
    private var started = false
    private var closed = false

    override fun generate(prompt: String): CrmOutput {
        val terminal = CompletableFuture<Unit>()
        val output = StringBuilder()
        val chunks = Any()
        var badOutput = false
        synchronized(lifecycle) {
            check(!closed && !started)
            if (cancelled) throw BackendFailure.inferenceFailed("CRM request cancelled.")
            started = true
            conversation.sendMessageAsync(Message.user(prompt), object : MessageCallback {
                override fun onMessage(message: Message) {
                    synchronized(chunks) {
                        if (terminal.isDone || badOutput) return
                        if (message.toolCalls.isNotEmpty() || message.channels.isNotEmpty()) badOutput = true
                        for (content in message.contents.contents) {
                            if (content !is Content.Text || output.length + content.text.length > GemmaCrmEngine.MAX_OUTPUT_CHARS) {
                                badOutput = true
                                break
                            }
                            output.append(content.text)
                        }
                    }
                    // Keep draining until the terminal callback. Native output tokens are bounded.
                }
                override fun onDone() { terminal.complete(Unit) }
                override fun onError(throwable: Throwable) {
                    terminal.completeExceptionally(BackendFailure.inferenceFailed())
                }
            }, maxOutputToken = maxTokens)
        }
        terminal.get() // Do not close a native conversation before completion/cancellation acknowledgment.
        return synchronized(chunks) {
            if (badOutput) throw BackendFailure.inferenceFailed("CRM returned unsupported or oversized output.")
            CrmOutput(output.toString(), conversation.getBenchmarkInfo().lastDecodeTokenCount)
        }
    }

    override fun cancel() = synchronized(lifecycle) {
        if (!closed) {
            cancelled = true
            if (started) conversation.cancelProcess()
        }
    }

    override fun close() = synchronized(lifecycle) {
        if (!closed) {
            conversation.close()
            closed = true
        }
    }
}
