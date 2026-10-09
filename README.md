# ReVise — ABPH Hackathon

Product requirements: [PRD.md](PRD.md). Android decisions: [ANDROID_IMPLEMENTATION_PLAN.md](ANDROID_IMPLEMENTATION_PLAN.md).

## Android backend development

- devS: `devs/android-crm-assets` — verified model assets, Gemma CRM, channels/controller, build configuration.
- devJ: `devj/android-captions-speakers` — capture, Moonshine transcription/diarization, speaker/caption adapters.
- Both submit PRs to **`codex/kotlin-development`**. See [ANDROID_WORK_SPLIT.md](ANDROID_WORK_SPLIT.md).

This checkout contains the devS backend milestone. The shared Flutter application currently lives on `jai-flutter`; integrate that existing shell rather than generating another app. The native speech implementation is supplied by devJ. Until those are integrated, this checkout is **not a runnable APK** and does not claim microphone or Gemma device inference readiness.

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
