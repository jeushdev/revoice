# ReVise Android implementation plan

October 9, 2026 (PHT) · branch `codex/kotlin-development`

Status: Android model choices and frozen final speaker policy approved by Jeush. Implementation has started on devS's feature branch; device verification and submission remain pending. [PRD.md](PRD.md) defines the shared product and channel contract; [ANDROID_WORK_SPLIT.md](ANDROID_WORK_SPLIT.md) assigns the Android backend work to devS and devJ. This plan covers the complete Android delivery path and the Flutter integration work needed from Jairus; it does not select or implement the iOS runtime.

## 1. Goal and approved decisions

Deliver F1–F4 on the Redmi Note 14 Pro 5G: live English captions, final transcript, session speaker labels and names, and automatic evidence-linked CRM cards, with all inference on the phone and every required model included in a fresh offline installation.

| Decision | Selected approach |
| --- | --- |
| UI and shared text logic | Flutter/Dart; retain the existing team ownership |
| Android capture and inference | Kotlin with native SDK bindings |
| Speech model | Moonshine **English Tiny Streaming**, quantized SDK assets |
| Speaker identification | Moonshine diarization, enabled explicitly with local assets |
| CRM model | **Gemma 3 1B INT4**, `gemma3-1b-it-int4.litertlm` |
| CRM runtime | **LiteRT-LM Kotlin**; CPU is the initial baseline |
| Speaker corrections | Freeze attribution at app-final emission; ignore later SDK corrections |
| Model residency | STT + diarization while recording; LLM after Stop; never both inference stacks together |
| Installation | Bundle one STT model, its diarization assets, and one LLM; no automatic downloads |
| Scope | English F1–F4 first; F2b cleaning is a separately scheduled stretch |

Selection is final for this plan. A failed compatibility or quality gate is grounds to report and revise the plan, not silently substitute Qwen, Gemma 4, a cloud API, or a manual implementation of a required AI feature.

## 2. Current state and assumptions

- Baseline is commit `fa1fd2f`; the branch contained only `PRD.md` before this planning change. There is no Flutter shell, Kotlin backend, dependency lock, model asset, or working-build evidence in this checkout.
- Reported phone details are Android 16 and 16 GB RAM. Verify OS, physical RAM, CPU/ABI, free storage, and microphone behavior during M0. Memory extension is not physical RAM.
- Jairus owns Flutter setup, text persistence, name rules, prompts, CRM schema, validation, and export. Jeush owns capture/STT/speakers. Sam owns Android LLM integration, builds, and disclosures. Zairus owns iOS.
- Package/application ID, Flutter version, JDK, AGP, Kotlin, Gradle, and compile/target SDK are inherited from the agreed Flutter shell and pinned in M0. Do not generate a second competing Flutter application in this branch.
- Moonshine's inspected Android library has `minSdk=26`. Use the higher minimum required by the resolved Flutter/Moonshine/LiteRT dependency set; confirm the actual merged requirements in M0.
- Source paths below assume Jairus supplies a conventional Flutter project at repository root. Adapt the package directory to its actual namespace without changing interfaces or creating another application.
- PRD times are team targets, not proof of progress. Confirm the official submission cutoff externally through the assigned team owner. Implementation follows the gates below even if a target time is missed.

## 3. Reproducible dependency and asset selection

Verified from publisher metadata on October 9, 2026. These are initial exact pins, not tested compatibility claims:

```kotlin
implementation("ai.moonshine:moonshine-voice:0.1.5")
implementation("com.google.ai.edge.litertlm:litertlm-android:0.18.0")
```

Do not use `latest.release`, floating model branches, or unrecorded model conversion. Record the resolved transitive dependencies and native ABIs after the build succeeds.

### Moonshine assets

- SDK release: `v0.1.5`, source commit `234f60faa0eb388b01cdf7e60aca232af37aefda`.
- Architecture: `MOONSHINE_MODEL_ARCH_TINY_STREAMING`, language `en`.
- Pinned CDN directory: `https://download.moonshine.ai/model/tiny-streaming-en/quantized_26_08_21/`.
- Required assets without optional word timestamps or spelling:

