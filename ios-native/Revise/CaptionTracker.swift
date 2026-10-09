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
    private var appSpeakerIds: [UInt64: Int] = [:]   // Moonshine speakerId -> 1, 2, 3... this session

    /// A finished line whose speaker isn't known yet. Moonshine attaches speaker data to a
    /// line a moment AFTER completing it (via a "speakers changed" event), so we hold the
    /// final briefly instead of sending it as Unknown. The grey partial stays on screen.
    private struct HeldFinal {
        var text: String
        var startMs: Int
        var endMs: Int
    }
    private var held: [String: HeldFinal] = [:]
    /// Speaker last sent for each finished line, so a later revision can be sent only if it differs.
    private var sentSpeaker: [String: Int] = [:]
    /// Longest we wait for a speaker before giving up and sending the final as Unknown (0).
    private static let maxSpeakerWaitSeconds = 2.5

    init(emit: @escaping @Sendable ([String: Any]) -> Void,
         onError: @escaping @Sendable (String) -> Void) {
        self.emit = emit
        self.onError = onError
    }

    /// Call once when a session starts. Segment keys include `run` so IDs from different
    /// sessions can never collide.
    func beginRun() {
        lock.lock(); defer { lock.unlock() }
        run += 1
    }

    /// Call on resume with how long the pause lasted. Moonshine's clock only counts audio it
    /// received, so paused wall time is added back (PRD: paused time stays in session time).
    func addPausedTime(ms: Int) {
        lock.lock(); defer { lock.unlock() }
        pausedOffsetMs += ms
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
        Self.logDiarization(event, line)
        let key = "\(run):\(line.lineId)"
        if finalized.contains(key) {
            // The text, times and "final" status of a finished line never change. But Moonshine
            // keeps refining WHO spoke it, so a changed speaker is sent as a separate small event.
            if event is LineSpeakersChanged || event is LineUpdated {
                reviseSpeaker(key: key, line: line)
            }
            return
        }

        // Line already completed, waiting for its speaker: release it once spans show up.
        if held[key] != nil {
            let speaker = appSpeakerId(for: line, assigningNew: true)
            if speaker != 0 { releaseHeld(key, speakerId: speaker) }
            return
        }

        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            // Empty speech: nothing to show. Close the key if Moonshine says it's done.
            if isFinal { finalized.insert(key); latest[key] = nil }
            return
        }

        let startMs = max(0, Int(line.startTime * 1000)) + pausedOffsetMs
        let endMs = max(startMs, startMs + Int(line.duration * 1000))
        let segmentId = segmentId(for: key)
        // Final lines hand out new app speaker numbers; partials only reuse known ones
        // (a partial's speaker can be provisional and must not use up a number).
        let speakerId = appSpeakerId(for: line, assigningNew: isFinal)

        if isFinal && speakerId == 0 {
            // Completed but no speaker yet: hold, then release on speaker data or the deadline.
            latest[key] = nil
            held[key] = HeldFinal(text: text, startMs: startMs, endMs: endMs)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + Self.maxSpeakerWaitSeconds
            ) { [weak self] in self?.releaseHeldIfStillWaiting(key) }
            return
        }
        if isFinal {
            finalized.insert(key)
            sentSpeaker[key] = speakerId
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
        for key in held.keys.sorted(by: { (held[$0]?.startMs ?? 0) < (held[$1]?.startMs ?? 0) }) {
            releaseHeld(key, speakerId: 0)       // stop/pause: don't wait any longer
        }
        for (key, value) in latest.sorted(by: { $0.value.startMs < $1.value.startMs }) {
            finalized.insert(key)
            sentSpeaker[key] = value.speakerId
            send(segmentId(for: key), value.text, value.speakerId, true, value.startMs, value.endMs)
        }
        latest.removeAll()
    }

    /// Stop accepting events. After this the tracker is inert.
    func close() {
        lock.lock(); defer { lock.unlock() }
        isOpen = false
        held.removeAll()
    }

    // MARK: - Helpers (call with the lock held)

    /// Sends {"type":"speaker", segmentId, speakerId} if Moonshine now attributes a finished
    /// line to a different (known) speaker than the one we last sent.
    private func reviseSpeaker(key: String, line: TranscriptLine) {
        guard let old = sentSpeaker[key] else { return }
        let new = appSpeakerId(for: line, assigningNew: true)
        guard new != 0, new != old else { return }
        sentSpeaker[key] = new
        emit(["type": "speaker", "segmentId": segmentId(for: key), "speakerId": new])
    }

    private func releaseHeld(_ key: String, speakerId: Int) {
        guard let value = held.removeValue(forKey: key) else { return }
        finalized.insert(key)
        sentSpeaker[key] = speakerId
        send(segmentId(for: key), value.text, speakerId, true, value.startMs, value.endMs)
    }

    /// Deadline callback (runs on a background queue, so it takes the lock itself).
    private func releaseHeldIfStillWaiting(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { return }
        releaseHeld(key, speakerId: 0)
    }

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

    /// DEBUG only: raw speaker values straight from Moonshine, to debug diarization.
    /// Filter the Xcode console by "REVISE-DIAR". Logs the event kind, IDs, timing and span
    /// data but never the transcript text (PRD: no transcript content in logs).
    private static func logDiarization(_ event: TranscriptEvent, _ line: TranscriptLine) {
        #if DEBUG
        let kind = String(describing: type(of: event))
        let spans = line.speakerSpans.map {
            "[id=\($0.speakerId % 100000) idx=\($0.speakerIndex) t=\(String(format: "%.2f", $0.startTime)) dur=\(String(format: "%.2f", $0.duration)) chars=\($0.startChar)-\($0.endChar)]"
        }.joined(separator: " ")
        NSLog("REVISE-DIAR %@ line=%llu complete=%d spansChanged=%d start=%.2f dur=%.2f textLen=%d spans(%d)=%@",
              kind, line.lineId % 100000, line.isComplete ? 1 : 0, line.haveSpeakersChanged ? 1 : 0,
              line.startTime, line.duration, line.text.count, line.speakerSpans.count, spans)
        #endif
    }

    /// App speaker ID: 1, 2, 3... in the order voices first appear in a final line this
    /// session; 0 = unknown (no speaker span yet). We number speakers ourselves because
    /// Moonshine's `speakerIndex` is a counter that never restarts and skips values whenever
    /// re-clustering drops a provisional speaker (seen: indexes 0 and 2, then 3 and 5 in the
    /// next session). Its `speakerId` is the stable identity, so we key on that.
    /// A line can hold several spans; we label it with whoever spoke longest.
    private func appSpeakerId(for line: TranscriptLine, assigningNew: Bool) -> Int {
        guard let span = line.speakerSpans.max(by: { $0.duration < $1.duration }) else { return 0 }
        if let known = appSpeakerIds[span.speakerId] { return known }
        guard assigningNew else { return 0 }
        let next = appSpeakerIds.count + 1
        appSpeakerIds[span.speakerId] = next
        return next
    }
}
