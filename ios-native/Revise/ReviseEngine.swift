import AVFoundation
import Foundation
import MoonshineVoice
import UIKit

/// Error codes from PRD section 7. The channel layer turns these into FlutterError.
struct ReviseError: Error {
    enum Code: String {
        case permissionDenied = "permission_denied"
        case modelMissing = "model_missing"
        case captureFailed = "capture_failed"
        case inferenceFailed = "inference_failed"
        case invalidState = "invalid_state"
    }
    let code: Code
    let message: String
}

/// The iOS side of `revise/engine`: mic -> Moonshine streaming STT -> speaker IDs.
/// No Flutter imports here, so it can be tested without the Flutter project.
///
/// It's an `actor` (a class whose methods run one at a time), so a `stop` and a
/// `start` arriving close together can't race each other.
///
/// States: idle -> ready -> listening <-> paused -> stopped -> (start again) listening.
/// `error` is entered on an async failure or an interruption; call `initialize` again.
actor ReviseEngine {
    enum State: String {
        case idle, ready, listening, paused, stopped, error
    }

    private var state: State = .idle
    private var mic: MoonshineMic?
    private var tracker: CaptionTracker?
    private var pausedAt: Date?
    private var observers: [NSObjectProtocol] = []

    // On-device LLM (llama.cpp). Loaded on the first request after Stop, kept for later requests,
    // freed before the next recording starts. Never loaded while Moonshine is loaded.
    private var llm: LlamaRunner?
    private var llmBusy = false
    private var prewarmTask: Task<Void, Never>?
    private let llmQueue = DispatchQueue(label: "revise.llm", qos: .userInitiated)

    /// Delivers one event map to Flutter. Must be safe to call from any thread.
    private let sendEvent: @Sendable ([String: Any]) -> Void

    init(sendEvent: @escaping @Sendable ([String: Any]) -> Void) {
        self.sendEvent = sendEvent
    }

    // MARK: - revise/engine methods

    /// Loads STT + diarization and checks the LLM files exist (without loading the LLM).
    func initialize() async -> [String: Bool] {
        startObservingInterruptions()
        if state == .listening || state == .paused {
            // Re-init mid-recording: end the recording first.
            _ = stopRecording()
        }
        await prewarmTask?.value
        if !llmBusy { llm = nil }          // free the LLM before the speech models load
        releaseSTT()
        let llmReady = ReviseModelStore.llmAssetPresent()
        do {
            try await loadSTT()
            setState(.ready)
            return ["sttReady": true, "llmReady": llmReady]
        } catch let error as ReviseError {
            setState(.error, message: error.message)
        } catch {
            setState(.error, message: "Could not load models")
        }
        return ["sttReady": false, "llmReady": llmReady]
    }

    func start(language: String) async throws {
        guard state == .ready || state == .stopped else { throw Self.invalidState("start") }
        guard language == "en" else {
            throw ReviseError(code: .modelMissing, message: "Only English is supported in v1")
        }
        await prewarmTask?.value           // let a background LLM load finish before freeing it
        guard !llmBusy else { throw ReviseError(code: .invalidState, message: "An LLM request is still running") }
        llm = nil                          // PRD: free the LLM before recording starts
        try await ensureMicPermission()
        try await loadSTT()  // reloads after a previous stop released the models
        guard let mic else { throw ReviseError(code: .modelMissing, message: "Speech model not loaded") }

        let tracker = CaptionTracker(
            emit: sendEvent,
            onError: { [weak self] message in
                Task { await self?.asyncFailure(message) }
            })
        tracker.beginRun()

        do {
            try mic.begin { event in tracker.handle(event) }   // fresh stream: speakers restart at 1
            try mic.startCapture()
        } catch {
            mic.finish()
            tracker.close()
            throw ReviseError(code: .captureFailed, message: error.localizedDescription)
        }
        self.tracker = tracker
        pausedAt = nil
        setState(.listening)
    }

    /// Pause = stop the mic, which makes Moonshine flush any speech in progress as final.
    func pause() throws {
        guard state == .listening, let mic else { throw Self.invalidState("pause") }
        let started = Date()
        mic.pauseCapture()                  // stops the mic and flushes pending speech as final
        tracker?.flushPendingAsFinal()
        pausedAt = Date()
        setState(.paused)
        Self.logTiming("pause flush", since: started)
    }

    func resume() async throws {
        guard state == .paused, let mic, let tracker else { throw Self.invalidState("resume") }
        try await ensureMicPermission()
        // Paused time still counts toward session time (PRD section 7).
        let pausedMs = Int(Date().timeIntervalSince(pausedAt ?? Date()) * 1000)
        tracker.addPausedTime(ms: pausedMs)
        do {
            try mic.resumeCapture()
        } catch {
            throw ReviseError(code: .captureFailed, message: error.localizedDescription)
        }
        pausedAt = nil
        setState(.listening)
    }

    /// Flushes everything as final, frees the models (PRD: free STT before the LLM loads),
    /// then emits `stopped`. Stopping twice is fine.
    func stop() throws {
        switch state {
        case .stopped:
            return
        case .listening, .paused, .error:
            break
        default:
            throw Self.invalidState("stop")
        }
        // Only the flush has to finish before we answer Flutter. Freeing the models (slow,
        // ~140 MB) happens right after the reply, as the next job on this actor, so it still
        // runs before any later `start` can reload them.
        let started = Date()
        _ = stopRecording(releasingModels: false)
        setState(.stopped)
        Self.logTiming("stop flush", since: started)
        Task { await self.releaseModelsAfterStop() }
    }

    private func releaseModelsAfterStop() {
        guard state == .stopped else { return }   // a newer session already owns the models
        let started = Date()
        releaseSTT()
        Self.logTiming("stop release models", since: started)
        startLlmPrewarm()
    }

    /// Right after Moonshine is freed, load the LLM and read the shared system prompt in the
    /// background, so the first CRM card doesn't pay for model loading and the prompt prefix.
    /// Requests that arrive meanwhile simply wait for it (`prewarmTask`).
    private func startLlmPrewarm() {
        guard llm == nil, prewarmTask == nil, let modelURL = ReviseModelStore.llmModelURL() else { return }
        prewarmTask = Task { [weak self] in
            guard let self else { return }
            await self.prewarmBody(modelURL)
        }
    }

    private func prewarmBody(_ modelURL: URL) async {
        defer { prewarmTask = nil }
        guard state == .stopped, llm == nil else { return }
        do {
            let runner = try await onLlmQueue { try LlamaRunner(modelPath: modelURL.path) }
            try await onLlmQueue { try runner.warmup(system: ReviseGrammars.crmValuesOnlySystem) }
            if state == .stopped { llm = runner }          // a restart in the meantime wins
        } catch {
            NSLog("REVISE-LLM prewarm failed: %@", "\(error)")   // generate() will retry and report properly
        }
    }

    private static func logTiming(_ what: String, since start: Date) {
        #if DEBUG
        NSLog("REVISE-TIMING %@ took %d ms", what, Int(Date().timeIntervalSince(start) * 1000))
        #endif
    }

    // MARK: - On-device LLM

    struct LlmResult {
        let text: String
        let stats: LlmStats
        let diagnostics: [String]      // llama.cpp backend lines from loading (Metal? layers offloaded?)
    }

    /// Runs one prompt on the on-device LLM. Only allowed while stopped (PRD section 7), one
    /// request at a time. Frees Moonshine first, loads the LLM on first use, and keeps it loaded
    /// for the next request. `grammar` is optional GBNF text that forces the output's shape.
    func generate(
        prompt: String, system: String?, maxTokens: Int, grammar: String?,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> LlmResult {
        guard state == .stopped else { throw Self.invalidState("LLM request") }
        await prewarmTask?.value                       // reuse the model the background load is preparing
        guard !llmBusy else { throw ReviseError(code: .invalidState, message: "An LLM request is already running") }
        guard let modelURL = ReviseModelStore.llmModelURL() else {
            throw ReviseError(code: .modelMissing, message: "No LLM file is bundled in the app (Models/llm)")
        }
        llmBusy = true
        defer { llmBusy = false }

        releaseSTT()                        // never keep Moonshine and the LLM in memory together
        do {
            let runner: LlamaRunner
            if let loaded = llm {
                runner = loaded
            } else {
                runner = try await onLlmQueue { try LlamaRunner(modelPath: modelURL.path) }
                llm = runner
            }
            let result = try await onLlmQueue {
                try runner.generate(
                    prompt: prompt, system: system, maxTokens: maxTokens, grammar: grammar, onToken: onToken)
            }
            return LlmResult(text: result.text, stats: result.stats, diagnostics: runner.diagnostics)
        } catch let error as ReviseError {
            throw error
        } catch {
            throw ReviseError(code: .inferenceFailed, message: "\(error)")
        }
    }

    /// Runs blocking work on the LLM queue and resumes when it's done. The actor is free to
    /// answer other calls meanwhile; `llmBusy` stops them from touching the LLM.
    private func onLlmQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            llmQueue.async {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Internals

    /// Stops the mic, flushes, closes the tracker, and releases STT. Returns nothing useful;
    /// callers set the next state themselves.
    private func stopRecording(releasingModels: Bool = true) -> Bool {
        mic?.finish()                       // stops the mic, flushes (final events), frees the stream once
        tracker?.flushPendingAsFinal()      // belt and braces: nothing stays partial
        tracker?.close()
        tracker = nil
        pausedAt = nil
        if releasingModels { releaseSTT() }
        return true
    }

    private func loadSTT() async throws {
        guard mic == nil else { return }
        guard let sttDir = ReviseModelStore.sttDirectory(),
            let diarizationDir = ReviseModelStore.diarizationDirectory()
        else {
            throw ReviseError(code: .modelMissing, message: ReviseModelStore.missingDescription())
        }
        let options = [
            TranscriberOption(name: "identify_speakers", value: "true"),
            TranscriberOption(name: "diarization_model_dir", value: diarizationDir.path),
            // Re-cluster speakers every 1.0 s (default 2.0) and analyze audio every 0.5 s (default 1.0).
            // Moonshine's clustering threshold itself is compiled in and cannot be changed; these only
            // make speakers appear sooner. On the two-voice test recording this turned the label sequence
            // [1,0,0,1,1,2,1,1,1,2,1] into [1,0,1,2,1,2,1,2,1,2,1]. Costs a little more CPU: if live
            // captions lag on the phone, set these back to "2.0" and "0".
            TranscriberOption(name: "diarization_cluster_cadence", value: "1.0"),
            TranscriberOption(name: "diarization_analyze_cadence", value: "0.5"),
        ]
        do {
            // Loading from local paths: no network involved.
            mic = try MoonshineMic(
                modelPath: sttDir.path,
                modelArch: ReviseModelStore.sttArch,
                options: options)
        } catch {
            throw ReviseError(
                code: .modelMissing, message: "Could not load models: \(error.localizedDescription)")
        }
    }

    /// Frees the speech model exactly once: `close()` ends any open stream, then dropping the
    /// last reference lets Moonshine free the transcriber. Calling it again is a no-op.
    private func releaseSTT() {
        guard let current = mic else { return }
        mic = nil
        current.close()
    }

    /// Asks for mic permission if the user hasn't decided yet. Throws `permission_denied`
    /// if refused, so Flutter can show a "open Settings" path.
    private func ensureMicPermission() async throws {
        // (deprecated in iOS 17 in favour of AVAudioApplication, but Moonshine uses the
        // same API internally and it still works on the demo phones)
        let session = AVAudioSession.sharedInstance()
        var granted = session.recordPermission == .granted
        if session.recordPermission == .undetermined {
            granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        if !granted {
            throw ReviseError(code: .permissionDenied, message: "Microphone permission denied")
        }
    }

    private func setState(_ new: State, message: String? = nil) {
        state = new
        sendEvent(["type": "state", "state": new.rawValue, "message": message ?? NSNull()])
    }

    private static func invalidState(_ method: String) -> ReviseError {
        ReviseError(code: .invalidState, message: "\(method) is not allowed in the current state")
    }

    // MARK: - Failures and interruptions (PRD: stop on backgrounding / mic interruption)

    private func asyncFailure(_ message: String) {
        guard state == .listening else { return }
        _ = stopRecording()
        setState(.error, message: message)
    }

    private func interrupted(_ reason: String) {
        guard state == .listening || state == .paused else { return }
        // Finalized lines are kept (flushed first); the error state marks it incomplete.
        _ = stopRecording()
        setState(.error, message: "Recording interrupted: \(reason)")
    }

    private func startObservingInterruptions() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { await self?.interrupted("app went to the background") }
            })
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    Task { await self?.interrupted("microphone was interrupted") }
                }
            })
    }
}
