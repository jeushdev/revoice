package com.larpcode.revise

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.larpcode.revise.backend.AndroidModelAssets
import com.larpcode.revise.backend.BackendEvents
import com.larpcode.revise.backend.BackendFailure
import com.larpcode.revise.backend.CrmRuntimeFactory
import com.larpcode.revise.backend.EngineController
import com.larpcode.revise.backend.GemmaCrmEngine
import com.larpcode.revise.backend.LiteRtCrmRuntime
import com.larpcode.revise.backend.SpeechBackendFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.CompletableFuture

/** Main-thread channel adapter. Inject devJ's real local-file speech factory at registration. */
class ReviseEnginePlugin(
    private val speechFactory: SpeechBackendFactory = SpeechBackendFactory {
        throw BackendFailure("capture_failed", "The Android speech backend has not been integrated yet.")
    },
) : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var attached = false
    private var bindingEpoch = 0L
    private var sinkEpoch = 0L
    private var sink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var controller: EngineController? = null
    private var releasing: CompletableFuture<Unit>? = null
    private var permission: PendingPermission? = null

    private data class PendingPermission(val controller: EngineController, val result: MethodChannel.Result, val epoch: Long)
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityPaused(activity: Activity) {
            if (activity === activityBinding?.activity) controller?.interrupt()
        }
        override fun onActivityCreated(activity: Activity, state: Bundle?) { }
        override fun onActivityStarted(activity: Activity) { }
        override fun onActivityResumed(activity: Activity) { }
        override fun onActivityStopped(activity: Activity) { }
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) { }
        override fun onActivityDestroyed(activity: Activity) { }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        bindingEpoch++
        attached = true
        methods = MethodChannel(binding.binaryMessenger, "revise/engine").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "revise/captions").also { it.setStreamHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        disposeController()
        detachActivity()
        sink = null
        attached = false
        bindingEpoch++
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (sink != null) disposeController()
        sinkEpoch++
        sink = events
    }
    override fun onCancel(arguments: Any?) {
        sinkEpoch++
        sink = null
        disposeController()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("init", "start", "pause", "resume", "stop", "generateCrm")) {
            result.notImplemented() // cleanLine is explicitly deferred.
            return
        }
        if (!attached || sink == null) { invalid(result, "Subscribe to captions before initializing the engine."); return }
        val args = call.arguments
        val empty = args == null || (args is Map<*, *> && args.isEmpty())
        when (call.method) {
            "init" -> {
                if (!empty) { invalid(result, "init takes no arguments."); return }
                if (releasing?.isDone == false) { invalid(result, "Native resources are still being released."); return }
                if (releasing?.isCompletedExceptionally == true) {
                    result.error("inference_failed", "Native cleanup failed; restart the app before reinitializing.", null)
                    return
                }
                releasing = null
                val current = controller ?: createController().also { controller = it }
                complete(current.init(), result)
            }
            "start" -> {
                if (args !is Map<*, *> || args.keys != setOf("language") || args["language"] != "en") {
                    invalid(result, "start requires language=en."); return
                }
                val current = controller ?: run { invalid(result, "Initialize first."); return }
                if (!current.canStart()) { invalid(result, "start requires a ready or stopped idle engine."); return }
                if (permission != null) { invalid(result, "A permission request is pending."); return }
                if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    complete(current.start(true), result)
                } else {
                    val activity = activityBinding?.activity
                    if (activity == null) { result.error("permission_denied", "An activity is required to request microphone permission.", null); return }
                    permission = PendingPermission(current, result, bindingEpoch)
                    try { activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST) }
                    catch (_: RuntimeException) {
                        permission = null
                        result.error("permission_denied", "Microphone permission could not be requested.", null)
                    }
                }
            }
            "generateCrm" -> {
                if (args !is Map<*, *> || args.keys != setOf("prompt", "maxTokens") ||
                    args["prompt"] !is String || args["maxTokens"] != 512) {
                    invalid(result, "generateCrm requires prompt and maxTokens=512."); return
                }
                val current = controller ?: run { invalid(result, "Initialize first."); return }
                complete(current.generateCrm(args["prompt"] as String), result)
            }
            else -> {
                if (!empty) { invalid(result, "${call.method} takes no arguments."); return }
                val current = controller ?: run { invalid(result, "Initialize first."); return }
                val task = when (call.method) { "pause" -> current.pause(); "resume" -> current.resume(); else -> current.stop() }
                complete(task, result)
            }
        }
    }

    private fun createController(): EngineController {
        val assets by lazy { AndroidModelAssets.create(context) }
        val targetSinkEpoch = sinkEpoch
        val targetBindingEpoch = bindingEpoch
        lateinit var current: EngineController
        current = EngineController({ assets.prepare() }, speechFactory,
            GemmaCrmEngine(CrmRuntimeFactory { LiteRtCrmRuntime.open(assets.requireGemma()) }),
            BackendEvents { token, event ->
                main.post {
                    if (attached && bindingEpoch == targetBindingEpoch && sinkEpoch == targetSinkEpoch &&
                        controller === current && current.isCurrentGeneration(token)) sink?.success(event)
                }
            })
        return current
    }

    private fun <T> complete(future: CompletableFuture<T>, result: MethodChannel.Result) {
        val epoch = bindingEpoch
        future.whenComplete { value, error -> main.post {
            if (!attached || bindingEpoch != epoch) return@post
            if (error == null) result.success(value)
            else {
                var cause = error
                while ((cause is java.util.concurrent.CompletionException || cause is java.util.concurrent.ExecutionException) && cause.cause != null) cause = cause.cause!!
                val safe = cause as? BackendFailure ?: BackendFailure.inferenceFailed()
                result.error(safe.code, safe.message, null)
            }
        } }
    }
    private fun invalid(result: MethodChannel.Result, message: String) { result.error("invalid_state", message, null) }
    private fun disposeController() {
        permission?.let { if (attached && it.epoch == bindingEpoch) invalid(it.result, "Permission request interrupted.") }
        permission = null
        controller?.let { releasing = it.closeAsync() }
        controller = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val pending = permission ?: return true
        permission = null
        if (!attached || pending.epoch != bindingEpoch) return true
        if (pending.controller !== controller) { invalid(pending.result, "Engine changed during permission request."); return true }
        val allowed = permissions.indices.any { permissions[it] == Manifest.permission.RECORD_AUDIO && grantResults.getOrNull(it) == PackageManager.PERMISSION_GRANTED }
        complete(pending.controller.start(allowed), pending.result)
        return true
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.activity.application.registerActivityLifecycleCallbacks(lifecycle)
    }
    override fun onDetachedFromActivityForConfigChanges() { detachActivity(); disposeController() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivity() { detachActivity(); disposeController() }
    private fun detachActivity() {
        activityBinding?.let {
            it.removeRequestPermissionsResultListener(this)
            it.activity.application.unregisterActivityLifecycleCallbacks(lifecycle)
        }
        activityBinding = null
    }
    companion object { private const val PERMISSION_REQUEST = 48120 }
}
