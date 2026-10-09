# devJ M0: pinned speech/capture boundary

October 10, 2026. **Preparation only; M0 device gate is NOT passed.** No production
adapter, second Flutter app, shared-file changes, installation, staging or commit.

## Decision / blockers

Same-stream silence is a plausible Pause mechanism, not proven phone behavior.
Stop/start is demonstrably unsuitable for Pause: it resets transcript, VAD time
and diarization clustering. Stop itself synchronously drains/transcribes, but
source inspection found discrepancies that block production implementation:

1. **Unchecked native failures.** Android `Transcriber.startStream`,
   `addAudioToStream` and `stopStream` discard JNI integer return codes. A failed
   add can silently omit accepted audio; a failed stop can still return after a
   cached transcript. Standalone tests reproduce these wrapper behaviors.
   `stopStream` also lacks the explicit null-transcript check present in add.
2. **Unreleased JNI array.** `moonshine-jni.cpp:643–658` calls
   `GetFloatArrayElements` for every audio append and returns without a matching
   `ReleaseFloatArrayElements` on either path. This violates JNI lifetime rules;
   copying/pinning and actual native/heap growth depend on ART. No phone leak
   measurement claimed. Batching or `return_audio_data=false` does not repair it.
3. **Sub-hop Stop tail.** VAD processes complete 512-sample hops and retains the
   remainder. Its `flush()` calls `process_audio()` then `stop()`, without padding
   or processing that remainder. Thus up to 511 internal 16 kHz samples
   (<32 ms) can remain unanalyzed at Stop. Need a phone check and reviewed
   padding policy, not an assertion that the existing stop covers every sample.
4. **No unconditional silence-finalization bound.** VAD options specify smoothing,
   not a fixed silence timeout. Model probabilities on zeros are not guaranteed
   by the options; the Java adaptive gate can additionally hide all proposed
   silence from a transcription pass. See the bounded proposal below.

**Gate:** devS/Jeush review the pinned artifact's JNI behavior and the error-checking
strategy before capture implementation. Do not silently patch/upgrade the SDK,
add an unapproved native shim, or substitute model families. Direct checked JNI
calls could address discarded statuses but would not fix the array lifetime bug.
The inspected source is the tag, not proof that a resolved Maven AAR is identical.

## Checkout, shell and tools actually inspected

- Remained on `devj/android-captions-speakers`, tracking its origin branch; initial
  working tree clean. No applicable `AGENTS.md` in checkout or ancestor paths.
- Current checkout has plans, preparation tooling and assets, but **no integrated
  Flutter shell**, `pubspec.yaml`, Android Gradle project or Kotlin backend.
- `git ls-remote` confirmed local remote refs current (no fetch necessary):
  - `origin/jai-flutter`: `73db4b676faff8f6e336fd7ad663f87198a4d17d`.
  - `origin/codex/kotlin-development`: `cf88c8689ffdeb9e9e336a77c27a9502e323bca2`.
- Read-only `git ls-tree`/`git show` confirmed **Jairus's existing shell is real**:
  namespace/application ID `com.larpcode.revise`, registered Android plugin,
  Flutter/Dart code and tests. No `AGENTS.md` in that tree.
- `git merge-base --is-ancestor origin/jai-flutter
  origin/codex/kotlin-development` returned **1**: shell not yet integrated.
- Shell pins: Dart `^3.13.5`, AGP `9.1.0`, Kotlin plugin `2.4.0`, Gradle
  `9.3.1-all`, Java/Kotlin bytecode target 17. Compile/target/min SDK and NDK
  inherit Flutter values; Moonshine dependency and explicit minSdk 26 absent.
  Gradle launcher scripts/JAR are not tracked in the inspected shell tree.
- Installed: Flutter `3.47.2` (`d3b14c8769`), Dart **3.13.2**, PATH Java/javac
  `26.0.2.1`, Python `3.14.0`. Android Studio bundled JBR `25.0.2` also exists.
  Local Dart is below shell's declared minimum: do not lower it without Jairus.
