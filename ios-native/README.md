# iOS native backend (Zairus)

Swift side of the PRD contract: `revise/engine` (MethodChannel) and `revise/captions` (EventChannel).
Moonshine streaming STT + speaker IDs. The on-device LLM (`generateCrm`, `cleanLine`) is **not built yet**
and answers `model_missing`.

| File | Job | Imports Flutter? |
| --- | --- | --- |
| `Revise/ReviseChannels.swift` | Registers both channels, maps errors to `PlatformException` codes | yes |
| `Revise/ReviseEngine.swift` | State machine (init/start/pause/resume/stop), mic permission, interruptions | no |
| `Revise/CaptionTracker.swift` | Moonshine events -> caption maps (segment IDs, speaker IDs, timestamps) | no |
| `Revise/ReviseModelStore.swift` | Finds model files (app bundle first, then Moonshine cache) | no |

## Wiring into the Flutter project (once `ios/Runner` exists)

1. Copy the `Revise` folder into `ios/Runner/Revise/` and add it to the **Runner** target in Xcode.
2. Xcode: File > Add Package Dependencies > `https://github.com/moonshine-ai/moonshine-swift.git`,
   rule **Exact Version 0.1.5**, add product `MoonshineVoice` to the **Runner** target.
3. Runner target > Info tab: add `Privacy - Microphone Usage Description`
   ("ReVise listens to the conversation to caption it. Audio never leaves this phone.").
4. In `AppDelegate.swift`, register once at launch. Use the one that matches the generated file:
   - Classic template (`GeneratedPluginRegistrant.register(with: self)` inside `didFinishLaunchingWithOptions`):
     ```swift
     let controller = window?.rootViewController as! FlutterViewController
     ReviseChannels.shared.register(with: controller.binaryMessenger)
     ```
   - Newer implicit-engine template (`didInitializeImplicitFlutterEngine`):
     ```swift
     ReviseChannels.shared.register(with: engineBridge.applicationRegistrar.messenger())
     ```
5. Runner target > Deployment Target: iOS 15 or higher (Moonshine package minimum).

## Models (bundled, no network ever)

Models live in `ios-native/Models/` (about 1.3 GB with the LLM, **not in git**). Rebuild them once on a Mac with internet:

```
sh ios-native/fetch-models.sh
```

Both `ios/Runner` and `ReviseHarness` reference that folder as a bundled "Models" folder, so a Debug or Release build
carries the files and works in airplane mode. If a file is missing, `init` returns `sttReady=false` and the `error`
state says which model is missing (it never waits on the network). Layout inside the app:

```
Models/stt-small-streaming/   Moonshine Small Streaming English (8 files)
Models/diarization/           segmentation.ort, embedding.ort
Models/llm/*.gguf             (later)
```

## On-device LLM (llama.cpp + Qwen 2.5 1.5B Instruct Q4_K_M)

- `LlamaPackage/` is a local Swift package that wraps llama.cpp's prebuilt XCFramework (release b11531, Metal GPU).
  It has an iPhone slice and a Mac slice but **no iOS Simulator slice**: test on a real phone.
- `Revise/LlamaRunner.swift` loads the GGUF and generates (greedy sampling, optional GBNF grammar).
  `Revise/ReviseGrammars.swift` holds the CRM grammar, the generic-JSON grammar and the CRM system prompt.
- Lifecycle (PRD): the LLM is loaded on the first request **after Stop**, after Moonshine is freed; it stays loaded for
  later requests and is freed before the next `start`. Requests run one at a time and only in state `stopped`.
- Model file: `Models/llm/*.gguf` (first by name). Switch models with `LLM=0.5b|1.5b|3b sh ios-native/fetch-models.sh`
  (delete the old .gguf first). 0.5b if the iPhone 13 runs out of memory; 3b only for the 6 GB iPhone 14 Pro Max.
- Logs: filter the Xcode console by `REVISE-LLM` (load time, free memory, GPU/offload lines, prompt and generation tokens/sec).

### Speed (iPhone 13 first measurement: 537-token prompt took ~16 s, 186 tokens generated at 15 tok/s, 30 s total)

- **Prompt cache.** `LlamaRunner` keeps the KV cache between calls and only processes the part of a prompt that differs
  from the previous one. Right after Stop (once Moonshine is freed) the engine loads the LLM and reads the system prompt in
  the background, so the first card skips ~260 tokens and the model load; later cards also skip Dart's fixed instruction block.
