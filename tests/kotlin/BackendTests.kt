package com.larpcode.revise.backend

import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

private var passes = 0
private fun test(name: String, block: () -> Unit) {
    block()
    passes++
    println("PASS $name")
}
private fun <T> CompletableFuture<T>.await(): T = get(3, TimeUnit.SECONDS)
private fun failure(future: CompletableFuture<*>, code: String): BackendFailure {
    val error = try { future.await(); error("Expected $code") } catch (e: ExecutionException) { e.cause }
    check(error is BackendFailure && error.code == code) { "Unexpected failure: ${error?.javaClass}" }
    return error
}
private fun waitFor(condition: () -> Boolean) {
    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
    while (!condition()) {
        check(System.nanoTime() < deadline) { "Condition timed out" }
        Thread.sleep(5)
    }
}

private class FakeFactory(
    private val output: CrmOutput = CrmOutput(" {\"raw\":true}\n", 12),
    private val terminal: CountDownLatch? = null,
    private val openGate: CountDownLatch? = null,
    private val failGenerate: Boolean = false,
) : CrmRuntimeFactory {
    val opened = AtomicInteger()
    val conversations = AtomicInteger()
    val cancelled = AtomicInteger()
    val closedConversations = AtomicInteger()
    val closedRuntimes = AtomicInteger()
    val running = AtomicInteger()
    val started = CountDownLatch(1)
    val prompts = mutableListOf<String>()
    override fun open(): CrmRuntime {
        opened.incrementAndGet()
        openGate?.await()
        return object : CrmRuntime {
            override fun newConversation(maxOutputTokens: Int): CrmConversation {
                check(maxOutputTokens == 512)
                conversations.incrementAndGet()
                return object : CrmConversation {
                    override fun generate(prompt: String): CrmOutput {
                        prompts.add(prompt)
                        running.incrementAndGet()
                        started.countDown()
                        try {
                            terminal?.await()
                            if (failGenerate) throw IllegalStateException("PRIVATE PROMPT SECRET")
                            return output
                        } finally { running.decrementAndGet() }
                    }
                    override fun cancel() { cancelled.incrementAndGet() }
                    override fun close() {
                        check(running.get() == 0) { "Conversation closed during inference" }
                        closedConversations.incrementAndGet()
                    }
                }
            }
            override fun close() {
                check(running.get() == 0) { "Engine closed during inference" }
                check(conversations.get() == closedConversations.get())
                closedRuntimes.incrementAndGet()
            }
        }
    }
}