- `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT` unset; no PATH `adb`, `gradle`,
  `kotlinc`. SDK exists at `%LOCALAPPDATA%\Android\Sdk`: platforms 34/35/36/37.0,
  build-tools 36.0.0, NDK 28.2.13676358, cmdline-tools `latest`, platform-tools.
  Gradle cache directories include 9.3.1; cache presence is not a successful build.
  No cached `ai.moonshine` Maven directory found in the usual modules cache.
- Explicit SDK `adb.exe devices -l` listed **zero devices** (started local ADB
  server only). No phone properties/inference, APK install or app-data access.
- Existing eight STT + two diarization files verified read-only:
  **10 files / 53,803,659 bytes**, preparation command exit 0. Gemma file and
  `complete=true` manifest already exist; neither full packaging nor CRM verified
  here. Moonshine-only verifier's `All Android model assets ready: False` is its
  partial-scope result, not evidence that the existing Gemma is missing.

### Concrete safe shell path

1. Jairus/devS integrate the reviewed **existing** `jai-flutter` shell and minimal
   SDK/build setup through `codex/kotlin-development`, per work-split lines 42–48.
   Then explicitly approve updating the devJ branch from that integration commit.
   No merge/import/worktree was performed in this task.
2. Jairus supplies a compatible installed Flutter/Dart selection or an approved
   SDK-constraint correction. devS pins local JDK/SDK, provides wrapper setup,
   resolves `ai.moonshine:moonshine-voice:0.1.5`, minSdk >=26 and reviewed local
   asset extraction. Review SDK source/artifact discrepancies first.
3. Only then add a devJ-owned feasibility instrumentation test under
   `android/app/src/androidTest/kotlin/com/larpcode/revise/`, initially invoking
   speech SDK directly, not altering plugin/controller/public channels. Use devS's
   verified local directories; do not duplicate asset scripts or create an app.
4. Build without deployment first. Request separate phone/APK-test approval before
   instrumentation (which installs APKs). Do not uninstall/clear existing sessions.

Shell plugin TODOs are scaffolding, not a completed state machine: no callback
barrier/generation protection yet; its stale Gemma 4/Qwen TODO conflicts with the
approved Gemma 3 choice. devS owns reconciliations even where TODO says Jeush.

## Authoritative source and exact local loading

GitHub tree API resolved `v0.1.5` to
`234f60faa0eb388b01cdf7e60aca232af37aefda`, matching the plan. Only small text
sources were fetched to the approved OpenCode temporary folder; no SDK/model
binaries downloaded. `source-pins.json` records SHA-256 of 12 relevant source files.
Links below use that immutable revision (`C`):

- [Java wrapper](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/language-bindings/android/java/main/java/ai/moonshine/voice/Transcriber.java)
- [Core transcriber](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/transcriber.cpp),
  [options](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/transcriber.h)
- [VAD](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/voice-activity-detector.cpp)
- [JNI](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/language-bindings/android/moonshine-jni/moonshine-jni.cpp)
- [Stable speaker IDs](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/speaker-diarizer.cpp),
  [diarization streaming](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/cpp-annote/src/cpp-annote-streaming.cpp)
- [SDK Android build](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/language-bindings/android/build.gradle.kts)

Loader sketch only, **not implemented or approved as production**:

```kotlin
val sdk = Transcriber(listOf(
    TranscriberOption("identify_speakers", "true"),
    TranscriberOption("diarization_model_dir", verifiedDiarizationDir),
    TranscriberOption("transcription_interval", "0.5"),
    TranscriberOption("vad_threshold", "0.5"),
    TranscriberOption("vad_window_duration", "0.5"),
    TranscriberOption("vad_hop_size", "512"),
    TranscriberOption("vad_look_behind_sample_count", "8192"),
    TranscriberOption("vad_max_segment_duration", "15.0"),
    TranscriberOption("return_audio_data", "false"),
    TranscriberOption("log_api_calls", "false"),
    TranscriberOption("log_output_text", "false"),
    TranscriberOption("log_ort_run", "false"),
))
sdk.setUpdateInterval(0.5) // Java gate, separate from native transcription_interval
sdk.loadFromFiles(verifiedSttDir, JNI.MOONSHINE_MODEL_ARCH_TINY_STREAMING) // 2
// Attach snapshot listener before starting/feeding. No downloader/cache helper.
```

