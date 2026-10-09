# Android backend integration

## devS milestone and dependency boundary

Native core files are in `android/app/src/main/kotlin/com/larpcode/revise/backend/`. The channel adapter remains `com.larpcode.revise.ReviseEnginePlugin`, matching the existing Flutter shell registration.

| Component | Implemented responsibility |
| --- | --- |
| `ModelAssets`, `AndroidModelAssets` | Validate the fixed inventory, stream/check SHA-256, check storage, atomically extract into `noBackupFilesDir/revise-models/<inventory hash>`; report Gemma separately from speech |
| `GemmaCrmEngine` | One active request, fresh conversation, stable sanitized errors, timeout/cancellation, idle unload and asynchronous disposal |
| `LiteRtCrmRuntime` | Actual LiteRT-LM 0.18.0 API, CPU, 4096-token total context, 512 output tokens, no tools or audio/vision backends |
| `EngineController` | Serialized native lifecycle, generation filtering, Stop/paused enqueue barriers, sequential STT/LLM residency |
| `ReviseEnginePlugin` | PRD channels, argument checks, runtime mic permission, main-thread FIFO delivery, background interruption and detach/sink-loss disposal |
| `SpeechBackend` | Shared interface for devJ's real capture/STT/speaker implementation; no fake speech implementation is shipped |

The default plugin constructor intentionally rejects speech initialization until devJ's factory is injected. It does not report `sttReady=true` for a stub. `llmReady=true` means a verified local Gemma file, not measured inference readiness.

## devJ integration contract

Implement `SpeechBackendFactory.open(PreparedModels)` to load STT and diarization from the supplied directories. On open failure, release any partially created resources. Do not call SDK download helpers. Inject the factory when MainActivity registers `ReviseEnginePlugin`.

- `start(listener)`: start real capture, emit immutable `CaptionSnapshot` objects, and return after capture has started. Do not retain/revise a final snapshot.
- `pause()`: shut down mic capture, drain accepted audio and callbacks, and finalize through the same SDK stream before returning. Keep speaker mappings/stream alive.
- `resume()`: restart capture in that same session. Keep elapsed timestamps and speaker IDs.
- `stop()`: finish capture/drain/final callbacks before returning. The controller then closes speech and enqueues `stopped`. Make Stop idempotent.
- `requestStop()`: thread-safe prompt interruption of microphone acceptance. Do not block waiting on the controller worker. Do not emit successful Stop on an interruption.
- `close()`: release native speech/capture resources; make cleanup idempotent.

All methods except `requestStop` are called on `revise-control`. Caption/error callbacks may come from SDK threads. The controller enqueues caption maps immediately; never dispatch a final callback after a pause/stop barrier has returned. Normalize IDs to 1–4/unknown=0, preserve final attribution, and enforce the PRD's timestamp/name boundaries in devJ's adapter/Dart respectively.

`BackendEvents.enqueue` must enqueue onto the main thread in FIFO order. Delivery must check `isCurrentGeneration(token)` again before touching Flutter; the plugin does this. Event-sink loss disposes the controller rather than continuing silent capture.

## Shared Flutter shell integration

Merge the existing `jai-flutter` shell into the integration branch through its own reviewed PR, then update both native feature branches. Preserve the shell's package ID, Flutter project and UI. When combining the devS changes:

1. Use this plugin in place of the shell's placeholder plugin. Retain the shell's thin MainActivity registration and inject devJ's speech factory there.
2. Add `apply(from = "revise-backend.gradle")` to `android/app/build.gradle.kts` **after** its existing Android/Flutter configuration. This adds exact native dependencies, minimum SDK 26, arm64 packaging, uncompressed native models and packaging integrity tasks.
3. In the existing main manifest, add the `tools` namespace and remove merged release networking permission:

   ```xml
   <manifest xmlns:android="http://schemas.android.com/apk/res/android"
       xmlns:tools="http://schemas.android.com/tools">
       <uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
       <!-- Keep the shell's RECORD_AUDIO permission, activity and Flutter metadata. -->
   </manifest>
   ```

4. Add these attributes to the shell's existing `<application>`:

   ```xml
   android:allowBackup="false"
   android:fullBackupContent="@xml/revise_backup_rules"
   android:dataExtractionRules="@xml/revise_data_extraction_rules"
   ```

   Model extraction already uses `noBackupFilesDir`; the XML rules also exclude app text/preferences/database and device transfer. Keep Flutter tooling's debug/profile networking only where needed, and inspect the final release merged manifest rather than assuming these changes are sufficient.

5. Combine `.gitignore` files so model binaries, local properties, scratch files and generated output remain ignored. Do not discard the shell's existing ignore entries.
6. Restore/regenerate the standard Flutter Gradle wrapper using the agreed installed Flutter SDK. Run the real application build and inspect resolved dependencies, notices, native ABIs and release manifest.

Build entry points after integration:

```powershell
# android/, with valid local.properties and the shared Flutter SDK installed.
./gradlew.bat :app:verifyReviseModels :app:assembleDebug
# Explicitly incomplete speech development build when Gemma is unavailable:
./gradlew.bat :app:assembleDebug -PreviseSpeechOnly=true
# Release always verifies all 11 models, even with the speech-only property.
```

The Gradle configuration and manifest edits above have not been exercised in an integrated Flutter APK yet. They are a handoff for the existing shell; they do not create a competing application.

## CRM behavior and device gates

The Dart prompt crosses unchanged, and raw output returns as `{json: string}`. Dart owns schema/evidence validation, the one card retry, persistence and display. No native retry, prompt template replacement, cloud request or tool execution is added.

Provisional settings: CPU, 4096 total context tokens, 512 maximum output tokens, topK=40, topP=0.9, temperature=0.2, 120-second request deadline. Record measured device behavior before treating them as performance decisions. Input has a 65,536-character memory bound, not a tokenizer-based context guarantee. An oversized tokenized prompt fails visibly through the SDK; Dart must fit the prompt plus output budget.

Decode-token metrics are enabled internally. Blank output, missing metrics, oversized output, or a decode count at/above 512 fails conservatively; even a complete-looking response at the cap is not accepted as a successful full response. No model output is parsed/repaired in Kotlin.

Timeout/caller cancellation/disposal invokes native cancellation. The caller can receive an error before cancellation finishes, but new inference/unload/recording stays blocked until terminal native completion and resource release. Initialization has no force-cancel API: if it times out, wait for it to return before cleanup. If native cancellation never acknowledges, the engine deliberately stays busy; validate this on the phone. It never closes live native handles to manufacture completion.

Before release: authorized Gemma acquisition and complete notice bundle; actual phone CPU loading/output-cap/cancellation; devJ flush/speaker checks; full APK/lint/build; repeated recording/CRM cycles; fresh install with all networking off; measured latency/memory/storage; inspect no release INTERNET permission and backup exclusions.

Extraction verifies reused files on each preparation. Older inventory directories are retained; measure upgrade storage as well as fresh-install extraction before implementing any model-only cleanup. Saved sessions are never deleted for model storage.
