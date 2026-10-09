# ReVise

Offline live captions for face-to-face conversations, with speaker labels, a
final transcript and Auto-CRM cards. All AI runs on the phone. Spec: [PRD.md](PRD.md).

## Layout

| Path | Owner | What |
| --- | --- | --- |
| `lib/engine/` | Jairus | Platform contract (PRD section 7): events, `CaptionEngine`, `PlatformCaptionEngine` (channels), `MockCaptionEngine` (scripted demo) |
| `lib/session/` | Jairus | Session state, partial/final handling, name rules (F3) |
| `lib/crm/` | Jairus | CRM prompt, JSON parsing, evidence validation, retry (F4) |
| `lib/ui/` | Jairus | Home, Live captions, Transcript, CRM cards |
| `ios/Runner/ReviseEnginePlugin.swift` | Zairus | iOS native engine. Channels and state machine done; wire Moonshine + LLM at `TODO(zairus)` |
| `android/app/src/main/kotlin/com/larpcode/revise/ReviseEnginePlugin.kt` | Jeush, Sam | Android native engine. Same contract; wire at `TODO(jeush)` / `TODO(sam)` |

Channels: EventChannel `revise/captions` (native to Dart, one map per event) and
MethodChannel `revise/engine` (`init`, `start`, `pause`, `resume`, `stop`,
`generateCrm`, `cleanLine`). Error codes: `permission_denied`, `model_missing`,
`capture_failed`, `inference_failed`, `invalid_state`.

## Run

```sh
flutter pub get
flutter test
flutter run            # Android phone or emulator; iOS needs Xcode on the Mac
```

Home has a **Demo / Sample data** switch (on by default). It replays a scripted
4-person meeting through the same events, so the UI works without native code.
Turn it off to use the native engine; until Moonshine is wired in, `start`
returns `model_missing`.

## iOS (Zairus)

Open `ios/Runner.xcworkspace` in Xcode, set your signing team, and run on the
iPhone. `ReviseEnginePlugin` is registered in `AppDelegate.swift`. The mic usage
text is in `Info.plist`. Deployment target is iOS 15.0; raise it if the
Moonshine or llama.cpp package needs more.