| File | Bytes |
| --- | ---: |
| `adapter.ort` | 1,319,664 |
| `cross_kv.ort` | 1,287,544 |
| `decoder_kv.ort` | 32,583,720 |
| `encoder.ort` | 7,675,440 |
| `frontend.model.ort` | 23,344 |
| `frontend.weights.ort` | 2,093,464 |
| `streaming_config.json` | 509 |
| `tokenizer.bin` | 249,974 |
| **STT total** | **45,233,659** |

- Diarization directory: `https://download.moonshine.ai/model/diarization-community1/`; `segmentation.ort` is 1,594,080 bytes and `embedding.ort` is 6,975,920 bytes, totaling 8,570,000 bytes.
- Obtain the release's canonical STT/diarization manifests during asset preparation; verify their listed lengths and CRC32C values, then record local SHA-256 values for every actual downloaded file. Preserve publisher license/notices for each asset, including the pyannote-derived diarization assets.
- Do not package `decoder_kv_with_attention.ort`, spelling models, other languages, or larger STT models for v1. The PRD requires segment timestamps, not word timestamps.

### Gemma asset

| Property | Pin |
| --- | --- |
| Publisher repository | `litert-community/Gemma3-1B-IT` |
| Revision | `a6306a4e292016480083b73b8dc6f3f939ae04c3` |
| File | `gemma3-1b-it-int4.litertlm` |
| Bytes | `584417280` |
| SHA-256 | `1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be` |
| Format | `.litertlm`, INT4; use the generic file rather than a different chipset-specific build |

An authorized team member must obtain the file after accepting the publisher's Gemma conditions. Do not put credentials in source, scripts, logs, the APK, or evidence. Preserve required redistribution terms/notices before distributing the installation.

The selected model assets total **638,220,939 bytes**, about **638.2 MB / 608.7 MiB**, excluding application code, native libraries, licenses, and caches. This is an asset inventory, not an APK, installed-size, RAM, or speed measurement. Copying bundled assets from the APK into internal storage may retain a second copy; measure both installation and extracted storage rather than promising a 638 MB app.

### Asset preparation and runtime loading

- Proposed source layout: `android/app/src/main/assets/revise/models/{stt,diarization,llm}/`, plus `model-manifest.json` containing asset paths, exact sizes, revisions, and hashes.
- Keep model binaries, build output, local properties, and credentials out of ordinary Git commits. Commit the manifest, notices, and development-only download/setup instructions; the build must fail clearly if mandatory packaging assets are absent. The APK itself still includes all required assets.
- A development-only preparation script may fetch the pinned Moonshine files and verify a locally supplied Gemma file. It must never run as an app startup task or write credentials to disk. Do not fetch the gated Gemma file without the authorized developer's accepted terms/access.
- `ModelAssets` validates files and copies packaged assets into a versioned app-private model directory using temporary files followed by atomic publication. Verify checksums on first extraction; reuse valid files on subsequent launches. An interrupted extraction cannot mark a model ready.
- Only initialize file-based SDK loaders with these local directories. Do not invoke Moonshine asset download workers or cache-warming network helpers at runtime.
- Verify available disk space for extraction; report `model_missing` with a clear missing/corrupt/unusable asset message and preserve saved text. Do not delete saved sessions to make room.
- The release merged manifest has no `INTERNET` permission. Exclude model directories, transcripts, and CRM storage from OS backup/device transfer through platform rules and verify the release configuration.

## 4. Proposed files and ownership

All code paths are future files; M0 must adapt them to the actual Flutter shell.

