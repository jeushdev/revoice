# devJ → devS Android handoff

October 10, 2026. Continue from `devj/android-captions-speakers`; PR base remains
`codex/kotlin-development`. This handoff contains research, review patches/tests,
and a portable integration overlay, **not production speech implementation**.
No APK, Android runtime inference, microphone, or M0 acceptance has been
demonstrated. Review-only real desktop inference is recorded in the follow-up
below; it does not approve SDK adoption.

## Start here

1. Fetch this branch. Cherry-pick its handoff commit onto devS's feature branch,
   or review/merge it through integration. It adds documentation/review assets;
   it does not change app dependencies or adopt a patched SDK.
2. Review `docs/evidence/android/devj/INTEGRATION_PREP.md` and the portable files in
   `docs/evidence/android/devj/integration/`. Use latest devS `5592677` and the
   existing `jai-flutter` shell `73db4b6`, **not a generated second app**.
3. Complete reviewed shell/backend integration first. Retain devS's real plugin,
   fixed `group`/`sizeBytes` model schema, both preparation implementations,
   licenses/provenance, Flutter UI and iOS work. No direct implementation commits
   to `main` or the integration branch.
4. Build/check the combined app without deployment. Resolve pinned dependencies,
   restore the wrapper, supply ignored local properties and verified model assets.
   The default speech factory must keep rejecting initialization truthfully until
   real speech is implemented. No successful build has been claimed here.
5. Decide the SDK correction/packaging policy below before implementing capture.
   Then implement `SpeechBackendFactory` against `docs/android-backend.md` from
   devS's branch; do not create a competing controller or public channel contract.
6. Reconnect/authorize the intended Redmi and obtain permission for test APK
   installation before device work. Preserve existing app sessions; no uninstall
   or data clearing. Execute `docs/evidence/android/devj/DEVICE_GATES.md`.

## Decisions still needed

October 10 full-core follow-up: [`SDK_FULL_CORE_REBUILD.md`](docs/evidence/android/devj/SDK_FULL_CORE_REBUILD.md)
records exact-revision source/LFS/dependency verification and review-only full
core/JNI linking for all three Android ABIs with the real embedded Silero model.
The full Windows core also linked; real ORT inference passed repeated/interleaved
VAD and tiny-streaming C API sessions, plus core-error propagation to the C API.
This does not establish Android runtime, diarization or caption delivery. The
[`core error review`](docs/evidence/android/devj/SDK_CORE_ERROR_REVIEW.md) also
identifies unchecked Java create-stream handles as an adoption blocker. No app
dependency, AAR adoption, microphone or device work is approved by these builds.

October 10 cross-session follow-up: user requested the native state correction
before microphone integration. [`SDK_CROSS_SESSION_FIX.md`](docs/evidence/android/devj/SDK_CROSS_SESSION_FIX.md)
records patch 0004: detector-owned recurrent/context history, real buffer clearing
and synchronized model initialization. Ten host groups, singleton retry, three
negative mutations and six Android object builds passed. Full core linking with
the real model, artifact adoption and device gates remain open; existing
JNI-only AARs **do not contain** this correction.

October 10 follow-up: user authorized required-path SDK safety fixes and desktop
tests, **not adoption or phone work**. See
[`SDK_REQUIRED_PATH_FIX.md`](docs/evidence/android/devj/SDK_REQUIRED_PATH_FIX.md)
for the additional review-only JNI patch, 403 fault/cleanup cases and three-ABI
syntax checks. Required converter/file-loader source fixes are now prepared;
core rebuild/inference validation, artifact adoption and device gates remain open.
The historical candidate AAR/hash below contains only patches 0001/0002, not
the new 0003 patch.

- **Moonshine SDK:** published `0.1.5` has confirmed discarded JNI statuses,
  unreleased audio-array elements, and a sub-hop Stop-tail mechanism. Read
  `SDK_ARTIFACT_REVIEW.md`, `SDK_FIX_PROPOSAL.md`, and `SDK_FIX_REVIEW.md` in the
  evidence directory. Narrow patches fix streaming-array cleanup, status checks
  and explicit update scheduling; they are review candidates, **not adopted**.
- **Inherited required-path defects:** transcript conversion has unchecked JNI
  allocations/exceptions; local loading retains strings without release. Review
  these plus cross-session VAD state/races before production approval. The narrow
  candidate is not a generally OOM-safe or leak-free SDK.
- **Stop:** choose verified exact-16-kHz input with hop-512 sample accounting and
  bounded zero-padding, or approve a separately reviewed core remainder fix.
  Do not apply the padding formula to arbitrary resampled input.
- **Pause:** keep the same stream/speaker registry. Synthetic silence cap is only
  an experiment; require genuine completion, otherwise fail closed. Never reset
  via stop/start or fabricate final captions.
- **Packaging/shrinker:** assign patched bytes a distinct internal identity and
  preserve/explicitly replace the Maven dependency graph, with exactly one SDK
  class/native provider. Neither original nor candidate AAR supplies consumer
  keep rules. Supply reviewed native-name rules or explicitly choose a
  non-minified feasibility build; neither establishes release readiness.