private fun crmTests() {
    test("sequential requests reuse engine, isolate conversations, preserve raw prompt/output") {
        val factory = FakeFactory()
        val engine = GemmaCrmEngine(factory)
        try {
            check(engine.generate(" first prompt ").await() == " {\"raw\":true}\n")
            check(engine.generate("second prompt").await() == " {\"raw\":true}\n")
            check(factory.opened.get() == 1 && factory.conversations.get() == 2)
            check(factory.closedConversations.get() == 2)
            check(factory.prompts == listOf(" first prompt ", "second prompt"))
        } finally { engine.closeAsync().await() }
        check(factory.closedRuntimes.get() == 1)
    }
    test("invalid input is rejected before model loading") {
        val factory = FakeFactory()
        val engine = GemmaCrmEngine(factory)
        try {
            failure(engine.generate(" "), "invalid_state")
            failure(engine.generate("x", 513), "invalid_state")
            failure(engine.generate("x".repeat(65_537)), "invalid_state")
            check(factory.opened.get() == 0)
        } finally { engine.closeAsync().await() }
    }
    for ((name, output) in listOf(
        "empty" to CrmOutput("", 1),
        "budget exhausted" to CrmOutput("{\"completeLooking\":true}", 512),
        "oversized" to CrmOutput("x".repeat(32_769), 1),
        "missing decode metric" to CrmOutput("{}", 0),
    )) test("$name output fails and closes the engine") {
        val factory = FakeFactory(output)
        val engine = GemmaCrmEngine(factory)
        try {
            failure(engine.generate("prompt"), "inference_failed")
            check(factory.closedRuntimes.get() == 1)
        } finally { engine.closeAsync().await() }
    }
    test("SDK exceptions do not expose text or cause through errors") {
        val engine = GemmaCrmEngine(FakeFactory(failGenerate = true))
        try {
            val error = failure(engine.generate("prompt"), "inference_failed")
            check(!error.toString().contains("SECRET") && error.cause == null)
        } finally { engine.closeAsync().await() }
    }
    test("missing model retains its stable model_missing error") {
        val engine = GemmaCrmEngine(CrmRuntimeFactory { throw BackendFailure.modelMissing("Missing local model.") })
        try { failure(engine.generate("prompt"), "model_missing") }
        finally { engine.closeAsync().await() }
    }
    test("busy engine rejects parallel generation and unload") {
        val terminal = CountDownLatch(1)
        val factory = FakeFactory(terminal = terminal)
        val engine = GemmaCrmEngine(factory)
        try {
            val first = engine.generate("first")
            check(factory.started.await(3, TimeUnit.SECONDS))
            failure(engine.generate("second"), "invalid_state")
            failure(engine.unload(), "invalid_state")
            terminal.countDown()
            first.await()
            check(factory.conversations.get() == 1)
        } finally { terminal.countDown(); engine.closeAsync().await() }
    }
    test("timeout keeps resources busy until native terminal acknowledgment") {
        val terminal = CountDownLatch(1)
        val factory = FakeFactory(terminal = terminal)
        val engine = GemmaCrmEngine(factory, timeoutMs = 250)
        try {
            val first = engine.generate("prompt")
            check(factory.started.await(3, TimeUnit.SECONDS))
            failure(first, "inference_failed")
            check(factory.cancelled.get() == 1 && factory.closedRuntimes.get() == 0)
            failure(engine.generate("new"), "invalid_state")
            failure(engine.unload(), "invalid_state")
            terminal.countDown()
            waitFor { factory.closedRuntimes.get() == 1 }
        } finally { terminal.countDown(); engine.closeAsync().await() }
    }
    test("disposal cancels, waits, closes once, and rejects new work") {
        val terminal = CountDownLatch(1)
        val factory = FakeFactory(terminal = terminal)
        val engine = GemmaCrmEngine(factory)
        val result = engine.generate("prompt")
        check(factory.started.await(3, TimeUnit.SECONDS))
        val closing = engine.closeAsync()
        check(engine.closeAsync() === closing && !closing.isDone)
        check(factory.cancelled.get() == 1 && factory.closedRuntimes.get() == 0)
        failure(result, "inference_failed")
        failure(engine.generate("later"), "invalid_state")
        terminal.countDown()
        closing.await()
        check(factory.closedConversations.get() == 1 && factory.closedRuntimes.get() == 1)
    }
    test("timeout during initialization cleans up before reuse") {
        val gate = CountDownLatch(1)
        val factory = FakeFactory(openGate = gate)
        val engine = GemmaCrmEngine(factory, timeoutMs = 100)
        try {
            failure(engine.generate("prompt"), "inference_failed")
            failure(engine.generate("new"), "invalid_state")
            gate.countDown()
            waitFor { factory.closedRuntimes.get() == 1 }
            check(factory.conversations.get() == 0)
        } finally { gate.countDown(); engine.closeAsync().await() }
    }
    test("unload releases idle LLM before the next model load") {
        val factory = FakeFactory()
        val engine = GemmaCrmEngine(factory)
        try {
            engine.generate("one").await()
            engine.unload().await()
            check(factory.closedRuntimes.get() == 1)
            engine.generate("two").await()
            check(factory.opened.get() == 2)
        } finally { engine.closeAsync().await() }
    }
    test("caller future cancellation also cancels native work") {
        val terminal = CountDownLatch(1)
        val factory = FakeFactory(terminal = terminal)
        val engine = GemmaCrmEngine(factory)
        try {
            val result = engine.generate("prompt")
            check(factory.started.await(3, TimeUnit.SECONDS))
            check(result.cancel(false))
            check(factory.cancelled.get() == 1)
            failure(engine.unload(), "invalid_state")
        } finally { terminal.countDown(); engine.closeAsync().await() }
    }
}

