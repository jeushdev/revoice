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

## Models

PRD wants models **bundled**, no download in the shipped app. Layout inside the app bundle:

```
Models/stt-small-streaming/   (Moonshine small streaming English files)
Models/diarization/           (Moonshine speaker-ID files, ~8 MB)
Models/llm/*.gguf             (later)
```

Until bundling is done, **Debug builds only** download STT + diarization once into the phone
(`ReviseModelStore.downloadMissingForDevelopment`, wrapped in `#if DEBUG`). Needs internet once.
Release builds contain no download path from our code.

## Not verified yet (needs the phone)

- `ReviseEngine` + `CaptionTracker` + `ReviseModelStore` compile against moonshine-swift 0.1.5. `ReviseChannels` has **not**
  been compiled (no Flutter project yet).
- Pause/resume assumes Moonshine's stream keeps counting time after `stop()` then `start()`. If timestamps jump
  backwards after resume, that assumption is wrong.
- Speaker IDs use Moonshine `speakerIndex + 1` of the longest span in a line; later re-clustering of already-final
  lines is ignored (contract: final never changes).
- Caption delay with speaker ID on (PRD section 11: about 1 second) is unmeasured.
