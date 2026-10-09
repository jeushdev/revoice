package com.larpcode.revise

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native side of the ReVise platform contract (PRD section 7).
 *
 * EventChannel `revise/captions` (native -> Dart, one map per event) and
 * MethodChannel `revise/engine` (Dart -> native). Channel plumbing and the
 * state machine are done; Jeush and Sam wire Moonshine and the local LLM into
 * the TODO spots. Audio never crosses into Dart.
 */
class ReviseEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private enum class State(val wire: String) { READY("ready"), LISTENING("listening"), PAUSED("paused"), STOPPED("stopped"), ERROR("error") }

    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var state: State? = null
    private var sttReady = false
    private var llmAssetsPresent = false
    private var llmBusy = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, "revise/engine").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "revise/captions").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }

    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                // TODO(jeush): load bundled Moonshine STT + diarization assets from local files (no auto-download).
                sttReady = false
                // TODO(sam): check the bundled LLM file exists. Do NOT load it here.
                llmAssetsPresent = false
                emitState(State.READY)
                result.success(mapOf("sttReady" to sttReady, "llmReady" to llmAssetsPresent))
            }
            "start" -> {
                if (state != State.READY && state != State.STOPPED) return invalidState(result, "start")
                if (!sttReady) return result.error("model_missing", "Moonshine is not wired in yet.", null)
                // TODO(jeush): free the LLM, reload STT if released, check RECORD_AUDIO (permission_denied),
                // start capture, and call emitCaption(...) for every partial and final segment.
                emitState(State.LISTENING)
                result.success(true)
            }
            "pause" -> {
                if (state != State.LISTENING) return invalidState(result, "pause")
                // TODO(jeush): stop capture and flush pending speech as final.
                emitState(State.PAUSED)
                result.success(true)
            }
            "resume" -> {
                if (state != State.PAUSED) return invalidState(result, "resume")
                // TODO(jeush): restart capture; keep the session and speaker mapping.
                emitState(State.LISTENING)
                result.success(true)
            }
            "stop" -> {
                if (state == State.STOPPED) return result.success(true)
                if (state != State.LISTENING && state != State.PAUSED) return invalidState(result, "stop")
                // TODO(jeush): stop capture, flush pending segments as final, release STT + diarization.
                emitState(State.STOPPED)
                result.success(true)
            }
            "generate", "cleanLine" -> runLlm(call, result)
            else -> result.notImplemented()
        }
    }

    private fun runLlm(call: MethodCall, result: MethodChannel.Result) {
        if (state != State.STOPPED) return invalidState(result, call.method)
        if (llmBusy) return result.error("invalid_state", "LLM request already running.", null)
        if (!llmAssetsPresent) return result.error("model_missing", "Bundled LLM not found.", null)
        val prompt = call.argument<String>("prompt") ?: return result.error("inference_failed", "Missing prompt.", null)
        val maxTokens = call.argument<Int>("maxTokens") ?: 512
        // generate: json=true means constrain output to JSON (grammar) when possible.
        @Suppress("UNUSED_VARIABLE") val json = call.argument<Boolean>("json") ?: false
        llmBusy = true
        Thread {
            // TODO(sam): load Gemma 4 E2B (LiteRT-LM) or Qwen 2.5 1.5B (llama.cpp) lazily, run prompt, return raw text.
            @Suppress("UNUSED_VARIABLE") val unused = prompt to maxTokens
            val output: String? = null
            main.post {
                llmBusy = false
                if (output == null) {
                    result.error("inference_failed", "LLM not wired in yet.", null)
                } else {
                    result.success(mapOf("text" to output))
                }
            }
        }.start()
    }

    /** Call for every partial and final segment. Safe from any thread. */
    fun emitCaption(segmentId: String, text: String, speakerId: Int, isFinal: Boolean, tStartMs: Long, tEndMs: Long) =
        send(mapOf("type" to "caption", "segmentId" to segmentId, "text" to text, "speakerId" to speakerId,
            "isFinal" to isFinal, "tStartMs" to tStartMs, "tEndMs" to tEndMs))

    /** Use for async failures (mic interrupted, capture failed). */
    fun emitError(message: String) {
        state = State.ERROR
        send(mapOf("type" to "state", "state" to State.ERROR.wire, "message" to message))
    }

    private fun emitState(newState: State) {
        state = newState
        send(mapOf("type" to "state", "state" to newState.wire, "message" to null))
    }

    private fun send(event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) sink?.success(event) else main.post { sink?.success(event) }
    }

    private fun invalidState(result: MethodChannel.Result, method: String) =
        result.error("invalid_state", "$method is not allowed while ${state?.wire ?: "uninitialized"}.", null)
}