private class AssetsFixture {
    val root: File = Files.createTempDirectory("revise-model-test-").toFile()
    val content = "123456789".toByteArray()
    val hash = MessageDigest.getInstance("SHA-256").digest(content).joinToString("") { "%02x".format(it.toInt() and 255) }
    val entries = ModelInventory.REQUIRED_PATHS.map { ModelEntry(it.split('/')[1], it, content.size.toLong(), hash) }
    val inventory = ModelInventory(entries)
    val missing = mutableSetOf<String>()
    var supplied = content
    val reads = AtomicInteger()
    fun assets(space: Long = Long.MAX_VALUE) = ModelAssets(inventory, PackagedModels { path ->
        reads.incrementAndGet()
        if (path.removePrefix("revise/") in missing) throw java.io.FileNotFoundException()
        ByteArrayInputStream(supplied)
    }, root, { space })
    fun target(path: String) = File(File(root, inventory.version), path)
    fun noTemporaryFiles() = check(root.walkTopDown().none { it.name.endsWith(".partial") })
    fun clean() { root.deleteRecursively() }
}

private fun assetTests() {
    test("extract all pinned models and reuse verified files without rereading APK") {
        val f = AssetsFixture()
        try {
            val assets = f.assets()
            val ready = assets.prepare()
            check(ready.gemma!!.readBytes().contentEquals(f.content))
            check(ready.speechDirectory.isDirectory && ready.diarizationDirectory.isDirectory)
            check(f.reads.get() == 11)
            assets.prepare()
            check(f.reads.get() == 11)
            f.noTemporaryFiles()
        } finally { f.clean() }
    }
    test("missing Gemma permits speech but requireGemma fails") {
        val f = AssetsFixture()
        try {
            f.missing.add(ModelInventory.GEMMA_PATH)
            check(f.assets().prepare().gemma == null)
            try { f.assets().requireGemma(); error("Expected missing Gemma") }
            catch (error: BackendFailure) { check(error.code == "model_missing") }
            f.noTemporaryFiles()
        } finally { f.clean() }
    }
    test("missing speech blocks initialization") {
        val f = AssetsFixture()
        try {
            f.missing.add("models/stt/encoder.ort")
            try { f.assets().prepare(); error("Expected missing speech") }
            catch (error: BackendFailure) { check(error.code == "model_missing") }
            f.noTemporaryFiles()
        } finally { f.clean() }
    }
    test("same-size corrupt local asset is replaced only by verified source") {
        val f = AssetsFixture()
        try {
            val assets = f.assets()
            val model = assets.requireGemma()
            model.writeText("corrupt!!")
            check(assets.requireGemma().readBytes().contentEquals(f.content))
            check(f.reads.get() == 2)
            f.noTemporaryFiles()
        } finally { f.clean() }
    }
    for (source in listOf("bad", "corrupt!!", "oversized-source")) test("invalid source $source is never published") {
        val f = AssetsFixture()
        try {
            f.supplied = source.toByteArray()
            try { f.assets().requireGemma(); error("Expected invalid source") }
            catch (error: BackendFailure) { check(error.code == "model_missing") }
            check(!f.target(ModelInventory.GEMMA_PATH).exists())
            f.noTemporaryFiles()
        } finally { f.clean() }
    }
    test("disk reserve failure leaves no partial or published model") {
        val f = AssetsFixture()
        try {
            try { f.assets(0).requireGemma(); error("Expected storage failure") }
            catch (error: BackendFailure) { check(error.message!!.contains("storage")) }
            check(f.reads.get() == 0 && !f.target(ModelInventory.GEMMA_PATH).exists())
            f.noTemporaryFiles()
        } finally { f.clean() }
    }
    test("manifest rejects duplicates, traversal, bad hashes and missing files") {
        val f = AssetsFixture()
        try {
            for (entries in listOf(
                f.entries.dropLast(1),
                f.entries.dropLast(1) + f.entries.first(),
                f.entries.dropLast(1) + f.entries.last().copy(path = "../../outside"),
                f.entries.dropLast(1) + f.entries.last().copy(sha256 = "invalid"),
            )) {
                try { ModelInventory(entries); error("Expected invalid inventory") }
                catch (_: IllegalArgumentException) { }
            }
        } finally { f.clean() }
    }
    test("changed inventory hash selects a separate version directory") {
        val f = AssetsFixture()
        try {
            val changed = ModelInventory(f.entries.dropLast(1) + f.entries.last().copy(sha256 = "0".repeat(64)))
            check(changed.version != f.inventory.version)
        } finally { f.clean() }
    }
}

