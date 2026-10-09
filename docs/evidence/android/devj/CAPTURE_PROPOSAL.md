# Capture boundary proposal for devS review — NOT agreed

No Kotlin shared interface has been created. This is a design sketch for the
existing `com.larpcode.revise` shell after its integration and SDK blockers are
resolved. No changes to `revise/engine`, `revise/captions` or devS's controller.

```kotlin
package com.larpcode.revise

// Illustrative internal types, not new public/wire contracts.
data class LocalSpeechPaths(val sttDir: String, val diarizationDir: String)
data class CaptionSnapshot(
    val segmentId: String, val text: String, val speakerId: Int,
    val isFinal: Boolean, val tStartMs: Long, val tEndMs: Long,
)
data class CaptureBoundary(
    val acceptedSamples: Long, val deliveredSamples: Long,
    val syntheticSamples: Long, val captureBoundaryMs: Long,
    val lastCaptionSequence: Long,
)

interface CaptionDelivery { // devS supplies generation-gated ordered sink
    fun enqueue(generation: Long, caption: CaptionSnapshot): Long
    suspend fun awaitDeliveredThrough(generation: Long, sequence: Long)
}
interface SessionCapture { // illustrative devJ boundary, names negotiable
    suspend fun load(paths: LocalSpeechPaths)
    suspend fun start(generation: Long, sessionStartElapsedRealtimeMs: Long,
                      delivery: CaptionDelivery)
    suspend fun pause(): CaptureBoundary
    suspend fun resume()
    suspend fun stop(): CaptureBoundary
    suspend fun close()
}
```

The boundary intentionally has no state-event emitter, Activity, Flutter binding,
CRM engine, downloader or raw audio/transcript SDK object. devS's controller owns
permissions, state transitions, generation, sink lifecycle and resource handoff.
devJ owns AudioRecord and serialized speech calls, snapshots, registry and clock
mapping. Permission must be granted before `start`; errors must not carry text or
SDK `toString` output. An async capture error needs a separately agreed callback
to devS that carries only generation, stable error code and safe message.

## Completion semantics proposed

1. Capture worker owns AudioRecord, reads mono PCM16, targets 16 kHz but records
   **actual** configured rate. Normalize by 32768, copy only valid samples. Initial
   trial: ~32 ms blocks and queue capacity 32 blocks (~1.024 s); exact AudioRecord
   buffer >= platform minimum and queue budget are device-tuned, not final pins.
2. Pause/Stop close real-audio acceptance, stop AudioRecord to unblock read, join
   capture, release it, then drain every accepted queued block exactly once on a
   single inference worker. Define cutoff using last accepted sample's monotonic
   time, not button time. A read racing shutdown is accepted and drained or not
   accepted; never silently drop an already accepted block. Queue saturation/read
   failure aborts capture visibly (`capture_failed`), not an audio-drop policy.
3. Pause uses the same live SDK stream + registry and bounded silence from
   `M0_FINDINGS.md`. Resume only recreates capture; does not SDK-start again.
   Stop uses checked SDK stop/final transcribe after the real queue drain, with
   reviewed sub-hop padding if approved. Verify all tracked partials complete.
4. Copy every callback to primitives inline. `enqueue` must synchronously accept
   into bounded FIFO or fail; its sequence is internal only. Snapshotting/delivery
   errors cannot be swallowed: successful completion requires every final accepted.
5. `awaitDeliveredThrough` runs without holding any actor/mutex needed for delivery.
   It means main-thread `EventSink.success` executed for all captions through the
   sequence, **not** Dart consumed them. Missing/cancelled sink fails and stops
   capture; no infinite buffer. Controller checks generation again, delivers
   `paused`/`stopped` after captions, then completes method exactly once. Dart still
   waits for consumed `stopped` before persistence/CRM, per existing PRD.
6. Stop while paused flushes once; repeat Stop returns prior successful boundary
   without new finals. Detach/error close is **not successful Stop**: stop/join
   capture, await in-flight native work, invalidate old deliveries, close safely;
   preserve already finalized transcript, leave interrupted partials unconfirmed.
7. devS waits for Stop + delivery, closes STT/diarization fully, then may load Gemma.
   A new session has new generation/registry, no retained PCM or pending callbacks.

## Review questions / gate requests

- Does devS accept this division and explicit main-thread delivery acknowledgement,
  or prefer a controller-owned barrier without `CaptionDelivery`?
- Decide checked-status/native-array fix strategy against the exact 0.1.5 AAR
  before selecting the wrapper or direct-JNI adapter. Who owns an SDK fix decision?
- Approve or revise the 2.048 s synthetic cap and failure path; a separate measured
  wall-time limit cannot cancel a synchronous native call by closing its engine.
- Decide Stop sub-hop padding and synthetic-only line rejection after device data,
  without inventing final text/attribution. Unknown speakers remain allowed.

These questions block shared wiring; this document does not grant agreement.
