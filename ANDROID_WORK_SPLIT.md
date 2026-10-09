# Android backend: devS and devJ

This is the shared ownership plan for the Android Kotlin backend. The PRD remains the product contract. Flutter UI, Dart names/storage/prompts/CRM validation, and iOS remain with their existing owners.

## Feature ownership

| Feature | devJ | devS |
| --- | --- | --- |
| F1 live captions | AudioRecord, bounded PCM queue, Moonshine Tiny Streaming and diarization, partial/final captions | Model assets and channel/controller integration |
| F2 final transcript | Pause/Stop drain and flush; exactly-once final snapshots and timestamps | Stop completion barrier, state/error delivery, release STT before CRM |
| F3 speaker labels | Stable per-session speaker IDs 1–4, unknown=0, frozen final attribution | Preserve the caption contract through native channels |
| F4 CRM cards | Review the STT-to-LLM resource handoff | Gemma 3 1B INT4/LiteRT-LM, fresh conversation per request, 512 output-token cap, timeout/cancellation, raw JSON result |
| Release | Speech/speaker/device measurements | Offline packaging, backup controls, hashes/licenses, Android builds and disclosure evidence |

F2b is deferred until the required features pass. Native code receives the full CRM prompt from Dart; it does not create prompts, validate card evidence, save transcripts, or retry cards itself.

## Files and boundaries

- devJ owns `AudioCapture.kt`, `MoonshineEngine.kt`, `CaptionAdapter.kt`, `SpeakerRegistry.kt`, and speech/capture tests.
- devS owns `GemmaCrmEngine.kt`, `ModelAssets.kt`, the model manifest and preparation tooling, native channel/controller files, `MainActivity.kt`, Gradle/manifest/backup configuration, and CRM/assets/controller tests.
- devS owns shared registration/state files. devJ supplies capture behavior through the agreed interface and requests changes instead of editing those files concurrently.
- Both use namespace `com.larpcode.revise` from the shared `jai-flutter` shell. Import the same shell through integration; do not create a second Flutter application.
- Keep evidence in separate `docs/evidence/android/devs/` and `docs/evidence/android/devj/` folders. devS consolidates release evidence.

Before wiring capture, agree on the Kotlin capture boundary: local STT/diarization paths in; immutable primitive caption snapshots out; completion of pause/stop includes accepted audio, SDK callbacks, and final event delivery. Both keep `revise/engine` and `revise/captions` unchanged.

## Branch and PR rules

| Developer | Feature branch | PR base |
| --- | --- | --- |
| devS | `devs/android-crm-assets` | `codex/kotlin-development` |
| devJ | `devj/android-captions-speakers` | `codex/kotlin-development` |

Each developer uses their own checkout/branch. No direct implementation commits go to the integration branch or `main`. Create devJ's branch with:

```powershell
git fetch origin
git switch -c devj/android-captions-speakers origin/codex/kotlin-development
git push -u origin devj/android-captions-speakers
```

Both tracks can develop and test independently using fake interfaces and native SDK examples. Merge the shared shell and minimal dependencies/interfaces first; update both feature branches from integration after that merge. Then merge coherent tested backend PRs, update the remaining branch, and run the combined native/device checks before accepting the final integration. Each PR records actual checks and pending device gates; the other developer reviews it.

## First deliverables

- devJ: prove local Tiny Streaming + diarization loading, capture shutdown, pause-preserving flush, stable IDs, and frozen finals on the target phone.
- devS: implement verified asset preparation/local extraction and the Gemma adapter; prove CPU loading, output limits, fresh conversations, and disposal on the target phone.
- Joint handoff: Stop flushes first, STT/diarization unloads, Gemma runs sequentially, and the next recording has no old resources/events.

Desktop tests can verify logic and corrupt/missing assets. Device inference, performance, pause/flush behavior, ABI compatibility, and fresh-install offline operation remain explicit device gates. Until those pass, implementation is not a completed M0 or a demo-ready build.