| Files/components | Owner | Responsibility |
| --- | --- | --- |
| `android/app/build.gradle.kts`, manifest, backup-rule XML, `.gitignore` | Sam | Pinned native dependencies, arm64 demo build, model packaging, offline/backup controls |
| `android/app/src/main/kotlin/<package>/MainActivity.kt` | devS; devJ reviews capture hooks | Thin registration, permission and activity lifecycle forwarding |
| `<package>/revise/ReviseEnginePlugin.kt` | devS | Method/EventChannel adapters, argument validation, one completion per method call |
| `<package>/revise/EngineController.kt`, `EngineState.kt` | devS; devJ reviews flush behavior | Serialized transitions, session generation, resource ownership, flush barriers |
| `<package>/revise/AudioCapture.kt` | Jeush | AudioRecord, mono PCM, bounded capture queue, actual microphone shutdown |
| `<package>/revise/MoonshineEngine.kt` | Jeush | Local loading, streaming, line callbacks, pause/final flush |
| `<package>/revise/CaptionAdapter.kt`, `SpeakerRegistry.kt` | Jeush | Immutable snapshots, stable IDs, unknown attribution, timestamp conversion |
| `<package>/revise/GemmaCrmEngine.kt` | Sam | LiteRT-LM local loading, fresh conversation per request, output cap/cancellation |
| `<package>/revise/ModelAssets.kt`, `model-manifest.json`, `scripts/prepare-android-models.ps1` | Sam | Asset inventory, hash verification, extraction and development setup |
| Android JVM/instrumentation tests under matching package | Jeush/Sam | Contract/state tests and real-device inference/capture checks |
| `lib/engine/caption_engine.dart`, `native_caption_engine.dart`, `mock_caption_engine.dart` | Jairus | Existing PRD wire contract and truthful mock path |
| `lib/session/`, `lib/crm/`, relevant screens and Dart tests | Jairus | Text storage, names, CRM prompt/schema/evidence, automatic queue, export |
| `README.md`, `THIRD_PARTY_NOTICES.md`, `docs/evidence/android/VERIFICATION.md` | Sam | Repeatable build/setup, exact models/licenses, measurements and limitations |

Keep MainActivity thin. One Android controller owns the resource lifecycle; STT and LLM helpers do not independently decide session state. Avoid extra database or networking stacks in Kotlin: shared text persistence stays with Dart.

## 5. Interfaces, threading, and data flow

Retain `revise/engine` and `revise/captions` exactly as in PRD section 7. No audio, SDK transcript objects, or raw JSON strings for caption events cross into Dart.

```text
AudioRecord -> bounded PCM queue -> Moonshine Transcriber
  -> CaptionAdapter snapshots -> ordered EventChannel maps -> Dart transcript

Stop -> flush/drain -> stopped event -> Dart saves final original transcript
  -> Dart builds one speaker prompt -> generateCrm -> Gemma/LiteRT-LM
  -> {json: string} -> Dart validates/evidences/saves -> next eligible speaker
```

- Use a single serialized control dispatcher and a dedicated inference worker. Mic capture writes to a bounded queue; inference consumes it. If inference cannot keep up and the queue fills, stop capture and report `capture_failed` rather than dropping audio silently or accumulating unbounded memory.
- Permission/UI callbacks and Flutter channel delivery use the main thread. Native loading and inference run off the main thread. A control mutex/actor must not wait for a callback that needs that same locked actor.
- Disable transcript-bearing SDK diagnostics, including API-call logging and SDK line-object `toString()` output. Logs may contain stable error codes and aggregate timings, never audio, text, prompts, or generated card contents.
- Assign an internal generation token to each session. Gate queued callbacks and event deliveries against it. Detach/disposal stops capture, cancels work, closes native resources, and prevents old callbacks from entering a later session.
- Register the Dart subscription before initialization. If the event sink disappears during capture, stop safely; reconnect through explicit initialization rather than buffering indefinitely or silently recording with no consumer.
- Marshal primitive caption/state maps through a FIFO delivery queue. A Stop completion barrier must include final callback processing and channel enqueueing; Dart still waits until it consumes `stopped` before saving/CRM.
- Validate method names, argument types, language `en`, and `maxTokens=512`. Reject unsupported arguments with `invalid_state` and a clear message; unknown methods use the channel's not-implemented response.

### Caption and speaker adapter

