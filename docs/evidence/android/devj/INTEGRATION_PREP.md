# Android integration preparation v2 — local review only

October 10, 2026. **Uncommitted review specimen; not a verified APK or completed M0.**

Handoff note: this is the preserved v2 preparation snapshot. Flutter 3.47.6 /
Dart 3.13.5 was subsequently installed and verified; the historical wait below is
superseded by `TOOLCHAIN_READINESS.md`. Portable integration deltas are committed
in `integration/`; see the root `ANDROID_DEVJ_HANDOFF.md` for current next steps.

## Current inputs and isolated scope

- Worktree: `C:\Users\jeush\AppData\Local\Temp\opencode\revoice-integration-prep-v2`
- Branch: `devj/android-integration-prep-v2`.
- HEAD: `559267737b8c7a72a2233123b10957f31493287b` (`origin/devs/android-crm-assets`).
- MERGE_HEAD: `73db4b676faff8f6e336fd7ad663f87198a4d17d` (`origin/jai-flutter`).
- Remote tips confirmed with `git ls-remote`; `codex/kotlin-development` still points to `cf88c8689ffdeb9e9e336a77c27a9502e323bca2`. Latest devS still contains no Flutter shell.
- Read work split, implementation plan, backend integration instructions, new model setup/evidence and devS incoming-merge notes. No applicable `AGENTS.md` found in v2 or its ancestors.
- All edits/check outputs are in v2. The old `revoice-integration-prep` worktree and its pending merge were not touched. Original checkout was read with optional Git locks disabled and remains on `devj/android-captions-speakers`, with its existing untracked `docs/evidence/android/devj/` unchanged.
- No explicit staging, commits, pushes, PR merges, extra agents, tool installations, app builds, device calls, patched SDK adoption or production speech implementation.

## Latest devS delta retained, not reimplemented

Reviewed the `42a1ecf..5592677` delta across all 22 changed paths: expanded shared ignores/README/notices; model lock, publisher/license snapshots; Python preparation and separately named PowerShell wrapper; interactive download helper; 19 Python tests; model docs and scoped evidence. Publisher snapshots are preserved content, not a new legal audit.

The incoming notes explain the resolved four-way asset/tooling conflicts and incompatible historical schema. V2 preserves those resolutions exactly:

- Native runtime inventory retains `group`/`sizeBytes`/`sha256`/`crc32c`/`sourceUrl`; no historical `bytes`-only inventory or readiness flags were copied over it.
- `scripts/prepare-android-models.ps1` remains the native PowerShell 7 entry point.
- `scripts/prepare-android-models-python.ps1` remains the Python wrapper; no naming collision introduced.
- Local verification status stays outside packaged assets in ignored `work/android-model-preparation-report.json`.
- Locks, provenance, license texts, notices, tests, preparation sources and devS backend/Gradle script/backup XML are unchanged from latest HEAD.
- Historical full-model verification applies to the originating checkout, not v2. No model binaries or large duplicate copies were added here.

## Working-file resolutions and integration edits

Ran `git merge --no-commit --no-ff origin/jai-flutter`; three add/add conflicts occurred:

| Path | Final working content |
| --- | --- |
| `.gitignore` | Union of all latest devS and Flutter shell patterns, including new Python/model/build/secret exclusions |
| `README.md` | Both sets of setup/layout content; latest Python-wrapper instructions retained; truthful readiness/toolchain handoff |
| `android/app/src/main/kotlin/com/larpcode/revise/ReviseEnginePlugin.kt` | Latest devS real plugin retained exactly; shell placeholder removed |
| `android/app/build.gradle.kts` | Appended exactly `apply(from = "revise-backend.gradle")` after shell configuration |
| `android/app/src/main/AndroidManifest.xml` | Tools namespace, INTERNET removal marker and disabled-backup/extraction attributes; shell RECORD_AUDIO, activity, Flutter metadata and queries preserved |
| `android/app/src/main/kotlin/com/larpcode/revise/MainActivity.kt` | Existing thin default plugin registration plus comment; no speech factory injection |
| `docs/evidence/android/devj/INTEGRATION_PREP.md` | This untracked handoff |

Missing speech assets fail with `model_missing`; valid assets still encounter the default factory's truthful `capture_failed` rejection until devJ's real factory is supplied. No stub reports speech readiness. UI/Dart/iOS/tests/package/toolchain pins remain untouched; no second app was generated.

### Precise merge-index state

- HEAD remains `5592677`; merge is **pending and uncommitted**.
- Merge machinery staged **82 shell additions**. No `git add` was run.
- `.gitignore`, `README.md`, and `ReviseEnginePlugin.kt` remain **AA/unmerged in the index**, with stages 2 and 3. Working-file resolutions have no conflict markers, but were deliberately not staged.
- App Gradle file, main manifest and MainActivity are **AM**: shell originals staged by merge, final integration edits unstaged.
- This handoff is untracked. Wrapper files, static checker, Python caches and test artifacts are ignored and unstaged.

## Actual v2 desktop checks

