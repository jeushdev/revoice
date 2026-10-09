# devS Android backend verification

Date: October 10, 2026, Asia/Manila. Feature branch: `devs/android-crm-assets`; PR base: `codex/kotlin-development`.

## Result summary

| Check | Result | Scope |
| --- | --- | --- |
| Kotlin JVM backend checks | **33 passed** | CRM lifecycle, raw prompt/output, fresh conversations, caps/errors, timeout/disposal, extraction/corruption/storage, controller transitions/flush ordering/resource handoff/stale events |
| PowerShell preparation checks | **11 passed** | Independent CRC32C/SHA vector, offline verification, corrupt/missing/unsafe inventories, verified local Gemma fixture import |
| Actual speech asset verification | **10 passed** | All pinned STT+diarization files checked against length, SHA-256 and publisher CRC32C |
| Android/LiteRT/Flutter API compilation | **Passed** | Native sources and channel adapter compiled against actual SDK API artifacts; no invented API stubs |
| Backup XML parsing | **Passed** | Both XML files are well-formed; this is not a merged-manifest/device-backup test |
| Git whitespace validation | **Passed before publication** | Source/documentation diff only |
| Full Flutter/Gradle APK build, lint | **Pending** | Shared shell integration and installed Flutter SDK required |
| Gemma inference on Redmi | **Pending** | Authorized pinned model file and connected device required |
| Actual microphone/Moonshine/pause/speakers | **Pending, devJ** | Fake speech in desktop tests proves controller behavior, not SDK flush/speaker performance |
| Fresh offline install, native cancellation, performance, memory, storage, release manifest/backup | **Pending** | No demo-ready or completed M0 claim |

## Toolchain and compile-only artifacts

- Kotlin compiler: Android Studio bundled `kotlinc-jvm 2.3.20`, JVM target 17. Its launcher reported JRE 26.0.2.1.
- Tests executed with Android Studio JBR OpenJDK **25.0.3**.
- Compile-only Android platform API: installed `android-37.0/android.jar`. This is not a declaration of the final app's compile/target SDK.
- LiteRT-LM AAR: Google Maven **0.18.0**, actual `classes.jar`. AAR manifest minSdk is 24; packaged native directories are `arm64-v8a` and `x86_64`. Combined application ABI/minSdk acceptance is still pending (build config uses minSdk 26/arm64).
- Flutter embedding: official artifact engine **`deb287481e3ce9468f3434937ced4240a70539ca`**, resolved from shared shell Flutter revision **`abaf9c523780a608bd46686fd5e53740a07077f8`**. The shell is on `jai-flutter`, inspected at `73db4b6`.
- CLI authentication checked as **`samuelordialeseya`** with repository pull/push permission. Connector selection is separate from CLI authentication.

Actual speech assets total **53,803,659 bytes**. The Gemma manifest pin is **584,417,280 bytes**, SHA-256 `1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be`. Gemma was not obtained or executed. Asset totals are not installed/APK size or RAM measurements.

## Commands executed

From the repository root, on the local Windows machine:

```powershell
./scripts/test-android-backend.ps1 `
  -LiteRtClassesJar "$PWD/work/kotlin-deps/litertlm/classes.jar" `
  -AndroidJar 'C:/Users/laptop ni sam/AppData/Local/Android/Sdk/platforms/android-37.0/android.jar' `
  -FlutterEmbeddingJar "$PWD/work/kotlin-deps/flutter-embedding.jar"

./tests/scripts/prepare-android-models.tests.ps1
./scripts/prepare-android-models.ps1 -SpeechOnly -VerifyOnly
git diff --check
```

SDK jars, test outputs and temporary fixtures are under ignored `work/`. Model binaries are under ignored packaged model directories. Test prompts, captions and Gemma import files are synthetic fixtures; no real transcript, audio or token is logged/committed.

## Reproduce compile-only verification

Obtain LiteRT-LM 0.18.0 from the [official Google Maven artifact](https://dl.google.com/dl/android/maven2/com/google/ai/edge/litertlm/litertlm-android/0.18.0/litertlm-android-0.18.0.aar), extract its `classes.jar` to ignored scratch space, and use an installed Android SDK `android.jar`. Flutter embedding matching the shell is available from the [official artifact](https://storage.googleapis.com/download.flutter.io/io/flutter/flutter_embedding_debug/1.0.0-deb287481e3ce9468f3434937ced4240a70539ca/flutter_embedding_debug-1.0.0-deb287481e3ce9468f3434937ced4240a70539ca.jar).

Override `-KotlinCompiler`/`-Java` for another machine. The exact shared-shell Kotlin/AGP/Flutter build must still be tested after integration; compiling API calls alone cannot establish native loading, ABI compatibility, merged permissions, SDK runtime behavior or phone performance.

## Required completion evidence

Follow [Android integration instructions](../../../android-backend.md) and the implementation plan's device gates. Record actual commands/results/device properties and aggregate measurements without transcripts/prompts. Keep the PR in draft while integrated builds/device checks are outstanding, or explicitly split a reviewed interface/core milestone from the final runtime acceptance.