- Map `(session generation, SDK line ID)` to one app `segmentId`. IDs remain unchanged across partial replacements. Deep-copy text, integer timestamps, and speaker choice immediately on callbacks; never retain an SDK `TranscriptLine` or its audio array in Flutter-facing state.
- Normalize stable SDK `speakerId` values, not speaker list positions, to app integers 1–4. Unknown/missing attribution uses 0; additional voices remain unknown and are disclosed. Never reuse or merge app speaker IDs within a session.
- One wire caption represents one textual line. Only a line clearly attributed to one known speaker gets that speaker's ID. Conflicting/multiple speaker spans or overlap produce 0; do not assign the longest span or split text using guessed character boundaries.
- At app-final emission, freeze text, timestamps, and attribution. Ignore duplicate completed events and later `LineSpeakersChanged` for that finalized segment. Before finalization, update attribution as available. Frozen attribution can be wrong; tap-to-rename changes the speaker's display name, not which voice a line belongs to.
- Name detection remains in Dart and runs only on final original segments. Manual names win. Unknown turns cannot infer a known identity. Retain PRD's immediate-next-different-speaker rule and consume/discard pending called-by-name candidates after the eligible turn.
- Use a monotonic session clock (`elapsedRealtime` or equivalent), not calendar time. Keep a piecewise mapping from fed-audio sample ranges to capture wall-time ranges; paused intervals count in session time. Clamp synthetic flush silence to the pause/stop capture boundary. Verify conversion from SDK seconds to integer milliseconds with `0 <= start <= end` and preserve old range mappings for delayed callbacks.

### Capture and pause/flush adapter

Use **AudioRecord + Moonshine's base Transcriber** for the product adapter. The high-level MicTranscriber is suitable for a first SDK example, but its `mute()` and asynchronous `stop()` must not be treated as the PRD implementation.

- Capture mono PCM, target 16 kHz where supported, convert to normalized float samples for Moonshine, and use the actual configured sample rate. Do not assume the requested hardware rate succeeded. Avoid saving raw audio and release processed buffers promptly.
- Keep the Moonshine stream and speaker registry alive across Pause. Stop and release AudioRecord, drain accepted real samples, then feed bounded synthetic silence through the same stream to reach VAD line completion before emitting `paused`. Resume creates capture again against that same stream and the existing session clock.
- M0 must determine and record the silence duration/limit from the pinned VAD options and prove finalization without resetting speaker state. A forced-update call alone is not proof of finalization. Do not call stop/start on the SDK stream for Pause if that resets its transcript/clustering.
- If the silence path cannot flush while preserving the contract, stop at this gate and report the incompatibility for a plan revision. Do not emit `paused` while capture continues, call unconfirmed text final, or invent a speaker-remapping heuristic.
- Stop shuts down capture, drains queued real samples, calls the base stream stop/flush, processes all final snapshots, emits `stopped`, and only then succeeds. A repeat Stop succeeds without duplicate captions. Release the STT/diarization stack once the flush barrier is complete.
- On backgrounding, mic interruption, permission revocation, or capture error, stop capture and preserve finalized lines. Interrupted partials remain visibly unconfirmed and are excluded from CRM. Native must emit `state=error` for asynchronous interruption so Dart persists an interrupted session; do not report successful completion.

## 6. State, concurrency, and resource policy

| Operation | Allowed from | Completion and resource behavior |
| --- | --- | --- |
| `init` | No active session; recoverable error | Close any idle LLM before loading STT; validate/extract assets, load STT/diarization; check LLM file only; emit `ready` on success |
| `start` | `ready`, `stopped` | Finish/cancel any prior CRM through the Dart coordinator first; free LLM; load STT if needed; request permission; reset session IDs only for a new session; emit `listening` after capture starts |
| `pause` | `listening` | Stop capture, flush within same stream; preserve registry; emit `paused` |
| `resume` | `paused` | Reopen capture, preserve stream/registry and elapsed clock; emit `listening` |
| `stop` | `listening`, `paused`, `stopped` | Flush once; emit `stopped`; unload STT; repeat succeeds |
| `generateCrm` | `stopped`, no inference request active | Load Gemma; process one request; return raw JSON text; retain engine only for sequential cards |
| `cleanLine` | Later stretch, `stopped`, idle | Same Gemma resource lock and safeguards; not part of F1–F4 acceptance |

Reject `init` while recording/paused or while inference is active. Starting while a CRM request is active returns `invalid_state`; the UI prevents the conflicting action until its queue has completed. No new channel cancellation method is needed for v1. Activity disposal cancels locally and drops stale results.