private class ControllerFixture(
    val runtime: FakeFactory = FakeFactory(),
    val stopGate: CountDownLatch? = null,
) {
    val delivered = java.util.Collections.synchronizedList(mutableListOf<Pair<Long, Map<String, Any>>>())
    val openedSpeech = AtomicInteger()
    val speechInstances = mutableListOf<FakeSpeech>()
    var missingAssets = false
    val crm = GemmaCrmEngine(CrmRuntimeFactory {
        check(openedSpeech.get() == 0) { "Speech is still resident while CRM loads" }
        runtime.open()
    }, timeoutMs = 300)
    val controller = EngineController({
        if (missingAssets) throw BackendFailure.modelMissing("Missing speech asset.")
        PreparedModels(File("fixture-stt"), File("fixture-diarization"), File("fixture-gemma"))
    }, SpeechBackendFactory {
        check(runtime.opened.get() == runtime.closedRuntimes.get()) { "LLM is still resident while STT loads" }
        openedSpeech.incrementAndGet()
        FakeSpeech().also { speechInstances.add(it) }
    }, crm, BackendEvents { token, event -> delivered.add(token to event) })

    inner class FakeSpeech : SpeechBackend {
        lateinit var listener: SpeechListener
        private var closed = false
        var stops = 0
        var pauses = 0
        override fun start(listener: SpeechListener) {
            this.listener = listener
            listener.onCaption(CaptionSnapshot("s1", "partial", 1, false, 0, 1))
        }
        override fun pause() {
            pauses++
            listener.onCaption(CaptionSnapshot("s1", "final at pause", 1, true, 0, 5))
        }
        override fun resume() { }
        override fun stop() {
            stops++
            stopGate?.await()
            listener.onCaption(CaptionSnapshot("s2", "final at stop", 2, true, 10, 15))
        }
        override fun requestStop() { }
        override fun close() {
            if (!closed) { closed = true; openedSpeech.decrementAndGet() }
        }
    }
    fun prepareSession() { controller.init().await(); controller.start(true).await() }
    fun close() { stopGate?.countDown(); controller.closeAsync().await() }
}

