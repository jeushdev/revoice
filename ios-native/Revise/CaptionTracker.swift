import Foundation
import MoonshineVoice

/// Turns Moonshine transcript events into the `revise/captions` caption maps
/// (PRD section 7). One tracker per recording session, so events from an old
/// session can never leak into a new one (`close()` makes it ignore everything).
///
/// Moonshine calls us from its audio thread, so all state sits behind a lock.
final class CaptionTracker: @unchecked Sendable {
    private struct Latest {
        var text: String
        var speakerId: Int
        var startMs: Int
        var endMs: Int
    }

    private let lock = NSLock()
    private let emit: @Sendable ([String: Any]) -> Void
    private let onError: @Sendable (String) -> Void

    private var isOpen = true
    private var run = 0                        // bumped on every start/resume
    private var segmentIds: [String: String] = [:]   // "run:lineId" -> "s-0001"
    private var nextSegment = 1
    private var finalized = Set<String>()      // keys already sent as final
    private var latest: [String: Latest] = [:] // last partial text per open segment
    private var pausedOffsetMs = 0             // paused time counts toward session time

    init(emit: @escaping @Sendable ([String: Any]) -> Void,
         onError: @escaping @Sendable (String) -> Void) {
        self.emit = emit
        self.onError = onError
    }

    /// Call when recording starts or resumes. Segment keys include `run`, so a
    /// restarted Moonshine stream that reuses line IDs can't collide with old ones.
    func beginRun(addingPausedMs: Int = 0) {
        lock.lock(); defer { lock.unlock() }
        run += 1
        pausedOffsetMs += addingPausedMs
    }

    /// Moonshine listener entry point.
    func handle(_ event: TranscriptEvent) {
        if let failure = event as? TranscriptError {
            // Only the error text, never transcript content, goes onward (PRD logging rule).
            onError(failure.error.localizedDescription)
            return
        }
        let isFinal = event is LineCompleted
        let isPartial =
            event is LineStarted || event is LineUpdated
            || event is LineTextChanged || event is LineSpeakersChanged
        guard isFinal || isPartial else { return }

        lock.lock(); defer { lock.unlock() }
        guard isOpen else { return }

        let line = event.line
        let key = "\(run):\(line.lineId)"
        if finalized.contains(key) { return }            // duplicate final, or late speaker revision

        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            // Empty speech: nothing to show. Close the key if Moonshine says it's done.
            if isFinal { finalized.insert(key); latest[key] = nil }
            return
        }

        let startMs = max(0, Int(line.startTime * 1000)) + pausedOffsetMs
        let endMs = max(startMs, startMs + Int(line.duration * 1000))
        let segmentId = segmentId(for: key)
        let speakerId = Self.dominantSpeaker(of: line)

        if isFinal {
            finalized.insert(key)
            latest[key] = nil
        } else {
            latest[key] = Latest(text: text, speakerId: speakerId, startMs: startMs, endMs: endMs)
        }
        send(segmentId, text, speakerId, isFinal, startMs, endMs)
    }

    /// Sends any still-partial segment as final. Called after Moonshine's own stop-time
    /// flush so `stop` guarantees "all pending segments are final" (PRD section 7).
    func flushPendingAsFinal() {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { return }
        for (key, value) in latest.sorted(by: { $0.value.startMs < $1.value.startMs }) {
            finalized.insert(key)
            send(segmentId(for: key), value.text, value.speakerId, true, value.startMs, value.endMs)
        }
        latest.removeAll()
    }

    /// Stop accepting events. After this the tracker is inert.
    func close() {
        lock.lock(); defer { lock.unlock() }
        isOpen = false
    }

    // MARK: - Helpers (call with the lock held)

    private func segmentId(for key: String) -> String {
        if let existing = segmentIds[key] { return existing }
        let id = String(format: "s-%04d", nextSegment)
        nextSegment += 1
        segmentIds[key] = id
        return id
    }

    private func send(_ segmentId: String, _ text: String, _ speakerId: Int,
                      _ isFinal: Bool, _ startMs: Int, _ endMs: Int) {
        emit([
            "type": "caption",
            "segmentId": segmentId,
            "text": text,
            "speakerId": speakerId,
            "isFinal": isFinal,
            "tStartMs": startMs,
            "tEndMs": endMs,
        ])
    }

    /// App speaker ID: Moonshine's `speakerIndex` (0 = first voice heard) + 1, so IDs are
    /// stable and start at 1. 0 means unknown (no speaker span for this line yet).
    /// A line can hold several spans; we label it with whoever spoke longest.
    private static func dominantSpeaker(of line: TranscriptLine) -> Int {
        guard let span = line.speakerSpans.max(by: { $0.duration < $1.duration }) else { return 0 }
        return Int(span.speakerIndex) + 1
    }
}
