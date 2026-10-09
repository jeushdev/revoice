# ReVise — ABPH Hackathon

Product requirements: [PRD.md](PRD.md). Android decisions: [ANDROID_IMPLEMENTATION_PLAN.md](ANDROID_IMPLEMENTATION_PLAN.md).

## Android backend development

- devS: `devs/android-crm-assets` — verified model assets, Gemma CRM, channels/controller, build configuration.
- devJ: `devj/android-captions-speakers` — capture, Moonshine transcription/diarization, speaker/caption adapters.
- Both submit PRs to **`codex/kotlin-development`**. See [ANDROID_WORK_SPLIT.md](ANDROID_WORK_SPLIT.md).

This local integration combines the existing `jai-flutter` application and the latest devS backend milestone. The native speech implementation is supplied by devJ; the default plugin intentionally rejects speech initialization until that implementation is injected. This checkout is **not a verified runnable APK** and does not claim microphone or Gemma device inference readiness. See the [local integration handoff](docs/evidence/android/devj/INTEGRATION_PREP.md) for checks and blockers.

See [Android backend setup and integration](docs/android-backend.md), [verification evidence](docs/evidence/android/devs/VERIFICATION.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

## Desktop checks

PowerShell 7, a Kotlin compiler and Java 17+ are required. The test script defaults to Android Studio's installed compiler/JDK; override its path parameters on other machines.

```powershell
./scripts/test-android-backend.ps1
./tests/scripts/prepare-android-models.tests.ps1
python -m unittest discover -s scripts/tests -v
```

The first command exercises lifecycle and asset logic with fake runtime/speech boundaries. It can also compile against actual Android, LiteRT and Flutter API jars; see its parameter help. These checks do not execute Android native libraries.

## Prepare pinned models

```powershell
# Developer-machine download of public speech assets only.
./scripts/prepare-android-models.ps1 -SpeechOnly
./scripts/prepare-android-models.ps1 -SpeechOnly -VerifyOnly

# After an authorized developer obtains the exact Gemma file:
./scripts/prepare-android-models.ps1 -GemmaPath 'C:/path/to/gemma3-1b-it-int4.litertlm'
./scripts/prepare-android-models.ps1 -VerifyOnly
```

Gemma acquisition/terms are handled by the developer. The script verifies the pinned local file and never downloads it or reads a token. Model binaries stay out of Git. Application code reads only packaged local assets; it does not run the preparation script or fetch models.

devJ's Python preparation/authorized-download workflow is preserved separately in
`scripts/prepare-android-models-python.ps1`; see [Android model preparation](docs/ANDROID_MODELS.md).
Both tools use the same runtime inventory. Pulling a model manifest does not pull
the ignored model binaries or establish local readiness.
Offline live captions for face-to-face conversations, with speaker labels, a
final transcript and Auto-CRM cards are the product goal. The shell's sample-data
mode is not evidence of native inference. Spec: [PRD.md](PRD.md).

## Layout

| Path | Owner | What |
| --- | --- | --- |
| `lib/engine/` | Jairus | Platform contract (PRD section 7): events, `CaptionEngine`, `PlatformCaptionEngine` (channels), `MockCaptionEngine` (scripted demo) |
| `lib/session/` | Jairus | Session state, partial/final handling, name rules (F3) |
| `lib/crm/` | Jairus | CRM prompt, JSON parsing, evidence validation, retry (F4) |
| `lib/ui/` | Jairus | Home, Live captions, Transcript, CRM cards |
| `ios/Runner/ReviseEnginePlugin.swift` | Zairus | iOS native engine. Channels and state machine done; wire Moonshine + LLM at `TODO(zairus)` |
| `android/app/src/main/kotlin/com/larpcode/revise/ReviseEnginePlugin.kt` | Sam | Real Android channels/controller/assets/CRM adapter; inject devJ's `SpeechBackendFactory` in the thin MainActivity when ready |

Channels: EventChannel `revise/captions` (native to Dart, one map per event) and
MethodChannel `revise/engine` (`init`, `start`, `pause`, `resume`, `stop`,
`generateCrm`, `cleanLine`). Error codes: `permission_denied`, `model_missing`,
`capture_failed`, `inference_failed`, `invalid_state`.

## Run the shared shell

The shell declares Dart `^3.13.5`; this requirement is unchanged. Flutter
3.47.6 / Dart 3.13.5 was verified on Jeush's machine, but that installation is
machine-local. Select a verified compatible SDK on each build host, restore the
ignored Gradle wrapper from its SDK, and prepare the required licensed assets
before an Android build. See the [integration readiness review](docs/evidence/android/INTEGRATION_REVIEW.md)
for the current host checks and open gates.

```sh
flutter pub get
flutter test
flutter run            # Android phone or emulator; iOS needs Xcode on the Mac
```

Home has a **Demo / Sample data** switch (on by default). It replays a scripted
4-person meeting through the same events, so the UI works without native code.
Turn it off to use the native engine. Missing packaged speech assets fail with
`model_missing`; with valid assets, `init` still fails with `capture_failed` until
devJ's real speech factory is injected. No speech stub reports readiness.

## iOS (Zairus)

Open `ios/Runner.xcworkspace` in Xcode, set your signing team, and run on the
iPhone. `ReviseEnginePlugin` is registered in `AppDelegate.swift`. The mic usage
text is in `Info.plist`. Deployment target is iOS 15.0; raise it if the
Moonshine or llama.cpp package needs more.