private fun controllerTests() {
    test("init loads speech and only reports Gemma assets, not inference readiness") {
        val f = ControllerFixture()
        try {
            check(f.controller.init().await() == mapOf("sttReady" to true, "llmReady" to true))
            check(f.runtime.opened.get() == 0 && f.openedSpeech.get() == 1)
            check(f.delivered.last().second["state"] == "ready")
            failure(f.controller.generateCrm("prompt"), "invalid_state")
            failure(f.controller.start(true, "fr"), "invalid_state")
        } finally { f.close() }
    }
    test("pause drains finals, resume preserves the same speech instance and generation") {
        val f = ControllerFixture()
        try {
            f.prepareSession()
            val token = f.delivered.last().first
            f.controller.pause().await()
            check(f.delivered.takeLast(2).map { it.second["type"] } == listOf("caption", "state"))
            check(f.delivered.last().second["state"] == "paused")
            f.controller.resume().await()
            check(f.speechInstances.size == 1 && f.delivered.last().first == token)
            failure(f.controller.init(), "invalid_state")
        } finally { f.close() }
    }
    test("stop enqueues finals then stopped, closes speech, and repeated stop emits nothing") {
        val f = ControllerFixture()
        try {
            f.prepareSession()
            f.controller.stop().await()
            check(f.delivered.takeLast(2).map { it.second["type"] } == listOf("caption", "state"))
            check(f.delivered.last().second["state"] == "stopped" && f.openedSpeech.get() == 0)
            val count = f.delivered.size
            f.controller.stop().await()
            check(f.delivered.size == count && f.speechInstances.single().stops == 1)
            f.speechInstances.single().listener.onCaption(CaptionSnapshot("late", "late", 0, true, 1, 2))
            check(f.delivered.size == count)
        } finally { f.close() }
    }
    test("controller prevents simultaneous STT/LLM residency and drops previous-session callbacks") {
        val f = ControllerFixture()
        try {
            f.prepareSession()
            val old = f.speechInstances.single().listener
            val oldToken = f.delivered.last().first
            f.controller.stop().await()
            check(f.controller.generateCrm("prompt").await()["json"] == " {\"raw\":true}\n")
            f.controller.start(true).await()
            check(f.runtime.closedRuntimes.get() == 1 && f.speechInstances.size == 2)
            check(!f.controller.isCurrentGeneration(oldToken))
            val count = f.delivered.size
            old.onCaption(CaptionSnapshot("stale", "stale", 1, true, 1, 2))
            old.onFailure("capture_failed")
            check(f.delivered.size == count)
        } finally { f.close() }
    }
    test("missing assets and permission errors are recoverable only through init") {
        val f = ControllerFixture()
        try {
            f.missingAssets = true
            failure(f.controller.init(), "model_missing")
            f.missingAssets = false
            f.controller.init().await()
            failure(f.controller.start(false), "permission_denied")
            failure(f.controller.start(true), "invalid_state")
            f.controller.init().await()
            f.controller.start(true).await()
        } finally { f.close() }
    }
    test("CRM failure preserves stopped state and permits a later recording") {
        val f = ControllerFixture(FakeFactory(failGenerate = true))
        try {
            f.prepareSession()
            f.controller.stop().await()
            val count = f.delivered.size
            failure(f.controller.generateCrm("prompt"), "inference_failed")
            check(f.delivered.size == count)
            f.controller.start(true).await()
        } finally { f.close() }
    }
    test("CRM timeout cannot restart capture before native cancellation finishes") {
        val terminal = CountDownLatch(1)
        val factory = FakeFactory(terminal = terminal)
        val f = ControllerFixture(factory)
        try {
            f.prepareSession()
            f.controller.stop().await()
            failure(f.controller.generateCrm("prompt"), "inference_failed")
            failure(f.controller.start(true), "invalid_state")
            check(f.openedSpeech.get() == 0 && f.delivered.last().second["state"] == "stopped")
            terminal.countDown()
            waitFor { factory.closedRuntimes.get() == 1 }
            f.controller.start(true).await()
        } finally { terminal.countDown(); f.close() }
    }
    test("a flush in progress rejects competing operations and does not emit stopped early") {
        val gate = CountDownLatch(1)
        val f = ControllerFixture(stopGate = gate)
        try {
            f.prepareSession()
            val stop = f.controller.stop()
            failure(f.controller.start(true), "invalid_state")
            check(!stop.isDone && f.delivered.last().second["state"] == "listening")
            gate.countDown()
            stop.await()
        } finally { f.close() }
    }
    test("interrupt reports error, rejects later captions, and disposal invalidates queued events") {
        val f = ControllerFixture()
        try {
            f.prepareSession()
            val listener = f.speechInstances.single().listener
            val token = f.delivered.last().first
            f.controller.interrupt()
            check(f.delivered.last().second["state"] == "error")
            val count = f.delivered.size
            listener.onCaption(CaptionSnapshot("late", "late", 1, true, 0, 1))
            check(f.delivered.size == count)
            f.close()
            check(!f.controller.isCurrentGeneration(token))
            failure(f.controller.init(), "invalid_state")
        } finally { f.close() }
    }
}

fun main() {
    crmTests()
    assetTests()
    controllerTests()
    println("$passes Kotlin backend checks passed.")
}
