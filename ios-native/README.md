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

Models live in `ios-native/Models/` (about 145 MB, **not in git**). Rebuild them once on a Mac with internet:

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