- **Values-only CRM.** For `generateCrm` the model writes only the values (grammar forces `"source_segments": {}`) and
  `CrmEvidence` fills the citations by looking each value up in the `[s-0001] ...` transcript lines of the prompt. About half
  the output tokens (81 instead of 186 in the Mac test) and the citations are now correct. Contact details must match a
  line word for word, otherwise they are removed (the 1.5B model invents emails). If the transcript lines can't be parsed
  from the prompt, it falls back to model-written citations with the full grammar.
- **Streaming.** Pass `requestId` to any LLM method and every new piece of text arrives on `revise/captions` as
  `{"type":"llm","requestId":..., "delta":"..."}` (Dart's `EngineEvent.fromMap` ignores unknown types, so nothing breaks).
  For `generateCrm` the streamed text is the raw values JSON; the final reply has the evidence added.
- **Metal checks.** Context uses all layers on the GPU (`n_gpu_layers=99`), `n_batch=n_ubatch=512`, flash attention on
  (auto-retry if unsupported), 2 CPU threads. **When timing, run a Release build with Metal API Validation off:**
  Xcode > Product > Scheme > Edit Scheme > Run > Info: Build Configuration = Release; Diagnostics: untick Metal API/Shader
  Validation. Validation under the debugger slows GPU work a lot. Also turn Low Power Mode off.
- The shortened system prompt was tried and **rejected**: citations got worse. System prompt length is nearly free now (cached).

### Mac LLM test tool and end-to-end check

`ios-native/MacLlmTest` is a command-line tool that runs the app's real `generateCrm` path (same `CrmEvidence.plan`,
`LlamaRunner`, grammars) on a prompt file, with no phone:

```
cd ios-native/MacLlmTest && swift build
DYLD_FRAMEWORK_PATH=$(dirname $(find .build -type d -name llama.framework -path "*macos*" | head -1)) \
  .build/debug/llmtest prompt.txt card.json
```

It was used to run Jairus's real `SessionController` + `CrmController` (scripted two-person conversation, Stop, automatic cards)
against the real Swift/LLM code: both cards generated first try, evidence correct, no invented email.

### Runner scheme

`ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`: the **Run** action is set to **Release** with Metal API Validation
off, so pressing Run in Xcode builds the fast configuration (Debug + validation made the LLM several times slower). Flutter's own
`flutter run` / `flutter build` pass their own configuration and are not affected.

### Channel methods for Dart (all only while state is `stopped`; errors: `model_missing`, `invalid_state`, `inference_failed`)

| Method | Args | Returns |
| --- | --- | --- |
| `generateCrm` | `{prompt, maxTokens}` | `{json}` (CRM grammar enforced) |
| `cleanLine` | `{text, prompt, maxTokens}` | `{text}` |
| `generate` | `{prompt, maxTokens, system?, jsonGrammar?}` | `{text}`; `jsonGrammar: true` = any valid JSON, a String = your own GBNF grammar |

Every reply also has `loadMs`, `promptTokens`, `generatedTokens`, `tokensPerSecond`.

Dart side for `generate` (add next to `cleanLine` in `CaptionEngine` / `PlatformCaptionEngine`):

```dart
Future<String> generate({required String prompt, int maxTokens = 512, String? system, Object? jsonGrammar}) async {
  final r = await _call<Map<Object?, Object?>>('generate', {
    'prompt': prompt, 'maxTokens': maxTokens,
    if (system != null) 'system': system,
    if (jsonGrammar != null) 'jsonGrammar': jsonGrammar,
  });
  return r?['text'] as String? ?? '';
}
```

## Speaker handling (what exists and why)

1. **Faster diarization.** Moonshine's clustering threshold is compiled in (no option). We set `diarization_cluster_cadence=1.0`
   and `diarization_analyze_cadence=0.5` so speakers appear sooner (two-voice test: Unknown lines 2 -> 1, labels followed the real
   alternation). If live captions lag on a phone, put them back to 2.0 / 0 in `ReviseEngine.loadSTT`.
2. **Suggested labels at Stop (`lib/session/speaker_suggestions.dart`).** Only when Moonshine gave at most one speaker for the whole
   conversation. Turn-taking cues (question -> answer by the other person, "Sure/Thanks/Hi/That sounds..." replies) plus names ("I'm X",
   "my name's X", "Thanks, X" = said to X). Shown with an on/off switch on the transcript, originals kept, applied inside
   `SessionController.stop()` so CRM cards use it. It is a 2-person heuristic, not a model.
   **An LLM was tried and rejected:** Qwen 2.5 1.5B scored 5/14 (just alternates A/B) and 7/14 on per-line change flags; asked
   "same or different person?" for adjacent lines it answered "different" every time. A bigger model (3B, only for the 6 GB iPhone 14 Pro Max)
   might work but was not tested; `CaptionEngine.generate()` is in place if you want to try.
