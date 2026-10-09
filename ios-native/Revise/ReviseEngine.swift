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
    private var mic: MicTranscriber?
    private var tracker: CaptionTracker?
    private var pausedAt: Date?
    private var observers: [NSObjectProtocol] = []

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
        try await ensureMicPermission()
        try await loadSTT()  // reloads after a previous stop released the models
        guard let mic else { throw ReviseError(code: .modelMissing, message: "Speech model not loaded") }

        let tracker = CaptionTracker(
            emit: sendEvent,
            onError: { [weak self] message in
                Task { await self?.asyncFailure(message) }
            })
        tracker.beginRun()
        mic.removeAllListeners()
        mic.addListener { event in tracker.handle(event) }

        do {
            try mic.start()
        } catch {
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
        try? mic.stop()
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
        tracker.beginRun(addingPausedMs: pausedMs)
        do {
            try mic.start()
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
    }

    private static func logTiming(_ what: String, since start: Date) {
        #if DEBUG
        NSLog("REVISE-TIMING %@ took %d ms", what, Int(Date().timeIntervalSince(start) * 1000))
        #endif
    }

    // MARK: - Internals

    /// Stops the mic, flushes, closes the tracker, and releases STT. Returns nothing useful;
    /// callers set the next state themselves.
    private func stopRecording(releasingModels: Bool = true) -> Bool {
        try? mic?.stop()                    // Moonshine emits final events for pending speech
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
        ]
        do {
            // Loading from local paths: no network involved.
            mic = try MicTranscriber(
                modelPath: sttDir.path,
                modelArch: ReviseModelStore.sttArch,
                updateInterval: 0.5,
                options: options)
        } catch {
            throw ReviseError(
                code: .modelMissing, message: "Could not load models: \(error.localizedDescription)")
        }
    }

    private func releaseSTT() {
        mic?.close()
        mic = nil
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