| Check | Actual result / limitation |
| --- | --- |
| Direct installed `kotlinc` + JBR execution of `tests/kotlin/BackendTests.kt` | **33 passed** with fake speech/CRM boundaries; ignored output `work/kotlin-tests/backend-tests.jar` |
| `python -m unittest discover -s scripts/tests -v` | **19 passed**, including publisher pins, fixed native inventory/schema, corruption, atomic publication and credential/redirect safeguards; temporary fixtures routed to ignored `work/python-temp/` |
| Windows PowerShell parser checks | **6 passed**: all five scripts/modules under `scripts/` plus `tests/scripts/prepare-android-models.tests.ps1` |
| `scripts/prepare-android-models-python.ps1 -VerifyOnly` | **Expected failure, exit 1:** `Missing required asset: models/stt/adapter.ort`. Confirms preserved wrapper invokes offline verifier; no model download, manifest/report write or credential prompt |
| PowerShell 7 runtime suites | **Not run:** `pwsh` and standard PowerShell 7 executable absent; installed Windows PowerShell is 5.1. Do not import devS's 11-pass result as a local result. |
| `python work/integration-static-check.py` | **Passed:** 79 shell-owned files and 42 latest devS files preserved (text line endings normalized); both ignore-pattern sets retained; XML/backup/apply-line checks; fixed 11-file inventory equals current Python generation; no readiness flags, models, local properties or first-party conflict markers |
| Wrapper restoration/integrity and `android/gradlew.bat --offline --version` | **Passed:** source-copy SHA-256 equality; properties unchanged; cached Gradle **9.3.1**, Android Studio JBR **25.0.2**; native-access warnings only |
| `git check-ignore --verbose` | **Passed:** wrapper scripts/JAR, static checker, Python caches and representative STT/Gemma model paths ignored |
| `git diff --check`, `git diff --cached --check` | **Passed**; ordinary LF-to-CRLF notices only. Preserved publisher snapshots are not new edits. |

The read-only static checker is an **ignored local review artifact** at `work/integration-static-check.py`, not a production change. JVM checks used the core commands directly because the launcher script requires unavailable PowerShell 7:

```powershell
# From v2; work/kotlin-tests/ already exists from this run.
$core = @(Get-ChildItem android/app/src/main/kotlin/com/larpcode/revise/backend -Filter '*.kt' |
    Where-Object Name -NotIn @('LiteRtCrmRuntime.kt', 'AndroidModelAssets.kt') | ForEach-Object FullName)
& 'C:/Program Files/Android/Android Studio/plugins/Kotlin/kotlinc/bin/kotlinc.bat' @core `
    tests/kotlin/BackendTests.kt -jvm-target 17 -include-runtime -d work/kotlin-tests/backend-tests.jar
& 'C:/Program Files/Android/Android Studio/jbr/bin/java.exe' -jar work/kotlin-tests/backend-tests.jar
```

### Wrapper restoration details

Copied only missing `android/gradlew`, `android/gradlew.bat` and `android/gradle/wrapper/gradle-wrapper.jar` from the already-installed cache at `C:\Users\jeush\develop\flutter\bin\cache\artifacts\gradle_wrapper`. Each copy matched the source SHA-256; tracked `gradle-wrapper.properties` retained Gradle 9.3.1-all unchanged. Confirmed the cached distribution completion marker before executing the wrapper; used process-local `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr`. No scaffold regeneration, wrapper download or installation. Recheck the agreed new SDK's wrapper at toolchain handoff rather than claiming these files pin the forthcoming side-by-side Flutter installation.

## Remaining blockers and safe transfer

1. **Wait for toolchain agent:** compatible side-by-side Flutter installation is separately approved/in progress. Shell Dart `^3.13.5` is unchanged. No Flutter pub/analyze/test/build or application Gradle task was raced here. Machine-local `android/local.properties` is absent; create it through approved setup after the exact SDK/JDK/Android pins are handed off.
2. **Packaging binaries absent here:** do not infer readiness from pulled metadata or originating-checkout evidence. Existing original-checkout binaries remain untouched. Future authorized packaging must use an agreed asset-source/transfer plan without unnecessary large copies and run full verification. Release always requires all 11 assets. Actual packaging of required notices and resolved SDK/transitive notices remains pending.
3. **Native speech and SDK gates remain separate:** default rejecting factory stays in place. No reviewed SDK fixes were adopted or production devJ capture code added. Combined plugin/API build, native ABI/page-size compatibility, release merged manifest/backup inspection and runtime resource behavior remain unverified.
4. **Redmi remains off:** no adb, installs, instrumentation, data clearing, mic/inference or offline-install testing. Any later device work requires renewed explicit authorization.
5. **Review v2, not v1:** use `git status --short`, `git ls-files --unmerged`, `git diff HEAD -- <path>` for final working content and `git diff --cached --name-status` for merge-staged originals. Preserve both older/original checkouts. This pending merge cannot be cherry-picked as an implementation commit.
6. **Owner-authorized integration:** review the existing shell PR and latest devS revision through the team's integration flow. Transfer only reviewed v2 integration deltas and this handoff, adapting ignores/docs to current integration content rather than overwriting newer work. Preserve latest devS plugin/schema/tools/notices; never copy historical v1 asset files over latest HEAD. Regenerate ignored wrapper locally; do not force-add binaries, local properties, models or scratch artifacts. Staging/commit/push are separate owner-authorized follow-up.
7. **devJ handoff after integration:** update from approved integration only after review, then separately implement/inject `SpeechBackendFactory`. Toolchain/app builds and device verification must precede any demo-ready claim.

**Bounded v2 preparation complete; final working resolutions intentionally remain unstaged.**
