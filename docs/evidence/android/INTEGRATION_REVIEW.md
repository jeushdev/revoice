# Android shell and devJ handoff: integration review

October 10, 2026. Local review branch `review/android-shell-devj-handoff`, based on
devS `5592677`. This is an uncommitted review working tree, not a built APK or M0
result. No device command, SDK substitution, dependency adoption, commit or push
was performed.

## Integrated working content

- Fetched current remote branches. Applied devJ's `0b4f410` documentation and
  review assets with `cherry-pick --no-commit`; the handoff is staged for review.
- Restored the 82 shell-only tracked paths from `origin/jai-flutter` `73db4b6`
  into the working tree. Kept devS's `PRD.md` and real Android
  `ReviseEnginePlugin.kt`, including its default `capture_failed` speech factory.
- Applied the handoff's exact-input ignore/README conflict-resolution and
  shell-wiring patches. The latter applies `revise-backend.gradle`, removes the
  SDK's INTERNET permission from the app manifest, uses devS's backup rules,
  and registers the real plugin in the existing thin `MainActivity`.
- Preserved the shared Flutter UI/tests and iOS files, devS's `group`/`sizeBytes`
  11-file model inventory, both model-preparation entry points, lock/provenance,
  notices and license snapshots. No second Flutter app was generated.
  Git blob comparison confirms 79 of the 82 shell-only paths match `jai-flutter`
  exactly after checkout text normalization; the other three are precisely the
  reviewed Gradle, manifest and MainActivity wiring edits.

The branch has no merge commit. The handoff, shell and integration edits are
staged as a reviewable diff, with ignored models, wrapper binaries and local
properties excluded. A later approved commit/merge must record shell ancestry
and resolve any changes that arrive meanwhile.

## Checks run on this host

| Check | Actual result |
| --- | --- |
| `scripts/test-android-backend.ps1` with Studio JBR 25.0.3 and Kotlin 2.3.20 | 33 JVM backend checks passed. The test needed normal filesystem atomic-move semantics and a workspace temp directory. Fake speech/CRM boundaries only. |
| `python -B -m unittest discover -s scripts/tests -v` | 19 passed. The test needed normal filesystem hard-link semantics and a workspace temp directory. |
| PowerShell parser on five scripts/modules and one test file | 6 parsed without errors. |
| `prepare-android-models.ps1 -VerifyOnly -SpeechOnly` | 10 speech/diarization assets passed length, SHA-256 and CRC32C checks. They were already present as ignored local files in this checkout; no transfer, download or replacement was done. |
| `prepare-android-models.ps1 -VerifyOnly` | Expected exit 1 at missing `models/llm/gemma3-1b-it-int4.litertlm`; full 11-asset packaging is blocked. |
| Static integration check | Manifest and backup XML parsed; inventory is 8 STT, 2 diarization, 1 LLM with `group`/`sizeBytes` and no legacy `bytes`; default plugin rejects speech initialization. |

`git diff --cached --check` reports intentional single-space unified-diff blank
context lines in devJ's committed `.patch` review assets. The ordinary working
diff has no whitespace findings.

## Application build readiness

No Flutter pub/analyze/test, Gradle application task, APK, native SDK load or
device check ran. This host has Studio JBR 25.0.3 and Android build-tools 36.0.0,
but no discovered compatible Flutter/Dart installation, API 36 platform, NDK
28.2.13676358, cached Gradle 9.3.1 distribution or local Gradle wrapper files.
`android/local.properties` is absent. Do not use PATH Java 26 for Gradle 9.3.1.
Restore the wrapper from a verified compatible Flutter SDK and create ignored
local properties after the approved machine-local SDK paths exist. Obtain the
licensed, pinned Gemma file through the team's authorized asset process; the
ten verified speech files alone cannot satisfy the default full build.

## Moonshine decision before adoption

The published 0.1.5 defects and review limits are documented in
`devj/SDK_ARTIFACT_REVIEW.md`, `devj/SDK_FIX_PROPOSAL.md` and
`devj/SDK_FIX_REVIEW.md`. The two candidate patches are suitable for a bounded
feasibility review: JNI streaming-array cleanup, checked native start/add/stop
statuses and explicit update scheduling. The final handoff reports 16 fake-JNI
scenarios, 10 Java groups and three deterministic JNI-only AAR builds, preserving
the published core and ORT. These results do not validate ART, real VAD, a
microphone or repeated sessions; no candidate has been installed here.

Proposed narrow decision, **requiring explicit approval before substitution**:

1. Repair the required transcript converter's JNI allocation/exception checks
   and release the local loader's acquired UTF strings on every path. Add fault
   injection for conversion/load failure and repeated local-load/feed/close/GC.
   Scope and review the process-global Silero recurrent state and reused
   probability/look-back buffers for a second-session fix before production use.
2. For Stop, require the actual SDK-fed stream to be exactly 16 kHz with hop 512.
   After capture join and real queue drain, count every accepted real and synthetic
   sample once; add `P = (512 - N % 512) % 512` zeros only when `P > 0`, then invoke
   checked Stop once. A post-acceptance error makes the ledger terminal-failed.
   The Java update cadence counters are not an accepted-audio ledger; never
   replay an append or retry a final callback after a partial failure.
   Never apply this formula to arbitrary resampled input. Same-stream Pause may
   force checked updates but must fail closed if a genuine final barrier cannot
   complete; it cannot synthesize final captions or reset the stream.
3. Give patched bytes a distinct internal identity, for example
   `com.larpcode.internal:moonshine-voice-revise:0.1.5-jni-r3`, with its own
   checksum and matching POM/Gradle module dependency metadata. Preserve the four
   published direct dependencies and resolve/report their transitives. Ensure
   exactly one SDK class provider and one JNI/core/ORT provider per ABI; never
   include stock and patched AARs together. Retain source, patch and license
   provenance. The candidate AAR hash in the handoff identifies review bytes,
   not a deployable coordinate.
4. Supply app-owned keep rules for the SDK classes, constructors and fields named
   from JNI and inspect the actual minified release output. An explicitly
   non-minified build is acceptable only for feasibility; it is not release
   shrinker validation. Check the resolved graph, merged manifest and native
   payload before any candidate build is called package-ready.

The existing Gradle script still names published `ai.moonshine:moonshine-voice:0.1.5`
because no substitution has been approved. It is not evidence that the published
artifact is safe for capture. Device approval remains separate; the Redmi is off.