- **Capture interface:** `CAPTURE_PROPOSAL.md` is historical and unagreed. The
  concrete devS `SpeechBackend` contract is the integration boundary to review/use.

## Checks actually completed

| Scope | Result | Limit |
| --- | --- | --- |
| Integration v2 | 33 Kotlin tests; 19 Python tests; six PowerShell parser checks; static preservation/XML/whitespace; cached Gradle bootstrap | Fake JVM boundaries; no Flutter application build; PowerShell 7 runtime suite unavailable here |
| Published SDK | Artifact hashes/ABIs; Java bytecode and JNI/core inspection; wrapper regressions | No Android inference/runtime test |
| Final SDK review suite | 16 host JNI scenarios; 10 Java groups, including stateful Stop ledger | Fake JNI/core; not ART, VAD or real audio proof |
| Candidate JNI rebuild | All three ABIs; three deterministic candidate AAR builds | Published core/ORT unchanged; no application adoption/load test |
| Full pinned native rebuild | 120 translation units per ABI; core/JNI linked for all three ABIs; 43 JNI exports / 44 resolved core imports each; full Windows core linked | Real embedded Silero, unchanged ORT; unstripped review binaries only; no AAR/app adoption or Android load/inference |
| Real desktop inference | ORT 1.23.2; 20 reused VAD sessions; isolated/interleaved/restart/gap checks; repeated/interleaved real tiny-streaming C API speech; real core error → C API | No real JNI/ART, diarization, sanitizer, mic, device, Stop/Pause finalization or caption-delivery acceptance |
| Flutter | Official archive SHA-256; installed Flutter 3.47.6 / Dart 3.13.5; Android precache | Toolchain accepted, not an app build |
| Models | Ten speech/diarization files verified in original checkout | Local binaries not transferred/committed; integration worktree has none |

Independent review predates the final test/documentation follow-ups. Its inherited
native and adoption gates remain open; expanded tests did not clear them.

Final pre-commit validation: `review.py --run-name handoff-final-check` exited 0
(16 JNI scenarios / 10 Java groups); both portable integration patches apply-check
against their exact input revisions; evidence JSON and Python syntax validated;
no credential-token/private-key patterns found in the evidence directory.
This final run did not rebuild native libraries or access the phone.
Whitespace checks exclude `*.patch`: unified-diff blank context lines deliberately
contain a single space. Scoped attributes retain LF patch bytes on Windows.

## Reproduce / continue on another PC

- All portable first-party tests, patches and input hashes are committed under
  `docs/evidence/android/devj/`. Model binaries, AARs, toolchains and raw temporary
  build logs intentionally are not.
- Read `sdk-fix/inputs.json` for the immutable upstream revision and source/artifact
  hashes. Acquire source at that exact revision and the AAR/source JAR from Maven
  Central; verify every listed hash. No gated model is needed for SDK review.
- Run `python -B docs/evidence/android/devj/sdk-fix/review.py --help`. Supply
  `--source-root`, `--artifact-root`, `--jdk`, `--host-cxx`, and `--ndk` for the new
  machine. Create the scratch parent directory first; use a fresh `--run-name`.
  Runner is Windows-oriented and offline; it does not fetch missing prerequisites.
  Cross-build requires pinned NDK inputs; do not bypass hash checks to claim the
  same candidate. See `SDK_FIX_PROPOSAL.md` for exact acceptance/output identities.
- Candidate AAR SHA-256:
  `3936002d9ff6e14cba0d41af7c3d1ccc4f7b4309f441f1d7029337e1cb700d3e`.
  This identifies a review artifact, not an approved dependency coordinate.
- Select compatible Flutter/Dart and an agreed JVM explicitly. Local verified
  Flutter is `C:\Users\jeush\AppData\Local\Temp\opencode\flutter-toolchain-3.47.6\flutter`;
  JBR is `C:\Program Files\Android\Android Studio\jbr` (25.0.2); Android SDK is
  `%LOCALAPPDATA%\Android\Sdk`. Gradle 9.3.1 does not support PATH Java 26.
  See `TOOLCHAIN_READINESS.md`; do not assume these paths exist on devS's PC.

## Local state preserved on Jeush's PC

- Original checkout stays on `devj/android-captions-speakers`. This handoff commit
  is the only new commit requested here; it does not complete another worktree's merge.
- Latest integration specimen:
  `C:\Users\jeush\AppData\Local\Temp\opencode\revoice-integration-prep-v2`,
  branch `devj/android-integration-prep-v2`, HEAD `5592677`, pending merge `73db4b6`.
  Three working-file conflict resolutions remain unmerged in its index; three
  integration edits are unstaged. **Do not cherry-pick that branch expecting them.**
- Old `revoice-integration-prep` remains untouched. Both specimens are temporary
  and not pushed. Portable integration patches below preserve the authored changes
  without committing duplicate shell/UI/iOS files or binaries.
- Original models and candidate-r1/r2/r3 outputs remain local and unadopted.
  No phone calls/deployment took place after the user powered the Redmi off.

Please record actual integrated build/device results and remaining limitations;
desktop success alone is not M0 or demo readiness.