3. **Manual safety net.** Live screen "Switch speaker" (forces the speaker of new lines, "Auto" returns to Moonshine) and tap a transcript
   line to choose its speaker. Stored in `Segment.manualSpeakerId`; `SessionController.speakerOf(segment)` decides the label
   (manual > suggested > Moonshine) and everything (UI, name rules, CRM) uses it.
4. **Name rule** also matches "my name's X", "name's X" and curly apostrophes.
5. **CRM `follow_up`** must be a concrete action: prompt rule + code guard in `CrmEvidence.isConcreteAction` (greetings, thanks, goodbyes
   and time-only phrases like "next week" become null).

### Contract addition: `speaker` event (speaker revisions)

Moonshine keeps refining who spoke a line AFTER the line is finished (`LineSpeakersChanged` on a completed line). The caption
contract still says a final never changes, so text, times and `isFinal` stay frozen; a changed speaker is sent as a separate event
on `revise/captions`:

```json
{"type":"speaker","segmentId":"s-0007","speakerId":2}
```

Dart updates that line's Moonshine label (`Segment.speakerId`), leaves anything the user chose untouched (`manualSpeakerId`: Switch
speaker / tapped line), and when a line goes Unknown -> known while still listening it applies the name rules once ("Hi, I'm David"
said before the voices were told apart). Unknown event types are ignored, so Android can ignore this event or send its own.
Moonshine has **no** "number of speakers" setting (checked the C API options, the Swift package and the diarizer config: only the
three cadences exist), so a "2 speakers" option is not possible.

### Dart changes made on zrs/ios (for Jairus)

- `lib/engine/caption_engine.dart`, `platform_caption_engine.dart`, `mock_caption_engine.dart`: new `generate({prompt, maxTokens, system, jsonGrammar})`
  (mock throws model_missing).
- `lib/session/session_controller.dart`: `Segment.manualSpeakerId` / `suggestedSpeakerId`; `speakerOf()`, `knownSpeakers` now use it;
  `switchSpeaker()`, `useAutoSpeaker()`, `setLineSpeaker()`, `liveSpeakerOverride`, `currentSpeaker`; `_applySuggestions()` called from `stop()`;
  `setUseSuggestions()`, `hasSuggestions`; name rules use `speakerOf(seg)`.
- `lib/session/speaker_suggestions.dart` (new), `lib/session/name_rules.dart` (self-intro regex).
- `lib/crm/crm_controller.dart` (one line: lines filtered by `session.speakerOf`), `lib/ui/crm_screen.dart` (one line), `lib/ui/live_screen.dart`
  (Switch speaker row, chip uses `speakerOf`), `lib/ui/transcript_screen.dart` (tap a line, suggestion banner), `lib/ui/speaker_chip.dart`
  (`showLineSpeakerPicker`).
- Tests: `test/manual_speaker_test.dart`, `test/speaker_suggestions_test.dart`, `test/name_rules_test.dart` (extended).
- Android: `generate` is a new channel method; Dart treats model_missing / MissingPlugin as "skip".

## Moonshine SDK gotchas found while testing (0.1.5)

- **`MicTranscriber` crashes on release with speaker ID on.** Its `close()` closes the stream, then `Stream.deinit` closes it
  again; the second free segfaults (`EXC_BAD_ACCESS` in `Transcriber::free_stream`). So we use `Revise/MoonshineMic.swift`
  (public `Transcriber` + `Stream`, each stream freed exactly once). Don't switch back to `MicTranscriber`.
- **`speakerIndex` is not "Speaker N".** It never restarts and skips numbers when re-clustering drops a provisional speaker.
  `CaptionTracker` numbers speakers 1, 2, 3... per session by first appearance of the stable `speakerId`.
- **Speaker data arrives after a line completes.** `CaptionTracker` holds a finished line up to 2.5 s for its speaker, then
  sends it as Unknown (0). The first ~8 s of a session are often Unknown while the diarizer warms up.
- **`Stream.stop()` then `start()` resets the stream clock and the speaker identities.** So Pause does not stop the stream:
  it stops the mic and feeds 1.2 s of silence so the phrase finishes; Resume keeps the same stream.

## Not verified yet (needs the phone)

- Everything above was tested in a macOS command-line program with recorded audio, not on the iPhone.
- Caption delay with speaker ID on (PRD section 11: about 1 second) is unmeasured on the phone.