- Distinguish public `stopped` from internal `generatingCrm`; recording remains unavailable until the active native request has safely completed/cancelled and its resources are closed.
- Publish stable PRD error codes: `permission_denied`, `model_missing`, `capture_failed`, `inference_failed`, `invalid_state`. Complete method results once. Recording failure also emits `error`; CRM failure leaves the stopped transcript valid.
- Missing Gemma permits caption initialization with `llmReady=false`; recording remains available but F4 readiness fails. Missing STT or diarization prevents recording. `llmReady=true` confirms packaged assets, not successful inference.
- Never close a native engine underneath an active call. Use the runtime cancellation API, await worker completion, then close resources. Verify disposal and repeated init/close on device.

## 7. Gemma CRM execution and shared Dart integration

### Kotlin runtime configuration

- Load the pinned file with LiteRT-LM `EngineConfig`, CPU backend, no vision/audio executors, and a bounded context. Initial total context is 4096 tokens; measure whether a smaller compatible limit materially reduces memory without excluding the prompt plus 512-token output.
- Map wire `maxTokens=512` to the inspected v0.18.0 **`ConversationConfig.maxOutputToken` / per-message `maxOutputToken`**. `EngineConfig.maxNumTokens` is the combined input/output context capacity and is not the output limit.
- Create a fresh conversation per card/retry. Do not retain another speaker's dialogue as model history. Use low-temperature sampling as a measured starting configuration; record exact values in evidence. Disable tools and automatic tool calling.
- Use asynchronous generation or a background inference worker; accumulate only the bounded output text. Handle EOS, cancellation, output exhaustion, and inference exceptions explicitly. A truncated output cannot be shown as a valid CRM card.
- Use `cancelProcess()` on disposal/timeout and await native completion before closing. Set the measured per-request timeout during M0; a timeout returns `inference_failed` without blocking transcript access or automatically extending indefinitely.
- Kotlin receives the canonical complete prompt from Dart. Do not duplicate or rewrite the CRM prompt/schema in Kotlin. The current wire contract does not carry a JSON schema, so constrained JSON decoding is optional future work requiring an explicit shared contract design. For v1, enforce Dart parsing/evidence validation and the single retry.

### Dart flow and validation

- After both native Stop success and consumed `stopped`, save final original segments first. Queue named, known speakers sequentially. An empty/unnamed transcript stays viewable and produces no fabricated card.
- Build prompts from that speaker's final original lines, stable segment IDs, known display name, canonical schema, and instructions to leave unsupported fields empty. Treat spoken instructions as transcript data. Include system/schema/chat-template overhead in context accounting; validate the actual budget in M0 rather than using a characters-to-tokens guarantee.
- Target at most 1500 input tokens plus the 512-token output, within the selected context. If truncating to recent complete lines, record the exact selected IDs and show **Based on recent lines only**. Context overflow returns a failure to be retried once with an explicitly reduced prompt; never silently lose coverage metadata.
- Parse strict JSON; verify required keys, scalar/array types, field paths, existing segment IDs, and speaker ownership. Test explicit factual support using synthetic fixtures. Structural citations do not prove semantic accuracy; keep source navigation for review and never claim an automatic validator proves truth.
- Failure gets one automatic retry per card, then persistent **CRM generation failed** with the known name/source lines and manual Retry CRM. Native does not add its own retry layer.
- Manual Retry CRM affects failed cards only. Preserve successful and user-edited values. User edits clear automatic evidence claims for those values and retain provenance.
- Renaming a known speaker after Stop makes it eligible if no card exists. Repeated callbacks/taps cannot duplicate jobs. Renaming an existing card updates its name through speaker ID, without merging cards for duplicate names.
- Persist statuses, coverage, speaker mapping, and edited cards in app-private storage. Background/disposal prevents stale results from being attached to another session. Restart offers a retry for unfinished generation; do not restart it as a second duplicate job.

## 8. Execution milestones and acceptance gates

Planning/review uses Sol. Once this plan is approved for implementation, Luna can execute one explicit milestone at a time. If the actual SDK behavior conflicts with the plan, stop that milestone, explain the discrepancy, and return the decision to Sol. Do not create subagents or additional chats automatically.