`loadFromFiles(String,int)` creates the default stream; `start()` activates it.
STT directory holds the eight canonical prepared files; diarization directory
holds `segmentation.ort`/`embedding.ort`. Missing diarization fails local loading,
not a runtime download (`transcriber.cpp:72–98,137–164`). Keep spelling flags 0;
never set `save_input_wav_path`. `loadFromAssets` is the fixed legacy
encoder/decoder loader, not the Tiny Streaming product path.

**Word-timing nuance:** `identify_speakers` internally forces `word_timestamps=true`
(`transcriber.cpp:108–113`). The attention decoder is loaded only **if present**
(328–340); it is not required for time-clipped line speaker spans
(1251 onward). Without word timings, speaker byte offsets stay 0/0
(1208–1217). Do not add the excluded attention model or infer text splits.

## Stream, completion and speaker facts

- Base Java callbacks are **inline on the add/stop caller**, not its unused
  executor. Per line: Started, Updated (only non-new incomplete), TextChanged,
  SpeakersChanged, Completed. Completed requires `isComplete && isUpdated` and
  is deduplicated by line ID. SDK objects are mutable/public: copy primitives
  immediately. Late speaker events can arrive for completed lines.
- Completed ID is recorded **before** listeners run; an exception in a listener
  aborts that call and is not retried as a final. Adapter/delivery failures must
  invalidate the operation, not report successful Pause/Stop. No callback should
  block on the controller actor that is awaiting inference.
- Java update gate is `min(max(updateInterval,lastPassSeconds),10*updateInterval)`:
  default 0.5 s, at most **5 s** of appended audio. Native gate separately needs
  0.5 s, force flag, or stopped state, and new audio. Generic documentation's
  `update_transcription()` is not exposed by this Android base Java wrapper.
- `start_stream` clears transcript; VAD starts sample clock over; diarizer
  `start_stream` resets session and speaker mapping (core 722–739; diarizer
  200–208). Pause must not call this or `stop_stream`/start as a workaround.
- Native Stop deactivates acceptance, hands residual new audio to diarizer and
  synchronously calls its `end_session`: all deferred complete analysis windows
  plus padded tail and final clustering. Java Stop then forces transcribe,
  consumes new audio even below native interval, closes VAD, marks incomplete
  lines complete and invokes listeners inline (core 741–920,1762–1774).
- Thus return from a **successful, checked** serialized stop covers SDK callbacks;
  it does not cover app main-thread/FIFO delivery or already queued mic samples.
  `close()` is resource freeing, not a flush/join/barrier. Never close concurrently
  with add/stop; repeat Stop idempotence must be app-owned.
- `SpeakerSpan`: `float startTime,duration` in stream seconds; `long speakerId`;
  `int speakerIndex` (first appearance, zero-based); `long startChar,endChar`
  **UTF-8 byte** offsets, not Kotlin UTF-16 indices. IDs are random 64-bit native
  values exposed as signed Java longs: negative values are valid opaque IDs, not
  unknown. Absence/ambiguity, not sign, means unknown.
- Proposed app mapping uses SDK ID equality -> first four stable IDs 1–4, never
  SDK index+1; further voices 0. One confidently single-speaker line only; missing,
  conflicting/overlapping/multiple-speaker spans 0. Freeze final text/time/speaker
  and ignore duplicates/later speaker revisions. This policy is approved by PRD;
  its real accuracy/stability is not proved by these tests.
