@preconcurrency import AVFoundation
import Foundation
import MoonshineVoice

/// Microphone -> Moonshine streaming transcriber, built on the public `Transcriber` and
/// `Stream` types instead of the SDK's `MicTranscriber`.
///
/// WHY NOT MicTranscriber: in moonshine-swift 0.1.5, `MicTranscriber.close()` closes its
/// stream and then lets `Stream.deinit` close the same stream a second time. With
/// `identify_speakers` on, that second free segfaults inside Moonshine (EXC_BAD_ACCESS in
/// `Transcriber::free_stream`). Reproduced in a standalone macOS test. Here every stream is
/// freed exactly once, by simply dropping it (its `deinit` does the one `close()`).
///
/// Lifecycle:  begin() -> startCapture() -> [pauseCapture() -> resumeCapture()]* -> finish()
/// Each begin()/finish() pair is one session with its own stream, so speaker numbering
/// starts fresh every session. The loaded model survives across sessions until `close()`.
final class MoonshineMic: @unchecked Sendable {
    private let transcriber: Transcriber
    private var stream: MoonshineVoice.Stream?
    private let updateInterval: TimeInterval

    private var audioEngine: AVAudioEngine?
    private let stateLock = NSLock()
    private var capturing = false

    // The capture tap runs on a time-critical audio thread, so it only queues audio; a
    // serial queue does the slow transcription. Every call into `stream` happens on it.
    private let audioQueue = DispatchQueue(label: "revise.moonshine.audio")
    private let pendingLock = NSLock()
    private var pendingChunks: [(audio: [Float], sampleRate: Int32)] = []

    init(modelPath: String, modelArch: ModelArch, options: [TranscriberOption],
         updateInterval: TimeInterval = 0.5) throws {
        transcriber = try Transcriber(modelPath: modelPath, modelArch: modelArch, options: options)
        self.updateInterval = updateInterval
    }

    // MARK: - Names to listen for

    /// Biases the decoder towards these spellings (names entered before recording). Commas are
    /// not allowed inside a term, and the list is capped. An empty list clears the previous
    /// session's terms. Never throws: returns a short description of what happened for the log.
    @discardableResult
    func setKeyterms(_ names: [String]) -> String {
        let terms = Array(Set(names.map {
            $0.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted().prefix(20)
        do {
            try transcriber.setKeyterms(Array(terms))
            return "ok (\(terms.count) terms)"
        } catch {
            return "failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session

    /// Creates a fresh stream for a new session and attaches the listener.
    func begin(listener: @escaping (TranscriptEvent) throws -> Void) throws {
        discardStream()
        let fresh = try transcriber.createStream(updateInterval: updateInterval)
        fresh.addListener(listener)
        stream = fresh
        try audioQueue.sync { try fresh.start() }
    }

    /// Ends the session: stops capture, flushes pending speech (Moonshine emits the final
    /// events), then frees the stream once. Safe to call repeatedly.
    func finish() {
        endCapture()
        flushStream()
        discardStream()
    }

    /// Frees everything. The `Transcriber` frees itself when this object goes away.
    func close() {
        finish()
    }

    // MARK: - Capture

    func startCapture() throws {
        guard stream != nil else {
            throw MoonshineError.custom(message: "No active session. Call begin() first.", code: -1)
        }
        stateLock.lock()
        if capturing { stateLock.unlock(); return }
        stateLock.unlock()

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        #endif

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        else {
            throw MoonshineError.custom(message: "Failed to create target audio format", code: -1)
        }
        let needsConversion =
            inputFormat.sampleRate != target.sampleRate || inputFormat.channelCount != target.channelCount
            || inputFormat.commonFormat != target.commonFormat
        let converter = needsConversion ? AVAudioConverter(from: inputFormat, to: target) : nil

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isCapturing else { return }
            if let converter {
                let capacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * target.sampleRate / inputFormat.sampleRate)
                guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var error: NSError?
                converter.convert(to: out, error: &error) { _, status in
                    status.pointee = .haveData
                    return buffer
                }
                guard error == nil, let data = out.floatChannelData else { return }
                self.feed(Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength))), sampleRate: 16000)
            } else if let data = buffer.floatChannelData {
                self.feed(Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))),
                          sampleRate: Int32(inputFormat.sampleRate))
            }
        }
        try engine.start()
        audioEngine = engine
        setCapturing(true)
    }

    /// Pause: stop the mic and let Moonshine finish the phrase in progress, but keep the
    /// session. We do NOT call `Stream.stop()` here: stopping and restarting a stream resets
    /// its clock to 0 and its speaker identities (measured), so the same person would come
    /// back as a new speaker. Instead we feed a short silence so the voice-activity detector
    /// ends the phrase and the line completes normally.
    func pauseCapture() {
        endCapture()
        guard let stream else { return }
        audioQueue.sync {
            drainPendingAudio()
            let silence = [Float](repeating: 0, count: Int(16000 * Self.pauseSilenceSeconds))
            try? stream.addAudio(silence, sampleRate: 16000)
            try? stream.updateTranscription(flags: TranscribeStreamFlags.flagForceUpdate)
        }
    }

    /// Resume after `pauseCapture()`: same stream, same clock, same speakers.
    func resumeCapture() throws {
        guard stream != nil else {
            throw MoonshineError.custom(message: "No active session.", code: -1)
        }
        try startCapture()
    }

    private static let pauseSilenceSeconds = 1.2

    // MARK: - Internals

    private var isCapturing: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return capturing
    }

    private func setCapturing(_ value: Bool) {
        stateLock.lock(); capturing = value; stateLock.unlock()
    }

    /// Stops the mic tap and engine and releases the audio session.
    private func endCapture() {
        setCapturing(false)
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    /// Drains queued audio and asks Moonshine for the final transcript of what's left.
    /// Runs on the audio queue so no transcription is still in flight afterwards.
    private func flushStream() {
        guard let stream else { return }
        audioQueue.sync {
            drainPendingAudio()
            try? stream.stop()
        }
    }

    /// Drops our only reference to the stream; its deinit frees it exactly once.
    private func discardStream() {
        guard stream != nil else { return }
        audioQueue.sync {}          // nothing queued may still touch the stream
        pendingLock.lock(); pendingChunks.removeAll(); pendingLock.unlock()
        stream = nil
    }

    /// Audio sink. Also used by tests to feed recorded audio instead of the mic.
    func feed(_ audio: [Float], sampleRate: Int32) {
        pendingLock.lock()
        pendingChunks.append((audio, sampleRate))
        pendingLock.unlock()
        audioQueue.async { [weak self] in self?.drainPendingAudio() }
    }

    /// Sends everything queued so far to the stream, merging chunks with the same sample
    /// rate so a backlog is transcribed in one pass. Runs on `audioQueue`.
    private func drainPendingAudio() {
        pendingLock.lock()
        let batch = pendingChunks
        pendingChunks.removeAll(keepingCapacity: true)
        pendingLock.unlock()
        guard !batch.isEmpty, let stream else { return }

        var run: [Float] = []
        var runRate: Int32?
        func flushRun() {
            if let rate = runRate, !run.isEmpty { try? stream.addAudio(run, sampleRate: rate) }
            run.removeAll(keepingCapacity: true)
        }
        for chunk in batch {
            if let rate = runRate, rate != chunk.sampleRate { flushRun() }
            run.append(contentsOf: chunk.audio)
            runRate = chunk.sampleRate
        }
        flushRun()
    }
}