| Milestone | Work and owner | Required exit evidence |
| --- | --- | --- |
| **M0: integration readiness** | Obtain agreed Flutter shell; pin toolchain; prepare licensed assets; run native examples on phone; Jeush/Sam | Exact device/toolchain/artifacts, local-file loaders, Tiny+diarization captions, pause-preserving flush proof, Gemma CPU load/output cap/context/timeout, one successful evidence fixture and one empty-fields fixture |
| **M1: native lifecycle and channels** | Controller/plugin/capture/assets plus Dart engine wrapper; Jeush/Sam/Jairus | Build, state/argument tests, real mic permission paths, ordered events, offline missing-model failure, resource disposal and stale-event isolation |
| **M2: captions and transcript** | Moonshine adapter/registry/timestamps, Dart names/store/export; Jeush/Jairus | F1–F3: partial replacement, frozen finals, 2/4 speakers, unknown/overlap, pause/resume/Stop while paused, second session, restart persistence, text export |
| **M3: automatic CRM** | Gemma engine and Dart queue/validation/cards; Sam/Jairus | F4: sequential named-speaker cards, cited fields, no invented contacts/commitments, one retry, failed-only manual retry, edit preservation, renamed-speaker eligibility |
| **M4: release/demo verification** | Complete packaged arm64 release, notices/readme/evidence; Sam/all | Fresh install offline, merged manifest/backup rules, complete repeated sessions, memory/storage/latency/thermal observations, PRD section 11 and disclosures complete |
| **M5: optional cleaning** | Only after M4 passes and team confirms time; Sam/Jairus | Original retained; filler/punctuation checks, protected names/numbers/dates/negations, rejection fallback; citations remain on Original |

M0 must block full integration if the chosen model cannot meet the CRM fixtures or the required lifecycle cannot be implemented. Do not scaffold an extensive backend around an unproven adapter. Demonstrating live captions alone does not pass automatic speaker labeling or F4.

After each coherent working milestone, summarize changes/checks and propose a Conventional Commit. Ask Jeush for explicit stage/commit approval; do not stage or commit automatically. Another milestone's implementation also needs the agreed execution scope, not an inference from this planning request.

## 9. Verification matrix

Use synthetic audio/conversations agreed for development; no real customer recordings. Unit tests cover behavior with fake SDK boundaries; phone checks establish real SDK behavior. No performance claim comes from mock data or an emulator.

| Area | Check | Evidence/pass condition |
| --- | --- | --- |
| Build/toolchain | Debug/release build, Kotlin/Dart checks, native dependency/ABI compatibility | Recorded exact successful commands after shell setup; inspect Android native page-size compatibility on actual OS |
| State and races | Invalid transitions, concurrent Start/Stop/CRM, duplicate Stop, init recovery, disposed sink | Stable errors; one method completion; no duplicate finals or stale session events |
| Microphone | Denial, permanent denial/settings, pause/background/interruption | Mic capture actually stops; finalized text survives; interrupted partials excluded |
| Caption adapter | Shrinking partial, immutable final, revised SDK speaker, unknown/multiple spans | Whole partial replacement, app finals unchanged, SDK speaker revisions ignored after finalization |
| Speaker stability | 2 speakers then 4, pause/resume, duplicate display names, second session | Stable per-session app IDs, no identity merge, attribution errors measured/disclosed |
| Timing | Pause gap, delayed callback, synthetic silence, long session | Wall elapsed includes pause; no future timestamps; final order valid; latency measured with diarization enabled |
| Names | Self-introduction, called-by-name immediate turn, ambiguity, manual override | PRD rules only on finals; manual names remain; unknown not guessed |
| CRM | Explicit fields, absent contacts/commitments, spoken prompt injection, cross-speaker citation, malformed JSON | Unsupported/wrong-speaker evidence rejected; one retry then visible failure; no tool execution |
| Persistence/export | Restart with edited card, unfinished job, unnamed/empty transcript, copy/share | Original/provenance survives; no duplicate generation; export only initiated by user |
| Assets/offline | Fresh release install with airplane mode/Wi-Fi off; missing/corrupt local asset | Complete captions+CRM without fetch; missing assets fail visibly; no release INTERNET permission/network attempt |
| Resource lifecycle | Two complete sessions, four sequential cards, restart recording after CRM | No simultaneous STT/LLM residency; no growing session/resource leak; no UI freeze |
| Measurements | At least 10 caption turns and 2/4-speaker cases; CRM per-card timing | Record median/slowest first-visible partial; target median <=1 second; record attribution failures and CRM duration |
| Storage/memory | APK bytes, installed+extracted bytes, free-space requirement, peak process/native memory | Actual selected build recorded; asset sizes are not reported as measured runtime memory |