- Diarizer append processes at most one complete window, refreshes on analyzed
  window cadence (defaults analyze step ~1 s, cluster 2 s, history 120 s).
  Non-stopping `refresh_and_snapshot` exists internally but is not exposed by
  Transcriber/JNI. Pause silence can finalize VAD without fully draining diarizer
  backlog; finals may have unknown/outdated spans. Do not claim Stop-grade
  diarization drain during Pause or invent remapping to improve results.
- `MicTranscriber.mute` leaves microphone active; `stop` just sets `running=false`
  and the processing loop later stops the stream. Neither meets capture Pause.

## Pause synthetic-silence proposal (review/device gate)

Pinned native defaults: threshold 0.5, window duration 0.5 s, hop 512 @16 kHz,
look-behind 8192 samples, max-segment option 15 s. Smoothing window is
`ceil(0.5*16000/512) = 16` hops = **8192 samples / 0.512 s**. With subsequent
Silero probabilities zero, 16 hops fully replace prior probabilities; strict
mean >0.5 becomes false (worst all-ones window crosses after 8 zero hops).
This is a **conditional probability bound, NOT guaranteed duration of silence**.
Silero is stateful; the global VAD model is not recreated/reset on Pause. Do not
interpret the max-segment option as a reliable silence timeout; source's fade
multiplier (VAD 169–179) also differs from its decreasing-score comment.

After microphone stop/join and real queue drain, trial four incremental
**8192-zero-sample batches @16 kHz**, maximum **32768 / 2.048 s** synthetic audio
per Pause. This cap is a proposed application budget, not an SDK guarantee or a
measured wall-clock timeout. Map every synthetic interval to the capture boundary.
Temporarily set Java update interval 0, restore it in `finally`; each 0.512 s batch
meets the native 0.5 s gate. A force-update without speech-end does not finalize.
Do not feed the whole budget before checking completion: avoid unnecessary silence.
Even with no previously visible partial, perform the first pass to expose pending
real speech. Require observed SDK completion of all pending real-speech lines and
ordered snapshot delivery. If still incomplete at cap, **fail Pause and report the
gate**, not `paused`, not a fake final. Never use SDK stop/start to recover Pause.

SDK input time includes synthetic audio but excludes real paused wall time.
Use a retained piecewise fed-sample -> monotonic wall-time mapping: real ranges
map capture times; synthetic ranges clamp to boundary; resumed real ranges begin
at resume wall time. Preserve old mappings for delayed speaker/caption callbacks.
Phone tests must confirm no synthetic-only hallucinated lines, repeated-pause
drift, tail loss, or speaker-state reset. A wall-time watchdog must not free native
resources underneath a blocked synchronous SDK call.

## Actual checks / reproducing standalone evidence

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-android-models.ps1 -MoonshineOnly -VerifyOnly
python docs/evidence/android/devj/check_boundary.py --source-root "$env:LOCALAPPDATA\Temp\opencode\devj-moonshine-0.1.5"
```

Both exited 0. Harness verified **12 source hashes**, ran **4 conditional math
tests**, compiled seven unchanged upstream Java sources plus Android/JNI test
stubs with `javac --release 11`, and passed **4 wrapper scenario groups**:
inline order/duplicate finals/Stop force flag; discarded JNI status failures;
adaptive throttle/bypass without claiming finalization; null Stop result and
non-retried listener failure. JDK emitted only the upstream deprecated-finalize
note. Temporary compilation files are removed; no third-party source vendored.

Runner downloads nothing. For another machine, supply the pinned text checkout
with all `source-pins.json` paths present (hashes must match); an existing writable
OpenCode scratch folder is required, or supply `--scratch-root` explicitly.
**No Android build, native VAD/STT/diarization, mic, performance, ABI or device
proof.** Remaining gates and proposed handoff: [DEVICE_GATES.md](DEVICE_GATES.md)
and [CAPTURE_PROPOSAL.md](CAPTURE_PROPOSAL.md).