Choose exact commands from the real generated project: Flutter analysis/tests, Android Gradle unit tests/lint/build, and targeted device instrumentation. Run relevant checks for each milestone once; repeat when edits/failures require it. Do not report build/test success from this document review.

Expected command entry points after shell/toolchain setup (planned, not run):

```powershell
# Repository root; only after the Flutter project and relevant tests exist.
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64

# android/; confirm task names and signing/build configuration in M0.
.\gradlew.bat :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
.\gradlew.bat :app:connectedDebugAndroidTest
```

Use instrumentation only with the intended test phone selected. Record release manifest inspection, checksum checks, and the manual fresh-install offline/device checks alongside command results. Installing a verification APK must preserve important existing sessions; use a separate agreed test application/backup path or request approval before uninstalling or clearing app data.

## 10. Readiness, risks, and evidence handoff

M0 evidence must record:

- Actual device model, OS/build, physical RAM, ABI, free storage, and toolchain versions.
- Exact Maven versions/resolved dependencies and model revisions/checksums. Every packaged file's license/notices and acquisition status.
- Required local loading calls/options; no runtime downloader. Capture rate/buffer/queue policy, VAD flush bound, thread ownership, and callback-drain behavior proven on the pinned SDK.
- LLM backend/context/output cap/sampling/timeout; raw-output fixture validation results and per-card duration without storing sensitive content in logs.
- Assets/package/extraction storage, peak memory, caption latency with speakers, attribution errors, repeated-session behavior, and observed crashes/thermal degradation.

Final demo limitations must state: English v1, 2–4 speakers tested, unknown/overlap handling, frozen final attribution can retain errors, names are heuristics/manual labels, evidence links need user review, and any truncated CRM coverage. List an unverified or degraded feature explicitly rather than calling it complete.

Remaining gates are integration evidence, asset access/terms, agreed Flutter shell/toolchain, real-device tests, and team submission artifacts. The Android model family and final-speaker policy no longer require discovery. No code, model download, build, device test, public upload, or submission was performed for this planning milestone.

## 11. Official references

- [Moonshine v0.1.5 release](https://github.com/moonshine-ai/moonshine/releases/tag/v0.1.5), [Android setup](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/docs/using/adding-the-library.md), and [library license](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/LICENSE).
- [Pinned model catalog](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/core/moonshine-model-catalog.cpp) and [asset sizes/checksums](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/core/moonshine-model-file-metadata.generated.cpp).
- [Diarization requirements](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/docs/diarization-models.md), [event guarantees](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/docs/using/transcription.md), [Android Transcriber](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/language-bindings/android/java/main/java/ai/moonshine/voice/Transcriber.java), and [speaker span fields](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/language-bindings/android/java/main/java/ai/moonshine/voice/SpeakerSpan.java).
- [LiteRT-LM v0.18.0 release](https://github.com/google-ai-edge/LiteRT-LM/releases/tag/v0.18.0), [Google Maven version metadata](https://dl.google.com/dl/android/maven2/com/google/ai/edge/litertlm/litertlm-android/maven-metadata.xml), [Kotlin guide](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/docs/api/kotlin/getting_started.md), [configuration fields](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/kotlin/java/com/google/ai/edge/litertlm/Config.kt), and [conversation lifecycle](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/kotlin/java/com/google/ai/edge/litertlm/Conversation.kt).
- [Gemma deployment repository](https://huggingface.co/litert-community/Gemma3-1B-IT/tree/a6306a4e292016480083b73b8dc6f3f939ae04c3), [publisher metadata](https://huggingface.co/api/models/litert-community/Gemma3-1B-IT?blobs=true), and [Gemma terms](https://ai.google.dev/gemma/terms).
- [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels), [Android AudioRecord](https://developer.android.com/reference/android/media/AudioRecord), and [Android backup controls](https://developer.android.com/identity/data/autobackup).
